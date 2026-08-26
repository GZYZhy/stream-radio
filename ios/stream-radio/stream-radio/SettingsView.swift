import SwiftUI

// 设置页：订阅管理（手动同步）+ 连通性检查
struct SettingsView: View {
    @Environment(StationStore.self) private var store

    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @AppStorage("autoSyncOnLaunch") private var autoSyncOnLaunch = false
    #if os(macOS)
    // 关闭主窗口时的行为（仅 macOS；iOS 无此概念，保持原样）
    @AppStorage("macCloseBehavior") private var closeBehavior = "ask"
    #endif
    @State private var showAddSub = false
    @State private var subName = ""
    @State private var subURL = ""
    @State private var syncing = false
    @State private var syncResult: String?
    @State private var checking = false
    @State private var checkResults: [String: ConnectivityChecker.Result] = [:]

    var body: some View {
        Form {
            Section("外观") {
                Picker("外观", selection: $appearanceMode) {
                    Text("跟随系统").tag("system")
                    Text("浅色").tag("light")
                    Text("深色").tag("dark")
                }
                .pickerStyle(.segmented)
            }

            #if os(macOS)
            Section("窗口") {
                Picker("关闭主窗口时", selection: $closeBehavior) {
                    Text("每次询问").tag("ask")
                    Text("最小化到托盘").tag("hideToTray")
                    Text("退出程序").tag("quit")
                }
                Text("选择「最小化到托盘」后，关闭窗口会隐藏到菜单栏托盘；选择「退出程序」则直接结束应用。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            #endif

            Section("订阅") {
                Toggle("启动时自动同步", isOn: $autoSyncOnLaunch)
                if store.subscriptions.isEmpty {
                    Text("暂无订阅。添加 m3u 链接后，用下方按钮手动同步拉取电台（按播放链接去重）。")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.subscriptions) { sub in
                    subscriptionRow(sub)
                }
                syncButtons
                if let syncResult {
                    Text(syncResult)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("网络") {
                networkCheckButton
                if checking {
                    ProgressView()
                } else if !checkResults.isEmpty {
                    checkResultsContent
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .formStyle(.grouped)
        #endif
        .navigationTitle("设置")
        .alert("添加订阅", isPresented: $showAddSub) {
            TextField("名称", text: $subName)
            TextField("m3u 链接", text: $subURL)
            Button("取消", role: .cancel) { resetSubFields() }
            Button("添加") {
                let name = subName.trimmingCharacters(in: .whitespaces)
                let url = subURL.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty && !url.isEmpty {
                    store.addSubscription(name: name, url: url)
                }
                resetSubFields()
            }
            .disabled(subName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    @ViewBuilder
    private func subscriptionRow(_ sub: Subscription) -> some View {
        #if os(iOS)
        VStack(alignment: .leading, spacing: 2) {
            Text(sub.name)
            Text(sub.url)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .swipeActions(edge: .trailing) {
            Button("删除", role: .destructive) { store.removeSubscription(sub) }
        }
        #else
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(sub.name)
                Text(sub.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button(role: .destructive) {
                store.removeSubscription(sub)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("删除订阅")
        }
        #endif
    }

    @ViewBuilder
    private var syncButtons: some View {
        #if os(iOS)
        Button {
            Task { await syncAll() }
        } label: {
            Label(syncing ? "同步中…" : "手动同步全部订阅",
                  systemImage: "arrow.triangle.2.circlepath")
        }
        .disabled(syncing || store.subscriptions.isEmpty)
        Button("添加订阅") { showAddSub = true }
        #else
        HStack {
            Button {
                Task { await syncAll() }
            } label: {
                Label(syncing ? "同步中…" : "手动同步全部订阅",
                      systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(syncing || store.subscriptions.isEmpty)
            .buttonStyle(.borderedProminent)

            Button("添加订阅") { showAddSub = true }
                .buttonStyle(.bordered)

            if syncing {
                ProgressView()
                    .controlSize(.small)
                    .padding(.leading, 4)
            }
        }
        #endif
    }

    @ViewBuilder
    private var networkCheckButton: some View {
        #if os(iOS)
        Button {
            Task { await runChecks() }
        } label: {
            Label(checking ? "检查中…" : "检查全部电台连通性",
                  systemImage: "network")
        }
        .disabled(checking)
        #else
        HStack {
            Button {
                Task { await runChecks() }
            } label: {
                Label(checking ? "检查中…" : "检查全部电台连通性",
                      systemImage: "network")
            }
            .disabled(checking)
            .buttonStyle(.bordered)

            if checking {
                ProgressView()
                    .controlSize(.small)
                    .padding(.leading, 4)
            }
        }
        #endif
    }

    @ViewBuilder
    private var checkResultsContent: some View {
        let ok = checkResults.values.filter(\.ok).count
        let fail = Array(checkResults.filter { !$0.value.ok })
        HStack {
            Text("可播 \(ok) 个，失败 \(fail.count) 个")
            Spacer()
            if !fail.isEmpty {
                Button("删除全部失败", role: .destructive) { deleteAllFailed() }
                    .font(.caption)
            }
        }
        ForEach(fail, id: \.key) { url, result in
            failedRow(url: url, result: result)
        }
    }

    @ViewBuilder
    private func failedRow(url: String, result: ConnectivityChecker.Result) -> some View {
        #if os(iOS)
        HStack {
            Text(store.stations.first { $0.url == url }?.name ?? url)
                .lineLimit(1)
            Spacer()
            Text(result.message ?? "失败")
                .font(.caption)
                .foregroundStyle(.red)
        }
        .swipeActions(edge: .trailing) {
            Button("从列表删除", role: .destructive) { deleteFailed(url) }
        }
        #else
        HStack {
            Text(store.stations.first { $0.url == url }?.name ?? url)
                .lineLimit(1)
            Spacer()
            Text(result.message ?? "失败")
                .font(.caption)
                .foregroundStyle(.red)
            Button(role: .destructive) {
                deleteFailed(url)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("从列表删除")
        }
        #endif
    }

    private func resetSubFields() {
        subName = ""
        subURL = ""
    }

    private func syncAll() async {
        syncing = true
        syncResult = nil
        let n = await store.syncAllSubscriptions()
        syncResult = n < 0 ? "同步失败，请检查网络与订阅链接" : "已新增 \(n) 个电台（按播放链接去重）"
        syncing = false
    }

    private func runChecks() async {
        checking = true
        checkResults = [:]
        for station in store.stations {
            checkResults[station.url] = await ConnectivityChecker.check(station.url)
        }
        checking = false
    }

    private func deleteFailed(_ url: String) {
        store.remove(store.stations.filter { $0.url == url })
        checkResults.removeValue(forKey: url)
    }

    private func deleteAllFailed() {
        let failedURLs = Set(checkResults.filter { !$0.value.ok }.keys)
        store.remove(store.stations.filter { failedURLs.contains($0.url) })
        checkResults = checkResults.filter { !failedURLs.contains($0.key) }
    }
}

// MARK: - 关于页
struct AboutView: View {
    static let appVersion: String = {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }()

    #if os(iOS)
    private let platformName = "iOS"
    #else
    private let platformName = "macOS"
    #endif

    var body: some View {
        Form {
            headerSection
                #if os(macOS)
                .listRowSeparator(.hidden)
                #endif

            Section("信息") {
                LabeledContent("版本") { Text("\(Self.appVersion) (\(platformName))") }
                LabeledContent("作者") { Text("GZYZhy") }
                LabeledContent("许可证") { Text("MIT") }
                Link(destination: URL(string: "https://github.com/GZYZhy/stream-radio")!) {
                    Label("GitHub 仓库", systemImage: "link")
                }
                Link(destination: URL(string: "https://www.zdeweb.cn")!) {
                    Label("作者博客", systemImage: "link")
                }
                Link(destination: URL(string: "https://github.com/GZYZhy/stream-radio#免责声明")!) {
                    Label("免责声明", systemImage: "link")
                }
            }

            Section("说明") {
                Text("极简原生网络电台播放器，支持电台播放、收藏、m3u 导入订阅、节目信息显示、通知栏控制等功能。\n\n本程序不运营、不存储、不提供任何音频内容，所有播放能力仅面向用户自行添加的音频流地址。\n电台质量与网络环境和电台来源有关，请自行添加拥有合法授权的音源。\n\n© 2026 GZYZhy")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .formStyle(.grouped)
        #endif
        .navigationTitle("关于")
    }

    @ViewBuilder
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image("app-icon")
                .resizable()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            Text("网络电台")
                .font(.title2.bold())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
}

// MARK: - 帮助页
struct HelpView: View {
    var body: some View {
        Form {
            Section("快速上手") {
                LabeledContent("播放电台") { Text("点击电台即可开始播放") }
                LabeledContent("搜索电台") { Text("列表顶部搜索框，按名称/地址过滤") }
                LabeledContent("节目信息") { Text("当电台来源包含节目单时会自动展示") }
            }

            Section("电台管理") {
                LabeledContent("添加电台") { Text("列表右上角「+」填写名称与播放地址") }
                LabeledContent("本地导入") { Text(importHint) }
                LabeledContent(longPressLabel) {
                    Text("编辑 / 上移 / 下移 / 标星 / 删除")
                }
                #if os(iOS)
                LabeledContent("左滑电台") { Text("编辑 / 删除") }
                #endif
            }

            Section("星标") {
                LabeledContent("标星") { Text(favoriteHint) }
                LabeledContent("星标列表") { Text("侧边栏 → 星标台 可查看所有标星电台") }
            }

            Section("订阅") {
                LabeledContent("入口") { Text("侧边栏 → 设置 → 订阅") }
                LabeledContent("添加订阅") { Text("填写名称与 m3u 链接") }
                LabeledContent("手动同步") { Text("下载解析后按播放链接去重，只新增不重复的电台") }
                LabeledContent("启动时同步") { Text("打开后启动时会自动拉取链接进行同步") }
                LabeledContent("说明") { Text("同步功能不会移除已存在的电台，仅新增不重复的电台") }
            }

            Section("网络") {
                LabeledContent("连通性检查") { Text("侧边栏 → 设置 → 检查全部电台") }
                LabeledContent("删除电台") { Text(deleteHint) }
                LabeledContent("说明") { Text("当电台数量过多时，检查可能需要较长时间") }
            }

            Section("外观与其他") {
                LabeledContent("深浅色") { Text("设置 → 外观，跟随系统 / 浅色 / 深色") }
                LabeledContent("后台播放") { Text("通知栏 / 控制中心可查看节目并切台") }
                LabeledContent("质量指示") { Text("播放页会展示获取到的码率、格式、延迟、声道数信息") }
                #if os(iOS)
                LabeledContent("播放设备") { Text("请通过控制中心切换播放声音的设备") }
                #endif
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .formStyle(.grouped)
        #endif
        .navigationTitle("帮助")
    }

    private var longPressLabel: String {
        #if os(iOS)
        "长按电台"
        #else
        "右键电台"
        #endif
    }

    private var importHint: String {
        #if os(iOS)
        "列表右上角「⇩」从「文件」选择m3u文件"
        #else
        "列表右上角「⇩」选择 m3u 文件"
        #endif
    }

    private var favoriteHint: String {
        #if os(iOS)
        "长按或点行尾星标，支持控制中心星标"
        #else
        "点击行尾星标图标 / 右键菜单，支持控制中心星标"
        #endif
    }

    private var deleteHint: String {
        #if os(iOS)
        "可一键删除 / 左划删除失败电台"
        #else
        "可一键删除 / 单独删除失败电台"
        #endif
    }
}
