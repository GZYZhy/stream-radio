import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// 侧边栏导航项
enum SidebarSection: Hashable {
    case all, favorites, settings, help, about
}

/// 导入预览 sheet 的数据载体（sheet(item:) 要求 Identifiable，
/// 用它把「显示开关」和「候选列表」绑在一起，避免首次 present 读到空数组）
struct ImportPreviewPayload: Identifiable {
    let id = UUID()
    let candidates: [Station]
}

// 根容器：侧边栏导航（iPad 双栏，iPhone 自动折叠）
struct RootView: View {
    @State private var selection: SidebarSection? = .all
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly
    @State private var showingPlayer = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selection) {
                Section("电台") {
                    Label("全部电台", systemImage: "radio").tag(SidebarSection.all)
                    Label("星标电台", systemImage: "star").tag(SidebarSection.favorites)
                }
                Section("更多") {
                    Label("设置", systemImage: "gearshape").tag(SidebarSection.settings)
                    Label("帮助", systemImage: "questionmark.circle").tag(SidebarSection.help)
                    Label("关于", systemImage: "info.circle").tag(SidebarSection.about)
                }
            }
            .navigationTitle("网络电台")
        } detail: {
            switch selection ?? .all {
            case .all: StationListView(showingPlayer: $showingPlayer)
            case .favorites: FavoriteListView(showingPlayer: $showingPlayer)
            case .settings: SettingsView()
            case .help: HelpView()
            case .about: AboutView()
            }
        }
        .onAppear { updateColumnVisibility() }
        .onChange(of: sizeClass) { _, _ in updateColumnVisibility() }
        // 托盘/菜单栏导航请求：设置 → 设置页；正在播放 → 弹出播放页
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
            selection = .settings
        }
        .onReceive(NotificationCenter.default.publisher(for: .openNowPlaying)) { _ in
            showingPlayer = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openHelp)) { _ in
            selection = .help
        }
        .sheet(isPresented: $showingPlayer) { NowPlayingView() }
    }

    /// iPad 横屏常驻侧边栏；iPad 竖屏与 iPhone 保持折叠（和手机一致）
    /// macOS 下默认显示双栏
    private func updateColumnVisibility() {
        #if os(iOS)
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad
        columnVisibility = (isIPad && sizeClass == .regular) ? .all : .detailOnly
        #elseif os(macOS)
        columnVisibility = .all
        #endif
    }
}

// 迷你播放悬浮球：右下角常驻小圆球，点击重新打开播放页
// 搜索激活时自动隐藏，避免遮挡搜索框的取消按钮
struct MiniPlayerBubble: View {
    @Environment(PlayerManager.self) private var player
    @Environment(\.isSearching) private var isSearching
    let onTap: () -> Void

    var body: some View {
        if isSearching {
            EmptyView()
        } else {
            Button(action: onTap) {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 56, height: 56)
                        .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                    Image(systemName: player.isPlaying ? "waveform" : "play.fill")
                        .font(.title3)
                        .foregroundStyle(.blue)
                }
            }
            .buttonStyle(.plain)
            .padding(.trailing, 16)
            .padding(.bottom, 16)
        }
    }
}

// 电台列表（全部）
struct StationListView: View {
    @Environment(StationStore.self) private var store
    @Environment(PlayerManager.self) private var player

    @State private var searchText = ""
    @State private var showingImport = false
    /// 导入预览 sheet 的数据（非 nil 即显示；sheet(item:) 确保首次 present 内容拿到的是真实数据，
    /// 避免「isPresented 已变 true 但 candidates 还没更新」导致的首次 0 个台）
    @State private var importPreviewData: ImportPreviewPayload?
    /// 导入失败时的错误信息（解析/读取失败弹窗提示，不静默）
    @State private var importError: String?
    @State private var showingImportError = false
    @State private var showingAdd = false
    @Binding var showingPlayer: Bool
    @State private var newName = ""
    @State private var newURL = ""
    @State private var editingStation: Station?
    @State private var showEdit = false
    @State private var editName = ""
    @State private var editURL = ""

