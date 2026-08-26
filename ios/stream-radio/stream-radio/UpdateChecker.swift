import Foundation

// 版本号：按「.」分段数字比较，正确处理 1.10 > 1.9（不能直接用字符串比较）
struct AppVersion: Comparable {
    let parts: [Int]

    init(_ raw: String) {
        // 去空白与 v/V 前缀，按「.」分段；非法数字段视为 0
        let cleaned = raw.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "^[vV]", with: "", options: .regularExpression)
        parts = cleaned.split(separator: ".").map { Int($0) ?? 0 }
    }

    static func == (a: AppVersion, b: AppVersion) -> Bool { a.parts == b.parts }

    static func < (a: AppVersion, b: AppVersion) -> Bool {
        // 缺位补 0 后逐段比较，如 1.6.1 > 1.6
        let count = max(a.parts.count, b.parts.count)
        for i in 0..<count {
            let x = i < a.parts.count ? a.parts[i] : 0
            let y = i < b.parts.count ? b.parts[i] : 0
            if x != y { return x < y }
        }
        return false
    }
}

// 检查更新结果
enum UpdateCheckResult {
    case upToDate
    case updateAvailable(latest: String, notes: String)  // 最新版本号 + 更新说明
    case failed
}

/// 检查更新：请求 GitHub releases/latest，与本地版本号比较
enum UpdateChecker {
    /// 更新下载页地址：当前为 GitHub releases，将来上架 App Store 后改为商店链接即可
    static let downloadURL = URL(string: "https://github.com/GZYZhy/stream-radio/releases")!
    /// GitHub release 接口响应（取 tag_name 与 body 更新说明）
    private struct GitHubRelease: Decodable {
        let tagName: String
        let body: String
        enum CodingKeys: String, CodingKey { case tagName = "tag_name"; case body }
    }

    /// 拉取 GitHub 最新 release 信息；失败返回 nil
    static func fetchLatestRelease() async -> (version: String, notes: String)? {
        let url = URL(string: "https://api.github.com/repos/GZYZhy/stream-radio/releases/latest")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        // GitHub API 强制要求带 User-Agent，否则返回 403
        request.setValue("StreamRadio-Updater/1.0", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let release = try? JSONDecoder().decode(GitHubRelease.self, from: data) else {
            return nil
        }
        return (release.tagName, release.body)
    }

    /// 检查更新：最新版本 > 当前版本则有新版本；拉取失败返回 failed
    static func check() async -> UpdateCheckResult {
        guard let release = await fetchLatestRelease() else { return .failed }
        let current = AppVersion(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0")
        return AppVersion(release.version) > current ? .updateAvailable(latest: release.version, notes: release.notes) : .upToDate
    }
}
