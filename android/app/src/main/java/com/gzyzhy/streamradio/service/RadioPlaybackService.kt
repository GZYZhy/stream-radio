package com.gzyzhy.streamradio.service

import android.app.Notification
import android.app.NotificationChannel
import android.util.Log
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.drawable.BitmapDrawable
import android.os.Build
import android.view.KeyEvent
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.media.app.NotificationCompat.MediaStyle
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.session.MediaButtonReceiver
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import androidx.media3.session.SessionToken
import com.gzyzhy.streamradio.MainActivity
import com.gzyzhy.streamradio.R
import com.gzyzhy.streamradio.data.AudioQuality
import com.gzyzhy.streamradio.data.Station
import com.gzyzhy.streamradio.data.StationRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// 播放服务：前台服务 + MediaSession + ExoPlayer
class RadioPlaybackService : MediaSessionService() {

    private var mediaSession: MediaSession? = null
    private var player: ExoPlayer? = null
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    // 当前播放状态（供 UI 观察）
    companion object {
        @Volatile private var instance: RadioPlaybackService? = null
        // 服务尚未就绪时缓存的播放请求（含换台来源列表，点击播放时服务可能还在启动）
        private data class PendingPlay(val station: Station, val sourceList: List<Station>?)
        private var pendingStation: PendingPlay? = null

        var currentStation: Station? = null
        var isPlaying: Boolean = false
        var programTitle: String? = null
        var errorMessage: String? = null
        var audioQuality: AudioQuality? = null
        var latencyMs: Int? = null
        var sleepTimerRemaining: Int? = null

        private var listeners = mutableSetOf<PlaybackListener>()
        private var stationProvider: (() -> List<Station>)? = null
        private var favoriteToggler: ((Station) -> Unit)? = null

        fun addListener(l: PlaybackListener) { listeners.add(l) }
        fun removeListener(l: PlaybackListener) { listeners.remove(l) }
        fun setStationProvider(provider: () -> List<Station>) { stationProvider = provider }
        fun setFavoriteToggler(toggler: (Station) -> Unit) { favoriteToggler = toggler }

        // 播放控制（UI 调用入口）：服务未就绪时缓存，就绪后播放
        // sourceList 为换台队列来源（星标页传星标列表，否则传全部列表，对齐 iOS）
        fun playStation(station: Station, sourceList: List<Station>? = null) {
            val svc = instance
            if (svc != null) svc.play(station, sourceList) else pendingStation = PendingPlay(station, sourceList)
        }
        fun togglePlay() { instance?.toggle() }
        fun stopPlayback() { instance?.stop() }
        fun nextStation() { instance?.next() }
        fun previousStation() { instance?.previous() }
        fun setSleepTimer(minutes: Int?) { instance?.setSleepTimer(minutes) }
        fun toggleFavorite() { instance?.toggleFavorite() }

        private fun notifyChanged() {
            listeners.forEach { it.onPlaybackStateChanged() }
        }
    }

    interface PlaybackListener {
        fun onPlaybackStateChanged()
    }

    private var latencyStart: Long = 0
    private var sleepTimerJob: Job? = null
    private var qualityJob: Job? = null
    // 当前换台队列来源（星标页为星标列表，否则全部列表）
    private var currentSourceList: List<Station>? = null
    // 应用图标 PNG 缓存
    private var artworkData: ByteArray? = null

    override fun onCreate() {
        super.onCreate()
        instance = this

        // 创建通知渠道
        createNotificationChannel()

        // 立即进入前台（占位通知）：startForegroundService 启动后必须在 5 秒内
        // startForeground，否则系统抛 ForegroundServiceDidNotStartInTimeException 闪退。
        // 华为设备首次冷启动加载 Media3 较慢，且无 MediaController 连接时 Media3
        // 不一定及时触发 onUpdateNotification，故先占位，之后由 Media3 更新通知内容。
        ensureForeground()

        // 初始化 ExoPlayer，携带 ICY 请求头
        val dataSourceFactory = DefaultHttpDataSource.Factory()
            .setUserAgent("Radio-Android/1.0")
            .setDefaultRequestProperties(mapOf("Icy-MetaData" to "1"))

        player = ExoPlayer.Builder(this)
            .setMediaSourceFactory(DefaultMediaSourceFactory(this).setDataSourceFactory(dataSourceFactory))
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(C.USAGE_MEDIA)
                    .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
                    .build(),
                true
            )
            .build()

        // 电台列表循环播放，系统控制中心的上一台/下一台才能在末尾循环
        player?.repeatMode = Player.REPEAT_MODE_ALL

