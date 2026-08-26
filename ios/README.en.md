# Stream Radio (iOS / iPadOS)

[简体中文](README.md)

A SwiftUI native port of the macOS version (PyQt6). The repository includes a complete Xcode project — open it directly in Xcode to build and run.

## Features

- **Station list + search** — Built-in stations consistent with the root `radio.m3u` (CCTV-1 / CCTV-13 / CNR China Voice)
- **Now Playing** — Program info (ICY metadata), favorites, Control Center integration (media keys + lock screen star)
- **m3u import** — Pick which stations to import before adding, with URL deduplication and robust parsing of "not-quite-clean" m3u files
- **Subscriptions** — Refresh subscription lists on a schedule, with optional auto-sync on launch (off by default)
- **Failed station management** — One-tap delete of all stations that failed connectivity checks; swipe-left to remove individual items
- **Floating bubble** — When the Now Playing screen is dismissed, it minimizes to a small floating bubble in the bottom-right corner; tap to reopen
- **Background playback** — Continues playing when locked or in the background; supports http plain-text streams
- Current version 1.6, supports iPhone / iPad (iOS 17+)

## Build & Run

```bash
open stream-radio/stream-radio.xcodeproj
```

In Xcode, select the `stream-radio` scheme, choose a physical device or simulator, then press ⌘R to build and run.

> Free Apple ID signing: apps expire every 7 days and must be rebuilt and reinstalled via Xcode. Publishing to the App Store requires a paid developer account (¥688/year).

## Files

| Path | Purpose |
| --- | --- |
| `stream-radio/stream-radio.xcodeproj/` | Xcode project (scheme: stream-radio) |
| `stream-radio/stream-radio/RadioApp.swift` | App entry point, injects data, starts auto-sync |
| `stream-radio/stream-radio/RadioModel.swift` | Station model + m3u parsing + subscriptions + persistence |
| `stream-radio/stream-radio/RadioPlayer.swift` | AVPlayer wrapper, background playback, lock-screen info |
| `stream-radio/stream-radio/StationListView.swift` | List, search, floating bubble, m3u import |
| `stream-radio/stream-radio/NowPlayingView.swift` | Now Playing screen, favorite button |
| `stream-radio/stream-radio/SettingsView.swift` | Settings: subscriptions, failed station management, about |
| `stream-radio/stream-radio/Info.plist` | Background audio, ATS exceptions, launch screen, icons |
| `stream-radio/stream-radio/Assets.xcassets/` | App icon assets |

## Notes

- Program info comes from **ICY in-stream metadata** (`AVPlayerItem.timedMetadata`). Stations that support ICY show "Artist - Title"; HLS stations and a few others that don't return metadata only show the station name, which is normal.
- The player sends a clean UA and `Icy-MetaData: 1` in request headers.
- Tap **+** on the home screen to manually add a single station; tap **⇩** to import a `.m3u` playlist from the Files app.
- See the repository root `README.md` for complete cross-platform documentation.

---

*This English translation was generated with the assistance of AI and may contain inaccuracies. Please refer to the Chinese version as the authoritative source.*
