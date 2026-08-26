package com.gzyzhy.streamradio.ui.screens

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.gzyzhy.streamradio.data.ConnectivityResult
import com.gzyzhy.streamradio.data.Station
import com.gzyzhy.streamradio.data.StationRepository
import com.gzyzhy.streamradio.data.Subscription
import com.gzyzhy.streamradio.data.ConnectivityChecker
import com.gzyzhy.streamradio.util.SettingsManager
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    repo: StationRepository,
    settings: SettingsManager,
    subscriptions: List<Subscription>,
    stations: List<Station>,
    onBack: () -> Unit,
    onNavigateToHelp: () -> Unit,
    onNavigateToAbout: () -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val appearanceMode by settings.appearanceMode.collectAsState(initial = "system")
    val autoSync by settings.autoSyncOnLaunch.collectAsState(initial = false)

    var showAddSub by remember { mutableStateOf(false) }
    var syncing by remember { mutableStateOf(false) }
    var syncResult by remember { mutableStateOf<String?>(null) }

    var checking by remember { mutableStateOf(false) }
    var checkResults by remember { mutableStateOf<Map<String, ConnectivityResult>>(emptyMap()) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("设置") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "返回")
                    }
                }
            )
        }
    ) { padding ->
        LazyColumn(modifier = Modifier.padding(padding)) {
            // 外观
            item {
                SectionHeader("外观")
                var expanded by remember { mutableStateOf(false) }
                val options = listOf("system" to "跟随系统", "light" to "浅色", "dark" to "深色")
                ListItem(
                    headlineContent = { Text("外观") },
                    trailingContent = {
                        TextButton(onClick = { expanded = true }) {
                            Text(options.first { it.first == appearanceMode }.second)
                        }
                        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                            options.forEach { (key, label) ->
                                DropdownMenuItem(
                                    text = { Text(label) },
                                    onClick = {
                                        scope.launch { settings.setAppearanceMode(key) }
                                        expanded = false
                                    }
                                )
                            }
                        }
                    }
                )
            }

            // 订阅
            item {
                SectionHeader("订阅")
                ListItem(
                    headlineContent = { Text("启动时自动同步") },
                    trailingContent = {
                        Switch(
                            checked = autoSync,
                            onCheckedChange = { v ->
                                scope.launch { settings.setAutoSyncOnLaunch(v) }
                            }
                        )
                    }
                )
                if (subscriptions.isEmpty()) {
                    ListItem(
                        headlineContent = {
                            Text(
                                "暂无订阅。添加 m3u 链接后手动同步拉取电台（按播放链接去重）。",
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    )
                }
            }

            items(subscriptions, key = { it.id }) { sub ->
                ListItem(
                    headlineContent = { Text(sub.name) },
                    supportingContent = { Text(sub.url, maxLines = 1) },
                    trailingContent = {
                        IconButton(onClick = {
                            scope.launch { repo.removeSubscription(sub) }
                        }) {
                            Icon(Icons.Default.Delete, contentDescription = "删除",
                                tint = MaterialTheme.colorScheme.error)
                        }
                    }
                )
            }

            item {
                ListItem(
                    headlineContent = {
                        Text(if (syncing) "同步中…" else "手动同步全部订阅")
                    },
                    leadingContent = {
                        if (syncing) {
                            CircularProgressIndicator(modifier = Modifier.size(24.dp))
                        } else {
                            Icon(Icons.Default.Sync, contentDescription = null)
                        }
                    },
                    modifier = Modifier.run {
                        if (!syncing && subscriptions.isNotEmpty()) clickable {
                            scope.launch {
                                syncing = true
                                syncResult = null
                                val n = repo.syncAllSubscriptions()
                                syncResult = if (n < 0) "同步失败，请检查网络与订阅链接"
                                else "已新增 $n 个电台（按播放链接去重）"
                                syncing = false
                            }
                        } else this
                    }
                )
                syncResult?.let {
                    ListItem(
                        headlineContent = {
                            Text(it, style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    )
                }
                ListItem(
                    headlineContent = { Text("添加订阅") },
                    leadingContent = { Icon(Icons.Default.Add, contentDescription = null) },
                    modifier = Modifier.clickable { showAddSub = true }
                )
            }

            // 网络
            item {
                SectionHeader("网络")
                ListItem(
                    headlineContent = {
                        Text(if (checking) "检查中…" else "检查全部电台连通性")
                    },
                    leadingContent = {
                        if (checking) {
                            CircularProgressIndicator(modifier = Modifier.size(24.dp))
                        } else {
                            Icon(Icons.Default.NetworkCheck, contentDescription = null)
                        }
                    },
                    modifier = Modifier.run {
                        if (!checking) clickable {
                            scope.launch {
                                checking = true
                                val results = mutableMapOf<String, ConnectivityResult>()
                                for (s in stations) {
                                    results[s.url] = ConnectivityChecker.check(s.url)
                                }
                                checkResults = results
                                checking = false
                            }
                        } else this
                    }
                )
            }

            if (checkResults.isNotEmpty() && !checking) {
                val ok = checkResults.values.count { it.ok }
                val fail = checkResults.filter { !it.value.ok }
                item {
                    Row(
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text("可播 $ok 个，失败 ${fail.size} 个")
                        Spacer(Modifier.weight(1f))
                        if (fail.isNotEmpty()) {
                            TextButton(onClick = {
                                scope.launch {
                                    val failedUrls = fail.keys
                                    repo.remove(stations.filter { it.url in failedUrls })
                                    checkResults = checkResults.filter { it.key !in failedUrls }
                                }
                            }) {
                                Text("删除全部失败", color = MaterialTheme.colorScheme.error)
                            }
                        }
                    }
                }
                items(fail.toList(), key = { it.first }) { (url, result) ->
                    val station = stations.firstOrNull { it.url == url }
                    ListItem(
                        headlineContent = { Text(station?.name ?: url, maxLines = 1) },
                        trailingContent = {
                            Text(result.message ?: "失败",
                                color = MaterialTheme.colorScheme.error,
                                style = MaterialTheme.typography.bodySmall)
                        }
                    )
                }
            }

            // 其他
            item {
                SectionHeader("其他")
                ListItem(
                    headlineContent = { Text("帮助") },
                    leadingContent = { Icon(Icons.Default.HelpOutline, contentDescription = null) },
                    modifier = Modifier.clickable { onNavigateToHelp() }
                )
                ListItem(
                    headlineContent = { Text("关于") },
                    leadingContent = { Icon(Icons.Default.Info, contentDescription = null) },
                    modifier = Modifier.clickable { onNavigateToAbout() }
                )
                // 免责声明：跳转 GitHub README 对应章节（与 iOS 端一致）
                ListItem(
                    headlineContent = { Text("免责声明") },
                    leadingContent = { Icon(Icons.Default.Link, contentDescription = null) },
                    modifier = Modifier.clickable {
                        openDisclaimer(context)
                    }
                )
            }
        }
    }

    // 添加订阅对话框
    if (showAddSub) {
        var name by remember { mutableStateOf("") }
        var url by remember { mutableStateOf("") }
        AlertDialog(
            onDismissRequest = { showAddSub = false },
            title = { Text("添加订阅") },
            text = {
                Column {
                    OutlinedTextField(value = name, onValueChange = { name = it },
                        label = { Text("名称") }, singleLine = true)
                    Spacer(Modifier.height(8.dp))
                    OutlinedTextField(value = url, onValueChange = { url = it },
                        label = { Text("m3u 链接") }, singleLine = true)
                }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        val n = name.trim()
                        val u = url.trim()
                        if (n.isNotEmpty() && u.isNotEmpty()) {
                            scope.launch {
                                repo.addSubscription(n, u)
                                showAddSub = false
                            }
                        }
                    },
                    enabled = name.trim().isNotEmpty() && url.trim().isNotEmpty()
                ) { Text("添加") }
            },
            dismissButton = {
                TextButton(onClick = { showAddSub = false }) { Text("取消") }
            }
        )
    }
}

// 打开免责声明：跳转 GitHub README 免责声明章节（与 iOS 端一致）
private fun openDisclaimer(context: Context) {
    try {
        context.startActivity(
            Intent(Intent.ACTION_VIEW, Uri.parse("https://github.com/GZYZhy/stream-radio#免责声明"))
        )
    } catch (_: Exception) {
        // 无可用浏览器时静默忽略
    }
}

@Composable
internal fun SectionHeader(title: String) {
    Text(
        title,
        style = MaterialTheme.typography.titleSmall,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(start = 16.dp, top = 16.dp, bottom = 4.dp)
    )
}
