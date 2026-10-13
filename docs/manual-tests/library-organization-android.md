# Library organization Android check

Validated on 2026-10-13 on MES_B, Android 16 / API 36, through USB ADB.

The final integration run used the separate debug application ID
`com.pocketcinema.app.organizercheck` and `--no-uninstall`. It selected a new
`Download/TidyReelOrganizerCheck-...` tree containing five tiny text fixtures,
with an exact-tree and application-ID guard before accessing files.

Passed:

- Persisted read/write access through the real Android folder picker.
- Movie rename/move to `Movies/Movie (2024)/Movie (2024).mkv`.
- Matching `.forced.en.srt` moved with the video's cleaned basename.
- Episode chain normalized to `TV/Show (2022)/Season 01/S01E01-E02.mkv`.
- All three moved files retained their exact bytes.
- Returned storage IDs and parent IDs agreed with a fresh provider enumeration.
- A second plan contained three unchanged files and zero moves.
- A differently cased existing destination prevented a collision; both source
  and existing file remained intact.
- The fixture grant was released and the isolated app's previous grants were
  unchanged.

The earlier attempts were interrupted by simultaneous deployments. The first
attempt used Flutter's default integration-test teardown, which uninstalled
Pocket Cinema and reset its private app data. No user media was moved or deleted.
No recoverable preference/inventory backup was found. The safe runner and
separate application ID now prevent this test from replacing the user's app.

Automated checks also passed: 478 Flutter app tests, 27 package tests, and 83
Android unit tests. Dart analysis reported no issues. See
[the device-check runner](../../tool/test-library-organization-android.ps1) and
[feature behavior](../library-organization.md).