    /// 按搜索关键字过滤
    private var filtered: [Station] {
        let kw = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if kw.isEmpty { return store.stations }
        return store.stations.filter {
            $0.name.lowercased().contains(kw) || $0.url.lowercased().contains(kw)
        }
    }

    var body: some View {
        Group {
            if filtered.isEmpty {
                EmptyStateView(
                    systemImage: "radio",
                    title: "暂无电台",
                    description: "点右上角 + 添加，或导入 m3u 列表"
                )
            } else {
                List {
                    ForEach(filtered) { station in
                        StationRow(station: station,
                                   onPlay: { playAndShow(station) },
                                   onEdit: { startEditing(station) })
                    }
                    .onDelete(perform: delete)
                }
                #if os(iOS)
                .listStyle(.insetGrouped)
                #else
                .listStyle(.inset)
                #endif
            }
        }
        .searchable(text: $searchText, prompt: "搜索电台…")
        .navigationTitle("全部电台")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                #if os(macOS)
                // macOS：弹 NSOpenPanel → 解析 → 发通知让本视图弹预览 sheet。
                // 与顶部菜单「文件 → 导入 m3u…」走同一函数（importM3UViaPanel）。
                Button { importM3UViaPanel(store: store) } label: { Image(systemName: "square.and.arrow.down") }
                #else
                Button { showingImport = true } label: { Image(systemName: "square.and.arrow.down") }
                #endif
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .alert("添加电台", isPresented: $showingAdd) {
            TextField("名称", text: $newName)
            TextField("播放地址", text: $newURL)
            Button("取消", role: .cancel) { resetAdd() }
            Button("添加") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                let url = newURL.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty && !url.isEmpty {
                    store.add(Station(name: name, url: url))
                }
                resetAdd()
            }
            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .alert("编辑电台", isPresented: $showEdit, presenting: editingStation) { station in
            TextField("名称", text: $editName)
            TextField("播放地址", text: $editURL)
            Button("取消", role: .cancel) { }
            Button("保存") { store.update(station, name: editName, url: editURL) }
                .disabled(editName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        // sheet(item:)：item 非 nil 时弹出，闭包直接拿到真实数据，
        // 彻底消除「isPresented 已翻转但数据还是旧值」导致的首次 0 个台
        .sheet(item: $importPreviewData) { payload in
            ImportPreviewView(candidates: payload.candidates, store: store) { chosen in
                store.importSelected(chosen)
            }
        }
        // 右下角迷你悬浮球（搜索激活时自动隐藏）
        .overlay(alignment: .bottomTrailing) {
            if player.currentStation != nil {
                MiniPlayerBubble { showingPlayer = true }
            }
        }
        // 文件选择器：iOS 用 UIDocumentPicker（macOS 直接在工具栏弹 NSOpenPanel，
        // 见 importM3UViaPanel，不再走透明 sheet）
        #if os(iOS)
        .fullScreenCover(isPresented: $showingImport) {
            FilePickerView { url in
                showingImport = false
                if let url {
                    DispatchQueue.main.async { importM3U(from: url) }
                }
            }
            .ignoresSafeArea()
        }
        #endif
        .alert("导入失败", isPresented: $showingImportError) {
            Button("好", role: .cancel) { }
        } message: {
            Text(importError ?? "")
        }
        // macOS：菜单栏/工具栏的「导入 m3u…」解析完成后发通知，
        // 这里接收并弹出预览 sheet（与 iOS 文件选择器走同一套预览）
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: .showImportPreview)) { note in
            if let candidates = note.object as? [Station] {
                importPreviewData = ImportPreviewPayload(candidates: candidates)
            }
        }
        #endif
    }

