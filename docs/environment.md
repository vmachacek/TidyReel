# Development environment

Recorded on 2026-10-07 for Milestone 0.

- Flutter 3.47.3 stable (`e8113bf456`), installed from the official Windows release bundle after SHA-256 verification.
- Dart 3.13.3; DevTools 2.60.0.
- Windows 11 25H2.
- Android SDK platform 36 with build-tools 30.0.3, 33.0.2, and 36.0.0;
  manifest inspection uses
  `C:\Users\vmach\AppData\Local\Android\Sdk\build-tools\36.0.0\aapt.exe`.
- Android Studio bundled JDK 17.0.6.
- Direct Gradle verification uses Microsoft OpenJDK 17.0.19 because the host `JAVA_HOME` still points at JDK 11 even though `java` on `PATH` is JDK 17.
- Primary device: Samsung SM-T500, Android 12 / API 31, `android-arm64`, ADB serial `R9TR30ABDQJ`.
- Flutter detected the tablet as a connected Android device.
- Playback packages resolved for the spike: `media_kit` 1.2.6, `media_kit_video` 2.0.1, and `media_kit_libs_video` 1.0.7.

`flutter doctor -v` reported that some Android SDK licenses are not accepted.
This did not block dependency resolution, Kotlin unit tests, debug APK builds,
installation, or device validation with the installed SDK components. Windows
desktop tooling is intentionally out of scope for this Android-only milestone.

## Reproducible Android checks

Direct Gradle commands need the verified JDK rather than the host's stale
`JAVA_HOME` value:

```powershell
$env:JAVA_HOME = 'C:\Program Files\Microsoft\jdk-17.0.19.10-hotspot'
Push-Location apps/pocket_cinema/android
.\gradlew.bat testDebugUnitTest
Pop-Location
```

Build and inspect the effective packaged manifest:

```powershell
Push-Location apps/pocket_cinema
C:\dev\sdks\flutter-3.47.3\flutter\bin\flutter.bat build apk --debug
Pop-Location

$aapt = 'C:\Users\vmach\AppData\Local\Android\Sdk\build-tools\36.0.0\aapt.exe'
$apk = 'apps\pocket_cinema\build\app\outputs\flutter-apk\app-debug.apk'
& $aapt dump permissions $apk
& $aapt dump xmltree $apk AndroidManifest.xml
```

The target tablet is addressed by ADB serial `R9TR30ABDQJ` in the manual test
record. Other contributors should select their own connected Android target
rather than copying that serial into product code.

The effective debug APK contains `android.permission.INTERNET` from Flutter's
`src/debug/AndroidManifest.xml`; it is present only for development tooling.
It contains no broad storage or media collection permission. In addition to
the exported launcher activity, AndroidX contributes an exported profile
installer receiver protected by the system-level `android.permission.DUMP`
permission; the AndroidX startup provider is not exported.