        player?.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(playbackState: Int) {
                refreshNotification()
                when (playbackState) {
                    Player.STATE_READY -> {
                        measureLatencyIfNeeded()
                        isPlaying = player?.playWhenReady == true
                        errorMessage = null
                        notifyChanged()
                    }
                    Player.STATE_BUFFERING -> {
                        errorMessage = null
                        notifyChanged()
                    }
                    Player.STATE_IDLE -> {
                        if (errorMessage != null) {
                            isPlaying = false
                            notifyChanged()
                        }
                    }
                    Player.STATE_ENDED -> {
                        isPlaying = false
                        notifyChanged()
                    }
                }
            }

            override fun onIsPlayingChanged(playing: Boolean) {
                isPlaying = playing
                refreshNotification()
                notifyChanged()
            }

            override fun onPlayerError(error: androidx.media3.common.PlaybackException) {
                errorMessage = error.message ?: "播放失败"
                isPlaying = false
                notifyChanged()
            }

            // 系统控制中心/播放列表切台时，同步当前电台状态
            override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
                val url = mediaItem?.localConfiguration?.uri?.toString()
                // 在来源列表里找（星标列表切台时保持星标范围）
                val s = currentSourceList?.firstOrNull { it.url == url }
                    ?: stationProvider?.invoke()?.firstOrNull { it.url == url }
                if (s != null && s.url != currentStation?.url) {
                    currentStation = s
                    programTitle = null
                    errorMessage = null
                    audioQuality = null
                    latencyMs = null
                    latencyStart = System.currentTimeMillis()
                    startQualityMonitoring()
                    refreshNotification()
                    notifyChanged()
                }
            }

            // 监听媒体元数据变化（ICY/ID3 节目信息）
            override fun onMediaMetadataChanged(mediaMetadata: MediaMetadata) {
                val title = mediaMetadata.title?.toString()
                if (!title.isNullOrEmpty() && title != currentStation?.name) {
                    programTitle = title
                    refreshNotification()
                    notifyChanged()
                }
            }
        })

        // MediaSession
        mediaSession = player?.let { p ->
            MediaSession.Builder(this, p)
                .setCallback(SessionCallback())
                .build()
        }

        // 会话创建后立即用带媒体样式的通知刷新前台通知，
        // 让系统控制中心尽快识别媒体会话（部分 ROM 依赖 MediaStyle 通知）
        ensureForeground(mediaSession)

        // 消费服务启动前缓存的播放请求（此时 player / mediaSession 已就绪）
        pendingStation?.let { play(it.station, it.sourceList) }
        pendingStation = null
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? = mediaSession

    // 确保服务处于前台：startForegroundService 后必须在 5 秒内 startForeground，
    // 停止后再次播放时服务已不在前台，也需重新进入前台，否则会再次超时崩溃。
    // session 不为空时用带媒体样式/媒体按钮的通知，否则用占位通知。
    private fun ensureForeground(session: MediaSession? = null) {
        startForeground(1001, buildNotification(session))
    }

    // 播放指定电台；sourceList 为换台队列来源（星标页传星标列表，否则用全部列表）
    fun play(station: Station, sourceList: List<Station>? = null) {
        try {
        currentStation = station
        ensureForeground(mediaSession)
        programTitle = null
        errorMessage = null
        audioQuality = null
        latencyMs = null
        latencyStart = System.currentTimeMillis()

        val p = player ?: return
        // 换台队列：优先调用方传入的来源列表，其次全部电台（对齐 iOS 的自适应换台）
        val list = sourceList?.takeIf { it.isNotEmpty() }
            ?: stationProvider?.invoke()
            ?: emptyList()
        currentSourceList = list
        val artwork = appIconArtwork()
        val index = list.indexOfFirst { it.url == station.url }
        if (index >= 0) {
            p.setMediaItems(
                list.map { buildMediaItem(it, artwork) },
                index,
                0L
            )
        } else {
            // 列表不可用或电台不在列表中：单曲播放
            p.setMediaItem(buildMediaItem(station, artwork))
        }
        p.prepare()
        p.playWhenReady = true
        isPlaying = true
        notifyChanged()

        // 启动质量检测
        startQualityMonitoring()
        } catch (e: Throwable) {
            Log.e("RadioPlaybackService", "播放异常", e)
            errorMessage = e.message ?: "播放失败"
            notifyChanged()
        }
    }

    // 构建播放队列项：台名做标题与副标题，封面恒用应用图标
    private fun buildMediaItem(s: Station, artwork: ByteArray?): MediaItem {
        val meta = MediaMetadata.Builder()
            .setTitle(s.name)
            .setArtist(s.name)
        artwork?.let { meta.setArtworkData(it) }
        return MediaItem.Builder()
            .setUri(s.url)
            .setMediaMetadata(meta.build())
            .build()
    }

    // 应用图标转 PNG 字节（缓存一次）
    private fun appIconArtwork(): ByteArray? {
        if (artworkData != null) return artworkData
        artworkData = try {
            val bmp = (ContextCompat.getDrawable(this, R.mipmap.ic_launcher) as? BitmapDrawable)?.bitmap
            bmp?.let {
                val out = java.io.ByteArrayOutputStream()
                it.compress(Bitmap.CompressFormat.PNG, 100, out)
                out.toByteArray()
            }
        } catch (e: Throwable) {
            null
        }
        return artworkData
    }

    fun toggle() {
        if (player?.isPlaying == true) {
            player?.pause()
            isPlaying = false
        } else {
            currentStation?.let {
                if (player?.currentMediaItem == null) {
                    play(it)
                } else {
                    player?.play()
                }
            }
        }
        notifyChanged()
    }

    fun stop() {
        player?.stop()
        player?.clearMediaItems()
        isPlaying = false
        programTitle = null
        audioQuality = null
        latencyMs = null
        qualityJob?.cancel()
        setSleepTimer(null)
        stopForeground(STOP_FOREGROUND_REMOVE)
        notifyChanged()
    }

    fun next() {
        val p = player ?: return
        if (p.mediaItemCount > 1) {
            // 播放列表模式：直接切下一台（系统控制中心同一入口）
            p.next()
        } else {
            // 单曲模式：基于电台列表手动切换
            val list = stationProvider?.invoke() ?: return
            if (list.isEmpty()) return
            val cur = currentStation ?: run { list.firstOrNull()?.let { play(it) }; return }
            val idx = list.indexOfFirst { it.url == cur.url }
            if (idx >= 0) {
                play(list[(idx + 1) % list.size])
            } else {
                list.firstOrNull()?.let { play(it) }
            }
        }
    }

    fun previous() {
        val p = player ?: return
        if (p.mediaItemCount > 1) {
            p.previous()
        } else {
            val list = stationProvider?.invoke() ?: return
            if (list.isEmpty()) return
            val cur = currentStation ?: run { list.firstOrNull()?.let { play(it) }; return }
            val idx = list.indexOfFirst { it.url == cur.url }
            if (idx >= 0) {
                play(list[(idx - 1 + list.size) % list.size])
            } else {
                list.firstOrNull()?.let { play(it) }
            }
        }
    }

    fun setSleepTimer(minutes: Int?) {
        sleepTimerJob?.cancel()
        sleepTimerJob = null
        sleepTimerRemaining = null
        if (minutes == null || minutes <= 0) {
            notifyChanged()
            return
        }
        sleepTimerRemaining = minutes * 60
        notifyChanged()
        sleepTimerJob = serviceScope.launch {
            while (sleepTimerRemaining != null && sleepTimerRemaining!! > 0) {
                delay(1000)
                sleepTimerRemaining = (sleepTimerRemaining ?: 0) - 1
                notifyChanged()
                if (sleepTimerRemaining != null && sleepTimerRemaining!! <= 0) {
                    stop()
                    break
                }
            }
        }
    }

    fun toggleFavorite() {
        currentStation?.let { favoriteToggler?.invoke(it) }
    }

    // 首次可播时计算延迟
    private fun measureLatencyIfNeeded() {
        if (latencyMs == null && latencyStart > 0) {
            latencyMs = (System.currentTimeMillis() - latencyStart).toInt()
            notifyChanged()
        }
    }

    // 说明：系统控制中心的元数据不手动设置（Media3 无 setMediaMetadata）。
    // 播放列表每一项的 title=台名、artist=台名；当流带 ICY 节目信息时，
    // ExoPlayer 自动把 title 覆盖为节目名，而 artist 保持台名，
    // 即实现 iOS 端"有节目名显示节目名、台名恒在副标题"的自适应。

    // 质量检测：定期读取音轨格式和码率
    private fun startQualityMonitoring() {
        qualityJob?.cancel()
        qualityJob = serviceScope.launch {
            try {
            val deadline = System.currentTimeMillis() + 8000
            while (System.currentTimeMillis() < deadline) {
                val p = player ?: break
                var quality = AudioQuality()

                // 从音频格式提取信息
                val trackGroups = p.currentTracks.groups
                for (group in trackGroups) {
                    if (group.type == C.TRACK_TYPE_AUDIO) {
                        val format = group.getTrackFormat(0)
                        quality = quality.copy(
                            codec = format.sampleMimeType?.let { codecName(it) },
                            sampleRateHz = if (format.sampleRate > 0) format.sampleRate else null,
                            channelCount = if (format.channelCount > 0) format.channelCount else null
                        )
                        break
                    }
                }

                // 码率估算
                if (quality.bitrateKbps == null) {
                    val bitrate = p.audioFormat?.bitrate ?: 0
                    if (bitrate > 0) {
                        quality = quality.copy(bitrateKbps = bitrate / 1000)
                    }
                }

                if (!quality.isEmpty) {
                    audioQuality = quality
                    notifyChanged()
                    break
                }
                delay(500)
            }
            } catch (e: Throwable) {
                Log.e("RadioPlaybackService", "质量检测异常", e)
            }
        }
    }

    private fun codecName(mimeType: String): String = when {
        mimeType.contains("mp3", true) || mimeType.contains("mpeg", true) -> "MP3"
        mimeType.contains("aac", true) || mimeType.contains("mp4a", true) -> "AAC"
        mimeType.contains("opus", true) -> "Opus"
        mimeType.contains("flac", true) -> "FLAC"
        mimeType.contains("alac", true) -> "ALAC"
        mimeType.contains("pcm", true) -> "PCM"
        else -> mimeType.substringAfterLast('/').uppercase()
    }

    // ---- 通知渠道 ----
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "playback_channel",
                getString(R.string.notification_channel_playback),
                NotificationManager.IMPORTANCE_LOW
            ).apply { description = "电台播放控制" }
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    override fun onUpdateNotification(session: MediaSession, startInForegroundRequired: Boolean) {
        val notification = buildNotification(session)
        if (startInForegroundRequired) {
            startForeground(1001, notification)
        }
    }

    private fun buildNotification(session: MediaSession?): Notification {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // 大小字自适应（对齐 iOS 锁屏）：有节目单时标题=节目名、副标题=台名；
        // 无节目单时标题=台名、副标题=网络电台
        val title = programTitle ?: (currentStation?.name ?: "网络电台")
        val text = programTitle?.let { currentStation?.name ?: "网络电台" } ?: "网络电台"
        val builder = NotificationCompat.Builder(this, "playback_channel")
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentIntent(pendingIntent)
            .setOngoing(true)                 // 前台服务通知，暂停时也保持媒体卡
            .setShowWhen(false)               // 媒体通知不显示时间戳
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC) // 锁屏也显示媒体卡

        // 媒体通知样式：让系统控制中心/锁屏识别媒体会话（部分 ROM 依赖 MediaStyle 才显示媒体卡片）
        if (session != null) {
            builder
                .setStyle(
                    MediaStyle()
                        .setMediaSession(session.sessionCompatToken)
                        .setShowActionsInCompactView(0, 1, 2)
                )
                .addAction(android.R.drawable.ic_media_previous, "上一台",
                    mediaButtonPendingIntent(KeyEvent.KEYCODE_MEDIA_PREVIOUS))
                .addAction(
                    if (isPlaying) android.R.drawable.ic_media_pause
                    else android.R.drawable.ic_media_play,
                    if (isPlaying) "暂停" else "播放",
                    mediaButtonPendingIntent(KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE)
                )
                .addAction(android.R.drawable.ic_media_next, "下一台",
                    mediaButtonPendingIntent(KeyEvent.KEYCODE_MEDIA_NEXT))
        }
        return builder.build()
    }

    // 主动刷新前台通知：节目名（ICY/ID3）或播放状态变化时，立即更新通知内容，
    // 让通知栏始终与节目单同步（仅靠 Media3 回调可能不及时）
    private fun refreshNotification() {
        val session = mediaSession ?: return
        try {
            (getSystemService(NotificationManager::class.java))
                .notify(1001, buildNotification(session))
        } catch (_: Throwable) {
        }
    }

    // 媒体按钮的 PendingIntent（广播转发给 MediaButtonReceiver → MediaSession）
    private fun mediaButtonPendingIntent(keyCode: Int): PendingIntent {
        val intent = Intent(this, MediaButtonReceiver::class.java).apply {
            action = Intent.ACTION_MEDIA_BUTTON
            putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
        }
        return PendingIntent.getBroadcast(this, keyCode, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    // MediaSession 回调（处理自定义动作）
    inner class SessionCallback : MediaSession.Callback {
        override fun onConnect(
            session: MediaSession,
            controller: MediaSession.ControllerInfo
        ): MediaSession.ConnectionResult {
            return super.onConnect(session, controller)
        }
    }

    override fun onDestroy() {
        instance = null
        mediaSession?.release()
        mediaSession = null
        player?.release()
        player = null
        super.onDestroy()
    }
}
