# Milestone 0 Android device validation

- Date: 2026-10-07
- Result: PASS
- Device: Samsung SM-T500, Android 12 / API 31, `android-arm64`
- App: debug build, application id `com.tidyreel.local_media_hub`
- Scope: Android Storage Access Framework (SAF), recursive enumeration,
  native probing, direct `content://` playback, subtitle attachment, and
  resource cleanup

## Test media

The test used generated, non-private fixtures in a dedicated device folder:

- a 65-second 640x360 H.264/AVC MP4 with AAC audio;
- a 65-second 640x360 H.265/HEVC MKV with AAC audio in a nested folder;
- a matching English SRT sidecar for the MP4; and
- an AppleDouble-prefixed MP4 decoy.

No raw document URI, device path, or user-owned filename was retained in the
repository.

## Direct-source gate

| Check | Result | Observed evidence |
| --- | --- | --- |
| Pick root and enumerate nested entries | PASS | The picker authorized the dedicated folder. The scan discovered four files, including the nested MKV. |
| Force-stop and relaunch; grant restores | PASS | After force-stop and cold launch, the selected root was restored and remained queryable. |
| AppleDouble files excluded | PASS | The scan reported one ignored item and did not offer the decoy as playable media. |
| H.264 MP4 audio/video and seek | PASS | Direct `content://` playback rendered video and active audio; three forward and three backward 10-second actions moved playback by approximately 30 seconds in each direction. |
| H.265 MKV audio/video and seek | PASS | Direct `content://` playback rendered video and active audio; forward and backward seek behavior passed. |
| Pause/resume | PASS | Playback paused without timestamp movement and resumed normally. |
| Background/foreground | PASS | Backgrounding closed the active session; foregrounding returned a usable UI and a new session opened normally. |
| Matching SRT appears | PASS | The matching sidecar was found, attached from bounded in-memory bytes, and visibly rendered over the MP4. |
| Probe fields | PASS | Both fixtures returned duration, container MIME, 640x360 dimensions, video codec, audio codec, and stream count. |
| Three sequential sessions | PASS | Three sessions opened and closed without fatal, access, or repeated-descriptor errors in filtered logs. |
| Release test access | PASS | Releasing access immediately showed the repair action. A subsequent cold launch showed no selected root, and Android reported no persisted URI permission for the app. |

## Probe observations

| Fixture | Duration | Container | Video | Audio | Streams |
| --- | ---: | --- | --- | --- | ---: |
| H.264 MP4 | 1:05 | `video/mp4` | `video/avc` | `audio/mp4a-latm` | 2 |
| H.265 MKV | 1:05 | `video/x-matroska` | `video/hevc` | `audio/mp4a-latm` | 2 |

## Resource and privacy observations

- Android AudioFlinger showed an active output during each playback check.
- After the final session closed, `dumpsys meminfo` reported approximately
  342 MB total PSS and 394 MB RSS for the debug process. This is a diagnostic
  observation, not a release-size or performance budget.
- Sanitized log review found zero fatal, descriptor, or storage-access error
  markers across the sequential sessions.
- Cancellation is covered by the native enumerator and Flutter controller
  tests. The four-file device fixture completes too quickly for a meaningful
  manual mid-scan cancellation observation.
- Raw logcat and dumpsys output was not committed because provider data can
  contain private names or document identifiers.

## Gate decision

Direct `content://` playback passed the MP4, MKV, seek, lifecycle, subtitle,
and sequential-session checks. `directContentUri` is therefore selected in
ADR-004. File-descriptor and loopback HTTP fallbacks were not implemented or
attempted because their execution condition was not met.

