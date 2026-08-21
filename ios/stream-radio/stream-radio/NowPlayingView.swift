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

    /// 日期时间格式：中文、含秒，用于播放页时钟
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日 HH:mm:ss"
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
            Text(player.programTitle ?? "正在连接…")
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
                                Text("延迟 \(latency) ms")
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
                        Label("定时停播 \(Self.formatRemaining(remaining))",
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
                            Label(isFavorite ? "已标星" : "标星",
                                  systemImage: isFavorite ? "star.fill" : "star")
                                .font(.headline)
                                .foregroundStyle(isFavorite ? .yellow : .secondary)
                        }
                    }
                    Button {
                        showingSleepMenu.toggle()
                    } label: {
                        let isActive = player.sleepTimerRemaining != nil
                        Label(isActive ? "定时中" : "定时停播",
                              systemImage: isActive ? "timer.fill" : "timer")
                            .font(.headline)
                            .foregroundStyle(isActive ? .blue : .secondary)
                    }
                }
                .padding(.top, 8)
            }
            Spacer()
        }
        .padding()
        .confirmationDialog("定时停播", isPresented: $showingSleepMenu, titleVisibility: .visible) {
            ForEach(presetMinutes, id: \.self) { min in
                Button("\(min) 分钟") {
                    player.setSleepTimer(minutes: min)
                }
            }
            Button("自定义…") {
                customMinutes = ""
                showingCustomSleep = true
            }
            if player.sleepTimerRemaining != nil {
                Button("取消定时", role: .destructive) {
                    player.setSleepTimer(minutes: nil)
                }
            }
            Button("取消", role: .cancel) { }
        } message: {
            if let remaining = player.sleepTimerRemaining {
                Text("剩余 \(Self.formatRemaining(remaining)) 后停止播放")
            } else {
                Text("选择时长后，倒计时结束自动停止播放")
            }
        }
        .alert("自定义时长", isPresented: $showingCustomSleep) {
            TextField("分钟", text: $customMinutes)
                .keyboardType(.numberPad)
            Button("取消", role: .cancel) { }
            Button("确定") {
                if let m = Int(customMinutes), m > 0 {
                    player.setSleepTimer(minutes: m)
                }
            }
        } message: {
            Text("输入分钟数（例如 25）")
        }
        .alert("质量说明", isPresented: $showingQualityHelp) {
            Button("知道了", role: .cancel) { }
        } message: {
            Text("质量由电台来源和网络环境决定")
        }
    }
}
