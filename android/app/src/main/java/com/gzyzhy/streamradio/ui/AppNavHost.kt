package com.gzyzhy.streamradio.ui

import android.content.Context
import android.content.Intent
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import com.gzyzhy.streamradio.PlaybackState
import com.gzyzhy.streamradio.data.Station
import com.gzyzhy.streamradio.data.StationRepository
import com.gzyzhy.streamradio.data.Subscription
import com.gzyzhy.streamradio.service.RadioPlaybackService
import com.gzyzhy.streamradio.ui.screens.*
import com.gzyzhy.streamradio.util.SettingsManager
import androidx.compose.ui.Modifier
import kotlinx.coroutines.launch

// 导航路由
sealed class Screen(val route: String) {
    data object Stations : Screen("stations")
    data object Favorites : Screen("favorites")
    data object Settings : Screen("settings")
    data object Help : Screen("help")
    data object About : Screen("about")
}

@Composable
fun AppNavHost(
    navController: NavHostController,
    repo: StationRepository,
    settings: SettingsManager,
    stations: List<Station>,
    subscriptions: List<Subscription>,
    playbackState: PlaybackState
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var showPlayer by remember { mutableStateOf(false) }
    var importCandidates by remember { mutableStateOf<List<Station>?>(null) }

    NavHost(navController = navController, startDestination = Screen.Stations.route) {
        composable(Screen.Stations.route) {
            StationListScreen(
                repo = repo,
                stations = stations,
                playbackState = playbackState,
                onPlay = { station ->
                    startAndPlay(context, station, stations)
                    showPlayer = true
                },
                onImportResult = { candidates -> importCandidates = candidates },
                onNavigateToFavorites = { navController.navigate(Screen.Favorites.route) },
                onNavigateToSettings = { navController.navigate(Screen.Settings.route) },
                onOpenNowPlaying = { showPlayer = true }
            )
        }
        composable(Screen.Favorites.route) {
            FavoritesScreen(
                repo = repo,
                stations = stations.filter { it.isFavorite },
                playbackState = playbackState,
                onPlay = { station ->
                    startAndPlay(context, station, stations.filter { it.isFavorite })
                    showPlayer = true
                },
                onBack = { navController.popBackStack() }
            )
        }
        composable(Screen.Settings.route) {
            SettingsScreen(
                repo = repo,
                settings = settings,
                subscriptions = subscriptions,
                stations = stations,
                onBack = { navController.popBackStack() },
                onNavigateToHelp = { navController.navigate(Screen.Help.route) },
                onNavigateToAbout = { navController.navigate(Screen.About.route) }
            )
        }
        composable(Screen.Help.route) {
            HelpScreen(onBack = { navController.popBackStack() })
        }
        composable(Screen.About.route) {
            AboutScreen(onBack = { navController.popBackStack() })
        }
    }

    // 播放页
    if (showPlayer && playbackState.currentStation != null) {
        NowPlayingSheet(
            repo = repo,
            stations = stations,
            playbackState = playbackState,
            onDismiss = { showPlayer = false }
        )
    }

    // 导入预览
    importCandidates?.let { candidates ->
        ImportPreviewDialog(
            candidates = candidates,
            existingUrls = stations.map { it.url }.toSet(),
            onDismiss = { importCandidates = null },
            onConfirm = { selected ->
                scope.launch { repo.importSelected(selected) }
                importCandidates = null
            }
        )
    }
}

// 启动服务并播放（确保服务在前台运行）；sourceList 为换台队列来源（星标页传星标列表）
private fun startAndPlay(context: Context, station: Station, sourceList: List<Station>) {
    // 先启动前台服务，再调用播放
    val intent = Intent(context, RadioPlaybackService::class.java)
    context.startForegroundService(intent)
    RadioPlaybackService.playStation(station, sourceList)
}
