# 网络电台（iOS / iPadOS 版）

macOS 版（PyQt6）的 SwiftUI 原生移植，**砍掉了录制、自定义 UA、订阅刷新、连通性检查**，只保留核心体验：电台列表 + 搜索 + 播放 + 节目信息 + 星标 + 锁屏控制中心。

## 文件

| 文件 | 作用 |
| --- | --- |
| `RadioApp.swift` | App 入口，注入数据 |
| `RadioModel.swift` | 电台模型 + m3u 解析 + UserDefaults 持久化 |
| `RadioPlayer.swift` | AVPlayer 封装、ICY 节目信息、后台播放、锁屏信息 |
| `StationListView.swift` | 列表、搜索、星标、添加、导入 m3u |
| `NowPlayingView.swift` | 正在播放界面 |

## 用 Xcode 跑起来（约 3 分钟）

1. **Xcode → File → New → Project → iOS App**
   - Product Name 随意（如 `Radio`），Interface 选 **SwiftUI**，Language 选 **Swift**，去掉所有勾选框（Core Data 等都不用）。
2. 把本目录的 4 个 `.swift` 文件**全部拖进**工程（替换自带的 `ContentView.swift`）。
3. 配置两个 Info.plist（Xcode 15+ 可在 TARGETS → Info 标签加）：
   - **后台播放**：`UIBackgroundModes` → 数组加 `audio`
   - **允许 http 电台**：`App Transport Security` → `NSAllowsArbitraryLoads = YES`（很多电台是 http 流，不开会被 ATS 拦截）
4. 选择你的 **Team**（免费 Apple ID 即可，签名用 Automatic），选一台设备或模拟器，Cmd+R 运行。

## 说明

- 目标平台 **iOS / iPadOS 17+**（使用了 `@Observable` 与 `@Environment` 新 API）。
- 节目信息来自 **ICY 流内元数据**（`AVPlayerItem.timedMetadata`，2 秒轮询）。支持 ICY 的电台会显示「歌手 - 曲目」；HLS 台和少数不返回元数据的台只显示站名，属正常现象。
- 播放器请求头内置了干净 UA 与 `Icy-MetaData: 1`，**没有**用户自定义 UA 入口。
- 首页「+」可手动添加单个电台；「⇩」可从「文件」App 导入 `.m3u` 播放列表。
- 上架 App Store 需要付费开发者账号（每年 ¥688）；用免费账号只能跑真机/模拟器，App 一周内会过期，需重新安装。

## 想继续扩展？

- **更可靠的节目信息**：可再加 Icecast `/status-json.xsl` 兜底（`URLSession` + `listenurl` 匹配），逻辑参考 macOS 版 `Player.py` 的 `IcecastStatusFetcher`。
- **收藏夹独立页签**：`Station.isFavorite` 已就位，加一个 `List` 过滤即可。
