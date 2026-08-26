package com.gzyzhy.streamradio.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.Star
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.gzyzhy.streamradio.PlaybackState
import com.gzyzhy.streamradio.R
import com.gzyzhy.streamradio.data.Station
import com.gzyzhy.streamradio.data.StationRepository
import com.gzyzhy.streamradio.service.RadioPlaybackService
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.*

// 播放页（底部 sheet）
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NowPlayingSheet(
    repo: StationRepository,
    stations: List<Station>,
    playbackState: PlaybackState,
    onDismiss: () -> Unit
) {
    // 优先从 stations（随 repo 实时刷新）里取最新的 station，
    // 确保标星等状态变化时 UI 能同步更新（playbackState 里的是服务副本，不会自动刷新）
    val rawStation = playbackState.currentStation ?: return
    val station = stations.firstOrNull { it.url == rawStation.url } ?: rawStation
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    // 当前时间（每秒刷新）
    var currentTime by remember { mutableStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) {
        while (true) {
            currentTime = System.currentTimeMillis()
            kotlinx.coroutines.delay(1000)
        }
    }

    val timeFormat = remember {
        SimpleDateFormat("yyyy年M月d日 HH:mm:ss", Locale.CHINA)
    }

    var showSleepMenu by remember { mutableStateOf(false) }
    var showCustomSleep by remember { mutableStateOf(false) }
    var customMinutes by remember { mutableStateOf("") }
    var showQualityHelp by remember { mutableStateOf(false) }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        shape = RoundedCornerShape(topStart = 20.dp, topEnd = 20.dp)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 24.dp)
                .padding(bottom = 48.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            // 顶部保留 ModalBottomSheet 默认拖拽横线即可，下滑或点外部收起
            Spacer(Modifier.height(16.dp))

            // 图标
            Icon(
                Icons.Default.Radio,
                contentDescription = null,
                modifier = Modifier.size(72.dp),
                tint = MaterialTheme.colorScheme.primary
            )
            Spacer(Modifier.height(20.dp))

            // 电台名
            Text(
                station.name,
                style = MaterialTheme.typography.titleLarge,
                textAlign = TextAlign.Center
            )
            Spacer(Modifier.height(4.dp))

            // 节目信息
            Text(
                playbackState.programTitle ?: stringResource(R.string.now_playing_connecting),
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center
            )

            Spacer(Modifier.height(16.dp))

            // 时间 + 质量
            Column(horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier.padding(vertical = 8.dp)) {
                Text(
                    timeFormat.format(Date(currentTime)),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Spacer(Modifier.height(4.dp))

                // 质量信息
                val quality = playbackState.audioQuality
                if (quality != null && !quality.isEmpty) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            quality.summary(context),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        playbackState.latencyMs?.let { latency ->
                            Spacer(Modifier.width(6.dp))
                            Text(
                                stringResource(R.string.now_playing_latency, latency),
                                style = MaterialTheme.typography.bodySmall,
                                color = latencyColor(latency)
                            )
                        }
                        IconButton(onClick = { showQualityHelp = true }, modifier = Modifier.size(20.dp)) {
                            Icon(
                                Icons.Default.Info,
                                contentDescription = "说明",
                                modifier = Modifier.size(16.dp),
                                tint = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                }

                // 定时停播
                playbackState.sleepTimerRemaining?.let { remaining ->
                    Spacer(Modifier.height(4.dp))
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            Icons.Default.Timer,
                            contentDescription = null,
                            modifier = Modifier.size(14.dp),
                            tint = MaterialTheme.colorScheme.primary
                        )
                        Spacer(Modifier.width(4.dp))
                        Text(
                            stringResource(R.string.sleep_timer_remaining, formatRemaining(remaining)),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.primary
                        )
                    }
                }
            }

            // 错误信息
            playbackState.errorMessage?.let { err ->
                Spacer(Modifier.height(8.dp))
                Text(err, color = MaterialTheme.colorScheme.error, fontSize = 12.sp)
            }

            Spacer(Modifier.height(32.dp))

            // 控制按钮
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(48.dp)
            ) {
                IconButton(
                    onClick = { RadioPlaybackService.previousStation() },
                    modifier = Modifier.size(48.dp)
                ) {
                    Icon(Icons.Default.SkipPrevious, contentDescription = "上一台",
                        modifier = Modifier.size(32.dp))
                }
                IconButton(
                    onClick = { RadioPlaybackService.togglePlay() },
                    modifier = Modifier.size(80.dp)
                ) {
                    Icon(
                        if (playbackState.isPlaying) Icons.Default.PauseCircle
                        else Icons.Default.PlayCircle,
                        contentDescription = if (playbackState.isPlaying) "暂停" else "播放",
                        modifier = Modifier.size(64.dp),
                        tint = MaterialTheme.colorScheme.primary
                    )
                }
                IconButton(
                    onClick = { RadioPlaybackService.nextStation() },
                    modifier = Modifier.size(48.dp)
                ) {
                    Icon(Icons.Default.SkipNext, contentDescription = "下一台",
                        modifier = Modifier.size(32.dp))
                }
            }

            Spacer(Modifier.height(24.dp))

            // 标星 + 定时
            Row(
                horizontalArrangement = Arrangement.spacedBy(32.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                TextButton(onClick = {
                    scope.launch {
                        repo.toggleFavorite(station)
                    }
                }) {
                    Icon(
                        if (station.isFavorite) Icons.Filled.Star else Icons.Outlined.Star,
                        contentDescription = null,
                        tint = if (station.isFavorite) MaterialTheme.colorScheme.tertiary
                        else MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Spacer(Modifier.width(4.dp))
                    Text(
                        if (station.isFavorite) stringResource(R.string.favorited)
                        else stringResource(R.string.favorite),
                        color = if (station.isFavorite) MaterialTheme.colorScheme.tertiary
                        else MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }

                TextButton(onClick = { showSleepMenu = true }) {
                    val active = playbackState.sleepTimerRemaining != null
                    Icon(
                        Icons.Default.Timer,
                        contentDescription = null,
                        tint = if (active) MaterialTheme.colorScheme.primary
                        else MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Spacer(Modifier.width(4.dp))
                    Text(
                        if (active) stringResource(R.string.sleep_timer_active)
                        else stringResource(R.string.sleep_timer_title),
                        color = if (active) MaterialTheme.colorScheme.primary
                        else MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }

            Spacer(Modifier.height(16.dp))
        }
    }

    // 定时停播菜单
    if (showSleepMenu) {
        AlertDialog(
            onDismissRequest = { showSleepMenu = false },
            title = { Text(stringResource(R.string.sleep_timer_title)) },
            text = {
                Column {
                    if (playbackState.sleepTimerRemaining != null) {
                        Text(stringResource(R.string.sleep_timer_remaining_text,
                            formatRemaining(playbackState.sleepTimerRemaining!!)),
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Spacer(Modifier.height(8.dp))
                    } else {
                        Text(stringResource(R.string.sleep_timer_hint),
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Spacer(Modifier.height(8.dp))
                    }
                    val presets = listOf(10, 15, 30, 45, 60, 90, 120)
                    presets.forEach { min ->
                        TextButton(
                            onClick = {
                                RadioPlaybackService.setSleepTimer(min)
                                showSleepMenu = false
                            },
                            modifier = Modifier.fillMaxWidth()
                        ) { Text(stringResource(R.string.sleep_timer_minutes, min)) }
                    }
                    TextButton(
                        onClick = {
                            showSleepMenu = false
                            showCustomSleep = true
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) { Text(stringResource(R.string.sleep_timer_custom)) }
                    if (playbackState.sleepTimerRemaining != null) {
                        TextButton(
                            onClick = {
                                RadioPlaybackService.setSleepTimer(null)
                                showSleepMenu = false
                            },
                            modifier = Modifier.fillMaxWidth(),
                            colors = ButtonDefaults.textButtonColors(
                                contentColor = MaterialTheme.colorScheme.error
                            )
                        ) { Text(stringResource(R.string.sleep_timer_cancel)) }
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = { showSleepMenu = false }) { Text(stringResource(R.string.ok)) }
            }
        )
    }

    // 自定义定时
    if (showCustomSleep) {
        var input by remember { mutableStateOf("") }
        AlertDialog(
            onDismissRequest = { showCustomSleep = false },
            title = { Text(stringResource(R.string.sleep_timer_custom_title)) },
            text = {
                Column {
                    Text(stringResource(R.string.sleep_timer_custom_hint))
                    Spacer(Modifier.height(8.dp))
                    TextField(
                        value = input,
                        onValueChange = { input = it.filter { c -> c.isDigit() } },
                        label = { Text(stringResource(R.string.minutes)) },
                        singleLine = true
                    )
                }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        input.toIntOrNull()?.let {
                            if (it > 0) {
                                RadioPlaybackService.setSleepTimer(it)
                            }
                        }
                        showCustomSleep = false
                    }
                ) { Text(stringResource(R.string.confirm)) }
            },
            dismissButton = {
                TextButton(onClick = { showCustomSleep = false }) { Text(stringResource(R.string.cancel)) }
            }
        )
    }

    // 质量说明
    if (showQualityHelp) {
        AlertDialog(
            onDismissRequest = { showQualityHelp = false },
            title = { Text(stringResource(R.string.quality_help_title)) },
            text = { Text(stringResource(R.string.quality_help_message)) },
            confirmButton = {
                TextButton(onClick = { showQualityHelp = false }) {
                    Text(stringResource(R.string.quality_help_got_it))
                }
            }
        )
    }
}

// 延迟颜色
fun latencyColor(ms: Int): Color = when {
    ms < 150 -> Color(0xFF34C759)
    ms < 300 -> Color(0xFFFFCC00)
    ms < 600 -> Color(0xFFFF9500)
    else -> Color(0xFFFF3B30)
}

// 秒数格式化为 mm:ss
fun formatRemaining(seconds: Int): String {
    val m = seconds / 60
    val s = seconds % 60
    return String.format("%02d:%02d", m, s)
}
