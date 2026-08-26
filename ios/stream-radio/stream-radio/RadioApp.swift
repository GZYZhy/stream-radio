import SwiftUI
#if os(macOS)
import AppKit
#endif

// App 入口：注入电台仓库与播放器到视图环境
@main
struct RadioApp: App {
    #if os(macOS)
    // macOS 应用代理：创建菜单栏托盘（左键切换窗口 / 右键功能菜单）
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif
    @State private var store = StationStore()
    @State private var player = PlayerManager()
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @AppStorage("autoSyncOnLaunch") private var autoSyncOnLaunch = false

    var body: some Scene {
        WindowGroup {
            rootContent
        }
        #if os(macOS)
        // macOS 顶部菜单栏（应用菜单）
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("关于网络电台") {
                    // 简单的关于窗口：用系统原生 About 面板
                    NSApp.orderFrontStandardAboutPanel(nil)
                }
            }
            // 导入 / 同步并入系统默认「文件」菜单（避免出现两个「文件」菜单）
            CommandGroup(after: .importExport) {
                Button("导入 m3u…") {
                    importM3UViaPanel(store: store)
                }
                .keyboardShortcut("o", modifiers: .command)
                Button("同步订阅") {
                    Task { await store.syncAllSubscriptions() }
                }
            }
            // 播放：播放暂停、换台、标星
            CommandMenu("播放") {
                Button("播放 / 暂停") {
                    player.toggle()
                }
                Button("上一台") {
                    let list = player.stationProvider?() ?? store.stations
                    guard !list.isEmpty else { return }
                    player.previous(in: list)
                }
                Button("下一台") {
                    let list = player.stationProvider?() ?? store.stations
                    guard !list.isEmpty else { return }
                    player.next(in: list)
                }
                Button("标星 / 取消标星") {
                    guard let cur = player.currentStation else { return }
                    player.favoriteToggler?(cur)
                }
                .disabled(player.currentStation == nil)
            }
            // 帮助：替换系统默认帮助菜单（默认「网络电台帮助」会去查帮助文档，
            // 报「未找到帮助」），改为打开应用内的帮助页
            CommandGroup(replacing: .help) {
                Button("网络电台帮助") {
                    NotificationCenter.default.post(name: .openHelp, object: nil)
                }
                .keyboardShortcut("?", modifiers: .command)
            }
        }
        #endif
    }

    /// 主界面内容（iOS / macOS 共用）
    @ViewBuilder
    private var rootContent: some View {
        RootView()
            .environment(store)
            .environment(player)
            .preferredColorScheme(appearanceScheme)
            #if os(macOS)
            // 把主窗口交给 AppDelegate：接管「关闭」为最小化到托盘 / 退出选择
            .background(WindowAccessor(onBecome: { window in
                AppDelegate.shared?.bind(window: window)
            }))
            #endif
            // 供控制中心切台 / 标星使用；onAppear 在 MainActor 运行，避免跨线程捕获
            .onAppear {
                player.stationProvider = { store.stations }
                player.favoriteToggler = { station in store.toggleFavorite(station) }
                #if os(macOS)
                // 把仓库与播放器提供给菜单栏托盘（读取状态 / 控制播放）
                AppDelegate.configure(store: store, player: player)
                #endif
                // 启动时自动同步订阅（默认关闭，由「设置→订阅」开关控制）
                if autoSyncOnLaunch {
                    Task { await store.syncAllSubscriptions() }
                }
            }
            #if os(macOS)
            .frame(minWidth: 640, minHeight: 480)
            #endif
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