    private func playAndShow(_ station: Station) {
        player.play(station)
        showingPlayer = true
    }

    private func startEditing(_ station: Station) {
        editingStation = station
        editName = station.name
        editURL = station.url
        showEdit = true
    }

    private func delete(at offsets: IndexSet) {
        let targets = offsets.map { filtered[$0] }
        store.remove(targets)
    }

    private func resetAdd() {
        newName = ""
        newURL = ""
    }

    /// 读取并解析用户选择的 m3u 文件；任何一步失败都弹窗报错，不静默
    private func importM3U(from url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            // UTF-8 优先，latin1 兜底（部分文件是其他编码）
            guard let text = String(data: data, encoding: .utf8)
                             ?? String(data: data, encoding: .isoLatin1) else {
                importError = "无法读取文件内容（编码不支持），请确认是文本格式的 m3u 播放列表。"
                showingImportError = true
                return
            }
            let parsed = StationStore.parseM3U(text)
            guard !parsed.isEmpty else {
                importError = "文件中没有解析到任何电台。请确认内容包含 #EXTINF 名称行或 http(s) 地址行。"
                showingImportError = true
                return
            }
            // 延迟到选择器收起动画结束后再弹预览，避免 present 冲突；
            // 用 sheet(item:) 一次性写入数据 + 触发显示，不会读到空数组
            DispatchQueue.main.async {
                importPreviewData = ImportPreviewPayload(candidates: parsed)
            }
        } catch {
            importError = "读取文件失败：\(error.localizedDescription)"
            showingImportError = true
        }
    }

}


