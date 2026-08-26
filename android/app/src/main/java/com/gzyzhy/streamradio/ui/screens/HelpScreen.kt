package com.gzyzhy.streamradio.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HelpScreen(onBack: () -> Unit) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("帮助") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "返回")
                    }
                }
            )
        }
    ) { padding ->
        LazyColumn(modifier = Modifier.padding(padding)) {
            item { SectionHeader("快速上手") }
            item { HelpItem("播放电台", "点击电台即可开始播放") }
            item { HelpItem("搜索电台", "列表顶部搜索框，按名称/地址过滤") }
            item { HelpItem("节目信息", "当电台来源包含节目单时会自动展示") }

            item { SectionHeader("电台管理") }
            item { HelpItem("添加电台", "列表右上角「+」填写名称与播放地址") }
            item { HelpItem("本地导入", "列表右上角「⇩」选择 m3u 文件导入") }
            item { HelpItem("长按电台", "编辑 / 上移 / 下移 / 标星 / 删除") }
            item { HelpItem("右侧菜单", "点行尾三个点打开操作菜单") }

            item { SectionHeader("星标") }
            item { HelpItem("标星", "点击行尾星标图标即可收藏") }
            item { HelpItem("星标列表", "顶部菜单 → 星标图标查看收藏的电台") }

            item { SectionHeader("订阅") }
            item { HelpItem("入口", "设置 → 订阅") }
            item { HelpItem("添加订阅", "填写名称与 m3u 链接") }
            item { HelpItem("手动同步", "下载解析后按播放链接去重，只新增不重复的电台") }
            item { HelpItem("启动时同步", "打开后启动时自动拉取链接同步") }
            item { HelpItem("说明", "同步功能不会移除已存在的电台，仅新增不重复的电台") }

            item { SectionHeader("网络") }
            item { HelpItem("连通性检查", "设置 → 检查全部电台连通性") }
            item { HelpItem("删除电台", "可一键删除 / 单独删除失败的电台") }
            item { HelpItem("说明", "电台数量过多时检查可能需要较长时间") }

            item { SectionHeader("外观与其他") }
            item { HelpItem("深浅色", "设置 → 外观，跟随系统 / 浅色 / 深色") }
            item { HelpItem("后台播放", "通知栏可查看节目并切台") }
            item { HelpItem("质量指示", "播放页展示码率、格式、延迟、声道数信息") }

            item { Spacer(Modifier.height(24.dp)) }
        }
    }
}

@Composable
private fun HelpItem(title: String, desc: String) {
    ListItem(
        headlineContent = { Text(title) },
        supportingContent = { Text(desc, color = MaterialTheme.colorScheme.onSurfaceVariant) }
    )
}
