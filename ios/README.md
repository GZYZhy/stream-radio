# 网络电台（iOS / iPadOS 版）

macOS 版（PyQt6）的 SwiftUI 原生移植。仓库内已含完整 Xcode 工程，直接用 Xcode 打开即可构建运行。

## 功能特性

- **电台列表 + 搜索**：内置台与根目录 `radio.m3u` 保持一致（CCTV-1 / CCTV-13 / CNR 中国之声）
- **播放页**：节目信息（ICY 元数据）、标星收藏、控制中心集成（媒体键 + 锁屏星标）
- **导入 m3u**：导入前可勾选要导入的台，按 URL 去重，稳健解析"不太干净"的 m3u
- **订阅**：定时刷新订阅列表，支持启动时自动同步（默认关闭）
- **失败台管理**：一键删除全部连接失败的台，列表项左滑可单个删除
- **悬浮球**：播放页收起后最小化为右下角小圆球，点击重新打开
- **后台播放**：锁屏 / 切后台继续播放；支持 http 明文流源
- 版本 1.2，支持 iPhone / iPad（iOS 17+）

## 构建运行

```bash
open stream-radio/stream-radio.xcodeproj
```

Xcode 中选择 `stream-radio` scheme，选中真机或模拟器后 ⌘R 构建运行。

> 免费 Apple ID 签名：App 每 7 天过期，需重新用 Xcode 构建安装一次。上架 App Store 需付费开发者账号（每年 ¥688）。

## 文件

| 路径 | 作用 |
| --- | --- |
| `stream-radio/stream-radio.xcodeproj/` | Xcode 工程（scheme 为 stream-radio） |
| `stream-radio/stream-radio/RadioApp.swift` | App 入口，注入数据、启动自动同步订阅 |
| `stream-radio/stream-radio/RadioModel.swift` | 电台模型 + m3u 解析 + 订阅 + 持久化 |
| `stream-radio/stream-radio/RadioPlayer.swift` | AVPlayer 封装、后台播放、锁屏信息 |
| `stream-radio/stream-radio/StationListView.swift` | 列表、搜索、悬浮球、导入 m3u |
| `stream-radio/stream-radio/NowPlayingView.swift` | 正在播放界面、标星按钮 |
| `stream-radio/stream-radio/SettingsView.swift` | 设置：订阅、失败台管理、关于 |
| `stream-radio/stream-radio/Info.plist` | 后台音频、http 放行（ATS）、启动屏、图标 |
| `stream-radio/stream-radio/Assets.xcassets/` | App 图标资源 |

## 说明

- 节目信息来自 **ICY 流内元数据**（`AVPlayerItem.timedMetadata`）。支持 ICY 的电台显示「歌手 - 曲目」；HLS 台和少数不返回元数据的台只显示站名，属正常现象。
- 播放器请求头内置了干净 UA 与 `Icy-MetaData: 1`。
- 首页「+」可手动添加单个电台；「⇩」可从「文件」App 导入 `.m3u` 播放列表。
- 完整双平台说明见仓库根目录 `README.md`。
