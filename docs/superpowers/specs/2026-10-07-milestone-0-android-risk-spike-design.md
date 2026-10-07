# Milestone 0 Android Storage, Playback, and Probe Risk Spike Design

- Date: 2026-10-07
- Status: Approved design direction
- Product: Pocket Cinema
- Governing requirements: `POCKET_CINEMA_BUILD_SPEC.md`, especially sections 3, 4, 7, 14, 15, 19, 21, 25, and 31

## Agreed outcome

Build the first vertical slice of Pocket Cinema as production-shaped Flutter code rather than a disposable demo. The slice proves that the target Android tablet can grant persistent read-only access to a user-selected directory, enumerate its files, play representative local MP4 and MKV media without copying whole videos, attach a sibling SRT subtitle, and probe useful technical metadata.

This milestone exists to retire platform risk before catalog, database, metadata-provider, matching, or polished-library UI work begins. Its success is empirical: important storage and playback claims must be demonstrated on the connected Samsung SM-T500, not inferred from package documentation or emulator behavior.

## Confirmed environment

- Development host: Windows workspace at `C:\dev\TidyReel`.
- Java: Microsoft OpenJDK 17.0.19.
- Android SDK platform tools: installed and usable.
- Target device: Samsung SM-T500 (`gta4lwifi`).
- Target OS: Android 12, API 31.
- Target ABIs: `arm64-v8a`, `armeabi-v7a`, `armeabi`.
- Physical display report: 1200 × 2000 at 240 dpi.
- Flutter and Dart: not installed or not available on `PATH` at design time.
- Current stable Flutter documentation lists Flutter 3.47.0. Implementation will install and record the current 3.47.x stable SDK and its bundled Dart version before project generation.

The Android application minimum SDK is 29 because the product targets Android 10 and newer. No broad storage permission, `MANAGE_EXTERNAL_STORAGE`, legacy external-storage permission, or Android media-library permission is needed for the user-selected SAF tree.

## Chosen approach

Use a minimal modular Flutter workspace whose boundaries are intended to survive into later milestones:

```text
Flutter diagnostic UI
        ↓
Milestone 0 application controller
        ↓
Pure Dart storage / probe / playback contracts
        ↑
Android SAF + probe bridge     media_kit playback adapter
```

The spike will not introduce Drift, Riverpod code generation, TMDB, LLM integration, catalog entities, or the complete repository set. Those dependencies do not help answer the storage/playback/probe questions and would obscure the risk being tested. The controller may use simple Flutter state with injected interfaces; later milestones can compose the same contracts through Riverpod.

### Planned repository shape

```text
analysis_options.yaml
pubspec.yaml
apps/pocket_cinema/
  android/
  integration_test/
  lib/
    app/
    features/risk_spike/
    infrastructure/android/
    infrastructure/playback/
  test/
  pubspec.yaml
packages/media_domain/
  lib/
  test/
packages/media_platform_storage/
  lib/
  test/
packages/media_playback/
  lib/
  test/
docs/
  environment.md
  implementation_status.md
  manual-tests/milestone-0-android.md
  adr/003-android-saf-storage-access.md
  adr/004-android-media-source-strategy.md
  adr/011-media-probing-implementation.md
```

`media_domain` owns the typed result/failure model, cancellation primitives, and opaque IDs/value objects shared by the other packages. `media_platform_storage` owns domain-facing storage and probe contracts plus pure classification rules. `media_playback` owns playback requests, leases, events, and engine contracts. Flutter, Android, and `media_kit` implementation types remain in the app infrastructure layer.

## Components

### 1. Storage gateway

The Dart-facing `LibraryStorageGateway` supports only the operations required by this milestone:

- choose a directory with `ACTION_OPEN_DOCUMENT_TREE`;
- take and retain read permission using the picker-returned flags;
- list and validate persisted tree grants after restart;
- enumerate descendants in cancellable bounded batches;
- read a small sidecar file with a strict byte limit;
- acquire and release a playback-source lease.

The Android implementation uses `DocumentsContract` cursor queries. Document IDs are opaque. Storage identity is `provider authority + "|" + document ID`; paths are synthesized only for display and matching evidence. Cursor work runs away from the Android main thread, closes resources deterministically, and emits batches rather than one platform call per file.

Pigeon defines typed command messages. A single EventChannel carries `started`, `batch`, `progress`, `warning`, `completed`, `cancelled`, and `failed` scan events, each tagged with a scan ID. Dart ignores events for unknown or terminal scan IDs.

### 2. File classification and selection

