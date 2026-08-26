package com.gzyzhy.streamradio.ui.screens

import android.content.Context
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.dp
import com.gzyzhy.streamradio.PlaybackState
import com.gzyzhy.streamradio.data.M3UParser
import com.gzyzhy.streamradio.data.Station
import com.gzyzhy.streamradio.data.StationRepository
import com.gzyzhy.streamradio.ui.components.MiniPlayerBubble
import com.gzyzhy.streamradio.ui.components.StationRow
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.InputStreamReader

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StationListScreen(
    repo: StationRepository,
    stations: List<Station>,
    playbackState: PlaybackState,
    onPlay: (Station) -> Unit,
    onImportResult: (List<Station>) -> Unit,
    onNavigateToFavorites: () -> Unit,
    onNavigateToSettings: () -> Unit,
    onOpenNowPlaying: () -> Unit
) {
    val context = LocalContext.current
    var searchText by rememberSaveable(stateSaver = TextFieldValue.Saver) {
        mutableStateOf(TextFieldValue(""))
    }
    var showAddDialog by remember { mutableStateOf(false) }
    var showEditDialog by remember { mutableStateOf(false) }
    var editingStation by remember { mutableStateOf<Station?>(null) }
    val scope = rememberCoroutineScope()

    val filtered = remember(stations, searchText.text) {
        val kw = searchText.text.trim().lowercase()
        if (kw.isEmpty()) stations
        else stations.filter {
            it.name.lowercase().contains(kw) || it.url.lowercase().contains(kw)
        }
    }

    // m3u 文件导入
    val importLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocument()
    ) { uri: Uri? ->
        uri ?: return@rememberLauncherForActivityResult
        scope.launch {
            val candidates = parseM3UFromUri(context, uri)
            if (candidates.isNotEmpty()) {
                onImportResult(candidates)
            }
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("全部电台") },
                actions = {
                    IconButton(onClick = { showAddDialog = true }) {
                        Icon(Icons.Default.Add, contentDescription = "添加")
                    }
                    IconButton(onClick = { importLauncher.launch(arrayOf("*/*")) }) {
                        Icon(Icons.Default.Download, contentDescription = "导入")
                    }
                    IconButton(onClick = onNavigateToFavorites) {
                        Icon(Icons.Default.Star, contentDescription = "星标")
                    }
                    IconButton(onClick = onNavigateToSettings) {
                        Icon(Icons.Default.Settings, contentDescription = "设置")
                    }
                }
            )
        }
    ) { padding ->
        Box(modifier = Modifier.padding(padding)) {
            Column {
                // 搜索框
                OutlinedTextField(
                    value = searchText,
                    onValueChange = { searchText = it },
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 8.dp),
                    placeholder = { Text("搜索电台…") },
                    leadingIcon = { Icon(Icons.Default.Search, null) },
                    singleLine = true
                )

                if (filtered.isEmpty()) {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Text("暂无电台，点右上角 + 添加",
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                } else {
                    LazyColumn(
                        modifier = Modifier.fillMaxSize(),
                        contentPadding = PaddingValues(bottom = 80.dp)
                    ) {
                        items(filtered, key = { it.id }) { station ->
                            StationRow(
                                station = station,
                                isCurrent = playbackState.currentStation?.url == station.url,
                                onPlay = { onPlay(station) },
                                onEdit = { editingStation = station; showEditDialog = true },
                                onToggleFavorite = { scope.launch { repo.toggleFavorite(station) } },
                                onDelete = { scope.launch { repo.remove(listOf(station)) } },
                                onMoveUp = { scope.launch { repo.moveUp(station) } },
                                onMoveDown = { scope.launch { repo.moveDown(station) } }
                            )
                        }
                    }
                }
            }

            // 右下角悬浮球
            if (playbackState.currentStation != null) {
                MiniPlayerBubble(
                    modifier = Modifier
                        .align(Alignment.BottomEnd)
                        .padding(16.dp),
                    isPlaying = playbackState.isPlaying,
                    onClick = onOpenNowPlaying
                )
            }
        }
    }

    // 添加电台对话框
    if (showAddDialog) {
        var name by remember { mutableStateOf("") }
        var url by remember { mutableStateOf("") }
        AlertDialog(
            onDismissRequest = { showAddDialog = false },
            title = { Text("添加电台") },
            text = {
                Column {
                    OutlinedTextField(
                        value = name, onValueChange = { name = it },
                        label = { Text("名称") }, singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                    Spacer(Modifier.height(8.dp))
                    OutlinedTextField(
                        value = url, onValueChange = { url = it },
                        label = { Text("播放地址") }, singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        val n = name.trim()
                        val u = url.trim()
                        if (n.isNotEmpty() && u.isNotEmpty()) {
                            scope.launch {
                                repo.add(Station(name = n, url = u))
                                showAddDialog = false
                            }
                        }
                    },
                    enabled = name.trim().isNotEmpty() && url.trim().isNotEmpty()
                ) { Text("添加") }
            },
            dismissButton = {
                TextButton(onClick = { showAddDialog = false }) { Text("取消") }
            }
        )
    }

    // 编辑电台对话框
    if (showEditDialog && editingStation != null) {
        var name by remember { mutableStateOf(editingStation!!.name) }
        var url by remember { mutableStateOf(editingStation!!.url) }
        AlertDialog(
            onDismissRequest = { showEditDialog = false },
            title = { Text("编辑电台") },
            text = {
                Column {
                    OutlinedTextField(
                        value = name, onValueChange = { name = it },
                        label = { Text("名称") }, singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                    Spacer(Modifier.height(8.dp))
                    OutlinedTextField(
                        value = url, onValueChange = { url = it },
                        label = { Text("播放地址") }, singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        scope.launch {
                            repo.update(editingStation!!, name, url)
                            showEditDialog = false
                        }
                    },
                    enabled = name.trim().isNotEmpty()
                ) { Text("保存") }
            },
            dismissButton = {
                TextButton(onClick = { showEditDialog = false }) { Text("取消") }
            }
        )
    }
}

// 从 Uri 读取并解析 m3u
suspend fun parseM3UFromUri(context: Context, uri: Uri): List<Station> =
    withContext(Dispatchers.IO) {
        try {
            context.contentResolver.openInputStream(uri)?.use { input ->
                val text = InputStreamReader(input).readText()
                M3UParser.parse(text)
            } ?: emptyList()
        } catch (e: Exception) {
            emptyList()
        }
    }
