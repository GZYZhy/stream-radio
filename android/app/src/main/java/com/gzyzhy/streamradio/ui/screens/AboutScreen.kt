package com.gzyzhy.streamradio.ui.screens

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import com.gzyzhy.streamradio.R

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AboutScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    // 读取实际安装版本号（与 iOS 版本保持一致）
    @Suppress("DEPRECATION")
    val versionName = remember {
        context.packageManager.getPackageInfo(context.packageName, 0).versionName ?: "1.0"
    }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("关于") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "返回")
                    }
                }
            )
        }
    ) { padding ->
        LazyColumn(modifier = Modifier.padding(padding)) {
            item {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 32.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Image(
                        painter = painterResource(R.mipmap.ic_launcher),
                        contentDescription = null,
                        modifier = Modifier.size(96.dp)
                    )
                    Spacer(Modifier.height(12.dp))
                    Text("网络电台", style = MaterialTheme.typography.titleLarge)
                }
            }

            item { SectionHeader("信息") }
            item {
                ListItem(
                    headlineContent = { Text("版本") },
                    supportingContent = { Text("$versionName (Android)") }
                )
            }
            item {
                ListItem(
                    headlineContent = { Text("作者") },
                    supportingContent = { Text("GZYZhy") }
                )
            }
            item {
                ListItem(
                    headlineContent = { Text("许可证") },
                    supportingContent = { Text("MIT") }
                )
            }
            item {
                ListItem(
                    headlineContent = { Text("GitHub 仓库") },
                    supportingContent = { Text("github.com/GZYZhy/stream-radio") }
                )
            }
            item {
                ListItem(
                    headlineContent = { Text("作者博客") },
                    supportingContent = { Text("www.zdeweb.cn") }
                )
            }

            item { SectionHeader("说明") }
            item {
                ListItem(
                    headlineContent = {
                        Text(
                            "极简原生网络电台播放器，支持电台播放、收藏、m3u 导入订阅、节目信息显示、通知栏控制等功能。\n\n" +
                                    "本程序不运营、不存储、不提供任何音频内容，所有播放能力仅面向用户自行添加的音频流地址。\n" +
                                    "电台质量与网络环境和电台来源有关，请自行添加拥有合法授权的音源。\n\n" +
                                    "© 2026 GZYZhy",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                )
            }

            item { Spacer(Modifier.height(24.dp)) }
        }
    }
}