The pure Dart classifier runs before items reach the playable list.

- Basenames beginning with `._` are system artifacts regardless of extension.
- `.mp4` and `.mkv` are the milestone's selectable video formats.
- `.srt` is a subtitle sidecar candidate.
- directories and other extensions remain counted for diagnostics but are not playable.
- uppercase extensions are normalized for comparison without changing displayed names.

The diagnostic UI shows enumeration totals, ignored totals, and selectable files. It displays root-relative paths only; it never displays or logs the underlying tree URI by default.

### 3. Playback source resolution

`PlaybackSourceLease` owns every native resource needed by one playback session and exposes an opaque source string to the playback adapter. Resolution is empirical and ordered:

1. **Direct content URI.** Pass the SAF document URI to `media_kit`. This strategy is accepted only if both representative MP4 and MKV files open, seek forward and backward, survive pause/resume, and release resources on the SM-T500.
2. **File-descriptor source.** Open a read-only `ParcelFileDescriptor`, duplicate or retain it for the full player lifetime, and expose the supported `fd://` form. This becomes the selected strategy if direct content URIs fail any gate and the descriptor path passes all gates.
3. **Loopback range proxy.** Implement only if the first two strategies fail. It binds to `127.0.0.1`, uses an unguessable per-lease token, supports `HEAD`, `GET`, and a single HTTP byte range, exposes no browsing endpoint, and closes its descriptor when the lease ends.

No strategy may copy a complete video into application cache. ADR-004 records the tested strategies, exact observations, selected strategy, and reversal criteria. A strategy remains `proposed` until its real-device checklist passes.

### 4. Playback adapter

The `media_kit` adapter is hidden behind `PlaybackEngine`. It initializes `MediaKit` before use; creates one `Player` and `VideoController` for the active diagnostic session; opens the leased source; exposes playing, buffering, position, duration, tracks, completion, and safe error events; supports play, pause, stop, and seek; and awaits disposal before releasing the storage lease.

The test UI provides video output, play/pause, a seek slider, ±10-second actions, current/total duration, and controlled status/error panels. It is intentionally diagnostic rather than the final player design.

### 5. External subtitle proof

After a video is selected, the app looks for a sibling `.srt` whose normalized basename matches the video. The storage adapter reads it only when its size is at or below the configured small-file limit. Dart decodes UTF-8 with controlled replacement behavior and attaches the contents through `SubtitleTrack.data`; this avoids assuming `media_kit` can independently reopen a SAF subtitle URI. Oversized, unreadable, or invalid sidecars produce a recoverable subtitle-specific state without stopping video playback.

### 6. Probe adapter

The Android probe opens the selected SAF document through `ContentResolver` and combines:

- `MediaMetadataRetriever` for duration, width, height, and rotation where available;
- `MediaExtractor` for container/track MIME evidence, track count, video codec MIME, audio codec MIME, language, channel count, and sample rate where available.

The result displays container/MIME evidence, duration, video codec, audio codec summary, dimensions, and stream count. Missing platform metadata is represented as unknown. `unsupported` is distinct from IO, permission, corruption, and unexpected failures. Probe resources close in `finally` blocks.

### 7. Diagnostic application controller

One controller coordinates the workflow without calling platform or player APIs from widgets. Its state machine is:

```text
checkingPersistedGrant
  → noRoot | ready
ready
  → choosingRoot → enumerating → filesAvailable
filesAvailable
  → probing → fileReady
fileReady
  → openingPlayback → playing | controlledFailure
any active operation
  → cancelled | controlledFailure
```

The UI observes immutable state and issues commands. It may retain the selected root and selected file across widget rebuilds, but Android's persisted URI permission—not an in-memory variable—is the source of authority after process restart.

## End-to-end data flow

1. App starts and asks Android for persisted URI grants.
2. A valid prior grant is checked and restored; otherwise the UI offers `Choose media folder`.
3. The system picker returns a tree URI and grant flags; Android persists read access.
4. Enumeration streams document snapshots to Dart in bounded batches.
5. Dart classifies entries and lists eligible MP4/MKV files plus matching SRT candidates.
6. The user selects a file.
7. Probe and source-resolution requests use the file's opaque storage key and root locator.
8. The probe result renders independently of playback success.
9. The playback lease remains open for the entire player session.
10. On close, failure, lifecycle teardown, or file change, the player disposes first and the lease releases second.

## Failure and recovery behavior

Every infrastructure exception is mapped to a typed `AppFailure` with a stable code, safe message, retryability, and diagnostic detail that excludes raw URIs and private absolute paths.

