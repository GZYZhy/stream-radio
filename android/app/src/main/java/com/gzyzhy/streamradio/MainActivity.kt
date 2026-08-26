package com.gzyzhy.streamradio

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.sp
import androidx.navigation.compose.rememberNavController
import com.gzyzhy.streamradio.data.StationRepository
import com.gzyzhy.streamradio.service.RadioPlaybackService
import com.gzyzhy.streamradio.ui.AppNavHost
import com.gzyzhy.streamradio.ui.theme.StreamRadioTheme
import com.gzyzhy.streamradio.util.LocaleHelper
import com.gzyzhy.streamradio.util.SettingsManager
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking

class MainActivity : ComponentActivity() {

    // 应用语言设置（重启生效）：在基础 context 上应用所选语言后再传给 super
    override fun attachBaseContext(newBase: Context?) {
        val base = newBase ?: return super.attachBaseContext(newBase)
        val lang = try {
            runBlocking { LocaleHelper.getAppLanguage(base) }
        } catch (_: Exception) {
            "system"
        }
        super.attachBaseContext(LocaleHelper.applyLanguage(base, lang))
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 请求通知权限（Android 13+ 必需）：系统控制中心只对已授予通知权限的
        // 应用显示媒体卡片，不请求则通知栏与控制中心都看不到媒体控件。
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1001)
        }
        setContent {
            val context = LocalContext.current
            val scope = rememberCoroutineScope()
            val repo = remember { StationRepository.get(context) }
            val stations by repo.stationsFlow.collectAsState(initial = emptyList())
            val subscriptions by repo.subscriptionsFlow.collectAsState(initial = emptyList())

            val settings = remember { SettingsManager(context) }
            val appearanceMode by settings.appearanceMode.collectAsState(initial = "system")
            val autoSync by settings.autoSyncOnLaunch.collectAsState(initial = false)

            // 播放状态
            var playbackState by remember { mutableStateOf(PlaybackState()) }
            val listener = remember {
                object : RadioPlaybackService.PlaybackListener {
                    override fun onPlaybackStateChanged() {
                        playbackState = PlaybackState(
                            currentStation = RadioPlaybackService.currentStation,
                            isPlaying = RadioPlaybackService.isPlaying,
                            programTitle = RadioPlaybackService.programTitle,
                            errorMessage = RadioPlaybackService.errorMessage,
                            audioQuality = RadioPlaybackService.audioQuality,
                            latencyMs = RadioPlaybackService.latencyMs,
                            sleepTimerRemaining = RadioPlaybackService.sleepTimerRemaining
                        )
                    }
                }
            }

            LaunchedEffect(Unit) {
                RadioPlaybackService.setStationProvider { stations }
                RadioPlaybackService.setFavoriteToggler { station ->
                    scope.launch { repo.toggleFavorite(station) }
                }
                RadioPlaybackService.addListener(listener)

                if (autoSync) {
                    repo.syncAllSubscriptions()
                }
            }

            DisposableEffect(Unit) {
                onDispose { RadioPlaybackService.removeListener(listener) }
            }

            // 当 stations 变化时重新设置 provider
            LaunchedEffect(stations) {
                RadioPlaybackService.setStationProvider { stations }
            }

            StreamRadioTheme(mode = appearanceMode) {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background
                ) {
                    val navController = rememberNavController()
                    AppNavHost(
                        navController = navController,
                        repo = repo,
                        settings = settings,
                        stations = stations,
                        subscriptions = subscriptions,
                        playbackState = playbackState
                    )
                }
            }
            // 崩溃诊断弹窗
            CrashReportDialog()
        }
    }
}

// 崩溃诊断弹窗：展示上次闪退的堆栈（仅诊断用，可截图反馈后清除）
@Composable
private fun CrashReportDialog() {
    val context = LocalContext.current
    var showDialog by remember { mutableStateOf(false) }
    val crash = remember {
        context.getSharedPreferences("crash_report", Context.MODE_PRIVATE)
            .getString("last_crash", null)
    }
    LaunchedEffect(crash) { if (crash != null) showDialog = true }
    if (showDialog && crash != null) {
        AlertDialog(
            onDismissRequest = { },
            title = { Text(stringResource(R.string.crash_report_title)) },
            text = {
                Text(
                    text = crash,
                    fontSize = 10.sp,
                    maxLines = 40,
                    overflow = TextOverflow.Ellipsis
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    context.getSharedPreferences("crash_report", Context.MODE_PRIVATE)
                        .edit().clear().commit()
                    showDialog = false
                }) { Text(stringResource(R.string.crash_report_close)) }
            }
        )
    }
}

// 播放状态快照
data class PlaybackState(
    val currentStation: com.gzyzhy.streamradio.data.Station? = null,
    val isPlaying: Boolean = false,
    val programTitle: String? = null,
    val errorMessage: String? = null,
    val audioQuality: com.gzyzhy.streamradio.data.AudioQuality? = null,
    val latencyMs: Int? = null,
    val sleepTimerRemaining: Int? = null
)
