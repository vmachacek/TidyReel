# TidyReel

TidyReel is a local-first Flutter media-library application. The current code
is the completed Milestone 0 Android risk spike: it proves scoped folder
access, recursive media discovery, native metadata probing, direct playback,
and external SRT subtitles on the target tablet before catalog features are
built.

## What works

- Choose a media folder with Android's Storage Access Framework.
- Persist read-only access across process restarts and explicitly release it.
- Recursively enumerate provider metadata without reading video bytes.
- Classify MP4/MKV files, ignore AppleDouble entries, and pair SRT sidecars.
- Probe duration, container, dimensions, codecs, rotation, and stream count
  with Android media APIs.
- Play SAF `content://` sources through `media_kit`, seek, pause/resume, and
  attach a bounded in-memory SRT sidecar.
- Present controlled repair and failure states in a tablet-friendly diagnostic
  UI.

The polished catalog, persistence database, matching, online metadata, LLM
verification, durable playback progress, diagnostics export, and release
pipeline are intentionally outside this milestone. See
[implementation status](docs/implementation_status.md).

## Repository layout

```text
apps/local_media_hub/            Flutter app and Android platform adapter
packages/media_domain/           Shared result, failure, and cancellation types
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
Push-Location apps/local_media_hub
C:\dev\sdks\flutter-3.47.3\flutter\bin\flutter.bat run
Pop-Location
```

The main application manifest does not request all-files, broad storage, media
collection, or Internet permission. Flutter's debug-only manifest adds
`INTERNET` for hot reload and debugger communication. Choose a folder in the
system picker; only that persisted read grant is used for media.

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

Push-Location apps/local_media_hub
C:\dev\sdks\flutter-3.47.3\flutter\bin\flutter.bat analyze
C:\dev\sdks\flutter-3.47.3\flutter\bin\flutter.bat test test
C:\dev\sdks\flutter-3.47.3\flutter\bin\flutter.bat build apk --debug
Pop-Location

$env:JAVA_HOME = 'C:\Program Files\Microsoft\jdk-17.0.19.10-hotspot'
Push-Location apps/local_media_hub/android
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
