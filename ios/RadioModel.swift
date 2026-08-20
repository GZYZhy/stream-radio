import Foundation
import Observation

// 电台模型
struct Station: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var url: String
    var isFavorite: Bool = false
}

// 订阅源（手动同步 m3u 列表）
struct Subscription: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var url: String
}

// 电台仓库：内置示例、增删改移、星标、m3u 导入、订阅同步、持久化
@Observable
final class StationStore {
    private static let key = "stations_v1"
    private static let subsKey = "subscriptions_v1"

    var stations: [Station]
    var subscriptions: [Subscription]

    init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([Station].self, from: data),
           !decoded.isEmpty {
            stations = decoded
        } else {
            stations = Self.builtin
        }
        if let data = defaults.data(forKey: Self.subsKey),
           let decoded = try? JSONDecoder().decode([Subscription].self, from: data) {
            subscriptions = decoded
        } else {
            subscriptions = []
        }
    }

    // ---- 电台增删改移 ----

    func add(_ station: Station) {
        stations.append(station)
        save()
    }

    /// 批量导入已选择的电台（按 URL 去重，重复的跳过）
    func importSelected(_ stations: [Station]) {
        var urls = existingURLs
        for s in stations where !urls.contains(s.url) {
            urls.insert(s.url)
            self.stations.append(s)
        }
        save()
    }

    func remove(_ targets: [Station]) {
        stations.removeAll { targets.contains($0) }
        save()
    }

    func update(_ station: Station, name: String, url: String) {
        guard let i = stations.firstIndex(of: station) else { return }
        let newName = name.trimmingCharacters(in: .whitespaces)
        let newURL = url.trimmingCharacters(in: .whitespaces)
        guard !newName.isEmpty else { return }
        stations[i].name = newName
        if !newURL.isEmpty { stations[i].url = newURL }
        save()
    }

    func moveUp(_ station: Station) {
        guard let i = stations.firstIndex(of: station), i > 0 else { return }
        stations.swapAt(i, i - 1)
        save()
    }

    func moveDown(_ station: Station) {
        guard let i = stations.firstIndex(of: station), i < stations.count - 1 else { return }
        stations.swapAt(i, i + 1)
        save()
    }

    func toggleFavorite(_ station: Station) {
        guard let i = stations.firstIndex(of: station) else { return }
        stations[i].isFavorite.toggle()
        save()
    }

    // ---- 订阅 ----

    func addSubscription(name: String, url: String) {
        let trimmed = url.trimmingCharacters(in: .whitespaces)
        // 相同链接的订阅不重复添加
        guard !subscriptions.contains(where: { $0.url == trimmed }) else { return }
        subscriptions.append(Subscription(name: name, url: trimmed))
        saveSubscriptions()
    }

    func removeSubscription(_ sub: Subscription) {
        subscriptions.removeAll { $0 == sub }
        saveSubscriptions()
    }

    /// 手动同步全部订阅，返回新增电台数（失败返回 -1）
    @MainActor
    func syncAllSubscriptions() async -> Int {
        var total = 0
        for sub in subscriptions {
            let n = await syncSubscription(sub)
            if n > 0 { total += n }
        }
        return total
    }

    /// 同步单个订阅：下载 m3u → 按播放链接去重合并
    @MainActor
    func syncSubscription(_ sub: Subscription) async -> Int {
        do {
            let text = try await Self.downloadText(sub.url)
            let fresh = Self.parseM3U(text).filter { !existingURLs.contains($0.url) }
            guard !fresh.isEmpty else { return 0 }
            stations.append(contentsOf: fresh)
            save()
            return fresh.count
        } catch {
            return -1
        }
    }

    private var existingURLs: Set<String> {
        Set(stations.map(\.url))
    }

    // ---- 持久化 ----

    private func save() {
        if let data = try? JSONEncoder().encode(stations) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    private func saveSubscriptions() {
        if let data = try? JSONEncoder().encode(subscriptions) {
            UserDefaults.standard.set(data, forKey: Self.subsKey)
        }
    }

    // ---- m3u 解析（与 macOS 版 load_radios 一致的宽松逻辑） ----

    /// 内置示例电台（与 radio.m3u 保持一致）
    static let builtin: [Station] = [
        Station(name: "CCTV-1", url: "https://piccpndali.v.myalicdn.com/audio/cctv1_2.m3u8"),
        Station(name: "CCTV-13", url: "https://piccpndali.v.myalicdn.com/audio/cctv13_2.m3u8"),
        Station(name: "CNR 中国之声", url: "https://ngcdn001.cnr.cn/live/zgzs/index.m3u8"),
    ]

    /// 解析 m3u 文本，兼容带 tvg-* / group-title 等扩展属性的脏格式：
    /// - #EXTINF 行频道名取最后一个逗号之后（属性里的逗号不影响）
    /// - #EXTM3U / #Update: / #EXTGRP: 等 # 注释行跳过
    /// - 裸地址行没有名称时回退为 URL 文件名
    /// - 自动去 BOM、去地址首尾引号、过滤非 http(s) 行、按 URL 去重
    static func parseM3U(_ text: String) -> [Station] {
        var result: [Station] = []
        var pendingName: String?
        var seen: Set<String> = []
        // 去掉 BOM（部分文件头带 \u{FEFF}）
        let cleaned = text.replacingOccurrences(of: "\u{FEFF}", with: "")
        for raw in cleaned.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            let upper = line.uppercased()
            if upper == "#EXTM3U" || line.hasPrefix("#Update:") { continue }
            if line.hasPrefix("#EXTINF:") {
                if let comma = line.lastIndex(of: ",") {
                    let name = String(line[line.index(after: comma)...]).trimmingCharacters(in: .whitespaces)
                    pendingName = name.isEmpty ? nil : name
                } else {
                    pendingName = nil
                }
            } else if line.hasPrefix("#") {
                continue
            } else {
                // 地址行：去掉首尾引号，仅接受 http(s)，过滤残留文本行与重复地址
                let url = line.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                let lower = url.lowercased()
                guard lower.hasPrefix("http://") || lower.hasPrefix("https://"),
                      !seen.contains(url) else { continue }
                seen.insert(url)
                let name = pendingName ?? Self.fallbackName(for: url)
                result.append(Station(name: name, url: url))
                pendingName = nil
            }
        }
        return result
    }

    private static func fallbackName(for url: String) -> String {
        let file = URL(string: url)?.lastPathComponent ?? ""
        return file.isEmpty ? url : file
    }

    /// 下载文本（订阅 m3u 用），UTF-8 优先，latin1 兜底
    static func downloadText(_ urlString: String) async throws -> String {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Mozilla/5.0 RadioPlayer/1.0", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
    }
}

