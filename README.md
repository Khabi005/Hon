<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/branding/banner-dark.png">
  <img src="docs/branding/banner-light.png" alt="Hon, a quiet place to read" width="720">
</picture>

<br>

**A calm, private reading app for Android.**<br>
Web novels, EPUBs and PDFs on one shelf, with the look and feel of Apple Books.

<br>

[![Latest release](https://img.shields.io/github/v/release/Khabi005/Hon?include_prereleases&label=release&style=flat-square&color=1C1C1E)](https://github.com/Khabi005/Hon/releases)
[![Downloads](https://img.shields.io/github/downloads/Khabi005/Hon/total?style=flat-square&color=1C1C1E)](https://github.com/Khabi005/Hon/releases)
[![Verify](https://img.shields.io/github/actions/workflow/status/Khabi005/Hon/verify.yml?branch=main&label=checks&style=flat-square)](https://github.com/Khabi005/Hon/actions/workflows/verify.yml)
[![Android 8.0+](https://img.shields.io/badge/Android-8.0%2B-34C759?style=flat-square&logo=android&logoColor=white)](#download)
[![License: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-8E8E93?style=flat-square)](LICENSE)
[![Discord](https://img.shields.io/badge/Discord-join-5865F2?style=flat-square&logo=discord&logoColor=white)](https://discord.gg/w2XsFwFTW)

[**Website**](https://khabi005.github.io/Hon/) · [**Download**](#download) · [**Screenshots**](#screenshots) · [**Features**](#features) · [**Build**](#build-from-source) · [**Changelog**](CHANGELOG.md) · [**Discord**](https://discord.gg/w2XsFwFTW)

</div>

> [!NOTE]
> Hon is an **early alpha** under active development. Reading, sources and downloads work well; expect rough edges while the polish catches up. Feedback on [Discord](https://discord.gg/w2XsFwFTW) shapes what comes next.

## Screenshots

<div align="center">

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/home-dark.png" width="230" alt="Home"><br><sub><b>Home</b></sub></td>
    <td align="center"><img src="docs/screenshots/library-dark.png" width="230" alt="Library"><br><sub><b>Library</b></sub></td>
    <td align="center"><img src="docs/screenshots/reader-themes.png" width="230" alt="Reader themes"><br><sub><b>Reader themes</b></sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/screenshots/browse-dark.png" width="230" alt="Browse sources"><br><sub><b>Browse</b></sub></td>
    <td align="center"><img src="docs/screenshots/history-dark.png" width="230" alt="Reading history"><br><sub><b>Reading history</b></sub></td>
    <td align="center"><img src="docs/screenshots/source-controls-dark.png" width="230" alt="Source controls"><br><sub><b>Source controls</b></sub></td>
  </tr>
</table>

<details>
<summary><sub>Light mode</sub></summary>
<br>
<img src="docs/screenshots/home-light.png" width="230" alt="Home in light mode">
</details>

</div>

## Features

### Reading
- **Six reader themes**: Original, Quiet, Paper, Bold, Calm and Focus, in the spirit of Apple Books.
- **Real book typography**: Newsreader, Literata, Lora and Libre Baskerville are bundled, with live size, spacing, margin and indent controls.
- **Scroll or page**: continuous scrolling or paginated turns, with a time-left estimate for the chapter.
- **Audiobook Mode**: text-to-speech that reads chapter after chapter and follows along on the page.
- **Hands-free**: auto-scroll, and page turns with the volume keys.
- **Highlights, bookmarks and search** inside every book.

### Web novels
- **170+ sources included**, compatible with **Shosetsu** extensions, plus your own extension repositories.
- **Native source engine** (Kotlin, LuaJ and Jsoup), with in-app sign-in for sources behind Cloudflare or a login.
- **Library updates** in the background, with rules for charging and finished novels.
- **Move to another source** when one breaks, keeping your place and collections.

### Downloads
- **Background downloads** with Android WorkManager that survive app kills and reboots.
- **Offline images**: chapter illustrations are saved with the text.
- **Download new chapters** automatically, and **delete after reading** to save space.
- **Bulk tools**: next 5/10/25, ranges, selections, or everything that's left.
- **EPUB export** of any downloaded novel.

### Library and privacy
- **One library** for web novels, EPUBs and PDFs, organised into collections.
- **Reading goals and history** with daily reading time.
- **Incognito mode** for reading without leaving history.
- **Local-first**: no account, no tracking, no telemetry. Full backup and restore to a single file.

## Download

Hon runs on **Android 8.0 (API 26) or newer**. Grab the latest APK from **[Releases](https://github.com/Khabi005/Hon/releases)**.

| File | Pick it if | Size |
| :--- | :--- | :---: |
| `Hon-vX.Y.Z-arm64-v8a.apk` | You have a phone or tablet from the last several years. **Recommended.** | ~30 MB |
| `Hon-vX.Y.Z-complete.apk` | You have an older 32-bit device or use an emulator. | ~75 MB |

1. Download the APK on your phone.
2. Open it and allow **Install unknown apps** for your browser or file manager when asked.
3. Open Hon and add something to read.

> [!TIP]
> Updating? Install the new APK over the old one and your library stays put. Stick with the same file type (arm64 or complete) each time, since Android won't switch between them without a reinstall.

## Build from source

You'll need the **Flutter SDK** (Dart 3.11+), **JDK 17** and the **Android SDK**.

```bash
git clone https://github.com/Khabi005/Hon.git
cd Hon
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # Drift database code
flutter test
flutter run                                                # or: flutter build apk --release
```

Release builds need your own signing key. See [`android/key.properties.example`](android/key.properties.example) and the [release guide](docs/RELEASE_GUIDE.md).

<details>
<summary><b>How Hon is put together</b></summary>

```
Flutter (Dart)          Riverpod state, custom Apple Books style UI, novel / EPUB / PDF readers
Native Android (Kotlin) Shosetsu source engine (LuaJ + Jsoup), WorkManager downloads,
                        Readium EPUB reader, WebKit source sign-in
Storage                 SQLite via Drift, offline chapters and images, single-file backups
```

More in [`docs/`](docs/README.md): design decisions, reader UI contract, the bundled source catalog and licensing.

</details>

## Contributing

Bug reports, ideas and pull requests are all welcome.

- **Found a bug?** [Open an issue](https://github.com/Khabi005/Hon/issues/new/choose) with your device, Android version and Hon version.
- **Have an idea?** Share it on [Discord](https://discord.gg/w2XsFwFTW) or as a feature request.
- **Want to code?** Read [CONTRIBUTING.md](CONTRIBUTING.md) first.

## Acknowledgements

Hon stands on the shoulders of [Shosetsu](https://gitlab.com/shosetsuorg) (source format and extensions), [LNReader](https://github.com/LNReader/lnreader) (ideas), [Readium](https://readium.org) (EPUB), and the designers of its bundled typefaces. Visual direction is inspired by Apple Books; Hon is not affiliated with Apple. Full credits are in [docs/LICENSING.md](docs/LICENSING.md).

## License

Hon is free software under the [GNU General Public License v3.0](LICENSE).

<div align="center">
<br>
<sub>本 · made for readers</sub>
</div>
