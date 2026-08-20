import SwiftUI

// 正在播放：站名、节目信息、播放/暂停、上一台/下一台
struct NowPlayingView: View {
    @Environment(StationStore.self) private var store
    @Environment(PlayerManager.self) private var player
    @Environment(\.dismiss) private var dismiss

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
            Spacer()
        }
        .padding()
    }
}
