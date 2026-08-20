import AVFoundation
import MediaPlayer
import Observation
import UIKit

// 播放器：AVPlayer 播放 + 流内元数据节目信息 + 锁屏控制中心
@MainActor
@Observable
final class PlayerManager {
    var currentStation: Station?
    var isPlaying = false
    var programTitle: String?
    var errorMessage: String?

    // ---- 定时停播 ----
    /// 剩余秒数（nil 表示未设置）
    var sleepTimerRemaining: Int?
    /// 定时器
    private var sleepTimer: Timer?

    private let player = AVPlayer()
    private var statusObserver: NSKeyValueObservation?
    private var metadataOutput: AVPlayerItemMetadataOutput?
    private var metadataDelegate: MetadataDelegate?

    /// 控制中心切台时取电台列表（由 App 注入）
    var stationProvider: (() -> [Station])?

    /// 控制中心标星时切换当前台收藏（由 App 注入）
    var favoriteToggler: ((Station) -> Void)?

    init() {
        configureAudioSession()
        setupRemoteCommands()
    }

    /// 配置后台播放（需 Info.plist 开启 audio 后台模式，见 README）
    func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        // 异步激活会话，避免同步 API 在主线程阻塞（可能引起启动卡顿）；
        // iOS 27+ 用新异步 API，低版本回退同步 setActive
        if #available(iOS 27, *) {
            session.activate(options: []) { _, _ in }
        } else {
            try? session.setActive(true)
        }
    }

    /// 设置定时停播（分钟数，传 nil 取消）
    func setSleepTimer(minutes: Int?) {
        sleepTimer?.invalidate()
        sleepTimer = nil
        guard let minutes, minutes > 0 else {
            sleepTimerRemaining = nil
            return
        }
        sleepTimerRemaining = minutes * 60
        sleepTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickSleepTimer() }
        }
    }

    private func tickSleepTimer() {
        guard var remaining = sleepTimerRemaining, remaining > 0 else { return }
        remaining -= 1
        sleepTimerRemaining = remaining
        if remaining <= 0 {
            // 时间到：停止播放并清理定时器
            sleepTimer?.invalidate()
            sleepTimer = nil
            sleepTimerRemaining = nil
            stop()
        }
    }

    func play(_ station: Station) {
        // 换台不重置定时停播（用户设定保持到手动取消或到期）
        currentStation = station
        programTitle = nil
        errorMessage = nil
        guard let url = URL(string: station.url) else {
            errorMessage = "无效的播放地址"
            return
        }
        // 携带默认 UA 与 Icy-MetaData 请求头，让支持 ICY 的电台返回流内节目信息
        // （用字符串字面量而非 AVURLAssetHTTPHeaderFieldsKey，兼容各 SDK 命名）
        let asset = AVURLAsset(url: url, options: [
            "AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": "Radio-iOS/1.0", "Icy-MetaData": "1"],
        ])
        let item = AVPlayerItem(asset: asset)

        statusObserver?.invalidate()
        statusObserver = item.observe(\AVPlayerItem.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let message = item.error?.localizedDescription ?? "播放失败"
            // 先解到局部 let，避免 Swift 6 下捕获 weak var 进并发 Task
            let me = self
            Task { @MainActor in
                me?.isPlaying = false
                me?.errorMessage = message
            }
        }

        // 推送式监听流内元数据（ICY/ID3），换曲自动回调，无需轮询
        let delegate = MetadataDelegate()
        delegate.onTitle = { [weak self] title in
            self?.programTitle = title
            self?.updateNowPlaying()
        }
        let output = AVPlayerItemMetadataOutput()
        output.setDelegate(delegate, queue: .main)
        item.add(output)
        metadataDelegate = delegate
        metadataOutput = output

        player.replaceCurrentItem(with: item)
        player.play()
        isPlaying = true
        updateNowPlaying()
    }

    func toggle() {
        if player.timeControlStatus == .playing {
            player.pause()
            isPlaying = false
            updateNowPlaying()  // 同步播放速率到控制中心
        } else if let currentStation {
            // 已停止（currentItem 被清）或暂停：重新加载流并播放（按当时直播开播）
            play(currentStation)
        } else {
            return
        }
    }

    func stop() {
        statusObserver?.invalidate()
        statusObserver = nil
        metadataDelegate = nil
        metadataOutput = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        isPlaying = false
        programTitle = nil
        // 注意：保留 currentStation，方便用户点击播放按钮重新开播同一台
        // 停止播放时同步取消定时停播（否则用户再开播会继续计时）
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepTimerRemaining = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    /// 完全清空播放状态（切换台失败等场景使用）
    func reset() {
        stop()
        currentStation = nil
    }

    func next(in stations: [Station]) {
        guard let cur = currentStation, let i = stations.firstIndex(of: cur) else {
            if let first = stations.first { play(first) }
            return
        }
        play(stations[(i + 1) % stations.count])
    }

    func previous(in stations: [Station]) {
        guard let cur = currentStation, let i = stations.firstIndex(of: cur) else {
            if let first = stations.first { play(first) }
            return
        }
        play(stations[(i - 1 + stations.count) % stations.count])
    }

    /// 同步信息到锁屏 / 控制中心；封面使用应用图标
    private func updateNowPlaying() {
        guard let currentStation else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyArtwork: Self.artwork,
            // 系统据此推断播放/暂停状态，影响锁屏控制按钮的显示
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if let programTitle, !programTitle.isEmpty {
            // 有节目单：标题=节目，艺术家=电台
            info[MPMediaItemPropertyTitle] = programTitle
            info[MPMediaItemPropertyArtist] = currentStation.name
        } else {
            // 无节目单：标题=电台，艺术家=应用名
            info[MPMediaItemPropertyTitle] = currentStation.name
            info[MPMediaItemPropertyArtist] = "网络电台"
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        refreshBookmarkState()
    }

    /// 刷新收藏按钮的实心/空心状态
    /// currentStation 是值副本，收藏状态需从仓库按 URL 取最新值
    func refreshBookmarkState() {
        guard let cur = currentStation else {
            MPRemoteCommandCenter.shared().likeCommand.isActive = false
            return
        }
        let live = stationProvider?().first { $0.url == cur.url } ?? cur
        MPRemoteCommandCenter.shared().likeCommand.isActive = live.isFavorite
    }

    /// 应用图标封面（来自 Assets 的 app-icon）
    private static let artwork: MPMediaItemArtwork = {
        MPMediaItemArtwork(boundsSize: CGSize(width: 1024, height: 1024)) { _ in
            UIImage(named: "app-icon") ?? UIImage(systemName: "radio")!
        }
    }()

    /// 注册控制中心远程命令：播放 / 暂停 / 上下台
    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            let me = self
            Task { @MainActor in
                me?.player.play()
                me?.isPlaying = true
                me?.updateNowPlaying()
            }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            let me = self
            Task { @MainActor in
                me?.player.pause()
                me?.isPlaying = false
                me?.updateNowPlaying()
            }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            let me = self
            Task { @MainActor in me?.toggle() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            let me = self
            Task { @MainActor in me?.remoteNext() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            let me = self
            Task { @MainActor in me?.remotePrevious() }
            return .success
        }
        // 收藏（like）：锁屏/控制中心的收藏按钮，本系统渲染为星形（与网易云一致）
        center.likeCommand.addTarget { [weak self] _ in
            let me = self
            Task { @MainActor in me?.toggleFavoriteFromRemote() }
            return .success
        }
        center.likeCommand.isActive = false
    }

    /// 控制中心「标星」：切换当前台收藏并刷新按钮状态
    private func toggleFavoriteFromRemote() {
        guard let cur = currentStation else { return }
        favoriteToggler?(cur)
        refreshBookmarkState()
    }

    /// 控制中心「下一台」
    private func remoteNext() {
        let list = stationProvider?() ?? []
        guard !list.isEmpty else { return }
        next(in: list)
    }

    /// 控制中心「上一台」
    private func remotePrevious() {
        let list = stationProvider?() ?? []
        guard !list.isEmpty else { return }
        previous(in: list)
    }
}

// AVPlayerItemMetadataOutput 回调代理：提取标题型元数据
@MainActor
final class MetadataDelegate: NSObject, AVPlayerItemMetadataOutputPushDelegate {
    var onTitle: ((String) -> Void)?

    nonisolated func metadataOutput(_ output: AVPlayerItemMetadataOutput,
                                    didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup],
                                    from track: AVPlayerItemTrack?) {
        // 取第一个标题型元数据项
        guard let meta = groups.flatMap({ $0.items })
            .first(where: { $0.commonKey == .commonKeyTitle }) else { return }
        Task { @MainActor in
            if let text = try? await meta.load(.stringValue) {
                self.onTitle?(text)
            }
        }
    }
}
