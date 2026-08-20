import SwiftUI
import UniformTypeIdentifiers

// 侧边栏导航项
enum SidebarSection: Hashable {
    case all, favorites, settings, help, about
}

// 根容器：侧边栏导航（iPad 双栏，iPhone 自动折叠）
struct RootView: View {
    @State private var selection: SidebarSection? = .all

    var body: some View {
        NavigationSplitView {
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
            case .all: StationListView()
            case .favorites: FavoriteListView()
            case .settings: SettingsView()
            case .help: HelpView()
            case .about: AboutView()
            }
        }
    }
}

// 电台列表（全部）
struct StationListView: View {
    @Environment(StationStore.self) private var store
    @Environment(PlayerManager.self) private var player

    @State private var searchText = ""
    @State private var showingImport = false
    @State private var showingAdd = false
    @State private var showingPlayer = false
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
        .fileImporter(isPresented: $showingImport,
                      allowedContentTypes: [.plainText, .item]) { result in
            importM3U(from: result)
        }
        .sheet(isPresented: $showingPlayer) { NowPlayingView() }
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

    private func importM3U(from result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            store.importM3U(text)
        }
    }
}

// 星标电台列表
struct FavoriteListView: View {
    @Environment(StationStore.self) private var store
    @Environment(PlayerManager.self) private var player

    @State private var showingPlayer = false
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
        .sheet(isPresented: $showingPlayer) { NowPlayingView() }
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
