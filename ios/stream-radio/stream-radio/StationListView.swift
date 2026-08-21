import SwiftUI
import UniformTypeIdentifiers
import UIKit

// 侧边栏导航项
enum SidebarSection: Hashable {
    case all, favorites, settings, help, about
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
        .sheet(isPresented: $showingPlayer) { NowPlayingView() }
    }

    /// iPad 横屏常驻侧边栏；iPad 竖屏与 iPhone 保持折叠（和手机一致）
    private func updateColumnVisibility() {
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad
        columnVisibility = (isIPad && sizeClass == .regular) ? .all : .detailOnly
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
    @State private var importCandidates: [Station] = []
    @State private var showingImportPreview = false
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
        List {
            ForEach(filtered) { station in
                StationRow(station: station,
                           onPlay: { playAndShow(station) },
                           onEdit: { startEditing(station) })
            }
            .onDelete(perform: delete)
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: "搜索电台…")
        .navigationTitle("全部电台")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
                Button { showingImport = true } label: { Image(systemName: "square.and.arrow.down") }
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
        .sheet(isPresented: $showingImportPreview) {
            ImportPreviewView(candidates: importCandidates, store: store) { chosen in
                store.importSelected(chosen)
            }
        }
        // 右下角迷你悬浮球（搜索激活时自动隐藏）
        .overlay(alignment: .bottomTrailing) {
            if player.currentStation != nil {
                MiniPlayerBubble { showingPlayer = true }
            }
        }
        // 文件选择器：用 UIKit 原生 UIDocumentPickerViewController。
        // （SwiftUI fileImporter 在 iOS 17 真机、挂 NavigationSplitView 内层时，
        //   选中文件后 completion 可能不触发，表现为「点选后没反应」；
        //   改用原生组件走 delegate 回调，不依赖 SwiftUI 视图树，最稳。）
        // 允许选择任意类型文件（UTType.item），解析不了会明确弹错。
        .fullScreenCover(isPresented: $showingImport) {
            DocumentPicker { url in
                showingImport = false
                if let url {
                    // 等全屏选择器收起后再处理，避免与预览弹窗的 present 动画冲突
                    DispatchQueue.main.async { importM3U(from: url) }
                }
            }
            .ignoresSafeArea()
        }
        .alert("导入失败", isPresented: $showingImportError) {
            Button("好", role: .cancel) { }
        } message: {
            Text(importError ?? "")
        }
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
            importCandidates = parsed
            // 延迟到选择器收起动画结束后再弹预览，避免 present 冲突
            DispatchQueue.main.async {
                showingImportPreview = true
            }
        } catch {
            importError = "读取文件失败：\(error.localizedDescription)"
            showingImportError = true
        }
    }
}

// 文件选择器：允许选择任意类型文件；选中回调 URL，取消回调 nil
struct DocumentPicker: UIViewControllerRepresentable {
    var onPick: (URL?) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item])
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker
        init(_ parent: DocumentPicker) { self.parent = parent }

        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            parent.onPick(urls.first)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.onPick(nil)
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
            List(candidates) { station in
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
            .navigationTitle("选择要导入的台")
            .toolbar {
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
            .safeAreaInset(edge: .bottom) {
                Text("共 \(candidates.count) 个，可导入 \(importableCount) 个，重复 \(duplicateCount) 个")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
        .presentationDetents([.medium, .large])
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

    var body: some View {
        List {
            if favorites.isEmpty {
                ContentUnavailableView(
                    "暂无星标电台",
                    systemImage: "star",
                    description: Text("在电台列表长按或左滑即可标星")
                )
            } else {
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
        }
        .listStyle(.insetGrouped)
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
