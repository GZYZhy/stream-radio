import AVFoundation
import CoreMedia
import MediaPlayer
import Observation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// 音频质量信息（由音轨格式 / 码率 / 采样率 / 声道汇总）
struct AudioQuality: Equatable {
    var codec: String?
    var bitrateKbps: Int?
    var sampleRateHz: Int?
    var channelCount: Int?

    /// 展示摘要：未知字段省略，用 · 连接（如 "MP3 · 128 kbps · 44.1 kHz · 立体声"）
    var summary: String {
        var parts: [String] = []
        if let codec { parts.append(codec) }
        if let bitrateKbps { parts.append("\(bitrateKbps) kbps") }
        if let sampleRateHz { parts.append(Self.formatSampleRate(sampleRateHz)) }
        if let channelCount { parts.append(Self.channelText(channelCount)) }
        return parts.joined(separator: " · ")
    }

    var isEmpty: Bool { summary.isEmpty }

    static func formatSampleRate(_ hz: Int) -> String {
        if hz % 1000 == 0 { return "\(hz / 1000) kHz" }
        return String(format: "%g kHz", Double(hz) / 1000)
    }

    static func channelText(_ n: Int) -> String {
        switch n {
        case 1: return "单声道"
        case 2: return "立体声"
        default: return "\(n) 声道"
        }
    }
}

// 播放器：AVPlayer 播放 + 流内元数据节目信息 + 锁屏控制中心
@MainActor
@Observable
final class PlayerManager {
    var currentStation: Station?
    var isPlaying = false
    var programTitle: String?
    var errorMessage: String?
    /// 播放质量（编码/码率/采样率/声道）
    var audioQuality: AudioQuality?
    /// 启动/缓冲延迟（毫秒，nil 表示未测到）
    var latencyMs: Int?

    // ---- 定时停播 ----
    /// 剩余秒数（nil 表示未设置）
    var sleepTimerRemaining: Int?
    /// 定时器
    private var sleepTimer: Timer?

    private let player = AVPlayer()
    private var statusObserver: NSKeyValueObservation?
    private var metadataOutput: AVPlayerItemMetadataOutput?
    private var metadataDelegate: MetadataDelegate?
    /// 测延迟用：播放发起时刻与首次可播状态观察
    private var latencyStart: Date?
    private var timeControlObserver: NSKeyValueObservation?

    /// 控制中心切台时取电台列表（由 App 注入）
    var stationProvider: (() -> [Station])?

    /// 控制中心标星时切换当前台收藏（由 App 注入）
    var favoriteToggler: ((Station) -> Void)?

    init() {
        #if os(iOS)
        configureAudioSession()
        #endif
        setupRemoteCommands()
    }

    #if os(iOS)
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
    #endif

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
            Task { @MainActor [weak self] in self?.tickSleepTimer() }
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
        // 重置质量并开始测启动/缓冲延迟
        audioQuality = nil
        latencyMs = nil
        latencyStart = Date()
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

        // 观察首次进入可播状态（.playing），用于计算启动/缓冲延迟
        timeControlObserver?.invalidate()
        timeControlObserver = player.observe(\AVPlayer.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.measureLatencyIfNeeded() }
        }

        player.replaceCurrentItem(with: item)
        player.play()
        isPlaying = true
        updateNowPlaying()

        // 后台读取音轨格式：编码 / 采样率 / 声道 / 码率（最多等约 3 秒）
        Task { [weak self] in
            await self?.loadAudioQuality(for: asset)
        }
    }

    /// 等音轨就绪后提取质量字段；网络流元数据可能延迟填充，最多重试约 8 秒。
    /// 多来源放宽：实际播放音轨格式描述 → asset 静态音轨 → 访问日志码率 → 估计数据率。
    private func loadAudioQuality(for asset: AVURLAsset) async {
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            var q = AudioQuality()
            // 音轨格式描述：优先实际播放音轨（HLS 缓冲后必填），其次 asset 静态音轨
            var audioTrack: AVAssetTrack?
            if let live = player.currentItem?.tracks.compactMap(\.assetTrack)
                .first(where: { $0.mediaType == .audio }) {
                audioTrack = live
            } else {
                audioTrack = try? await asset.loadTracks(withMediaType: .audio).first
            }
            if let audioTrack,
               let desc = try? await audioTrack.load(.formatDescriptions).first {
                q.codec = Self.fourCCName(CMFormatDescriptionGetMediaSubType(desc))
                if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc)?.pointee {
                    q.sampleRateHz = Int(asbd.mSampleRate)
                    q.channelCount = Int(asbd.mChannelsPerFrame)
                }
            }
            // 码率：优先实际音轨估计数据率（字节/秒），accessLog 兜底（位/秒，实际解码报告）
            if q.bitrateKbps == nil {
                var bitrateBits = 0
                if let liveTrack = player.currentItem?.tracks.compactMap(\.assetTrack)
                    .first(where: { $0.mediaType == .audio }),
                   let rate = try? await liveTrack.load(.estimatedDataRate), rate > 0 {
                    bitrateBits = Int(rate * 8)
                } else if let item = player.currentItem {
                    let log: AVPlayerItemAccessLog?
                    if #available(iOS 27, *) {
                        log = await withCheckedContinuation { cont in
                            item.fetchAccessLog(completionHandler: { l in cont.resume(returning: l) })
                        }
                    } else {
                        log = item.accessLog()
                    }
                    if let ev = log?.events.last, ev.indicatedBitrate > 0 {
                        bitrateBits = Int(ev.indicatedBitrate)
                    }
                }
                if bitrateBits > 0 { q.bitrateKbps = max(1, bitrateBits / 1000) }
            }
            // 任一字段到手即可显示（编码/采样率/声道/码率都行）
            if !q.isEmpty {
                audioQuality = q
                return
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
    }

    /// 首次进入可播状态时记录启动/缓冲延迟（毫秒），只记一次
    private func measureLatencyIfNeeded() {
        guard latencyMs == nil, let start = latencyStart else { return }
        latencyMs = Int(Date().timeIntervalSince(start) * 1000)
    }

    /// 音频格式四字码 → 展示名（未知则回退为四字码字符串）
    static func fourCCName(_ code: FourCharCode) -> String {
        switch code {
        case 0x6D703320: return "MP3"     // 'mp3 '
        case 0x2E6D7033: return "MP3"     // '.mp3'
        case 0x6D70346D: return "MP3"     // 'mp4m'
        case 0x61616320: return "AAC"     // 'aac '
        case 0x61616364: return "AAC"     // 'aacd'
        case 0x6F707573: return "Opus"    // 'opus'
        case 0x664C6143: return "FLAC"    // 'fLaC'
        case 0x616C6163: return "ALAC"    // 'alac'
        case 0x6C70636D: return "PCM"     // 'lpcm'
        default:
            return String(format: "%c%c%c%c",
                          (code >> 24) & 0xFF, (code >> 16) & 0xFF,
                          (code >> 8) & 0xFF, code & 0xFF)
        }
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
        timeControlObserver?.invalidate()
        timeControlObserver = nil
        audioQuality = nil
        latencyMs = nil
        latencyStart = nil
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
            #if os(iOS)
            UIImage(named: "app-icon") ?? UIImage(systemName: "radio")!
            #elseif os(macOS)
            NSImage(named: "app-icon") ?? NSImage(systemSymbolName: "radio", accessibilityDescription: nil) ?? NSImage(size: .zero)
            #endif
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
