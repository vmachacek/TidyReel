# Pocket Cinema

Pocket Cinema is a local-first Flutter media-library application with scoped
Android folder access, a movie and TV catalog, and direct local playback. TV
files are grouped as **show → season → episode**. Optional TMDB matching adds
canonical titles and episode names while retaining uncertain local evidence.

## What works

- Use an unpaired [Bluetooth kill switch](docs/kill-switch.md) on an Android phone
  to pause nearby Pocket Cinema tablets behind a continuous loading screen.

- Choose a media folder with Android's Storage Access Framework.
- Persist read-only access across process restarts and explicitly release it.
- Recursively enumerate provider metadata without reading video bytes.
- Save completed file inventories on the device and restore them at startup
  after checking folder access. Once the saved library is visible, refresh it
  automatically in the background on each launch. **Rescan library** also
  discovers changes on demand; missing-cache libraries show loading placeholders
  during their first scan.
- Show stable loading placeholders until the initial inventory, saved view,
  and local title grouping are ready. Refreshing keeps the current library
  visible, and interrupted scans retain the last completed inventory.
- Process refresh inventories and title grouping on background workers, with
  limited progress updates to keep browsing and playback responsive.
- Classify MP4/MKV files, ignore AppleDouble entries, and pair SRT sidecars.
- Probe duration, container, dimensions, codecs, rotation, and stream count
  with Android media APIs.
- Play SAF `content://` sources through `media_kit`, seek, pause/resume, and
  attach a bounded in-memory SRT sidecar.
- Present controlled repair and failure states in a tablet-friendly diagnostic
  UI.
- Group TV files across nested release folders, preserve combined episodes and
  segment letters, and keep unresolved episodes visible within their season.
- Browse the catalog, use local artwork, save a watchlist, and resume playback.
- Connect TMDB in Library Settings with a securely stored Read Access Token.
- Cache metadata offline, review title candidates, and preserve manual choices.
- Refresh TV posters and backdrops from TMDB, compare with current artwork, and
  save a chosen image on the device for offline use in a dedicated artwork screen.
- Capture artwork from local S01E01 video: move the timeline slider, preview the
  frame, and save it as a poster or backdrop without needing TMDB.

The recognition policies from NormieRename have been ported into a pure Dart
parser; the Android app does not require its .NET or Claude runtime. See
[media matching](docs/media-matching.md) for setup and current limits, and
[implementation status](docs/implementation_status.md) for remaining work.

## Repository layout

```text
apps/pocket_cinema/            Flutter app and Android platform adapter
packages/media_domain/           Shared result, failure, and cancellation types
packages/media_parser/           Local filename/folder recognition and fixtures
packages/media_platform_storage/ Storage/probe contracts and classification
packages/media_playback/         Playback contracts
docs/adr/                        Accepted platform decisions
docs/manual-tests/               Real-device validation record
tool/generate.ps1                Rebuilds the typed Flutter/Kotlin bridge
```

## Prerequisites

- Windows with PowerShell
- Flutter 3.47.3 / Dart 3.13.3 at
  `C:\dev\sdks\flutter-3.47.3\flutter`
- Android SDK 36 and JDK 17
- An Android device or emulator on API 29 or newer

The exact validated host and device configuration is in
[docs/environment.md](docs/environment.md).

## Build and run

From the repository root:

```powershell
C:\dev\sdks\flutter-3.47.3\flutter\bin\flutter.bat pub get
Push-Location apps/pocket_cinema
C:\dev\sdks\flutter-3.47.3\flutter\bin\flutter.bat run
Pop-Location
```

To build an APK and move it into your local Google Drive folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\build-apk.ps1
```

The script builds a release APK and saves it with a timestamped filename in
`$env:USERPROFILE\My Drive\Pocket Cinema\APKs`. Google Drive for desktop syncs
the file from there. To choose another local destination or build a debug APK:

```powershell
.\tool\build-apk.ps1 -DestinationDirectory "$env:USERPROFILE\My Drive\APKs" -BuildMode Debug
```

Run the script from the repository root, or use its full path from any folder.
Use `-FlutterPath` to override the pinned Flutter executable. Release APKs
currently use the app's debug signing key for personal installation.

Build logs are saved in `apps/pocket_cinema/build/apk-script/`. If a release
build hits a stale `integration_test` entry in the generated Android plugin
registrant, the script automatically retries once to regenerate release tooling.

The main application manifest requests Internet access for optional TMDB
metadata. It does not request all-files, broad storage, or media collection
permissions. Choose a folder in the system picker; only that persisted read
grant is used for media. Online matching stays disabled until a token is added.

## Generate and verify

```powershell
C:\dev\sdks\flutter-3.47.3\flutter\bin\dart.bat format --output=none --set-exit-if-changed .
powershell -ExecutionPolicy Bypass -File tool/generate.ps1

Push-Location packages/media_domain
C:\dev\sdks\flutter-3.47.3\flutter\bin\dart.bat analyze
C:\dev\sdks\flutter-3.47.3\flutter\bin\dart.bat test
Pop-Location

Push-Location packages/media_platform_storage
C:\dev\sdks\flutter-3.47.3\flutter\bin\dart.bat analyze
C:\dev\sdks\flutter-3.47.3\flutter\bin\dart.bat test
Pop-Location

Push-Location packages/media_playback
C:\dev\sdks\flutter-3.47.3\flutter\bin\dart.bat analyze
C:\dev\sdks\flutter-3.47.3\flutter\bin\dart.bat test
Pop-Location

Push-Location apps/pocket_cinema
C:\dev\sdks\flutter-3.47.3\flutter\bin\flutter.bat analyze
C:\dev\sdks\flutter-3.47.3\flutter\bin\flutter.bat test test
C:\dev\sdks\flutter-3.47.3\flutter\bin\flutter.bat build apk --debug
Pop-Location

$env:JAVA_HOME = 'C:\Program Files\Microsoft\jdk-17.0.19.10-hotspot'
Push-Location apps/pocket_cinema/android
.\gradlew.bat testDebugUnitTest
Pop-Location
```

Run the device checklist in
[docs/manual-tests/milestone-0-android.md](docs/manual-tests/milestone-0-android.md)
before changing the Android source strategy.

## Architecture decisions

- [ADR-003: Android SAF storage access](docs/adr/003-android-saf-storage-access.md)
- [ADR-004: Android media source strategy](docs/adr/004-android-media-source-strategy.md)
- [ADR-011: Media probing implementation](docs/adr/011-media-probing-implementation.md)
