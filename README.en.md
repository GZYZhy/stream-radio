# 📻 Stream Radio

[简体中文](README.md)

A minimal m3u internet radio player for **iPhone / iPad (iOS 17+)** and **macOS (macOS 14+)**.

An Android version is also available.

## Features

- **Radio Playback** — Play internet radio streams in m3u format (supports `m3u8` / `mp3` / `aac` and more)
- **Import Stations** — Import m3u lists from local files, pick which stations to import, with automatic URL deduplication
- **Favorites** — Star your frequently used stations and access them quickly from the Favorites list
- **Program Info** — Parses ICY metadata from the stream to show the current program in real time
- **Playback Quality Indicator** — Shows codec / bitrate / sample rate / channel count, plus startup/buffer latency (color-coded: green / yellow / orange / red)
- **Subscription Sync** — Refresh subscribed m3u lists manually or automatically on launch to keep station sources up to date
- **Dark / Light Theme** — Follows system setting by default, or switch manually
- **Menu Bar Tray** (macOS) — Minimize to the menu bar for background playback; quick controls for play/pause, favorite, and settings from the tray menu
- **Sleep Timer** — Preset durations + custom length, playback stops automatically when the countdown ends

## Build & Run

```bash
open ios/stream-radio/stream-radio.xcodeproj
```

In Xcode, select the `stream-radio` scheme, choose a target device (iPhone / iPad simulator, physical device, or My Mac), then press ⌘R to run.

| Platform | Minimum Version | Notes |
|----------|-----------------|-------|
| iOS | iOS 17 | iPhone / iPad supported |
| macOS | macOS 14 (Sonoma) | Native Apple Silicon / Intel |
| Android | Android 8.0+ | See `android/` directory |

> When signing with a free Apple ID, iOS apps expire every 7 days; macOS builds run directly.

## Usage

| Action | How |
|--------|-----|
| Play a station | Tap a list item to start playing |
| Add a station | Tap the **+** in the top-right to add manually |
| Import a list | Tap the **download icon** in the top-right, choose a local m3u file, select stations, and import |
| Favorite | Tap the star icon at the end of a station row, or long-press (iOS) / right-click (macOS) and choose Favorite |
| Edit / Delete | Long-press (iOS) / right-click (macOS) menu, or swipe left to delete (iOS) |
| Sleep timer | On the Now Playing screen, tap **Sleep Timer** and choose a preset or custom duration |
| Sync subscriptions | Settings → Subscriptions → Manual sync, or enable **Auto-sync on launch** |

## Project Structure

```
├── ios/                      # iOS / macOS native (SwiftUI, single target)
│   └── stream-radio/
│       ├── stream-radio.xcodeproj   # Xcode project
│       └── stream-radio/            # Source code (Swift)
├── android/                  # Android version (Kotlin)
├── build_ios.sh              # iOS build script (outputs .ipa)
├── build_macos.sh            # macOS build script (outputs universal .zip)
├── build_android.sh          # Android build script (outputs .apk)
├── CHANGELOG.md              # Changelog
└── LICENSE                   # MIT License
```

## Tech Stack

**iOS / macOS**
- SwiftUI + AVFoundation (audio playback)
- MediaPlayer framework (Control Center / notification / lock screen info, media keys)
- Single target for both platforms (Supported Destinations include iPhone / iPad / Mac)
- Xcode project with folder-synced source files

**Android**
- Kotlin + Jetpack Compose
- Media3 / ExoPlayer (audio playback)

## Disclaimer

> By using this project, you acknowledge that you have read, understood, and agree to all terms of this disclaimer.

1. **Nature of the Tool**

   This project is an open-source internet audio stream player. It does not operate, host, provide, or recommend any audio streams or media content. All playback is for audio stream URLs added by the user. This project provides only technical functionality and is not a content service provider.

2. **Compliant Use**

   When using this tool (including adding audio sources), you must strictly comply with copyright and related laws and regulations in your country/region:

   - You may not reproduce or distribute copyrighted content without authorization, or use this tool for any infringing or illegal activities;
   - You bear full legal responsibility for all your use of this tool.

3. **Limitation of Liability**

   This project is provided "as is" without warranty of any kind. Any legal disputes, losses, or consequences arising from users adding illegal audio sources or distributing infringing content shall be borne solely by the user. The project developers and contributors shall not be liable for any direct, indirect, or consequential damages.

4. **Copyright Complaints**

   If you believe that any test sources or related content in this project infringes upon your legitimate rights, please contact us via Issue and we will promptly verify and remove the relevant content.

5. **Important Notice**

   This software is a general-purpose M3U audio player. It does not include, provide, or distribute any internet radio station sources.

   All playback URLs are added by the user. The software does not upload or record any playback links you enter.

   Users guarantee that they will only use this tool to access legal, authorized internet audio resources.

   It is strictly forbidden to use this software to listen to or distribute content that violates the laws and regulations of the People's Republic of China, endangers national security, or disturbs public order.

   Users bear full legal responsibility for all their playback behavior. Developers are not liable for third-party playback source content or improper user behavior.

## License

[MIT](LICENSE) — Please retain the copyright notice and license text when using.

© 2026 [GZYZhy](https://www.zdeweb.cn)

> 💡 If you use code from this project in your own work, a mention in your acknowledgments would be greatly appreciated.

---

*This English translation was generated with the assistance of AI and may contain inaccuracies. Please refer to the [Chinese version](README.md) as the authoritative source.*
