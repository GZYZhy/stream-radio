import SwiftUI

// App 入口：注入电台仓库与播放器到视图环境
@main
struct RadioApp: App {
    @State private var store = StationStore()
    @State private var player = PlayerManager()
    @AppStorage("appearanceMode") private var appearanceMode = "system"

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(player)
                .preferredColorScheme(appearanceScheme)
                // 供控制中心切台 / 标星使用；onAppear 在 MainActor 运行，避免跨线程捕获
                .onAppear {
                    player.stationProvider = { store.stations }
                    player.favoriteToggler = { station in store.toggleFavorite(station) }
                }
        }
    }

    /// 外观模式：system 返回 nil 即跟随系统深浅色
    private var appearanceScheme: ColorScheme? {
        switch appearanceMode {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}
