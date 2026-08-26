# Changelog

[简体中文](CHANGELOG.md)

This project follows a version-based format, with each release recording Added / Fixed / Improved.

## 1.6 (2026-08-26)

### Added
- **Multi-language support** — Simplified Chinese / English / French / Japanese, switchable in Settings (default: follow system), takes effect after restart
- **Per-platform language settings** — iOS / macOS / Android each store their own language preference
- **Check for updates** — Manually check the latest GitHub release from Settings; shows the version and release notes with a download link

### Fixed
- **Android notification skip next/previous not working**
- **Android Now Playing screen favorite state not refreshing**
- **macOS App icon size warnings**

### Improved
- **Multilingual documentation** — English versions of README / CHANGELOG / platform READMEs

## 1.5 (2026-08-26)

### Added
- **macOS Menu Bar Tray** — Left-click toggles window visibility; right-click opens a function menu.
- **macOS App Menu Bar** — Complete File / Play / Help menus.
- **macOS Sleep Timer Menu** — Uses a native Menu to show all preset durations + custom + cancel timer.

### Fixed
- **macOS import has no preview confirmation**
- **macOS Help menu "no help found"** — Replaced the default Help menu with one that opens the in-app help page.
- **macOS close prompt "remember my choice" was unchecked by default** — Now checked by default.
- **Various other UI and wording issues**

### Improved
- **Unified display name** — All user-visible names are now "网络电台" (Stream Radio).
- **More robust m3u parsing** — All non-`#EXTINF` lines starting with `#` are now skipped.
- **macOS close-window behavior** — New "Ask every time" mode, with a dialog offering "Minimize to menu bar" or "Quit", and a "remember my choice" option.

### Known Issues
- Installing the iOS version with "universal signing" causes m3u file import to fail. It is recommended to use the online subscription feature instead; Xcode-installed builds are not affected.

## 1.4 (2026-08-21)

### Added
- **Cross-platform playback quality indicator** (macOS Now Playing bar + iOS Now Playing screen): shows codec (MP3 / AAC / Opus, etc.), bitrate (kbps), sample rate (kHz), channel count (mono / stereo / n channels).
- **Startup / buffer latency** — Time from playback start to stream-ready (in milliseconds), color-coded in four levels: green (<150), yellow (150–299), orange (300–599), red (≥600).
- **Multi-tier quality source fallback** — macOS: ICY response headers → Icecast status-json → Qt metadata; iOS: actual playback track format description → static track → access log bitrate.
- **Quality info tooltip** — Hover on macOS, tap the question mark on iOS; shows "quality depends on the station source and network conditions".
- **macOS program change notifications** — Sends a system notification when the program/track changes (only when program info is available). Large text = artist - program name, small text = station name; duplicate text is not repeated.

### Fixed
- **iOS first m3u import shows 0 stations** — `sheet(isPresented:)` captured the old value on the first frame, causing an empty preview. Switched to `sheet(item:)` to bind data with the display toggle, eliminating the race condition entirely.
- Known issue: Using "universal signing" to install this app causes the import issue described above. As a workaround, start a simple HTTP server on your computer to serve the m3u file and use the online subscription feature. Installing via Xcode is not affected. For how to start an HTTP server, consult your AI assistant.

### Improved
- **iOS About page version number** — Now reads dynamically from Info.plist instead of being hardcoded, avoiding misses when releasing.

## 1.3

- Moved the iOS sleep timer button next to the star icon; the station is retained after stopping so playback can be restarted.
- Added sleep timer feature on both platforms (optional durations + custom + countdown display).

## 1.2

- Added unsigned iOS ipa build script `build_ios.sh`.

---

*This English translation was generated with the assistance of AI and may contain inaccuracies. Please refer to the Chinese version as the authoritative source.*
