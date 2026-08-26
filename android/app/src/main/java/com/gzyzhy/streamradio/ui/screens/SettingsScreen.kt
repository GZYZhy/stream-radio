package com.gzyzhy.streamradio.ui.screens

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.gzyzhy.streamradio.R
import com.gzyzhy.streamradio.data.ConnectivityResult
import com.gzyzhy.streamradio.data.Station
import com.gzyzhy.streamradio.data.StationRepository
import com.gzyzhy.streamradio.data.Subscription
import com.gzyzhy.streamradio.data.ConnectivityChecker
import com.gzyzhy.streamradio.data.LatestRelease
import com.gzyzhy.streamradio.data.UpdateChecker
import com.gzyzhy.streamradio.util.SettingsManager
import com.gzyzhy.streamradio.util.compareVersions
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
    val appLanguage by settings.appLanguage.collectAsState(initial = "system")
    val autoSync by settings.autoSyncOnLaunch.collectAsState(initial = false)

    var showAddSub by remember { mutableStateOf(false) }
    var syncing by remember { mutableStateOf(false) }
    var syncResult by remember { mutableStateOf<String?>(null) }

    var checking by remember { mutableStateOf(false) }
    var checkResults by remember { mutableStateOf<Map<String, ConnectivityResult>>(emptyMap()) }

    // 语言设置需重启生效，选择后弹出提示
    var showLanguageHint by remember { mutableStateOf(false) }
    // 检查更新：Idle/Checking/UpToDate/Available/Failed
    var updateState by remember { mutableStateOf<UpdateState>(UpdateState.Idle) }
    // 当前版本号（与 About 页一致）
    @Suppress("DEPRECATION")
    val currentVersion = remember(context) {
        context.packageManager.getPackageInfo(context.packageName, 0).versionName ?: ""
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.settings_title)) },
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
                SectionHeader(stringResource(R.string.settings_section_appearance))
                var expanded by remember { mutableStateOf(false) }
                val options = listOf(
                    "system" to stringResource(R.string.settings_appearance_system),
                    "light" to stringResource(R.string.settings_appearance_light),
                    "dark" to stringResource(R.string.settings_appearance_dark)
                )
                ListItem(
                    headlineContent = { Text(stringResource(R.string.settings_appearance)) },
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
                // 语言选择
                var langExpanded by remember { mutableStateOf(false) }
                val languageOptions = listOf(
                    "system" to stringResource(R.string.settings_language_system),
                    "zh-Hans" to stringResource(R.string.settings_language_zh),
                    "en" to stringResource(R.string.settings_language_en),
                    "fr" to stringResource(R.string.settings_language_fr),
                    "ja" to stringResource(R.string.settings_language_ja)
                )
                ListItem(
                    headlineContent = { Text(stringResource(R.string.settings_language)) },
                    trailingContent = {
                        TextButton(onClick = { langExpanded = true }) {
                            Text(languageOptions.first { it.first == appLanguage }.second)
                        }
                        DropdownMenu(expanded = langExpanded, onDismissRequest = { langExpanded = false }) {
                            languageOptions.forEach { (key, label) ->
                                DropdownMenuItem(
                                    text = { Text(label) },
                                    onClick = {
                                        scope.launch { settings.setAppLanguage(key) }
                                        langExpanded = false
                                        showLanguageHint = true
                                    }
                                )
                            }
                        }
                    }
                )
            }

            // 订阅
            item {
                SectionHeader(stringResource(R.string.settings_section_subscription))
                ListItem(
                    headlineContent = { Text(stringResource(R.string.settings_auto_sync)) },
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
                                stringResource(R.string.settings_no_subscription),
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
                            Icon(Icons.Default.Delete, contentDescription = stringResource(R.string.delete),
                                tint = MaterialTheme.colorScheme.error)
                        }
                    }
                )
            }

            item {
                ListItem(
                    headlineContent = {
                        Text(if (syncing) stringResource(R.string.settings_syncing)
                        else stringResource(R.string.settings_sync_manual))
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
                                syncResult = if (n < 0) context.getString(R.string.settings_sync_failed)
                                else context.getString(R.string.settings_sync_success, n)
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
                    headlineContent = { Text(stringResource(R.string.settings_add_subscription)) },
                    leadingContent = { Icon(Icons.Default.Add, contentDescription = null) },
                    modifier = Modifier.clickable { showAddSub = true }
                )
            }

            // 网络
            item {
                SectionHeader(stringResource(R.string.settings_section_network))
                ListItem(
                    headlineContent = {
                        Text(if (checking) stringResource(R.string.settings_checking)
                        else stringResource(R.string.settings_check_connectivity))
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
                        Text(stringResource(R.string.settings_check_result, ok, fail.size))
                        Spacer(Modifier.weight(1f))
                        if (fail.isNotEmpty()) {
                            TextButton(onClick = {
                                scope.launch {
                                    val failedUrls = fail.keys
                                    repo.remove(stations.filter { it.url in failedUrls })
                                    checkResults = checkResults.filter { it.key !in failedUrls }
                                }
                            }) {
                                Text(stringResource(R.string.settings_delete_all_failed),
                                    color = MaterialTheme.colorScheme.error)
                            }
                        }
                    }
                }
                items(fail.toList(), key = { it.first }) { (url, result) ->
                    val station = stations.firstOrNull { it.url == url }
                    ListItem(
                        headlineContent = { Text(station?.name ?: url, maxLines = 1) },
                        trailingContent = {
                            Text(result.message ?: stringResource(R.string.settings_failed_default),
                                color = MaterialTheme.colorScheme.error,
                                style = MaterialTheme.typography.bodySmall)
                        }
                    )
                }
            }

            // 其他
            item {
                SectionHeader(stringResource(R.string.settings_section_other))
                ListItem(
                    headlineContent = { Text(stringResource(R.string.settings_help)) },
                    leadingContent = { Icon(Icons.Default.HelpOutline, contentDescription = null) },
                    modifier = Modifier.clickable { onNavigateToHelp() }
                )
                ListItem(
                    headlineContent = { Text(stringResource(R.string.settings_about)) },
                    leadingContent = { Icon(Icons.Default.Info, contentDescription = null) },
                    modifier = Modifier.clickable { onNavigateToAbout() }
                )
                // 免责声明：跳转 GitHub README 对应章节（与 iOS 端一致）
                ListItem(
                    headlineContent = { Text(stringResource(R.string.settings_disclaimer)) },
                    leadingContent = { Icon(Icons.Default.Link, contentDescription = null) },
                    modifier = Modifier.clickable {
                        openDisclaimer(context)
                    }
                )
                // 检查更新：手动触发，联网比较 GitHub 最新 release 版本
                ListItem(
                    headlineContent = {
                        Text(stringResource(
                            if (updateState is UpdateState.Checking) R.string.checking_update
                            else R.string.settings_check_update
                        ))
                    },
                    leadingContent = {
                        if (updateState is UpdateState.Checking) {
                            CircularProgressIndicator(modifier = Modifier.size(24.dp))
                        } else {
                            Icon(Icons.Default.SystemUpdate, contentDescription = null)
                        }
                    },
                    modifier = Modifier.clickable {
                        if (updateState !is UpdateState.Checking) {
                            scope.launch {
                                updateState = UpdateState.Checking
                                val release = UpdateChecker.fetchLatestRelease()
                                updateState = when {
                                    release == null -> UpdateState.Failed
                                    compareVersions(release.version, currentVersion) > 0 ->
                                        UpdateState.Available(release)
                                    else -> UpdateState.UpToDate
                                }
                            }
                        }
                    }
                )
            }
        }
    }

    // 语言设置重启生效提示
    if (showLanguageHint) {
        AlertDialog(
            onDismissRequest = { showLanguageHint = false },
            text = { Text(stringResource(R.string.settings_language_restart_hint)) },
            confirmButton = {
                TextButton(onClick = { showLanguageHint = false }) {
                    Text(stringResource(R.string.ok))
                }
            }
        )
    }

    // 检查更新结果弹窗：发现新版本（说明可滚动）/ 已是最新 / 失败
    when (val state = updateState) {
        is UpdateState.Available -> {
            AlertDialog(
                onDismissRequest = { updateState = UpdateState.Idle },
                title = { Text(stringResource(R.string.update_available_title, state.release.version)) },
                text = {
                    // 更新说明可能很长：限定高度 + 可滚动
                    Column(
                        modifier = Modifier
                            .heightIn(max = 280.dp)
                            .verticalScroll(rememberScrollState())
                    ) {
                        Text(state.release.notes.ifBlank { stringResource(R.string.update_notes_empty) })
                    }
                },
                confirmButton = {
                    TextButton(onClick = {
                        updateState = UpdateState.Idle
                        openDownloads(context)
                    }) { Text(stringResource(R.string.update_go)) }
                },
                dismissButton = {
                    TextButton(onClick = { updateState = UpdateState.Idle }) {
                        Text(stringResource(R.string.update_later))
                    }
                }
            )
        }
        UpdateState.UpToDate -> {
            AlertDialog(
                onDismissRequest = { updateState = UpdateState.Idle },
                text = { Text(stringResource(R.string.update_latest)) },
                confirmButton = {
                    TextButton(onClick = { updateState = UpdateState.Idle }) { Text(stringResource(R.string.ok)) }
                }
            )
        }
        UpdateState.Failed -> {
            AlertDialog(
                onDismissRequest = { updateState = UpdateState.Idle },
                text = { Text(stringResource(R.string.update_failed)) },
                confirmButton = {
                    TextButton(onClick = { updateState = UpdateState.Idle }) { Text(stringResource(R.string.ok)) }
                }
            )
        }
        else -> {}
    }

    // 添加订阅对话框
    if (showAddSub) {
        var name by remember { mutableStateOf("") }
        var url by remember { mutableStateOf("") }
        AlertDialog(
            onDismissRequest = { showAddSub = false },
            title = { Text(stringResource(R.string.settings_add_subscription)) },
            text = {
                Column {
                    OutlinedTextField(value = name, onValueChange = { name = it },
                        label = { Text(stringResource(R.string.settings_sub_name)) }, singleLine = true)
                    Spacer(Modifier.height(8.dp))
                    OutlinedTextField(value = url, onValueChange = { url = it },
                        label = { Text(stringResource(R.string.settings_sub_url)) }, singleLine = true)
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
                ) { Text(stringResource(R.string.add)) }
            },
            dismissButton = {
                TextButton(onClick = { showAddSub = false }) { Text(stringResource(R.string.cancel)) }
            }
        )
    }
}

// 打开免责声明：根据当前语言跳中文版或英文版（与 iOS 端一致）
private fun openDisclaimer(context: Context) {
    try {
        val isZh = context.resources.configuration.locales[0].language == "zh"
        val anchor = if (isZh) "#免责声明" else "#disclaimer"
        val file = if (isZh) "README.md" else "README.en.md"
        context.startActivity(
            Intent(Intent.ACTION_VIEW, Uri.parse("https://github.com/GZYZhy/stream-radio/blob/main/$file$anchor"))
        )
    } catch (_: Exception) {
        // 无可用浏览器时静默忽略
    }
}

// 打开更新下载页：当前跳 GitHub releases，将来上架应用商店后改为商店链接
private fun openDownloads(context: Context) {
    try {
        context.startActivity(
            Intent(Intent.ACTION_VIEW, Uri.parse("https://github.com/GZYZhy/stream-radio/releases"))
        )
    } catch (_: Exception) {
        // 无可用浏览器时静默忽略
    }
}

// 检查更新状态
private sealed interface UpdateState {
    object Idle : UpdateState
    object Checking : UpdateState
    object UpToDate : UpdateState
    data class Available(val release: LatestRelease) : UpdateState
    object Failed : UpdateState
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
