# Hesh-IPTV

A cross-platform **Windows & Android** IPTV player built with **Flutter** and `media_kit` (`libmpv`), licensed under the **MIT License** (free to use, modify, and distribute).

## Features

- **Playlist Sources:**
  - Remote **M3U / M3U8** URLs (with automatic `url-tvg` / `x-tvg-url` EPG detection)
  - Local `.m3u` / `.m3u8` files
  - **Xtream Codes API** (Live TV, VOD Movies, Series & Episodes)
- **Hardware-Accelerated Playback (`media_kit` / `libmpv`):**
  - Supports HLS, MPEG-TS, DASH, MKV, and custom `#EXTVLCOPT` HTTP headers (`User-Agent`, `Referer`)
  - Desktop keyboard shortcuts (`Space` play/pause, `M` mute)
- **EPG & Library (SQLite):**
  - Background-isolated streaming **XMLTV** parser (`.xml` and `.xml.gz`)
  - 3-hour **TV Guide** timeline grid + live `Now:` program progress bars
  - Persistent **Favorites**, **Recents**, and VOD/Series **Resume Progress**
- **Power Features:**
  - **Multi-View Grid** (2 or 4 simultaneous streams with one-click audio focus)
  - **Cross-Device Sync** via JSON export/import (OneDrive, Google Drive, Syncthing) or **WebDAV** Push/Pull

## Getting Started

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (`3.x` stable)
- **Windows:** Visual Studio with Desktop C++ workload + Windows **Developer Mode** enabled (`start ms-settings:developers`)
- **Android:** Android SDK + accepted licenses (`flutter doctor --android-licenses`)

### Run Locally
```bash
flutter pub get

# Windows
flutter run -d windows

# Android
flutter run -d android
```

### Run Tests
```bash
flutter analyze --no-fatal-infos
flutter test
```

## License
[MIT](LICENSE) — free to use or modify for anyone.
