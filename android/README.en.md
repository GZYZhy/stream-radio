# 📻 Stream Radio (Android)

[简体中文](README.md)

A native Android internet radio player built with **Kotlin + Jetpack Compose + Media3 (ExoPlayer)**, feature-aligned with the iOS version.

> Minimum supported version: Android 8.0 (API 26)

## Features

- **Station list + search** — Built-in stations (matching the iOS / macOS version), with search filtering
- **Now Playing** — Program info, favorites, notification controls (media buttons), playback quality indicator (codec / bitrate / sample rate / channels / latency, color-coded in four levels)
- **m3u import** — Import from local files, pick which stations to import, with URL deduplication
- **Subscriptions** — Refresh subscription lists on a schedule, with optional auto-sync on launch (off by default)
- **Failed station management** — One-tap delete of all stations that failed connectivity checks
- **Floating bubble** — A small floating ball during playback (global floating window requires manual permission)
- **Background playback** — Continues playing when locked or in the background; supports http plain-text streams
- **Sleep timer** — Preset durations + custom
- **Dark / light theme** — System / Light / Dark

## Build & Run

### Option 1: Android Studio (recommended)

```bash
# Open the android directory in Android Studio
# File → Open → select stream-radio/android
# Connect a device or start an emulator, then click Run
```

### Option 2: Command line

```bash
cd android

# First run will automatically download Gradle and dependencies
./gradlew assembleDebug

# Install to a connected device
./gradlew installDebug
```

> APK output path: `app/build/outputs/apk/debug/app-debug.apk`

## Project Structure

```
android/
├── app/
│   └── src/main/
│       ├── AndroidManifest.xml
│       ├── java/com/gzyzhy/streamradio/
│       │   ├── RadioApp.kt              # Application entry
│       │   ├── MainActivity.kt          # Main Activity
│       │   ├── data/                    # Data layer
│       │   │   ├── Models.kt            # Data models (Station / Subscription, etc.)
│       │   │   ├── M3UParser.kt         # m3u parsing + connectivity check
│       │   │   └── StationRepository.kt # Station repository (CRUD + persistence)
│       │   ├── service/                 # Service layer
│       │   │   ├── RadioPlaybackService.kt  # Playback foreground service + MediaSession
│       │   │   └── FloatingBubbleService.kt # Global floating bubble service
│       │   ├── ui/                      # UI layer
│       │   │   ├── AppNavHost.kt        # Navigation
│       │   │   ├── theme/               # Theme
│       │   │   ├── components/          # Shared components
│       │   │   └── screens/             # Screens
│       │   └── util/
│       │       └── SettingsManager.kt   # Settings management
│       └── res/                         # Resources
├── build.gradle.kts
├── settings.gradle.kts
└── gradle.properties
```

## Tech Stack

- **Language**: Kotlin
- **UI**: Jetpack Compose (Material 3)
- **Navigation**: Navigation Compose
- **Media playback**: AndroidX Media3 (ExoPlayer)
- **Media controls**: MediaSession + MediaStyle notifications
- **Data storage**: DataStore Preferences
- **Network**: OkHttp
- **Architecture**: Single Activity + layered architecture (data / service / ui)

## Feature Comparison with iOS

| Feature | iOS (SwiftUI) | Android (Compose) |
|---------|---------------|-------------------|
| Station list | ✅ | ✅ |
| Search | ✅ | ✅ |
| Play / Pause | ✅ | ✅ |
| Previous / Next | ✅ | ✅ |
| Program info (ICY) | ✅ | ✅ |
| Quality indicator | ✅ | ✅ |
| Favorites | ✅ | ✅ |
| Add / Edit / Delete stations | ✅ | ✅ |
| Move up / down | ✅ | ✅ |
| m3u file import | ✅ | ✅ |
| Import preview (selection) | ✅ | ✅ |
| Subscription management | ✅ | ✅ |
| Auto-sync on launch | ✅ | ✅ |
| Connectivity check | ✅ | ✅ |
| Delete all failed | ✅ | ✅ |
| Sleep timer | ✅ | ✅ |
| Notification / Control Center | ✅ | ✅ |
| Lock screen controls | ✅ | ✅ |
| Dark / light theme | ✅ | ✅ |
| Floating bubble | ✅ (in-app) | ✅ (global) |
| Background playback | ✅ | ✅ |
| Help / About pages | ✅ | ✅ |

## Floating Bubble Permission

The global floating bubble requires "Display over other apps" permission:
- Android 6.0+: First use will jump to the settings page; please manually enable "Display over other apps".

## Disclaimer

Consistent with the main project. See the [README.md](../README.md) disclaimer section for details.

## License

MIT License

---

*This English translation was generated with the assistance of AI and may contain inaccuracies. Please refer to the Chinese version as the authoritative source.*
