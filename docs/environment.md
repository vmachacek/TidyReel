# Development environment

Recorded on 2026-10-07 for Milestone 0.

- Flutter 3.47.3 stable (`e8113bf456`), installed from the official Windows release bundle after SHA-256 verification.
- Dart 3.13.3; DevTools 2.60.0.
- Windows 11 25H2.
- Android SDK 36.0.0 with platform and build-tools 36.0.0.
- Android Studio bundled JDK 17.0.6.
- Direct Gradle verification uses Microsoft OpenJDK 17.0.19 because the host `JAVA_HOME` still points at JDK 11 even though `java` on `PATH` is JDK 17.
- Primary device: Samsung SM-T500, Android 12 / API 31, `android-arm64`, ADB serial `R9TR30ABDQJ`.
- Flutter detected the tablet as a connected Android device.
- Playback packages resolved for the spike: `media_kit` 1.2.6, `media_kit_video` 2.0.1, and `media_kit_libs_video` 1.0.7.

`flutter doctor -v` reported that some Android SDK licenses are not accepted. The installed platform is available; build and device verification will determine whether any additional SDK component is required. Windows desktop tooling is intentionally out of scope for this Android-only milestone.
