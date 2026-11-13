# HK Tools

<img src="assets/branding/logo.png" width="140" alt="HK Tools logo">

**Made by Hisham Khateeb for the Community.**
Telegram: [t.me/xavior963](https://t.me/xavior963) · Website: [hishamkhateeb.com](https://hishamkhateeb.com)

A desktop app (macOS and Windows 10/11, built with Flutter) for working with iPhones
and iPads: device info and control, firmware (IPSW) downloads and flashing, apps,
backups, and WhatsApp transfer between Android and iPhone.

Version **3.0.0**.

---

## Contents

- [Features](#features)
- [My Device](#my-device)
- [Firmware: library, downloads, repository](#firmware-library-downloads-repository)
- [Flashing (restore)](#flashing-restore)
- [Apps: App Store and IPA Library](#apps-app-store-and-ipa-library)
- [WhatsApp](#whatsapp)
- [Interface](#interface)
- [Installing the device tools](#installing-the-device-tools)
- [Development](#development)
- [Credits and licences](#credits-and-licences)

---

## Features

| Area | What you get |
| --- | --- |
| **My Device** | Waits for a device, then shows a photo of the exact model, details, battery, storage and every tool for it |
| **Firmware** | Browse every IPSW from IPSW.me, fast multi-threaded downloads, repository audit, duplicate reclaim |
| **Flashing** | Update or erase-restore with a clear progress bar, plain-language errors and automatic activation |
| **Apps** | App Store search and downloads (any version), IPA library with update checks, install on device |
| **WhatsApp** | Read and export chats, Android → iPhone, iPhone → Android, restore from iTunes / 3uTools / Dr.Fone backups |
| **Interface** | English and Arabic (right-to-left), light and dark mode, native translucent sidebar |

## My Device

The app opens on **My Device**. With nothing connected it shows how to connect
(plug in, unlock, trust). When a device is connected:

- **Header:** a product photo of the exact model and colour (from Apple's device-image
  server, cached), name (renamable), model, iOS version, capacity, activation state,
  battery and storage at a glance, and shortcuts to *Get firmware*, *Back up* and
  *Update / restore*.
- **Overview:** a two-column details sheet (serial, IMEI, UDID and phone number stay
  hidden until you press the eye button; click any value to copy it), a storage bar by
  category (System, Apps, Photos, Other, Free), battery health and cycles, activation
  and Skip Setup, and actions (restart, shut down, sleep, Recovery, factory reset,
  pair / unpair).
- **Tabs:** Apps · Files · Photos · Contacts · Screen · Logs · Backup · Tools · Firmware.

| Tab | What it does | Tool |
| --- | --- | --- |
| Apps | List, install `.ipa`, uninstall, browse app documents | `ideviceinstaller`, `afcclient` |
| Files | Browse the media partition, download, upload, rename, delete | `afcclient` |
| Photos | Camera roll by album, preview, export | `afcclient` |
| Contacts | Read contacts from a local backup, find duplicates, export vCard / CSV | `idevicebackup2` + SQLite |
| Screen | Screenshots and live view (needs a mounted Developer Disk Image) | `idevicescreenshot` |
| Logs | Live device log with filters | `idevicesyslog` |
| Backup | Full backups, encryption on/off, restore or delete | `idevicebackup2` |
| Tools | Virtual location, Developer Disk Image, Developer Mode, crash reports, MobileGestalt | `idevicesetlocation`, `ideviceimagemounter`, … |
| Firmware | Flash an IPSW in update or erase mode | `idevicerestore` |

**Backups** are saved as `<Device Data>/Backups/<device name> <date>/<udid>`, so every
backup is kept and easy to recognise. Devices in **Recovery** and **DFU** mode are
detected too and can be flashed directly.

## Firmware: library, downloads, repository

- **IPSW Library:** every device and build from IPSW.me, with signing status. Search
  examples: `iPhone 15 Pro` · `Mac14,2` · `A2442` · `iOS 18.0.1` · `22A3354` ·
  `is:signed` · `platform:ios|ipados|macos` · `chip:m-series` · `version:18.0` · `build:22A`.
  Builds shared by several devices are downloaded once.
- **Downloads:** multi-threaded ranged downloads, pre-allocated files, resume after a
  restart, automatic link refresh when Apple's link expires, SHA1 check after download,
  global and per-download speed caps.
- **Repository:** scans your IPSW folder (reads `BuildManifest.plist` straight from the
  ZIP), flags bad or mismatched files, lists the latest signed firmware you are missing,
  merges duplicates into hardlinks, and can add `By Device/…` hardlinks per device.

## Flashing (restore)

- Lists IPSWs from your repository that fit the device, with signing status; offers to
  download the latest signed one.
- **Update** keeps data; **Erase and restore** is required for downgrades and DFU and
  asks you to type `ERASE`.
- One progress bar for the whole restore, the current step in plain words, and a step
  checklist. The raw `idevicerestore` output is under **Show technical details**.
- **Clear errors:** common failures are explained with what to try (Apple not signing
  the build, lost connection, disk space, damaged IPSW, wrong model, modem, trust,
  Activation Lock, "erase required" with a *Try again with erase* button, outdated
  restore tools).
- **Activate after flashing:** when the restore finishes, the app waits for the device
  to start and activates it with Apple, as Finder does (Settings › Device tools; on by
  default). Activation Lock is never bypassed.
- Logs: `<app support>/restore_logs`.

## Apps: App Store and IPA Library

- **App Store** (via [ipatool](https://github.com/majd/ipatool)): sign in with your
  Apple ID (the password goes to Apple only), search, list purchases, download the
  latest or any older version, install on a connected device.
- **IPA Library:** every `.ipa` in your library folder, grouped by app, with installed
  state on the device and App Store update checks (*Update* / *Update all*).

## WhatsApp

Everything runs on this computer; nothing is uploaded. Use it only for your own data.

The page has two parts: **Move & restore** (pick a source and run a transfer) and
**Preview** (browse chats and media).

**Sources**

- **From file:** a `msgstore.db.crypt15` / `.crypt14` with its key file or 64-digit
  key, or a decrypted `msgstore.db`.
- **From Android:** connect the phone with USB debugging. The app reads the 64-digit
  backup key off the phone's screen, waits for the backup, copies it (and the media)
  over USB and decrypts it. Shows the phone's name, photo, Android version, battery and
  storage, and lets you pick between several connected phones.
- **iPhone / iTunes / 3uTools:** back up the connected iPhone, or open any existing
  backup made by HK Tools, Finder / iTunes, 3uTools or Dr.Fone (found automatically, or
  *Choose backup folder…*). Works without an iPhone connected.

**Preview:** chats with photo, video and sticker thumbnails, a media grid for the whole
backup, and export to HTML or CSV.

**Transfers** (WhatsApp and WhatsApp Business)

- **Android → iPhone:** backs up the iPhone, merges the Android chats, media and calls
  into its WhatsApp data, and restores only WhatsApp to the iPhone (photos, apps and
  settings are left alone).
- **Backup → iPhone:** restores WhatsApp from a chosen iTunes / 3uTools / HK Tools
  backup onto the connected iPhone, WhatsApp only.
- **iPhone → Android:** converts the chats into Android's format and restores them on
  the phone through WhatsApp's own local-backup restore.

Backups must not be encrypted. Find My must be off on the iPhone for restores.

## Interface

- **Language:** English or Arabic with a right-to-left layout. *Automatic* follows the
  computer's language (Settings › Interface).
- **Appearance:** light or dark. *Automatic* follows the computer.
- **Translucent sidebar:** the native window material shows through the sidebar
  (macOS sidebar vibrancy, Windows 11 Mica via
  [flutter_acrylic](https://pub.dev/packages/flutter_acrylic)); the main panel stays
  solid. *Reduced visual effects* turns it off.
- **Interface size:** 75–125% (Windows defaults to 90%).

## Installing the device tools

The app finds tools in: the folder set in Settings › Device tools → `tools/` next to the
app → `PATH` → Homebrew / MacPorts. The **Setup assistant** (Settings › Device tools,
also offered at startup) checks everything and installs what is missing.

**macOS** (Homebrew)

```
brew install libimobiledevice ideviceinstaller libirecovery ipatool
brew install --cask android-platform-tools      # adb, for WhatsApp from Android
# idevicerestore is not in Homebrew:
brew install libtatsu libzip openssl@3 autoconf automake libtool pkgconf
git clone https://github.com/libimobiledevice/idevicerestore
cd idevicerestore && ./autogen.sh && make && sudo make install
```

pymobiledevice3 (activation, Skip Setup, factory reset, app icons) is installed by the
setup assistant with [uv](https://github.com/astral-sh/uv), using its own Python.

**Windows** (all one-click from the setup assistant, verified by SHA-256, installed to
`%LOCALAPPDATA%\HK Tools\tools`, no administrator rights):

| Component | Needed for | Source |
| --- | --- | --- |
| Apple Devices (required) | USB, Recovery and DFU drivers | Microsoft Store |
| libimobiledevice tools (required) | detection, info, files, backups, screen, logs | [jrjr/libimobiledevice-windows](https://github.com/jrjr/libimobiledevice-windows) |
| idevicerestore, irecovery, ideviceinstaller | flashing, Recovery/DFU, app installs | this repo's [releases](https://github.com/shamoos63/HK-TOOLS/releases), built by `.github/workflows/windows-device-tools.yml` |
| ipatool | App Store | [majd/ipatool](https://github.com/majd/ipatool) releases |
| pymobiledevice3 | activation, Skip Setup, factory reset, icons | uv with a private Python 3.12 |
| adb | WhatsApp from Android | `winget install Google.PlatformTools` |

The Windows device tools workflow rebuilds the libimobiledevice stack monthly (or on
demand from the Actions tab) and publishes `hk-tools-windows-device-tools.zip` as the
latest release. The repository must stay public so the app can download it.

## Development

```
flutter pub get
flutter test
flutter run -d macos        # or -d windows
```

```
lib/
├── core/            # theme (palettes, glass), l10n (English / Arabic), utils
├── domain/          # entities: devices, firmware, downloads, settings
├── data/            # IPSW.me API client, Hive caches, repositories
├── services/        # catalog, download engine, device tools, restore, app store,
│                    # setup assistant, whatsapp, android
└── presentation/    # Riverpod providers, shell (sidebar, header), screens, widgets
```

Translations live in `lib/core/l10n/strings_ar.dart`, keyed by the English text; wrap
new interface text in `tr('…')` or `trf('… {0} …', [value])`.

Launch flags for screenshots and QA:

| Flag | Example |
| --- | --- |
| `HK_START_SECTION` | `--dart-define=HK_START_SECTION=repository` |
| `HK_START_SEARCH` | `--dart-define=HK_START_SEARCH="is:signed platform:ios"` |
| `HK_APPEARANCE` | `--dart-define=HK_APPEARANCE=light` |
| `HK_LANGUAGE` | `--dart-define=HK_LANGUAGE=arabic` |
| `HK_WA_SOURCE` | `--dart-define=HK_WA_SOURCE=android` |
| `HK_REPO_DIR` | `--dart-define=HK_REPO_DIR=/path/to/ipsws` |

## Credits and licences

Device features use [libimobiledevice](https://libimobiledevice.org) (LGPL),
[idevicerestore](https://github.com/libimobiledevice/idevicerestore),
[pymobiledevice3](https://github.com/doronz88/pymobiledevice3) (GPL-3.0) and
[ipatool](https://github.com/majd/ipatool) (MIT), all run as separate programs, never
linked. Firmware data comes from [IPSW.me](https://ipsw.me), Android device names from
Google Play's public device list, device photos from Apple and Wikipedia.