// 连通性检查：HEAD 优先，失败时 GET 读少量字节兜底（部分流媒体服务器不支持 HEAD）
enum ConnectivityChecker {
    struct Result {
        var ok: Bool
        var durationMs: Int
        var message: String?
    }

    static func check(_ urlString: String, timeout: TimeInterval = 5) async -> Result {
        guard let url = URL(string: urlString) else {
            return Result(ok: false, durationMs: 0, message: "无效地址")
        }
        let start = Date()
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue("Mozilla/5.0 RadioPlayer/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("1", forHTTPHeaderField: "Icy-MetaData")

        // 1) HEAD
        request.httpMethod = "HEAD"
        do {
            let (_, resp) = try await URLSession.shared.data(for: request)
            if let code = (resp as? HTTPURLResponse)?.statusCode, (200..<400).contains(code) {
                return Result(ok: true, durationMs: Self.elapsed(start), message: nil)
            }
        } catch {}

        // 2) GET 兜底：读少量字节确认可播
        request.httpMethod = "GET"
        do {
            let (bytes, resp) = try await URLSession.shared.bytes(for: request)
            var count = 0
            do {
                for try await _ in bytes {
                    count += 1
                    if count >= 4096 { break }
                }
            } catch {}
            bytes.task.cancel()
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<400).contains(code) {
                return Result(ok: true, durationMs: Self.elapsed(start), message: nil)
            }
            if [401, 403, 404, 405, 416].contains(code) {
                // 部分服务器对不支持的操作返回这些状态，但实际能播
                return Result(ok: true, durationMs: Self.elapsed(start), message: "HTTP \(code)")
            }
            return Result(ok: false, durationMs: Self.elapsed(start), message: "HTTP \(code)")
        } catch {
            return Result(ok: false, durationMs: Self.elapsed(start), message: error.localizedDescription)
        }
    }

    private static func elapsed(_ start: Date) -> Int {
        Int(Date().timeIntervalSince(start) * 1000)
    }
}
