import SwiftUI

// 设置页：订阅管理（手动同步）+ 连通性检查
struct SettingsView: View {
    @Environment(StationStore.self) private var store

    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @AppStorage("autoSyncOnLaunch") private var autoSyncOnLaunch = false
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

            Section("订阅") {
                Toggle("启动时自动同步", isOn: $autoSyncOnLaunch)
                if store.subscriptions.isEmpty {
                    Text("暂无订阅。添加 m3u 链接后，用下方按钮手动同步拉取电台（按播放链接去重）。")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.subscriptions) { sub in
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
                }
                Button {
                    Task { await syncAll() }
                } label: {
                    Label(syncing ? "同步中…" : "手动同步全部订阅",
                          systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(syncing || store.subscriptions.isEmpty)
                if let syncResult {
                    Text(syncResult)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("添加订阅") { showAddSub = true }
            }

            Section("网络") {
                Button {
                    Task { await runChecks() }
                } label: {
                    Label(checking ? "检查中…" : "检查全部电台连通性",
                          systemImage: "network")
                }
                .disabled(checking)
                if checking {
                    ProgressView()
                } else if !checkResults.isEmpty {
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
                    }
                }
            }

        }
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

    /// 左划删除单个失败电台
    private func deleteFailed(_ url: String) {
        store.remove(store.stations.filter { $0.url == url })
        checkResults.removeValue(forKey: url)
    }

    /// 一键删除全部失败电台
    private func deleteAllFailed() {
        let failedURLs = Set(checkResults.filter { !$0.value.ok }.keys)
        store.remove(store.stations.filter { failedURLs.contains($0.url) })
        checkResults = checkResults.filter { !failedURLs.contains($0.key) }
    }
}

// 关于页：应用图标 + 信息（图标资源在 Assets 的 app-icon）
struct AboutView: View {
    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    Image("app-icon")
                        .resizable()
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .padding(.top, 28)
                    Text("网络电台")
                        .font(.title2.bold())
                    Text("版本 1.2 (iOS)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("MIT License")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 24)
                }
                .frame(maxWidth: .infinity)
            }
            .listRowBackground(Color.clear)
            Section("信息") {
                LabeledContent("作者") {
                    Link("GZYZhy", destination: URL(string: "https://www.zdeweb.cn")!)
                }
                Link(destination: URL(string: "https://github.com/GZYZhy/stream-radio")!) {
                    Label("GitHub 仓库", systemImage: "link")
                }
            }
            Section("说明") {
                Text("极简原生网络电台播放器。\n基于 SwiftUI + AVPlayer，支持 ICY 节目信息、星标、订阅与连通性检查。")
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("关于")
    }
}

// 帮助页：功能介绍
struct HelpView: View {
    var body: some View {
        List {
            Section("快速上手") {
                LabeledContent("播放电台", value: "点击电台行即可开始播放")
                LabeledContent("搜索电台", value: "列表顶部搜索框，按名称/地址实时过滤")
                LabeledContent("节目信息", value: "播放页显示 ICY 流内节目；HLS 台一般只显示站名")
            }
            Section("电台管理") {
                LabeledContent("添加电台", value: "列表右上角「+」填写名称与播放地址")
                LabeledContent("导入 m3u", value: "列表右上角「⇩」从「文件」App 选择播放列表")
                LabeledContent("长按电台", value: "编辑 / 上移 / 下移 / 标星 / 删除")
                LabeledContent("左滑电台", value: "编辑 / 删除")
            }
            Section("星标") {
                LabeledContent("标星", value: "长按或点行尾星标；星标台在侧边栏单独查看")
            }
            Section("订阅") {
                LabeledContent("入口", value: "侧边栏 → 设置 → 订阅")
                LabeledContent("添加订阅", value: "填写名称与 m3u 链接")
                LabeledContent("手动同步", value: "下载解析后按播放链接去重，只新增不重复的电台")
            }
            Section("网络") {
                LabeledContent("连通性检查", value: "侧边栏 → 设置 → 检查全部电台")
                LabeledContent("原理", value: "HEAD 探测，部分服务器不支持时自动 GET 兜底")
            }
            Section("外观与其他") {
                LabeledContent("深浅色", value: "设置 → 外观，跟随系统 / 浅色 / 深色")
                LabeledContent("后台播放", value: "锁屏与控制中心可查看节目并切台")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("帮助")
    }
}
