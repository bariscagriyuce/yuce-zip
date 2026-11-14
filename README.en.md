<p align="center"><img src="docs/icon.png" width="128" alt="YUCE ZIP"></p>

<h1 align="center">YUCE ZIP</h1>

<p align="center">
  <a href="README.md">🇹🇷 Türkçe</a> ·
  <a href="README.en.md">🇬🇧 English</a> ·
  <a href="README.pt-BR.md">🇧🇷 Português (Brasil)</a>
</p>

<p align="center">Free, open-source archive manager with a graphical interface for macOS — powered by <b>7-Zip</b>.</p>

<p align="center">
  <a href="https://github.com/bariscagriyuce/yuce-zip/releases/latest"><img alt="Release" src="https://img.shields.io/github/v/release/bariscagriyuce/yuce-zip?label=release"></a>
  <img alt="macOS 13+" src="https://img.shields.io/badge/macOS-13%2B-blue">
  <img alt="Apple Silicon" src="https://img.shields.io/badge/Apple%20Silicon-arm64-black">
  <img alt="License" src="https://img.shields.io/badge/license-MIT-green">
</p>

<p align="center"><a href="https://github.com/bariscagriyuce/yuce-zip/releases/latest"><b>⬇︎ Download YUCE ZIP (.dmg)</b></a></p>

---

## Features

- **Opens:** 7z, ZIP, RAR, TAR, GZ, BZ2, XZ, ZSTD, ISO, DMG, CAB, WIM, ARJ, LZH, CPIO, RPM, DEB and many more
- **Creates:** 7z, ZIP, TAR, TAR.GZ, TAR.BZ2, TAR.XZ and WIM archives
- Browse folders inside archives; double-click to open a file
- Extract everything or only the selected items, **Extract Here**
- **AES-256 encryption** (7z and ZIP), file-name encryption for 7z
- Split into volumes (CD, DVD, FAT32…) and selectable compression level
- Test archives; add files to and delete files from archives (7z, ZIP, TAR, WIM)
- **Drag & drop:** drop an archive to open it, drop files to compress them
- Shows up in Finder's **Open With** menu
- **Türkçe, English, Português (Brasil)** UI — switch instantly in Settings
- **Update checker:** looks for new versions on GitHub Releases

## Installation

1. Download `YUCE-ZIP-x.y.z.dmg` from the [Releases](https://github.com/bariscagriyuce/yuce-zip/releases/latest) page.
2. Open the DMG and drag **YUCE ZIP** into the **Applications** folder.
3. Launch it. The app is signed with a Developer ID and notarized by Apple, so it opens without warnings.

**Requirements:** macOS 13 Ventura or later, Apple Silicon (M1, M2, M3, M4…).

## Usage

| Task | How |
|---|---|
| Open an archive | Drop it on the window or the Dock icon, or **File → Open Archive…** (⌘O) |
| Compress | Drop files on an empty window, or **File → Compress Files…** (⌘K) |
| Extract | **Extract** button (⌘E) or **Extract Here** (⇧⌘E) |
| Test an archive | **Test** button (⌘T) |
| Change language | **YUCE ZIP → Settings…** (⌘,) |
| Check for updates | **YUCE ZIP → Check for Updates…** |

## Building from source

```bash
brew install sevenzip      # 7zz compression engine
./scripts/build.sh         # build/YUCE ZIP.app + dist/YUCE-ZIP-<version>.dmg
```

The script signs with the **Developer ID Application** certificate from your keychain and, if a `notarytool`
profile exists, notarizes the DMG with Apple (`NOTARY_PROFILE=<profile> ./scripts/build.sh`).

## Publishing a new version

```bash
echo 1.0.1 > VERSION && ./scripts/build.sh
gh release create v1.0.1 dist/YUCE-ZIP-1.0.1.dmg --title "YUCE ZIP 1.0.1" --notes "What's new…"
```

The app queries `https://api.github.com/repos/bariscagriyuce/yuce-zip/releases/latest`; if the tag
(e.g. `v1.0.1`) is newer than the installed version, it offers the download.

## Project layout

| File | Description |
|---|---|
| `Sources/YuceZip/AppDelegate.swift` | App lifecycle, menus, windows |
| `Sources/YuceZip/BrowserView.swift` | Main window: toolbar, file table, drag & drop |
| `Sources/YuceZip/Sheets.swift` | Extract, compress and properties dialogs |
| `Sources/YuceZip/ArchiveModel.swift` | Archive model and operations |
| `Sources/YuceZip/SevenZip.swift` | `7zz` process wrapper and output parser |
| `Sources/YuceZip/UpdateChecker.swift` | GitHub update checker |
| `Sources/YuceZip/Localization.swift` | Turkish / English / Portuguese translations |
| `scripts/build.sh` | App bundling, icon, signing, notarization, DMG |

## License

YUCE ZIP is licensed under [MIT](LICENSE). The bundled 7-Zip engine (`7zz`) is © Igor Pavlov, GNU LGPL + unRAR
restriction — see [`Resources/7-Zip-License.txt`](Resources/7-Zip-License.txt).