Required visible states and actions:

| Failure | User-visible behavior | Recovery |
|---|---|---|
| Grant revoked | Folder access is no longer available | Choose/repair folder |
| Root unavailable | Cached friendly root name remains visible | Retry or choose folder |
| Enumeration failure | Partial count may be shown but is not called complete | Retry scan |
| File missing | Selected file is no longer available | Return to list/rescan |
| Probe unsupported | Playback remains available to try | Try playback |
| Probe failed | Safe reason and diagnostic ID | Retry probe |
| Player initialization failed | No raw exception; lease is released | Retry/open another file |
| Unsupported source/codec | Controlled playback error | Try another file/strategy |
| Seek failed | Playback remains usable when possible | Retry seek |
| Subtitle failed | Video continues without subtitle | Retry/continue without it |

Cancellation is a normal terminal state, not an error. A cancelled or failed enumeration never reports a complete snapshot.

## Security and privacy

- Request only the system picker grant and network permission required by `media_kit` internals or a loopback fallback; do not request broad media/storage access.
- Keep cleartext network traffic disabled. If a loopback proxy is necessary, allow only loopback traffic through the narrowest Android network-security configuration.
- Never log tree URIs, document IDs, absolute paths, full filenames at normal log levels, or media contents.
- Bind a fallback proxy exclusively to loopback and require a random expiring token.
- Do not expose Android components unless Flutter requires them.
- Never modify, rename, delete, or upload user files.

## Testing strategy

Implementation follows red-green-refactor for behavior-bearing Dart and Kotlin code.

### Pure Dart tests

- AppleDouble entries are always classified as system artifacts.
- Extension matching is case-insensitive.
- MP4/MKV files are selectable and SRT files are sidecars, not playable titles.
- Exact normalized basename associates one SRT with one video.
- Storage snapshots and platform messages map without leaking platform types.
- Controller state transitions preserve controlled failure and cancellation semantics.
- Player teardown disposes the player before releasing the lease.
- Subtitle failure does not convert successful video playback into a fatal state.

### Android tests

- Persisted-grant records map to typed messages.
- Document cursor rows map missing size/modified-time fields safely.
- Opaque document IDs are not parsed for path meaning.
- Probe extraction maps representative platform metadata and closes resources on success/failure.
- File descriptors and leases are closed exactly once.

### Flutter tests

- No-root, permission-lost, enumerating, files-available, probe result, playback, and controlled error states render with recovery actions.
- Critical controls have stable keys and semantic labels.
- Background/lifecycle transitions trigger orderly stop and release.

### Real-device validation on Samsung SM-T500

The manual checklist records pass/fail evidence for:

1. choose a directory and persist the read grant;
2. force-stop/relaunch and restore the same root without another picker;
3. enumerate nested files and exclude `._` entries;
4. open and play one representative H.264 MP4;
5. open and play one representative H.265/MKV if present;
6. seek forward and backward in both representative files;
7. pause/resume and background/foreground the app;
8. attach a matching external SRT;
9. display required probe fields;
10. play multiple files sequentially without stale descriptors;
11. revoke the grant and observe a controlled repair state;
12. confirm the manifest does not request `MANAGE_EXTERNAL_STORAGE` or broad media access.

An unavailable representative codec is recorded as a device capability result, not hidden or misreported as success.

## Documentation and decision records

Implementation updates:

- `docs/environment.md` with exact Flutter, Dart, Java, Android SDK, Gradle, Kotlin, and device details;
- `docs/implementation_status.md` with only demonstrated capability status;
- ADR-003 with observed SAF behavior and grant persistence;
- ADR-004 with the selected playback source strategy and rejected alternatives;
- ADR-011 with probe coverage and limitations;
- `docs/manual-tests/milestone-0-android.md` with dated evidence and exact media characteristics;
- README commands for setup, tests, Android run, and device validation.

## Completion criteria

Milestone 0 is complete only when:

- format, analysis, unit/widget/adapter tests, and an Android debug build pass;
- the SM-T500 completes the real-device checklist with results recorded;
- a persisted SAF grant survives process restart;
- representative MP4 and MKV behavior is documented truthfully;
- seeking, subtitle attachment, probing, permission loss, and resource cleanup have evidence;
- no full-file copy or broad storage permission is used;
- ADR-003, ADR-004, and ADR-011 reflect observed behavior rather than assumptions;
- no placeholder production behavior is presented as complete.

If a source strategy or codec cannot pass on the device, Milestone 0 remains a documented spike or blocker and later catalog milestones do not conceal that risk.