// 导入预览：勾选要导入的台（与已存在 URL 重复的默认跳过）
struct ImportPreviewView: View {
    let candidates: [Station]
    let onImport: ([Station]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<UUID>
    /// 已存在（URL 与当前列表重复）的台
    private let existingURLs: Set<String>

    init(candidates: [Station], store: StationStore, onImport: @escaping ([Station]) -> Void) {
        self.candidates = candidates
        self.onImport = onImport
        let existing = Set(store.stations.map(\.url))
        self.existingURLs = existing
        // 默认勾选所有可导入的台
        _selected = State(initialValue: Set(candidates.filter { !existing.contains($0.url) }.map(\.id)))
    }

    private var checkedCount: Int { selected.count }
    private var duplicateCount: Int { candidates.filter { existingURLs.contains($0.url) }.count }
    private var importableCount: Int { candidates.count - duplicateCount }

    var body: some View {
        NavigationStack {
            #if os(macOS)
            // macOS：用 VStack 把列表和底部汇总分开。safeAreaInset 在 macOS 上
            // 会覆盖在列表内容之上导致重叠，故改用分隔线 + 独立一行
            VStack(spacing: 0) {
                List(candidates) { station in
                    stationRow(station)
                }
                Divider()
                importSummary
                    .padding(8)
            }
            .navigationTitle("选择要导入的台")
            .toolbar { importToolbar }
            // macOS 没有 sheet detent 机制：不设最小尺寸的话 sheet 会按内容收缩成一行，
            // 列表无法滚动、行内控件也点不到
            .frame(minWidth: 480, minHeight: 420)
            #else
            List(candidates) { station in
                stationRow(station)
            }
            .navigationTitle("选择要导入的台")
            .toolbar { importToolbar }
            .safeAreaInset(edge: .bottom) { importSummary }
            .presentationDetents([.medium, .large])
            #endif
        }
    }

    /// 行内容：复选框 + 名称/地址 + 「已存在」标记
    private func stationRow(_ station: Station) -> some View {
        HStack {
            Toggle("", isOn: Binding(
                get: { selected.contains(station.id) },
                set: { on in
                    if on { selected.insert(station.id) } else { selected.remove(station.id) }
                }
            ))
            .labelsHidden()
            .disabled(existingURLs.contains(station.url))
            VStack(alignment: .leading, spacing: 2) {
                Text(station.name)
                Text(station.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if existingURLs.contains(station.url) {
                Text("已存在")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 底部汇总：共 / 可导入 / 重复
    private var importSummary: some View {
        Text("共 \(candidates.count) 个，可导入 \(importableCount) 个，重复 \(duplicateCount) 个")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    /// 顶部工具栏：取消 / 导入
    @ToolbarContentBuilder
    private var importToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("取消") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("导入 (\(checkedCount))") {
                onImport(candidates.filter { selected.contains($0.id) })
                dismiss()
            }
            .disabled(checkedCount == 0)
        }
    }
}

// 星标电台列表
struct FavoriteListView: View {
    @Environment(StationStore.self) private var store
    @Environment(PlayerManager.self) private var player

    @Binding var showingPlayer: Bool
    @State private var editingStation: Station?
    @State private var showEdit = false
    @State private var editName = ""
    @State private var editURL = ""

    private var favorites: [Station] { store.stations.filter(\.isFavorite) }

    #if os(iOS)
    private let favoriteHint = "点击电台行尾的星标图标，或长按菜单标星"
    #else
    private let favoriteHint = "点击电台行尾的星标图标，或右键菜单标星"
    #endif

    var body: some View {
        Group {
            if favorites.isEmpty {
                EmptyStateView(
                    systemImage: "star",
                    title: "暂无星标电台",
                    description: favoriteHint
                )
            } else {
                List {
                    ForEach(favorites) { station in
                        StationRow(station: station,
                                   onPlay: {
                                       player.play(station)
                                       showingPlayer = true
                                   },
                                   onEdit: { startEditing(station) })
                    }
                    .onDelete { offsets in
                        let targets = offsets.map { favorites[$0] }
                        store.remove(targets)
                    }
                }
                #if os(iOS)
                .listStyle(.insetGrouped)
                #else
                .listStyle(.inset)
                #endif
            }
        }
        .navigationTitle("星标电台")
        .alert("编辑电台", isPresented: $showEdit, presenting: editingStation) { station in
            TextField("名称", text: $editName)
            TextField("播放地址", text: $editURL)
            Button("取消", role: .cancel) { }
            Button("保存") { store.update(station, name: editName, url: editURL) }
                .disabled(editName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        // 右下角迷你悬浮球
        .overlay(alignment: .bottomTrailing) {
            if player.currentStation != nil {
                MiniPlayerBubble { showingPlayer = true }
            }
        }
    }

    private func startEditing(_ station: Station) {
        editingStation = station
        editName = station.name
        editURL = station.url
        showEdit = true
    }
}

// 通用空状态视图（居中显示图标 + 标题 + 描述）
struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let description: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3.bold())
            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// 单行电台：名称 + 地址 + 当前播放标记 + 星标；长按菜单 + 左滑操作
struct StationRow: View {
    let station: Station
    let onPlay: () -> Void
    let onEdit: () -> Void

    @Environment(StationStore.self) private var store
    @Environment(PlayerManager.self) private var player

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(station.name)
                Text(station.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if player.currentStation == station {
                Image(systemName: "waveform")
                    .foregroundStyle(.blue)
            }
            Button(action: { store.toggleFavorite(station) }) {
                Image(systemName: station.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(station.isFavorite ? .yellow : .gray)
            }
            .buttonStyle(.borderless)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onPlay)
        .contextMenu {
            Button("编辑") { onEdit() }
            Button(station.isFavorite ? "取消星标" : "标星") { store.toggleFavorite(station) }
            Button("上移") { store.moveUp(station) }
            Button("下移") { store.moveDown(station) }
            Divider()
            Button("删除", role: .destructive) { store.remove([station]) }
        }
        .swipeActions(edge: .trailing) {
            Button("删除", role: .destructive) { store.remove([station]) }
            Button("编辑") { onEdit() }
                .tint(.blue)
        }
    }
}
