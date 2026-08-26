import Foundation

// 菜单栏/托盘向主界面发起的导航请求（RootView 监听切换视图）。
// 放在条件编译外：iOS 端 RootView 也引用这些通知名。
extension Notification.Name {
    static let openSettings = Notification.Name("openSettings")
    static let openNowPlaying = Notification.Name("openNowPlaying")
    static let openHelp = Notification.Name("openHelp")
    /// macOS 导入 m3u 解析完成后，携带候选列表让 StationListView 弹出预览 sheet。
    /// object 为 [Station]（解析得到的候选电台）
    static let showImportPreview = Notification.Name("showImportPreview")
}

// 仅 macOS 编译：菜单栏托盘 + 应用菜单栏辅助（RadioApp 通过 AppDelegate 接入）
#if os(macOS)

import AppKit
import SwiftUI
import UniformTypeIdentifiers

// 应用代理：创建菜单栏托盘图标（左键切换窗口，右键功能菜单）
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    /// 供 SwiftUI 侧（WindowAccessor）绑定主窗口使用
    static weak var shared: AppDelegate?
    /// 由 RadioApp 在 onAppear 注入，菜单栏据此读取/控制播放与电台
    static weak var store: StationStore?
    static weak var player: PlayerManager?

    private var statusItem: NSStatusItem?
    /// 主窗口引用（bind 时保存）：窗口隐藏后 canBecomeMain 可能返回 false，
    /// 若靠 NSApp.windows 查找会导致托盘无法重新显示，故直接持有引用
    private weak var primaryWindow: NSWindow?

    static func configure(store: StationStore, player: PlayerManager) {
        AppDelegate.store = store
        AppDelegate.player = player
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "dot.radiowaves.left.and.right",
                                   accessibilityDescription: NSLocalizedString("mac_tray_accessibility", comment: ""))
            button.target = self
            button.action = #selector(statusItemClicked)
            // 让左右键都回调 action，在 action 里区分（默认只响应左键）
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
    }

    // 左键：切换主窗口显隐；右键：弹出功能菜单
    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            statusItem?.menu = buildMenu()
            statusItem?.button?.performClick(nil)
        } else {
            statusItem?.menu = nil
            toggleMainWindow()
        }
    }

    // ---- 主窗口显隐 ----

    private func mainWindow() -> NSWindow? {
        primaryWindow ?? NSApp.windows.first { $0.canBecomeMain }
    }

    // 显示主窗口：先从托盘隐藏状态恢复（NSApp.unhide），再前置窗口。
    // 隐藏/恢复都用 NSApp.hide/unhide 而非直接改窗口可见性——
    // 直接 orderOut 会让 WindowGroup 误判「没有窗口」而在重新激活时自动新建
    // （多开窗口），在 Window scene 下操作 SwiftUI 窗口还会闪退。
    private func showMainWindow() {
        if NSApp.isHidden { NSApp.unhide(nil) }
        if let window = mainWindow() {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    // 左键切换：隐藏（NSApp.hide，Dock 缩略图一并消失）或恢复显示
    private func toggleMainWindow() {
        if NSApp.isHidden {
            showMainWindow()
        } else if let window = mainWindow(), window.isVisible {
            NSApp.hide(nil)
        } else {
            showMainWindow()
        }
    }

    // Dock 图标 / 启动台重新打开应用：恢复显示并前置
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    // ---- 主窗口关闭行为 ----

    /// SwiftUI 主窗口创建后绑定到 AppDelegate（接管关闭行为，并记住窗口引用）
    func bind(window: NSWindow) {
        window.delegate = self
        primaryWindow = window
    }

    // 点击窗口关闭按钮（或 ⌘W）：按「设置→窗口→关闭主窗口时」的偏好分流。
    // - 每次询问：弹窗让用户选「最小化到托盘」或「退出程序」
    // - 最小化到托盘：orderOut 隐藏窗口（不真正关闭、不占 Dock 缩略图区），
    //   之后托盘图标 / Dock / 启动台均可再恢复
    // - 退出程序：直接结束应用
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        switch UserDefaults.standard.string(forKey: "macCloseBehavior") {
        case "hideToTray":
            NSApp.hide(nil)
            return false
        case "quit":
            NSApp.terminate(nil)
            return true
        default:  // "ask" 或未知值：每次询问，但可勾选「记住选择」下次不再询问
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("mac_close_alert_title", comment: "")
            alert.informativeText = NSLocalizedString("mac_close_alert_message", comment: "")
            alert.addButton(withTitle: NSLocalizedString("settings_close_hide", comment: ""))
            alert.addButton(withTitle: NSLocalizedString("settings_close_quit", comment: ""))
            alert.alertStyle = .informational
            // 勾选后把本次选择写入偏好（macCloseBehavior），之后关闭不再询问；
            // 仍可在「设置 → 窗口 → 关闭主窗口时」改回「每次询问」
            let remember = NSButton(checkboxWithTitle: NSLocalizedString("mac_close_remember", comment: ""),
                                    target: nil, action: nil)
            remember.state = .on  // 默认勾选：记录本次选择，之后不再询问
            alert.accessoryView = remember
            let resp = alert.runModal()
            let choice = (resp == .alertFirstButtonReturn) ? "hideToTray" : "quit"
            if remember.state == .on {
                UserDefaults.standard.set(choice, forKey: "macCloseBehavior")
            }
            if choice == "hideToTray" {
                NSApp.hide(nil)
                return false
            } else {
                NSApp.terminate(nil)
                return true
            }
        }
    }

    // ---- 托盘菜单 ----

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let p = AppDelegate.player
        let store = AppDelegate.store

        // 正在播放：台名 · 节目名（未播放则灰字提示）
        let nowPlayingText: String
        if let cur = p?.currentStation {
            nowPlayingText = p?.programTitle.map { "\(cur.name) · \($0)" } ?? cur.name
        } else {
            nowPlayingText = NSLocalizedString("mac_tray_not_playing", comment: "")
        }
        let nowPlaying = NSMenuItem(title: String(format: NSLocalizedString("mac_tray_now_playing", comment: ""), nowPlayingText),
                                    action: nil, keyEquivalent: "")
        nowPlaying.isEnabled = false
        menu.addItem(nowPlaying)
        menu.addItem(.separator())

        // 播放 / 暂停（标题随状态切换）
        let toggleTitle = (p?.isPlaying == true)
            ? NSLocalizedString("mac_tray_pause", comment: "")
            : NSLocalizedString("mac_tray_play", comment: "")
        menu.addItem(item(toggleTitle, #selector(togglePlayback), key: " "))

        // 换台
        menu.addItem(item(NSLocalizedString("mac_menu_previous", comment: ""), #selector(previousStation), key: ""))
        menu.addItem(item(NSLocalizedString("mac_menu_next", comment: ""), #selector(nextStation), key: ""))

        // 标星 / 取消标星（无当前台禁用；收藏状态从列表实时取，避免值副本过期）
        var isFav = false
        if let cur = p?.currentStation {
            let live = p?.stationProvider?().first { $0.url == cur.url } ?? cur
            isFav = live.isFavorite
        }
        let fav = item(isFav
                       ? NSLocalizedString("row_unfavorite", comment: "")
                       : NSLocalizedString("row_favorite", comment: ""),
                       #selector(toggleFavorite), key: "")
        fav.isEnabled = (p?.currentStation != nil)
        menu.addItem(fav)

        menu.addItem(.separator())

        // 导航到主界面视图
        menu.addItem(item(NSLocalizedString("mac_tray_now_playing_nav", comment: ""), #selector(openNowPlaying), key: "P"))
        menu.addItem(item(NSLocalizedString("mac_tray_settings", comment: ""), #selector(openSettings), key: ","))

        menu.addItem(.separator())
        // 退出：terminate 是 NSApp 的方法，target 必须指向 NSApp（指向 self 会因
        // 找不到该方法而灰显无法点选）
        let quit = NSMenuItem(title: NSLocalizedString("mac_tray_quit", comment: ""),
                              action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)

        _ = store  // 保留引用以便后续扩展
        return menu
    }

    /// 便捷构造：target 固定为 self 的菜单项
    private func item(_ title: String, _ action: Selector?, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    // ---- 菜单动作 ----

    @objc private func togglePlayback() { AppDelegate.player?.toggle() }

    @objc private func nextStation() {
        guard let p = AppDelegate.player else { return }
        let list = p.stationProvider?() ?? AppDelegate.store?.stations ?? []
        guard !list.isEmpty else { return }
        p.next(in: list)
    }

    @objc private func previousStation() {
        guard let p = AppDelegate.player else { return }
        let list = p.stationProvider?() ?? AppDelegate.store?.stations ?? []
        guard !list.isEmpty else { return }
        p.previous(in: list)
    }

    @objc private func toggleFavorite() {
        guard let cur = AppDelegate.player?.currentStation else { return }
        AppDelegate.player?.favoriteToggler?(cur)
    }

    @objc private func openNowPlaying() {
        NotificationCenter.default.post(name: .openNowPlaying, object: nil)
        activateApp()
    }

    @objc private func openSettings() {
        NotificationCenter.default.post(name: .openSettings, object: nil)
        activateApp()
    }

    /// 从托盘菜单打开视图时，确保窗口在前台
    private func activateApp() {
        mainWindow()?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// 把 SwiftUI 主窗口暴露给 AppDelegate：视图挂到窗口后回调 window，
// 供 bind(window:) 设置关闭拦截
struct WindowAccessor: NSViewRepresentable {
    let onBecome: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            if let window = view?.window {
                onBecome(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// 顶部菜单 / 工具栏「导入 m3u…」：弹 NSOpenPanel 选文件 → 解析 →
/// 发 showImportPreview 通知让 StationListView 弹出预览 sheet（用户勾选后再导入）。
/// 失败时直接弹窗报错，不静默。
func importM3UViaPanel(store: StationStore) {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.item]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.prompt = NSLocalizedString("mac_import_prompt", comment: "")
    guard panel.runModal() == .OK, let url = panel.url else { return }

    let accessing = url.startAccessingSecurityScopedResource()
    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
    do {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8)
                 ?? String(data: data, encoding: .isoLatin1) else {
            showImportAlert(title: NSLocalizedString("import_failed_title", comment: ""),
                            message: NSLocalizedString("import_failed_encoding", comment: ""))
            return
        }
        let parsed = StationStore.parseM3U(text)
        guard !parsed.isEmpty else {
            showImportAlert(title: NSLocalizedString("import_failed_title", comment: ""),
                            message: NSLocalizedString("import_failed_empty", comment: ""))
            return
        }
        // 发通知让 StationListView 弹出预览 sheet（用户勾选确认后再导入）。
        // 用通知而不是直接操作状态：菜单栏/工具栏两个入口都走同一个函数，
        // StationListView 通过 sheet(item:) 接收，避免首次 present 读到空数据。
        NotificationCenter.default.post(name: .showImportPreview, object: parsed)
    } catch {
        showImportAlert(title: NSLocalizedString("import_failed_title", comment: ""),
                        message: String(format: NSLocalizedString("import_failed_read", comment: ""), error.localizedDescription))
    }
}

/// 导入失败的警告弹窗（成功走预览 sheet，不再用这个）
private func showImportAlert(title: String, message: String) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.alertStyle = .warning
    alert.addButton(withTitle: NSLocalizedString("ok", comment: ""))
    alert.runModal()
}

#endif
