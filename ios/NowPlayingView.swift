import SwiftUI

// 正在播放：站名、节目信息、播放/暂停、上一台/下一台
struct NowPlayingView: View {
    @Environment(StationStore.self) private var store
    @Environment(PlayerManager.self) private var player
    @Environment(\.dismiss) private var dismiss

    /// 日期时间格式：中文、含秒，用于播放页时钟
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日 HH:mm:ss"
        return f
    }()

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
                Text(Self.timeFormatter.string(from: context.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
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
            // 标星/取消标星当前台（星形状态实时反映仓库最新收藏）
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
                .padding(.top, 8)
            }
            Spacer()
        }
        .padding()
    }
}
