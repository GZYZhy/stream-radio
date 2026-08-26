package com.gzyzhy.streamradio.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.gzyzhy.streamradio.PlaybackState
import com.gzyzhy.streamradio.data.Station
import com.gzyzhy.streamradio.data.StationRepository
import com.gzyzhy.streamradio.ui.components.MiniPlayerBubble
import com.gzyzhy.streamradio.ui.components.StationRow
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FavoritesScreen(
    repo: StationRepository,
    stations: List<Station>,
    playbackState: PlaybackState,
    onPlay: (Station) -> Unit,
    onBack: () -> Unit
) {
    var showEditDialog by remember { mutableStateOf(false) }
    var editingStation by remember { mutableStateOf<Station?>(null) }
    val scope = rememberCoroutineScope()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("星标电台") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "返回")
                    }
                }
            )
        }
    ) { padding ->
        Box(modifier = Modifier.padding(padding)) {
            if (stations.isEmpty()) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Icon(
                            Icons.Default.Star, null,
                            modifier = Modifier.size(64.dp),
                            tint = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        Spacer(Modifier.height(16.dp))
                        Text("暂无星标电台", color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text("在电台列表中点击星标即可收藏",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            } else {
                LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(bottom = 80.dp)
                ) {
                    items(stations, key = { it.id }) { station ->
                        StationRow(
                            station = station,
                            isCurrent = playbackState.currentStation?.url == station.url,
                            onPlay = { onPlay(station) },
                            onEdit = { editingStation = station; showEditDialog = true },
                            onToggleFavorite = { scope.launch { repo.toggleFavorite(station) } },
                            onDelete = { scope.launch { repo.remove(listOf(station)) } },
                            onMoveUp = { },
                            onMoveDown = { }
                        )
                    }
                }
            }

            if (playbackState.currentStation != null) {
                MiniPlayerBubble(
                    modifier = Modifier
                        .align(Alignment.BottomEnd)
                        .padding(16.dp),
                    isPlaying = playbackState.isPlaying,
                    onClick = { }
                )
            }
        }
    }

    // 编辑对话框
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
                    label = { Text("名称") }, singleLine = true
                )
                Spacer(Modifier.height(8.dp))
                OutlinedTextField(
                    value = url, onValueChange = { url = it },
                    label = { Text("播放地址") }, singleLine = true
                )
            }},
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
