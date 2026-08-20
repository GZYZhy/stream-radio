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
        try? session.setActive(true)
    }

    func play(_ station: Station) {
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
        } else if currentStation != nil {
            player.play()
            isPlaying = true
        }
    }

    func stop() {
        statusObserver?.invalidate()
        statusObserver = nil
        metadataDelegate = nil
        metadataOutput = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        currentStation = nil
        isPlaying = false
        programTitle = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
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
        var info: [String: Any] = [MPMediaItemPropertyArtwork: Self.artwork]
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

    /// 刷新控制中心星标按钮的实心/空心状态
    private func refreshBookmarkState() {
        MPRemoteCommandCenter.shared().bookmarkCommand.isActive = currentStation?.isFavorite ?? false
    }

    /// 应用图标封面（来自 Assets 的 app-icon）
    private static let artwork: MPMediaItemArtwork = {
        MPMediaItemArtwork(boundsSize: CGSize(width: 512, height: 512)) { _ in
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
        // 星标（收藏）：锁屏/控制中心的星形按钮，实心=已收藏
        center.bookmarkCommand.addTarget { [weak self] _ in
            let me = self
            Task { @MainActor in me?.toggleFavoriteFromRemote() }
            return .success
        }
        center.bookmarkCommand.isActive = false
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
