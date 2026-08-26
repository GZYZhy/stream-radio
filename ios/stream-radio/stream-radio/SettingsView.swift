import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

// 设置页：订阅管理（手动同步）+ 连通性检查
struct SettingsView: View {
    @Environment(StationStore.self) private var store

    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @AppStorage("appLanguage") private var appLanguage = "system"
    @AppStorage("autoSyncOnLaunch") private var autoSyncOnLaunch = false
    @State private var showLanguageRestartAlert = false
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
    // 检查更新：手动触发，结果用 alert（简单提示）或 sheet（可滚动更新说明）展示
    @State private var checkingUpdate = false
    @State private var updateResult: UpdateCheckResult?
    @State private var showUpdateAlert = false
    @State private var showUpdateSheet = false

    var body: some View {
        Form {
            Section(NSLocalizedString("settings_section_appearance", comment: "")) {
                Picker(NSLocalizedString("settings_appearance", comment: ""), selection: $appearanceMode) {
                    Text(NSLocalizedString("settings_appearance_system", comment: "")).tag("system")
                    Text(NSLocalizedString("settings_appearance_light", comment: "")).tag("light")
                    Text(NSLocalizedString("settings_appearance_dark", comment: "")).tag("dark")
                }
                .pickerStyle(.segmented)

                Picker(NSLocalizedString("settings_language", comment: ""), selection: $appLanguage) {
                    Text(NSLocalizedString("settings_language_system", comment: "")).tag("system")
                    Text(NSLocalizedString("settings_language_zh", comment: "")).tag("zh-Hans")
                    Text(NSLocalizedString("settings_language_en", comment: "")).tag("en")
                    Text(NSLocalizedString("settings_language_fr", comment: "")).tag("fr")
                    Text(NSLocalizedString("settings_language_ja", comment: "")).tag("ja")
                }
                .onChange(of: appLanguage) { _, _ in
                    showLanguageRestartAlert = true
                }
            }

            #if os(macOS)
            Section(NSLocalizedString("settings_section_window", comment: "")) {
                Picker(NSLocalizedString("settings_close_behavior", comment: ""), selection: $closeBehavior) {
                    Text(NSLocalizedString("settings_close_ask", comment: "")).tag("ask")
                    Text(NSLocalizedString("settings_close_hide", comment: "")).tag("hideToTray")
                    Text(NSLocalizedString("settings_close_quit", comment: "")).tag("quit")
                }
                Text(NSLocalizedString("settings_close_hint", comment: ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            #endif

            Section(NSLocalizedString("settings_section_subscription", comment: "")) {
                Toggle(NSLocalizedString("settings_auto_sync", comment: ""), isOn: $autoSyncOnLaunch)
                if store.subscriptions.isEmpty {
                    Text(NSLocalizedString("settings_no_subscription", comment: ""))
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

            Section(NSLocalizedString("settings_section_network", comment: "")) {
                networkCheckButton
                if checking {
                    ProgressView()
                } else if !checkResults.isEmpty {
                    checkResultsContent
                }
            }

            Section(NSLocalizedString("settings_section_other", comment: "")) {
                updateButton
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .formStyle(.grouped)
        #endif
        .navigationTitle(NSLocalizedString("nav_title_settings", comment: ""))
        .alert(NSLocalizedString("settings_add_sub_title", comment: ""), isPresented: $showAddSub) {
            TextField(NSLocalizedString("name", comment: ""), text: $subName)
            TextField(NSLocalizedString("m3u_link", comment: ""), text: $subURL)
            Button(NSLocalizedString("cancel", comment: ""), role: .cancel) { resetSubFields() }
            Button(NSLocalizedString("add", comment: "")) {
                let name = subName.trimmingCharacters(in: .whitespaces)
                let url = subURL.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty && !url.isEmpty {
                    store.addSubscription(name: name, url: url)
                }
                resetSubFields()
            }
            .disabled(subName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .alert(NSLocalizedString("settings_language", comment: ""), isPresented: $showLanguageRestartAlert) {
            Button(NSLocalizedString("ok", comment: ""), role: .cancel) { }
        } message: {
            Text(NSLocalizedString("settings_language_restart_hint", comment: ""))
        }
        .alert(updateAlertTitle, isPresented: $showUpdateAlert) {
            Button(NSLocalizedString("ok", comment: ""), role: .cancel) { }
        }
        .sheet(isPresented: $showUpdateSheet) {
            if case let .updateAvailable(latest, notes) = updateResult {
                UpdateSheetView(version: latest, notes: notes) { openDownloadPage() }
            }
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
            Button(NSLocalizedString("delete", comment: ""), role: .destructive) { store.removeSubscription(sub) }
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
            .help(NSLocalizedString("row_delete_subscription", comment: ""))
        }
        #endif
    }

    @ViewBuilder
    private var syncButtons: some View {
        let syncLabel = syncing
            ? NSLocalizedString("settings_syncing", comment: "")
            : NSLocalizedString("settings_sync_manual", comment: "")
        #if os(iOS)
        Button {
            Task { await syncAll() }
        } label: {
            Label(syncLabel, systemImage: "arrow.triangle.2.circlepath")
        }
        .disabled(syncing || store.subscriptions.isEmpty)
        Button(NSLocalizedString("settings_add_subscription", comment: "")) { showAddSub = true }
        #else
        HStack {
            Button {
                Task { await syncAll() }
            } label: {
                Label(syncLabel, systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(syncing || store.subscriptions.isEmpty)
            .buttonStyle(.borderedProminent)

            Button(NSLocalizedString("settings_add_subscription", comment: "")) { showAddSub = true }
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
        let checkLabel = checking
            ? NSLocalizedString("settings_checking", comment: "")
            : NSLocalizedString("settings_check_connectivity", comment: "")
        #if os(iOS)
        Button {
            Task { await runChecks() }
        } label: {
            Label(checkLabel, systemImage: "network")
        }
        .disabled(checking)
        #else
        HStack {
            Button {
                Task { await runChecks() }
            } label: {
                Label(checkLabel, systemImage: "network")
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
    private var updateButton: some View {
        let label = checkingUpdate
            ? NSLocalizedString("checking_update", comment: "")
            : NSLocalizedString("settings_check_update", comment: "")
        #if os(iOS)
        Button {
            Task { await checkUpdate() }
        } label: {
            Label(label, systemImage: "arrow.down.circle")
        }
        .disabled(checkingUpdate)
        #else
        HStack {
            Button {
                Task { await checkUpdate() }
            } label: {
                Label(label, systemImage: "arrow.down.circle")
            }
            .disabled(checkingUpdate)
            .buttonStyle(.bordered)

            if checkingUpdate {
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
            Text(String(format: NSLocalizedString("settings_check_result", comment: ""), ok, fail.count))
            Spacer()
            if !fail.isEmpty {
                Button(NSLocalizedString("settings_delete_all_failed", comment: ""), role: .destructive) { deleteAllFailed() }
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
            Text(result.message ?? NSLocalizedString("settings_failed_default", comment: ""))
                .font(.caption)
                .foregroundStyle(.red)
        }
        .swipeActions(edge: .trailing) {
            Button(NSLocalizedString("row_delete_from_list", comment: ""), role: .destructive) { deleteFailed(url) }
        }
        #else
        HStack {
            Text(store.stations.first { $0.url == url }?.name ?? url)
                .lineLimit(1)
            Spacer()
            Text(result.message ?? NSLocalizedString("settings_failed_default", comment: ""))
                .font(.caption)
                .foregroundStyle(.red)
            Button(role: .destructive) {
                deleteFailed(url)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help(NSLocalizedString("row_delete_from_list", comment: ""))
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
        syncResult = n < 0
            ? NSLocalizedString("settings_sync_result_failed", comment: "")
            : String(format: NSLocalizedString("settings_sync_result_success", comment: ""), n)
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

    /// 手动检查更新：网络请求在后台执行，完成后按结果展示弹窗或可滚动更新说明
    private func checkUpdate() async {
        checkingUpdate = true
        let result = await UpdateChecker.check()
        updateResult = result
        checkingUpdate = false
        switch result {
        case .updateAvailable: showUpdateSheet = true
        case .upToDate, .failed: showUpdateAlert = true
        }
    }

    /// 简单提示的标题（已是最新 / 检查失败）
    private var updateAlertTitle: String {
        switch updateResult {
        case .upToDate: return NSLocalizedString("update_latest", comment: "")
        case .failed, nil: return NSLocalizedString("update_failed", comment: "")
        default: return ""
        }
    }

    /// 打开更新下载页（当前跳 GitHub releases，将来可改为 App Store）
    private func openDownloadPage() {
        #if os(iOS)
        UIApplication.shared.open(UpdateChecker.downloadURL)
        #else
        NSWorkspace.shared.open(UpdateChecker.downloadURL)
        #endif
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

    /// 免责声明链接：中文环境跳中文版，其他跳英文版
    static var disclaimerURL: URL {
        let isZh = Bundle.main.preferredLocalizations.first?.hasPrefix("zh") ?? true
        let anchor = isZh ? "#%E5%85%8D%E8%B4%A3%E5%A3%B0%E6%98%8E" : "#disclaimer"
        let file = isZh ? "README.md" : "README.en.md"
        return URL(string: "https://github.com/GZYZhy/stream-radio/blob/main/\(file)\(anchor)")!
    }

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

            Section(NSLocalizedString("about_section_info", comment: "")) {
                LabeledContent(NSLocalizedString("about_version", comment: "")) { Text("\(Self.appVersion) (\(platformName))") }
                LabeledContent(NSLocalizedString("about_author", comment: "")) { Text("GZYZhy") }
                LabeledContent(NSLocalizedString("about_license", comment: "")) { Text("MIT") }
                Link(destination: URL(string: "https://github.com/GZYZhy/stream-radio")!) {
                    Label(NSLocalizedString("about_github", comment: ""), systemImage: "link")
                }
                Link(destination: URL(string: "https://www.zdeweb.cn")!) {
                    Label(NSLocalizedString("about_blog", comment: ""), systemImage: "link")
                }
                Link(destination: Self.disclaimerURL) {
                    Label(NSLocalizedString("about_disclaimer_link", comment: ""), systemImage: "link")
                }
            }

            Section(NSLocalizedString("about_section_description", comment: "")) {
                Text(NSLocalizedString("about_description", comment: ""))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .formStyle(.grouped)
        #endif
        .navigationTitle(NSLocalizedString("nav_title_about", comment: ""))
    }

    @ViewBuilder
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image("app-icon")
                .resizable()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            Text(NSLocalizedString("app_name", comment: ""))
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
            Section(NSLocalizedString("help_section_getting_started", comment: "")) {
                LabeledContent(NSLocalizedString("help_play", comment: "")) { Text(NSLocalizedString("help_play_desc", comment: "")) }
                LabeledContent(NSLocalizedString("help_search", comment: "")) { Text(NSLocalizedString("help_search_desc", comment: "")) }
                LabeledContent(NSLocalizedString("help_program_info", comment: "")) { Text(NSLocalizedString("help_program_info_desc", comment: "")) }
            }

            Section(NSLocalizedString("help_section_station_mgmt", comment: "")) {
                LabeledContent(NSLocalizedString("help_add_station", comment: "")) { Text(NSLocalizedString("help_add_station_desc", comment: "")) }
                LabeledContent(NSLocalizedString("help_import_local", comment: "")) { Text(importHint) }
                LabeledContent(longPressLabel) {
                    Text(NSLocalizedString("help_context_menu_desc", comment: ""))
                }
                #if os(iOS)
                LabeledContent(NSLocalizedString("help_swipe_left", comment: "")) { Text(NSLocalizedString("help_swipe_left_desc", comment: "")) }
                #endif
            }

            Section(NSLocalizedString("help_section_favorites", comment: "")) {
                LabeledContent(NSLocalizedString("help_favorite", comment: "")) { Text(favoriteHint) }
                LabeledContent(NSLocalizedString("help_favorites_list", comment: "")) { Text(NSLocalizedString("help_favorites_list_desc", comment: "")) }
            }

            Section(NSLocalizedString("help_section_subscriptions", comment: "")) {
                LabeledContent(NSLocalizedString("help_sub_entry", comment: "")) { Text(NSLocalizedString("help_sub_entry_desc", comment: "")) }
                LabeledContent(NSLocalizedString("help_sub_add", comment: "")) { Text(NSLocalizedString("help_sub_add_desc", comment: "")) }
                LabeledContent(NSLocalizedString("help_sub_manual_sync", comment: "")) { Text(NSLocalizedString("help_sub_manual_sync_desc", comment: "")) }
                LabeledContent(NSLocalizedString("help_sub_auto_sync", comment: "")) { Text(NSLocalizedString("help_sub_auto_sync_desc", comment: "")) }
                LabeledContent(NSLocalizedString("help_sub_note", comment: "")) { Text(NSLocalizedString("help_sub_note_desc", comment: "")) }
            }

            Section(NSLocalizedString("help_section_network", comment: "")) {
                LabeledContent(NSLocalizedString("help_connectivity_check", comment: "")) { Text(NSLocalizedString("help_connectivity_check_desc", comment: "")) }
                LabeledContent(NSLocalizedString("help_delete_station", comment: "")) { Text(deleteHint) }
                LabeledContent(NSLocalizedString("help_network_note", comment: "")) { Text(NSLocalizedString("help_network_note_desc", comment: "")) }
            }

            Section(NSLocalizedString("help_section_appearance_other", comment: "")) {
                LabeledContent(NSLocalizedString("help_theme", comment: "")) { Text(NSLocalizedString("help_theme_desc", comment: "")) }
                LabeledContent(NSLocalizedString("help_background_playback", comment: "")) { Text(NSLocalizedString("help_background_playback_desc", comment: "")) }
                LabeledContent(NSLocalizedString("help_quality_indicator", comment: "")) { Text(NSLocalizedString("help_quality_indicator_desc", comment: "")) }
                #if os(iOS)
                LabeledContent(NSLocalizedString("help_playback_device", comment: "")) { Text(NSLocalizedString("help_playback_device_desc", comment: "")) }
                #endif
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .formStyle(.grouped)
        #endif
        .navigationTitle(NSLocalizedString("nav_title_help", comment: ""))
    }

    private var longPressLabel: String {
        #if os(iOS)
        NSLocalizedString("help_long_press_ios", comment: "")
        #else
        NSLocalizedString("help_right_click_macos", comment: "")
        #endif
    }

    private var importHint: String {
        #if os(iOS)
        NSLocalizedString("help_import_ios", comment: "")
        #else
        NSLocalizedString("help_import_macos", comment: "")
        #endif
    }

    private var favoriteHint: String {
        #if os(iOS)
        NSLocalizedString("help_favorite_ios", comment: "")
        #else
        NSLocalizedString("help_favorite_macos", comment: "")
        #endif
    }

    private var deleteHint: String {
        #if os(iOS)
        NSLocalizedString("help_delete_ios", comment: "")
        #else
        NSLocalizedString("help_delete_macos", comment: "")
        #endif
    }
}

// MARK: - 发现新版本弹窗
// 可滚动展示更新说明（说明可能很长），底部提供「前往下载 / 稍后」
private struct UpdateSheetView: View {
    let version: String
    let notes: String
    let onDownload: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Text(String(format: NSLocalizedString("update_available_title", comment: ""), version))
                .font(.headline)
                .padding()
            Divider()
            ScrollView {
                Text(notes.isEmpty ? NSLocalizedString("update_notes_empty", comment: "") : notes)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            Divider()
            HStack {
                Button(NSLocalizedString("update_later", comment: "")) { dismiss() }
                Spacer()
                Button(NSLocalizedString("update_go", comment: "")) {
                    dismiss()
                    onDownload()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(minWidth: 380, minHeight: 320)
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
    }
}
