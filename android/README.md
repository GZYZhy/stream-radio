# 📻 网络电台 (Android 版)

[English](README.en.md)

Android 原生版网络电台播放器，使用 **Kotlin + Jetpack Compose + Media3 (ExoPlayer)** 实现，与 iOS 版功能对齐。

> 最低支持 Android 8.0（API 26）

## 功能特性

- **电台列表 + 搜索**：内置电台（与 iOS / macOS 版一致），支持搜索筛选
- **播放页**：节目信息、标星收藏、通知栏控制（媒体按钮）、播放质量指示器（编码/码率/采样率/声道/延迟四色标注）
- **导入 m3u**：本地文件导入，导入前可勾选要导入的台，按 URL 去重
- **订阅**：定时刷新订阅列表，支持启动时自动同步（默认关闭）
- **失败台管理**：一键删除全部连接失败的台
- **悬浮球**：播放时右下角小圆球（全局悬浮窗需手动授权）
- **后台播放**：锁屏 / 切后台继续播放；支持 http 明文流源
- **定时停播**：预设时长 + 自定义
- **深色 / 浅色主题**：跟随系统 / 浅色 / 深色

## 构建运行

### 方式一：Android Studio（推荐）

```bash
# 用 Android Studio 打开 android 目录
# File → Open → 选择 stream-radio/android
# 连接真机或启动模拟器，点击 Run
```

### 方式二：命令行

```bash
cd android

# 首次运行会自动下载 Gradle 和依赖
./gradlew assembleDebug

# 安装到已连接的设备
./gradlew installDebug
```

> APK 输出路径：`app/build/outputs/apk/debug/app-debug.apk`

## 目录结构

```
android/
├── app/
│   └── src/main/
│       ├── AndroidManifest.xml
│       ├── java/com/gzyzhy/streamradio/
│       │   ├── RadioApp.kt              # Application 入口
│       │   ├── MainActivity.kt          # 主 Activity
│       │   ├── data/                    # 数据层
│       │   │   ├── Models.kt            # 数据模型（Station / Subscription 等）
│       │   │   ├── M3UParser.kt         # m3u 解析 + 连通性检查
│       │   │   └── StationRepository.kt # 电台仓库（增删改查 + 持久化）
│       │   ├── service/                 # 服务层
│       │   │   ├── RadioPlaybackService.kt  # 播放前台服务 + MediaSession
│       │   │   └── FloatingBubbleService.kt # 全局悬浮球服务
│       │   ├── ui/                      # UI 层
│       │   │   ├── AppNavHost.kt        # 导航
│       │   │   ├── theme/               # 主题
│       │   │   ├── components/          # 公共组件
│       │   │   └── screens/             # 各页面
│       │   └── util/
│       │       └── SettingsManager.kt   # 设置项管理
│       └── res/                         # 资源
├── build.gradle.kts
├── settings.gradle.kts
└── gradle.properties
```

## 技术栈

- **语言**：Kotlin
- **UI**：Jetpack Compose（Material 3）
- **导航**：Navigation Compose
- **媒体播放**：AndroidX Media3 (ExoPlayer)
- **媒体控制**：MediaSession + MediaStyle 通知
- **数据存储**：DataStore Preferences
- **网络**：OkHttp
- **架构**：单 Activity + 分层架构（data / service / ui）

## 与 iOS 版功能对照

| 功能 | iOS (SwiftUI) | Android (Compose) |
|------|---------------|-------------------|
| 电台列表 | ✅ | ✅ |
| 搜索 | ✅ | ✅ |
| 播放 / 暂停 | ✅ | ✅ |
| 上下换台 | ✅ | ✅ |
| 节目信息（ICY） | ✅ | ✅ |
| 播放质量指示器 | ✅ | ✅ |
| 星标收藏 | ✅ | ✅ |
| 添加 / 编辑 / 删除电台 | ✅ | ✅ |
| 上移 / 下移排序 | ✅ | ✅ |
| m3u 文件导入 | ✅ | ✅ |
| 导入预览（勾选） | ✅ | ✅ |
| 订阅管理 | ✅ | ✅ |
| 启动时自动同步 | ✅ | ✅ |
| 连通性检查 | ✅ | ✅ |
| 一键删除失败台 | ✅ | ✅ |
| 定时停播 | ✅ | ✅ |
| 通知栏 / 控制中心 | ✅ | ✅ |
| 锁屏控制 | ✅ | ✅ |
| 深浅色主题 | ✅ | ✅ |
| 悬浮球 | ✅（应用内） | ✅（全局悬浮窗） |
| 后台播放 | ✅ | ✅ |
| 帮助 / 关于页 | ✅ | ✅ |

## 悬浮球权限

全局悬浮球需要「悬浮窗」权限：
- Android 6.0+：首次使用会跳转设置页，请手动开启「显示在其他应用上层」

## 免责声明

与主项目一致，详见 [README.md](../README.md) 免责声明章节。

## 许可证

MIT License
