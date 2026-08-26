import SwiftUI

// 正在播放：站名、节目信息、播放/暂停、上一台/下一台、定时停播
struct NowPlayingView: View {
    @Environment(StationStore.self) private var store
    @Environment(PlayerManager.self) private var player
    @Environment(\.dismiss) private var dismiss

    @State private var showingSleepMenu = false
    @State private var showingCustomSleep = false
    @State private var customMinutes = ""
    /// 质量说明弹窗
    @State private var showingQualityHelp = false

    /// 可选的定时停播时长（分钟）
    private let presetMinutes = [10, 15, 30, 45, 60, 90, 120]

    /// 日期时间格式：跟随系统语言，用于播放页时钟
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f
    }()

    /// 将秒数格式化为 "mm:ss"
    private static func formatRemaining(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    /// 延迟毫秒 → 颜色：绿 <150 / 黄 150-299 / 橙 300-599 / 红 ≥600
    static func latencyColor(_ ms: Int) -> Color {
        if ms < 150 { return Color(red: 0.204, green: 0.780, blue: 0.349) }   // #34c759
        if ms < 300 { return Color(red: 1.000, green: 0.800, blue: 0.000) }   // #ffcc00
        if ms < 600 { return Color(red: 1.000, green: 0.584, blue: 0.000) }   // #ff9500
        return Color(red: 1.000, green: 0.231, blue: 0.188)                   // #ff3b30
    }

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Spacer()
                Button { dismiss() } label: { Image(systemName: "chevron.down") }
                    .font(.title2)
                    .padding()
            }
            Spacer()
            Image(systemName: "radio")
                .font(.system(size: 72))
                .foregroundStyle(.blue)
            Text(player.currentStation?.name ?? "")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text(player.programTitle ?? NSLocalizedString("now_playing_connecting", comment: ""))
                .font(.headline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            // 当前日期时间（每秒刷新）
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(spacing: 4) {
                    Text(Self.timeFormatter.string(from: context.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    // 播放质量（与日期同一样式）：编码 · 码率 · 采样率 · 声道 · 延迟
                    if let q = player.audioQuality, !q.summary.isEmpty {
                        HStack(spacing: 6) {
                            Text(q.summary)
                            if let latency = player.latencyMs {
                                Text(String(format: NSLocalizedString("now_playing_latency", comment: ""), latency))
                                    .foregroundStyle(Self.latencyColor(latency))
                            }
                            Button { showingQualityHelp = true } label: {
                                Image(systemName: "questionmark.circle")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    }
                    if let remaining = player.sleepTimerRemaining {
                        Label(String(format: NSLocalizedString("sleep_timer_remaining", comment: ""),
                                     Self.formatRemaining(remaining)),
                              systemImage: "timer")
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .monospacedDigit()
                    }
                }
            }
            if let error = player.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Spacer()
            HStack(spacing: 48) {
                Button { player.previous(in: store.stations) } label: {
                    Image(systemName: "backward.fill").font(.title)
                }
                Button { player.toggle() } label: {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 64))
                }
                Button { player.next(in: store.stations) } label: {
                    Image(systemName: "forward.fill").font(.title)
                }
            }
            .tint(.primary)
            // 标星 + 定时停播（并列一行）
            if player.currentStation != nil {
                HStack(spacing: 24) {
                    if let station = player.currentStation {
                        let isFavorite = store.stations.first { $0.url == station.url }?.isFavorite ?? false
                        Button {
                            store.toggleFavorite(station)
                            player.refreshBookmarkState()
                        } label: {
                            Label(isFavorite
                                  ? NSLocalizedString("now_playing_favorited", comment: "")
                                  : NSLocalizedString("now_playing_favorite", comment: ""),
                                  systemImage: isFavorite ? "star.fill" : "star")
                                .font(.headline)
                                .foregroundStyle(isFavorite ? .yellow : .secondary)
                        }
                    }
                    #if os(macOS)
                    // macOS 用原生 Menu：可完整显示全部档位 + 自定义 + 取消定时。
                    // confirmationDialog 在 macOS 上按钮过多时会显示不全（自定义项被截掉）
                    Menu {
                        ForEach(presetMinutes, id: \.self) { min in
                            Button(String(format: NSLocalizedString("sleep_timer_minutes", comment: ""), min)) {
                                player.setSleepTimer(minutes: min)
                            }
                        }
                        Button(NSLocalizedString("sleep_timer_custom", comment: "")) {
                            customMinutes = ""
                            showingCustomSleep = true
                        }
                        if player.sleepTimerRemaining != nil {
                            Button(NSLocalizedString("sleep_timer_cancel", comment: ""), role: .destructive) {
                                player.setSleepTimer(minutes: nil)
                            }
                        }
                    } label: {
                        let isActive = player.sleepTimerRemaining != nil
                        Label(isActive
                              ? NSLocalizedString("sleep_timer_active", comment: "")
                              : NSLocalizedString("sleep_timer_title", comment: ""),
                              systemImage: isActive ? "timer.fill" : "timer")
                            .font(.headline)
                            .foregroundStyle(isActive ? .blue : .secondary)
                    }
                    #else
                    Button {
                        showingSleepMenu.toggle()
                    } label: {
                        let isActive = player.sleepTimerRemaining != nil
                        Label(isActive
                              ? NSLocalizedString("sleep_timer_active", comment: "")
                              : NSLocalizedString("sleep_timer_title", comment: ""),
                              systemImage: isActive ? "timer.fill" : "timer")
                            .font(.headline)
                            .foregroundStyle(isActive ? .blue : .secondary)
                    }
                    #endif
                }
                .padding(.top, 8)
            }
            Spacer()
        }
        .padding()
        .confirmationDialog(NSLocalizedString("sleep_timer_title", comment: ""), isPresented: $showingSleepMenu, titleVisibility: .visible) {
            ForEach(presetMinutes, id: \.self) { min in
                Button(String(format: NSLocalizedString("sleep_timer_minutes", comment: ""), min)) {
                    player.setSleepTimer(minutes: min)
                }
            }
            Button(NSLocalizedString("sleep_timer_custom", comment: "")) {
                customMinutes = ""
                showingCustomSleep = true
            }
            if player.sleepTimerRemaining != nil {
                Button(NSLocalizedString("sleep_timer_cancel", comment: ""), role: .destructive) {
                    player.setSleepTimer(minutes: nil)
                }
            }
            Button(NSLocalizedString("cancel", comment: ""), role: .cancel) { }
        } message: {
            if let remaining = player.sleepTimerRemaining {
                Text(String(format: NSLocalizedString("sleep_timer_remaining_text", comment: ""),
                            Self.formatRemaining(remaining)))
            } else {
                Text(NSLocalizedString("sleep_timer_hint", comment: ""))
            }
        }
        .alert(NSLocalizedString("sleep_timer_custom_title", comment: ""), isPresented: $showingCustomSleep) {
            TextField(NSLocalizedString("sleep_timer_custom_placeholder", comment: ""), text: $customMinutes)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
            Button(NSLocalizedString("cancel", comment: ""), role: .cancel) { }
            Button(NSLocalizedString("confirm", comment: "")) {
                if let m = Int(customMinutes), m > 0 {
                    player.setSleepTimer(minutes: m)
                }
            }
        } message: {
            Text(NSLocalizedString("sleep_timer_custom_hint", comment: ""))
        }
        .alert(NSLocalizedString("quality_help_title", comment: ""), isPresented: $showingQualityHelp) {
            Button(NSLocalizedString("quality_help_got_it", comment: ""), role: .cancel) { }
        } message: {
            Text(NSLocalizedString("quality_help_message", comment: ""))
        }
    }
}
