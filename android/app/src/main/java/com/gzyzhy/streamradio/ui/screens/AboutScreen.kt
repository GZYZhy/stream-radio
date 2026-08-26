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
import androidx.compose.ui.res.stringResource
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
                title = { Text(stringResource(R.string.about_title)) },
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
                    Text(stringResource(R.string.app_name), style = MaterialTheme.typography.titleLarge)
                }
            }

            item { SectionHeader(stringResource(R.string.about_section_info)) }
            item {
                ListItem(
                    headlineContent = { Text(stringResource(R.string.about_version)) },
                    supportingContent = { Text("$versionName (Android)") }
                )
            }
            item {
                ListItem(
                    headlineContent = { Text(stringResource(R.string.about_author)) },
                    supportingContent = { Text("GZYZhy") }
                )
            }
            item {
                ListItem(
                    headlineContent = { Text(stringResource(R.string.about_license)) },
                    supportingContent = { Text("MIT") }
                )
            }
            item {
                ListItem(
                    headlineContent = { Text(stringResource(R.string.about_github)) },
                    supportingContent = { Text("github.com/GZYZhy/stream-radio") }
                )
            }
            item {
                ListItem(
                    headlineContent = { Text(stringResource(R.string.about_blog)) },
                    supportingContent = { Text("www.zdeweb.cn") }
                )
            }

            item { SectionHeader(stringResource(R.string.about_section_description)) }
            item {
                ListItem(
                    headlineContent = {
                        Text(
                            stringResource(R.string.about_description),
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
