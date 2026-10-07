# Milestone 0 Android Risk Spike Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and validate a production-shaped Flutter vertical slice that selects a local Android SAF directory, persists read access, enumerates media, probes MP4/MKV files, attaches sibling SRT subtitles, and plays media on the Samsung SM-T500 without copying whole files.

**Architecture:** A minimal Dart workspace separates pure domain results, storage/probe contracts, and playback contracts from Flutter and Android implementations. Pigeon carries typed commands, one EventChannel streams scan batches, Android `DocumentsContract` performs SAF access, Android media APIs perform probing, and `media_kit` is isolated behind `PlaybackEngine`. Direct content-URI playback is tested first; file-descriptor and loopback fallbacks are gated by observed device failures.

**Tech Stack:** Flutter 3.47.3 stable with bundled Dart, Dart pub workspaces, Material 3, Flutter localization, Kotlin/JDK 17, Android SDK API 31 target device with minimum SDK 29, Pigeon, `media_kit`, `media_kit_video`, `media_kit_libs_video`, Flutter test, Kotlin/JUnit, and Android instrumentation tests.

**Spec:** `docs/superpowers/specs/2026-10-07-milestone-0-android-risk-spike-design.md`

## Global Constraints

- Primary validation device: Samsung SM-T500, Android 12/API 31, `arm64-v8a`, ADB serial `R9TR30ABDQJ`.
- Android minimum SDK: 29; target/compile SDK use the versions selected by Flutter 3.47.3 and the installed Android SDK.
- Request read-only SAF access through `ACTION_OPEN_DOCUMENT_TREE`; never request `MANAGE_EXTERNAL_STORAGE`, `READ_EXTERNAL_STORAGE`, `READ_MEDIA_VIDEO`, or `READ_MEDIA_AUDIO` for the selected tree.
- Never copy a complete video to cache for playback.
- Domain packages must not import Flutter, Android, Pigeon-generated, or `media_kit` types.
- Widgets must not call filesystem, platform-channel, probe, or player APIs directly.
- Document IDs are opaque; storage identity is provider authority plus opaque document ID.
- Raw tree URIs, document IDs, absolute paths, and secrets must not enter normal logs or UI.
- Every asynchronous native resource closes exactly once; player disposal completes before its media-source lease closes.
- A cancelled or failed enumeration never emits a successful-complete snapshot.
- Native enumeration batches contain at most 128 file entries.
- SRT sidecar reads are capped at 2 MiB; larger files produce `SMALL_FILE_LIMIT_EXCEEDED` without blocking video playback.
- Flutter/package versions are added with `flutter pub add`/`dart pub add` and pinned by the committed application lockfile; do not guess dependency versions in YAML.
- Real-device claims remain `Spike` or `Implemented, unvalidated` until the dated SM-T500 checklist records the observation.

## Review Focus

- A persisted root can be revoked or disconnected between access validation and probe/playback; the user must get a repair action and every opened resource must close.
- A document provider can omit size or modified time, repeat document IDs, or expose a cycle; enumeration must stay bounded, deterministic, and cancellable.
- A selected file can disappear between enumeration and source open; the app must return `FILE_UNAVAILABLE`, not crash or leak a lease.
- An SRT can be oversized or malformed UTF-8; video playback must continue without subtitles and show a recoverable subtitle warning.
- Rapid file switching or app backgrounding can race player teardown; disposal and lease release must remain ordered and idempotent.

---

## File map

```text
.gitignore                                      ignored SDK/build/editor files
analysis_options.yaml                           repository-wide lint policy
pubspec.yaml                                    Dart workspace membership
apps/pocket_cinema/                           generated Android Flutter app
  pigeons/storage_api.dart                      typed Android command contract
  lib/app/pocket_cinema_app.dart              Material/localization root
  lib/features/risk_spike/                      state, controller, and UI
  lib/infrastructure/android/                   Pigeon/EventChannel gateway
  lib/infrastructure/playback/                  media_kit adapter
  lib/l10n/app_en.arb                           user-facing strings
  android/app/src/main/kotlin/com/pocketcinema/app/platform/
                                                SAF, scan, lease, and probe code
  android/app/src/test/kotlin/com/pocketcinema/app/platform/
                                                pure Kotlin adapter tests
  test/                                         controller, widget, adapter tests
  integration_test/                             fake-backed app flow test
packages/media_domain/                          result/failure/cancellation types
packages/media_platform_storage/                storage/probe models and contracts
packages/media_playback/                        player models and contract
docs/environment.md                             recorded toolchain/device facts
docs/implementation_status.md                   truthful milestone status
docs/adr/003-*.md                               SAF observations
docs/adr/004-*.md                               selected source strategy
docs/adr/011-*.md                               probe observations
docs/manual-tests/milestone-0-android.md        real-device evidence
```

### Task 1: Bootstrap the pinned Flutter workspace and typed result foundation

**Files:**
- Create: `.gitignore`
- Create: `analysis_options.yaml`
- Create: `pubspec.yaml`
- Create: `apps/pocket_cinema/**` with `flutter create`
- Create: `packages/media_domain/pubspec.yaml`
- Create: `packages/media_domain/lib/media_domain.dart`
- Create: `packages/media_domain/lib/src/app_failure.dart`
- Create: `packages/media_domain/lib/src/app_result.dart`
- Create: `packages/media_domain/lib/src/cancellation_token.dart`
- Create: `packages/media_domain/test/app_result_test.dart`
- Create: `docs/environment.md`
- Create: `docs/implementation_status.md`
- Add unchanged: `POCKET_CINEMA_BUILD_SPEC.md`

**Interfaces:**
- Produces: `AppFailure`, `AppResult<T>`, `Success<T>`, `FailureResult<T>`, `CancellationToken`, and `CancellationController`.
- Consumes: no product interfaces; generated Flutter scaffolding and Flutter 3.47.3 tooling only.

- [ ] **Step 1: Install and record Flutter 3.47.3 stable**

Use the official Windows bundle in a short, versioned path. This writes outside the repository and therefore requires the normal host approval when executed.

```powershell
$archive = Join-Path $env:TEMP 'flutter_windows_3.47.3-stable.zip'
$manifestUri = 'https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json'
$manifest = Invoke-RestMethod -Uri $manifestUri
$release = $manifest.releases | Where-Object {
  $_.version -eq '3.47.3' -and
  $_.channel -eq 'stable' -and
  $_.archive -eq 'stable/windows/flutter_windows_3.47.3-stable.zip'
} | Select-Object -First 1
if ($null -eq $release) { throw 'Flutter 3.47.3 stable is absent from the official manifest.' }
$archiveUri = "$($manifest.base_url)/$($release.archive)"
Invoke-WebRequest -Uri $archiveUri -OutFile $archive
$actualHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualHash -ne $release.sha256.ToLowerInvariant()) {
  throw "Flutter archive SHA-256 mismatch."
}
New-Item -ItemType Directory -Force 'C:\dev\sdks\flutter-3.47.3' | Out-Null
Expand-Archive -LiteralPath $archive -DestinationPath 'C:\dev\sdks\flutter-3.47.3'
$flutter = 'C:\dev\sdks\flutter-3.47.3\flutter\bin\flutter.bat'
& $flutter --version
& $flutter doctor -v
& $flutter devices
```

Expected: Flutter reports 3.47.3 stable, Android tooling is usable, and `SM-T500` appears. Copy the non-secret output summary into `docs/environment.md` with the date `2026-10-07`.

- [ ] **Step 2: Generate the app/packages, then remove generated counter behavior**

```powershell
$flutter = 'C:\dev\sdks\flutter-3.47.3\flutter\bin\flutter.bat'
$dart = 'C:\dev\sdks\flutter-3.47.3\flutter\bin\dart.bat'
& $flutter create --platforms=android --org com.pocketcinema --project-name pocket_cinema apps/pocket_cinema
& $dart create --force -t package packages/media_domain
& $dart create --force -t package packages/media_platform_storage
& $dart create --force -t package packages/media_playback
```

Delete the generated counter test and sample library files with `apply_patch`. Keep Android scaffolding. Set the app label to `Pocket Cinema` and Android `minSdk` to 29.

Replace generated counter behavior with a compile-only shell that Task 8 will replace:

```dart
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('Pocket Cinema setup'))),
    ),
  );
}
```

- [ ] **Step 3: Configure the workspace and lints**

Create the root `pubspec.yaml`:

```yaml
name: tidy_reel_workspace
publish_to: none

environment:
  sdk: '>=3.12.0 <4.0.0'

workspace:
  - apps/pocket_cinema
  - packages/media_domain
  - packages/media_platform_storage
  - packages/media_playback
```

Add `resolution: workspace` to every member pubspec. Reference workspace packages by their `1.0.0` package versions, add `flutter_lints` to the app and Dart packages, and make `analysis_options.yaml` include `package:flutter_lints/flutter.yaml` with `avoid_print`, `discarded_futures`, `unawaited_futures`, and `use_build_context_synchronously` enabled.

Use these workspace package constraints (all generated packages retain version `1.0.0`):

```yaml
# packages/media_platform_storage/pubspec.yaml
resolution: workspace
dependencies:
  media_domain: ^1.0.0

# packages/media_playback/pubspec.yaml
resolution: workspace
dependencies:
  media_domain: ^1.0.0
  media_platform_storage: ^1.0.0

# apps/pocket_cinema/pubspec.yaml
resolution: workspace
dependencies:
  flutter:
    sdk: flutter
  media_domain: ^1.0.0
  media_platform_storage: ^1.0.0
  media_playback: ^1.0.0
```

Resolve the workspace after editing:

```powershell
Push-Location packages/media_domain
C:\dev\sdks\flutter-3.47.3\flutter\bin\dart.bat pub add flutter_lints --dev
Pop-Location
Push-Location packages/media_platform_storage
C:\dev\sdks\flutter-3.47.3\flutter\bin\dart.bat pub add flutter_lints --dev
Pop-Location
Push-Location packages/media_playback
C:\dev\sdks\flutter-3.47.3\flutter\bin\dart.bat pub add flutter_lints --dev
Pop-Location
Push-Location apps/pocket_cinema
C:\dev\sdks\flutter-3.47.3\flutter\bin\flutter.bat pub get
Pop-Location
```

- [ ] **Step 4: Write the failing result/cancellation tests**

```dart
import 'package:media_domain/media_domain.dart';
import 'package:test/test.dart';

void main() {
  test('success fold invokes only the success branch', () {
    const result = Success<int>(7);
    var failureCalled = false;

    final value = result.fold(
      onSuccess: (value) => value * 2,
      onFailure: (failure) {
        failureCalled = true;
        return -1;
      },
    );

    expect(value, 14);
    expect(failureCalled, isFalse);
  });

  test('failure preserves a safe stable code and retryability', () {
    const failure = AppFailure(
      code: 'ROOT_PERMISSION_REVOKED',
      messageKey: 'rootPermissionRevoked',
      retryable: true,
      safeDetail: 'Persisted read grant is absent.',
    );
    const result = FailureResult<int>(failure);

    expect(result.failure.code, 'ROOT_PERMISSION_REVOKED');
    expect(result.failure.retryable, isTrue);
  });

  test('cancellation controller notifies once and stays cancelled', () async {
    final controller = CancellationController();
    var notifications = 0;
    controller.token.whenCancelled.then((_) => notifications++);

    controller.cancel();
    controller.cancel();
    await controller.token.whenCancelled;

    expect(controller.token.isCancelled, isTrue);
    expect(notifications, 1);
  });
}
```

- [ ] **Step 5: Run the test and verify RED**

```powershell
Push-Location packages/media_domain
C:\dev\sdks\flutter-3.47.3\flutter\bin\dart.bat test test/app_result_test.dart
Pop-Location
```

Expected: compilation fails because `AppResult`, `AppFailure`, and cancellation types do not exist.

- [ ] **Step 6: Implement the minimal domain foundation**

```dart
final class AppFailure {
  const AppFailure({
    required this.code,
    required this.messageKey,
    required this.retryable,
    this.safeDetail,
  });

  final String code;
  final String messageKey;
  final bool retryable;
  final String? safeDetail;
}

sealed class AppResult<T> {
  const AppResult();

  R fold<R>({
    required R Function(T value) onSuccess,
    required R Function(AppFailure failure) onFailure,
  });
}

final class Success<T> extends AppResult<T> {
  const Success(this.value);
  final T value;

  @override
  R fold<R>({required R Function(T) onSuccess, required R Function(AppFailure) onFailure}) =>
      onSuccess(value);
}

final class FailureResult<T> extends AppResult<T> {
  const FailureResult(this.failure);
  final AppFailure failure;

  @override
  R fold<R>({required R Function(T) onSuccess, required R Function(AppFailure) onFailure}) =>
      onFailure(failure);
}
```

Implement `CancellationController` with one `Completer<void>`, an idempotent `cancel()`, and a read-only `CancellationToken` exposing `isCancelled` and `whenCancelled`.

- [ ] **Step 7: Verify GREEN and commit**

```powershell
Push-Location packages/media_domain
C:\dev\sdks\flutter-3.47.3\flutter\bin\dart.bat test test/app_result_test.dart
C:\dev\sdks\flutter-3.47.3\flutter\bin\dart.bat format .
Pop-Location
git add .gitignore analysis_options.yaml pubspec.yaml apps/pocket_cinema packages docs/environment.md docs/implementation_status.md POCKET_CINEMA_BUILD_SPEC.md
git commit -m "build: scaffold Flutter workspace and domain foundation"
```

Expected: three tests pass; `docs/implementation_status.md` marks only `App scaffold` as `In progress`.

### Task 2: Define storage/probe contracts, classification, and sidecar matching

**Files:**
- Create: `packages/media_platform_storage/lib/media_platform_storage.dart`
- Create: `packages/media_platform_storage/lib/src/storage_models.dart`
- Create: `packages/media_platform_storage/lib/src/storage_gateway.dart`
- Create: `packages/media_platform_storage/lib/src/media_probe.dart`
- Create: `packages/media_platform_storage/lib/src/file_classifier.dart`
- Create: `packages/media_platform_storage/lib/src/sidecar_matcher.dart`
- Create: `packages/media_platform_storage/test/file_classifier_test.dart`
- Create: `packages/media_platform_storage/test/sidecar_matcher_test.dart`

**Interfaces:**
- Consumes: `AppResult<T>` and `CancellationToken` from `media_domain`.
- Produces: `LibraryRootLocator`, `AuthorizedLibraryRoot`, `StorageEntrySnapshot`, `StorageScanEvent`, `SmallFileContent`, `MediaSourceLease`, `LibraryStorageGateway`, `MediaProbe`, `MediaProbeResult`, `FileClassification`, and `SidecarMatcher`.

- [ ] **Step 1: Write failing classification tests**

```dart
test('AppleDouble video is always a system artifact', () {
  final result = const FileClassifier().classify('._Movie.MKV', isDirectory: false);
  expect(result.kind, LibraryFileKind.systemArtifact);
  expect(result.reasonCode, 'APPLEDOUBLE_RESOURCE_FORK');
});

test('video and subtitle extensions are case insensitive', () {
  const classifier = FileClassifier();
  expect(classifier.classify('Movie.MP4', isDirectory: false).kind, LibraryFileKind.video);
  expect(classifier.classify('Movie.En.SRT', isDirectory: false).kind, LibraryFileKind.subtitle);
});

test('missing size and modified time remain valid snapshot values', () {
  const entry = StorageEntrySnapshot(
    storageKey: 'provider|opaque',
    parentStorageKey: null,
    relativePath: 'Movie.mkv',
    displayName: 'Movie.mkv',
    isDirectory: false,
    mimeType: null,
    sizeBytes: null,
    modifiedAtUtc: null,
    flags: <StorageEntryFlag>{},
  );
  expect(entry.sizeBytes, isNull);
  expect(entry.modifiedAtUtc, isNull);
});
```

- [ ] **Step 2: Write failing sidecar tests**

```dart
test('matches one exact sibling SRT after language suffix removal', () {
  final video = entry('Bluey S01E01 - The Magic Xylophone.mp4');
  final subtitle = entry('Bluey S01E01 - The Magic Xylophone.en.srt');
  final unrelated = entry('Bluey S01E02 - Hospital.en.srt');

  final match = const SidecarMatcher().matchSrt(video, [subtitle, unrelated]);

  expect(match?.entry.storageKey, subtitle.storageKey);
  expect(match?.languageTag, 'en');
});

test('ambiguous generic subtitle does not attach', () {
  final match = const SidecarMatcher().matchSrt(
    entry('Movie.mp4'),
    [entry('subtitle.srt')],
  );
  expect(match, isNull);
});

StorageEntrySnapshot entry(String name) => StorageEntrySnapshot(
      storageKey: 'provider|$name',
      parentStorageKey: 'provider|folder',
      relativePath: 'Folder/$name',
      displayName: name,
      isDirectory: false,
      mimeType: null,
      sizeBytes: 1024,
      modifiedAtUtc: DateTime.utc(2026, 1, 1),
      flags: const <StorageEntryFlag>{StorageEntryFlag.supportsRead},
    );
```

- [ ] **Step 3: Verify RED**

```powershell
Push-Location packages/media_platform_storage
C:\dev\sdks\flutter-3.47.3\flutter\bin\dart.bat test
Pop-Location
```

Expected: imports/types are missing.

- [ ] **Step 4: Implement exact storage/probe public APIs**

```dart
enum StorageKind { androidSaf }
enum RootAccessState { available, permissionRevoked, unavailable }
enum LibraryFileKind { video, subtitle, systemArtifact, ignoredOther, directory }
enum StorageEntryFlag { supportsRead, virtualDocument }
enum PlaybackSourceStrategy { directContentUri, fileDescriptor, loopbackProxy }

final class LibraryRootLocator {
  const LibraryRootLocator({required this.storageKind, required this.opaqueValue});
  final StorageKind storageKind;
  final String opaqueValue;
}

sealed class StorageScanEvent {
  const StorageScanEvent(this.scanId);
  final String scanId;
}

abstract interface class LibraryStorageGateway {
  Future<AppResult<AuthorizedLibraryRoot>> chooseRoot();
  Future<AppResult<List<AuthorizedLibraryRoot>>> listPersistedRoots();
  Future<AppResult<RootAccessState>> checkAccess(LibraryRootLocator root);
  Stream<StorageScanEvent> enumerateRecursively({
    required LibraryRootLocator root,
    required String scanId,
    required CancellationToken cancellationToken,
  });
  Future<AppResult<SmallFileContent>> readSmallFile({
    required LibraryRootLocator root,
    required String storageKey,
    required int maximumBytes,
  });
  Future<AppResult<MediaSourceLease>> openPlaybackSource({
    required LibraryRootLocator root,
    required String storageKey,
    required PlaybackSourceStrategy strategy,
  });
  Future<void> releasePlaybackSource(MediaSourceLease lease);
  Future<AppResult<void>> releaseRootPermission(LibraryRootLocator root);
}

abstract interface class MediaProbe {
  Future<AppResult<MediaProbeResult>> probe({
    required LibraryRootLocator root,
    required String storageKey,
    required CancellationToken cancellationToken,
  });
}
```

`StorageEntrySnapshot` uses nullable `sizeBytes`/`modifiedAtUtc`. Batch, progress, warning, completed, cancelled, and failed events are distinct final subclasses. `MediaSourceLease` contains `leaseId`, `sourceUri`, and `strategy`; its `toString()` returns only `MediaSourceLease(strategy: <name>)`.

- [ ] **Step 5: Implement classifier and sidecar matcher**

Classifier precedence is directory → `._` → `.mp4`/`.mkv` → `.srt` → ignored. `SidecarMatcher` compares lowercased separator-normalized stems, strips `.forced`, `.default`, and one terminal language token (`en`, `en-US`, `cs`, `cz`, `sk`), normalizes `cz` to `cs`, requires the same parent storage key, and returns a match only when exactly one candidate remains.

```dart
FileClassification classify(String displayName, {required bool isDirectory}) {
  if (isDirectory) {
    return const FileClassification(LibraryFileKind.directory, 'DIRECTORY_ENTRY');
  }
  final lower = displayName.toLowerCase();
  if (lower.startsWith('._')) {
    return const FileClassification(
      LibraryFileKind.systemArtifact,
      'APPLEDOUBLE_RESOURCE_FORK',
    );
  }
  if (lower.endsWith('.mp4') || lower.endsWith('.mkv')) {
    return const FileClassification(LibraryFileKind.video, 'VIDEO_EXTENSION');
  }
  if (lower.endsWith('.srt')) {
    return const FileClassification(LibraryFileKind.subtitle, 'SUBTITLE_SIDECAR');
  }
  return const FileClassification(LibraryFileKind.ignoredOther, 'UNSUPPORTED_EXTENSION');
}
```

- [ ] **Step 6: Verify GREEN and commit**

```powershell
Push-Location packages/media_platform_storage
C:\dev\sdks\flutter-3.47.3\flutter\bin\dart.bat test
Pop-Location
git add packages/media_platform_storage packages/media_domain/pubspec.yaml pubspec.lock
git commit -m "feat: define storage contracts and media classification"
```

Expected: all classifier, nullable metadata, and sidecar tests pass.

### Task 3: Generate the typed Android bridge and map failures safely

**Files:**
- Create: `apps/pocket_cinema/pigeons/storage_api.dart`
- Modify: `apps/pocket_cinema/pubspec.yaml`
- Create: `apps/pocket_cinema/lib/infrastructure/android/storage_platform_api.dart`
- Create: `apps/pocket_cinema/lib/infrastructure/android/pigeon_storage_platform_api.dart`
- Create: `apps/pocket_cinema/lib/infrastructure/android/android_storage_gateway.dart`
- Generate: `apps/pocket_cinema/lib/infrastructure/android/generated/storage_api.g.dart`
- Generate: `apps/pocket_cinema/android/app/src/main/kotlin/com/pocketcinema/app/platform/StorageApi.g.kt`
- Create: `apps/pocket_cinema/test/infrastructure/android/android_storage_gateway_test.dart`
- Create: `apps/pocket_cinema/test/support/fake_storage_platform_api.dart`
- Create: `tool/generate.ps1`
- Create: `docs/dependencies.md`

**Interfaces:**
- Consumes: all Task 2 storage/probe models.
- Produces: `StoragePlatformApi` for dependency injection and `AndroidStorageGateway` implementing `LibraryStorageGateway`.

- [ ] **Step 1: Record and add the Pigeon dependency**

Add a Pigeon entry to `docs/dependencies.md`: purpose is typed Flutter/Kotlin messages; maintainer is the Flutter team in `flutter/packages`; license is BSD-3-Clause; runtime impact is generated code with no network behavior; removal path is replacing generated interfaces while preserving `StoragePlatformApi`.

```powershell
Push-Location apps/pocket_cinema
C:\dev\sdks\flutter-3.47.3\flutter\bin\flutter.bat pub add pigeon --dev
Pop-Location
```

- [ ] **Step 2: Write the failing adapter tests with a hand fake**

```dart
test('platform exception becomes a redacted typed failure', () async {
  final api = FakeStoragePlatformApi(
    chooseError: PlatformException(
      code: 'PERMISSION_REVOKED',
      message: 'content://private/tree/id',
    ),
  );
  final gateway = AndroidStorageGateway(api: api, scanEvents: const Stream.empty());

  final result = await gateway.chooseRoot();

  final failure = (result as FailureResult<AuthorizedLibraryRoot>).failure;
  expect(failure.code, 'STORAGE_PERMISSION_REVOKED');
  expect(failure.safeDetail, isNot(contains('content://')));
});

test('unknown scan ids and events after completion are ignored', () async {
  final events = StreamController<Map<Object?, Object?>>();
  final gateway = AndroidStorageGateway(
    api: FakeStoragePlatformApi(),
    scanEvents: events.stream,
  );
  final token = CancellationController();
  final received = <StorageScanEvent>[];
  final subscription = gateway
      .enumerateRecursively(
        root: root,
        scanId: 'known',
        cancellationToken: token.token,
      )
      .listen(received.add);

  events.add({'scanId': 'other', 'eventType': 'completed'});
  events.add({'scanId': 'known', 'eventType': 'completed'});
  events.add({'scanId': 'known', 'eventType': 'batch', 'entries': <Object?>[]});
  await events.close();
  await subscription.asFuture<void>();

  expect(received, hasLength(1));
  expect(received.single, isA<StorageScanCompleted>());
});

const root = LibraryRootLocator(
  storageKind: StorageKind.androidSaf,
  opaqueValue: 'content://redacted-tree',
);
```

In the same test support file, define `FakeStoragePlatformApi implements StoragePlatformApi` with constructor fields `chooseResult`, `chooseError`, and `probeError`. Each configured method returns its result or throws its error; every unused method throws `StateError('Unexpected platform call')`. Task 5 and Task 6 reuse this strict fake so a newly introduced platform call fails a test instead of silently succeeding.

- [ ] **Step 3: Verify RED**

```powershell
Push-Location apps/pocket_cinema
C:\dev\sdks\flutter-3.47.3\flutter\bin\flutter.bat test test/infrastructure/android/android_storage_gateway_test.dart
Pop-Location
```

Expected: `StoragePlatformApi` and `AndroidStorageGateway` are missing.

- [ ] **Step 4: Define and generate the Pigeon contract**

The schema contains `AuthorizedRootMessage`, `RootAccessMessage`, `StorageEntryMessage`, `SmallFileMessage`, `PlaybackLeaseMessage`, and `ProbeResultMessage`. Define this host API:

```dart
import 'dart:typed_data';
import 'package:pigeon/pigeon.dart';

class AuthorizedRootMessage {
  AuthorizedRootMessage({required this.treeUri, required this.displayName});
  String treeUri;
  String displayName;
}

class RootAccessMessage {
  RootAccessMessage({required this.state});
  String state;
}

class StorageEntryMessage {
  StorageEntryMessage({
    required this.storageKey,
    required this.relativePath,
    required this.displayName,
    required this.isDirectory,
    required this.flags,
    this.parentStorageKey,
    this.mimeType,
    this.sizeBytes,
    this.modifiedAtEpochMs,
  });
  String storageKey;
  String? parentStorageKey;
  String relativePath;
  String displayName;
  bool isDirectory;
  String? mimeType;
  int? sizeBytes;
  int? modifiedAtEpochMs;
  int flags;
}

class SmallFileMessage {
  SmallFileMessage({required this.bytes});
  Uint8List bytes;
}

class PlaybackLeaseMessage {
  PlaybackLeaseMessage({
    required this.leaseId,
    required this.sourceUri,
    required this.strategy,
  });
  String leaseId;
  String sourceUri;
  String strategy;
}

class ProbeResultMessage {
  ProbeResultMessage({
    required this.streamCount,
    this.durationMs,
    this.containerFormat,
    this.width,
    this.height,
    this.rotationDegrees,
    this.videoCodec,
    this.audioCodecSummary,
  });
  int? durationMs;
  String? containerFormat;
  int? width;
  int? height;
  int? rotationDegrees;
  String? videoCodec;
  String? audioCodecSummary;
  int streamCount;
}

@HostApi()
abstract class StorageHostApi {
  @async
  AuthorizedRootMessage chooseDirectory();

  List<AuthorizedRootMessage> listPersistedPermissions();
  RootAccessMessage checkRoot(String treeUri);
  void startScan(String treeUri, String scanId, int batchSize);
  void cancelScan(String scanId);
  SmallFileMessage readSmallFile(String treeUri, String storageKey, int maximumBytes);
  PlaybackLeaseMessage openPlaybackSource(
    String treeUri,
    String storageKey,
    String strategy,
  );
  void closePlaybackSource(String leaseId);
  ProbeResultMessage probeFile(String treeUri, String storageKey);
  void releasePermission(String treeUri);
}
```

Run Pigeon with Dart output in `lib/infrastructure/android/generated/` and Kotlin package `com.pocketcinema.app.platform`. Configure the exact command under `tool/generate.ps1` and make it exit nonzero on failure.

```powershell
$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$app = Join-Path $workspace 'apps\pocket_cinema'
$dart = 'C:\dev\sdks\flutter-3.47.3\flutter\bin\dart.bat'
if (-not (Test-Path -LiteralPath $dart)) {
  throw "Pinned Dart executable not found at $dart"
}
Push-Location $app
try {
  & $dart run pigeon `
    --input pigeons/storage_api.dart `
    --dart_out lib/infrastructure/android/generated/storage_api.g.dart `
    --kotlin_out android/app/src/main/kotlin/com/pocketcinema/app/platform/StorageApi.g.kt `
    --kotlin_package com.pocketcinema.app.platform
  if ($LASTEXITCODE -ne 0) { throw "Pigeon failed with exit code $LASTEXITCODE" }
} finally {
  Pop-Location
}
```

- [ ] **Step 5: Implement injected platform API and safe mapper**

`StoragePlatformApi` mirrors the generated API with Dart domain-neutral DTOs. `PigeonStoragePlatformApi` is the only class importing generated types. `AndroidStorageGateway` maps DTOs to domain models and maps `PlatformException.code` through an allowlisted switch:

```dart
AppFailure mapPlatformFailure(PlatformException exception) {
  return switch (exception.code) {
    'PERMISSION_REVOKED' => const AppFailure(
        code: 'STORAGE_PERMISSION_REVOKED',
        messageKey: 'rootPermissionRevoked',
        retryable: true,
      ),
    'FILE_UNAVAILABLE' => const AppFailure(
        code: 'FILE_UNAVAILABLE',
        messageKey: 'fileUnavailable',
        retryable: true,
      ),
    'FILE_TOO_LARGE' => const AppFailure(
        code: 'SMALL_FILE_LIMIT_EXCEEDED',
        messageKey: 'subtitleTooLarge',
        retryable: false,
      ),
    _ => AppFailure(
        code: 'STORAGE_OPERATION_FAILED',
        messageKey: 'storageOperationFailed',
        retryable: true,
        safeDetail: 'Android storage operation failed with ${exception.code}.',
      ),
  };
}
```

Use EventChannel name `com.pocketcinema.app/storage_scan_events`. Cancel the native scan when the cancellation token completes. Never copy `PlatformException.message` or `details` into `safeDetail`.

- [ ] **Step 6: Verify GREEN, generation stability, and commit**

```powershell
Push-Location apps/pocket_cinema
C:\dev\sdks\flutter-3.47.3\flutter\bin\flutter.bat test test/infrastructure/android/android_storage_gateway_test.dart
Pop-Location
powershell -ExecutionPolicy Bypass -File tool/generate.ps1
git diff --exit-code -- apps/pocket_cinema/lib/infrastructure/android/generated apps/pocket_cinema/android/app/src/main/kotlin/com/pocketcinema/app/platform/StorageApi.g.kt
git add apps/pocket_cinema tool/generate.ps1 pubspec.lock docs/dependencies.md
git commit -m "feat: add typed Android storage bridge"
```

### Task 4: Implement persisted SAF directory authorization and restoration

**Files:**
- Modify: `apps/pocket_cinema/android/app/src/main/kotlin/com/pocketcinema/app/MainActivity.kt`
- Create: `apps/pocket_cinema/android/app/src/main/kotlin/com/pocketcinema/app/platform/PersistableFlagPolicy.kt`
- Create: `apps/pocket_cinema/android/app/src/main/kotlin/com/pocketcinema/app/platform/RootAccessEvaluator.kt`
- Create: `apps/pocket_cinema/android/app/src/main/kotlin/com/pocketcinema/app/platform/AndroidRootPermissionStore.kt`
- Create: `apps/pocket_cinema/android/app/src/main/kotlin/com/pocketcinema/app/platform/StorageHostApiImpl.kt`
- Create: `apps/pocket_cinema/android/app/src/test/kotlin/com/pocketcinema/app/platform/PersistableFlagPolicyTest.kt`
- Create: `apps/pocket_cinema/android/app/src/test/kotlin/com/pocketcinema/app/platform/RootAccessEvaluatorTest.kt`

**Interfaces:**
- Consumes: generated `StorageHostApi` and messages from Task 3.
- Produces: `chooseDirectory`, `listPersistedPermissions`, and `checkRoot` native behavior.

- [ ] **Step 1: Write failing Kotlin policy tests**

```kotlin
@Test
fun `retains only returned read flag`() {
    val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
    assertEquals(
        Intent.FLAG_GRANT_READ_URI_PERMISSION,
        PersistableFlagPolicy.readOnly(flags),
    )
}

@Test
fun `missing read grant is permission revoked`() {
    assertEquals(
        RootAccessState.PERMISSION_REVOKED,
        RootAccessEvaluator.evaluate(hasPersistedRead = false, rootQueryable = false),
    )
}

@Test
fun `persisted grant with unavailable provider is unavailable`() {
    assertEquals(
        RootAccessState.UNAVAILABLE,
        RootAccessEvaluator.evaluate(hasPersistedRead = true, rootQueryable = false),
    )
}
```

- [ ] **Step 2: Verify RED**

```powershell
Push-Location apps/pocket_cinema/android
.\gradlew.bat testDebugUnitTest --tests "com.pocketcinema.app.platform.*"
Pop-Location
```

Expected: policy/evaluator types are missing.

- [ ] **Step 3: Implement root picker and permission store**

`MainActivity` registers `ActivityResultContracts.StartActivityForResult`, launches an explicit `Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)` containing read and persistable grant flags, retains one pending Pigeon callback, and returns `USER_CANCELLED` when `result.data?.data` is null. On a URI result, compute read-only flags from `result.data?.flags` and call `contentResolver.takePersistableUriPermission`. The root store reads `contentResolver.persistedUriPermissions`, keeps only `isReadPermission`, queries `DocumentsContract.Document.COLUMN_DISPLAY_NAME`, and returns a redacted friendly name.

```kotlin
object PersistableFlagPolicy {
    fun readOnly(returnedFlags: Int): Int =
        returnedFlags and Intent.FLAG_GRANT_READ_URI_PERMISSION
}

object RootAccessEvaluator {
    fun evaluate(hasPersistedRead: Boolean, rootQueryable: Boolean): RootAccessState = when {
        !hasPersistedRead -> RootAccessState.PERMISSION_REVOKED
        !rootQueryable -> RootAccessState.UNAVAILABLE
        else -> RootAccessState.AVAILABLE
    }
}
```

Use `FLAG_GRANT_READ_URI_PERMISSION` and `FLAG_GRANT_PERSISTABLE_URI_PERMISSION` on the picker intent; do not request write. Register `StorageHostApi.setUp(binaryMessenger, implementation)` during engine configuration and clear it during engine cleanup.

Implement `releasePermission(treeUri)` with `contentResolver.releasePersistableUriPermission(uri, FLAG_GRANT_READ_URI_PERMISSION)`. Map a missing grant to `PERMISSION_REVOKED`. This method is exposed by the diagnostic screen as `Release test access` so revocation behavior can be reproduced without clearing unrelated app data.

- [ ] **Step 4: Verify GREEN**

```powershell
Push-Location apps/pocket_cinema/android
.\gradlew.bat testDebugUnitTest --tests "com.pocketcinema.app.platform.*"
Pop-Location
```

Expected: all permission flag and root access policy tests pass. Picker and restart behavior are exercised after the user-reachable UI exists in Task 9.

- [ ] **Step 5: Commit**

```powershell
git add apps/pocket_cinema/android
git commit -m "feat: persist Android SAF directory grants"
```

### Task 5: Stream recursive enumeration with bounded batches and cancellation

**Files:**
- Create: `apps/pocket_cinema/android/app/src/main/kotlin/com/pocketcinema/app/platform/DocumentNode.kt`
- Create: `apps/pocket_cinema/android/app/src/main/kotlin/com/pocketcinema/app/platform/DocumentQueryGateway.kt`
- Create: `apps/pocket_cinema/android/app/src/main/kotlin/com/pocketcinema/app/platform/AndroidDocumentQueryGateway.kt`
- Create: `apps/pocket_cinema/android/app/src/main/kotlin/com/pocketcinema/app/platform/DocumentTreeEnumerator.kt`
- Create: `apps/pocket_cinema/android/app/src/main/kotlin/com/pocketcinema/app/platform/ScanSessionRegistry.kt`
- Create: `apps/pocket_cinema/android/app/src/main/kotlin/com/pocketcinema/app/platform/StorageScanEventHandler.kt`
- Create: `apps/pocket_cinema/android/app/src/main/kotlin/com/pocketcinema/app/platform/SmallFileReader.kt`
- Modify: `apps/pocket_cinema/android/app/src/main/kotlin/com/pocketcinema/app/platform/StorageHostApiImpl.kt`
- Create: `apps/pocket_cinema/android/app/src/test/kotlin/com/pocketcinema/app/platform/DocumentTreeEnumeratorTest.kt`
- Create: `apps/pocket_cinema/android/app/src/test/kotlin/com/pocketcinema/app/platform/SmallFileReaderTest.kt`
- Create: `apps/pocket_cinema/test/infrastructure/android/scan_event_mapper_test.dart`

**Interfaces:**
- Consumes: `startScan`, `cancelScan`, EventChannel schema, and Task 2 scan-event classes.
- Produces: streamed `StorageScanBatch`, progress, completion, cancellation, and failure events.

- [ ] **Step 1: Write failing recursive/cycle/cancellation Kotlin tests**

```kotlin
@Test
fun `enumerates nested nodes once when provider repeats an id`() {
    val gateway = FakeDocumentQueryGateway.tree(
        root = listOf(dir("shows"), file("movie", "Movie.mkv", size = null)),
        children = mapOf("shows" to listOf(file("episode", "Episode.mp4"), dir("shows"))),
    )
    val sink = RecordingScanSink()

    DocumentTreeEnumerator(gateway, batchSize = 2).enumerate("root", sink, TestScanCancellation())

    assertEquals(listOf("movie", "episode"), sink.files.map { it.documentId })
    assertEquals(1, sink.completedCount)
}

@Test
fun `cancellation emits cancelled and never completed`() {
    val signal = TestScanCancellation(cancelled = true)
    val sink = RecordingScanSink()

    DocumentTreeEnumerator(FakeDocumentQueryGateway.empty(), 100)
        .enumerate("root", sink, signal)

    assertEquals(1, sink.cancelledCount)
    assertEquals(0, sink.completedCount)
}

@Test
fun `small file reader rejects content above limit and closes stream`() {
    val stream = RecordingInputStream(ByteArray(9) { 1 })
    val failure = assertFailsWith<SmallFileException> {
        SmallFileReader { stream }.read("content://subtitle", maximumBytes = 8)
    }

    assertEquals("FILE_TOO_LARGE", failure.code)
    assertEquals(1, stream.closeCount)
}
```

- [ ] **Step 2: Write failing Dart event-mapping test**

```dart
test('maps nullable entry metadata and ignores events after completion', () async {
  final controller = StreamController<Map<Object?, Object?>>();
  final gateway = AndroidStorageGateway(
    api: FakeStoragePlatformApi(),
    scanEvents: controller.stream,
  );
  final cancellation = CancellationController();
  final values = gateway
      .enumerateRecursively(
        root: root,
        scanId: 'scan-1',
        cancellationToken: cancellation.token,
      )
      .toList();

  controller.add({
    'scanId': 'scan-1',
    'eventType': 'batch',
    'entries': [
      {
        'storageKey': 'provider|opaque',
        'parentStorageKey': null,
        'relativePath': 'Movie.mkv',
        'displayName': 'Movie.mkv',
        'isDirectory': false,
        'mimeType': null,
        'sizeBytes': null,
        'modifiedAtEpochMs': null,
        'flags': 0,
      },
    ],
  });
  controller.add({'scanId': 'scan-1', 'eventType': 'completed'});
  controller.add({'scanId': 'scan-1', 'eventType': 'completed'});
  await controller.close();

  final events = await values;
  final batch = events.whereType<StorageScanBatch>().single;
  expect(batch.entries.single.sizeBytes, isNull);
  expect(batch.entries.single.modifiedAtUtc, isNull);
  expect(events.whereType<StorageScanCompleted>(), hasLength(1));
});
```

Reuse the strict `FakeStoragePlatformApi` and literal `root` fixture from Task 3.

- [ ] **Step 3: Verify RED**

```powershell
Push-Location apps/pocket_cinema/android
.\gradlew.bat testDebugUnitTest --tests "com.pocketcinema.app.platform.DocumentTreeEnumeratorTest"
Pop-Location
Push-Location apps/pocket_cinema
C:\dev\sdks\flutter-3.47.3\flutter\bin\flutter.bat test test/infrastructure/android/scan_event_mapper_test.dart
Pop-Location
```

- [ ] **Step 4: Implement bounded breadth-first enumeration**

Use `ArrayDeque<DirectoryWork>`, a `MutableSet<String>` of visited document IDs, and an `ArrayList<StorageEntryMessage>` capped at 128 entries. `DocumentQueryGateway` exposes `authority` and `children(parentDocumentId)`. `AndroidDocumentQueryGateway` captures the tree URI, queries only document ID, display name, MIME type, size, last modified, and flags using `buildChildDocumentsUriUsingTree`; every cursor is wrapped in `use`. File messages synthesize relative paths from the queued parent path, while storage keys are `authority|documentId`.

```kotlin
while (queue.isNotEmpty() && !cancellation.isCancelled) {
    val directory = queue.removeFirst()
    for (node in queryGateway.children(directory.documentId)) {
        if (!visited.add(node.documentId)) continue
        val relativePath = directory.relativePath
            .takeIf { it.isNotEmpty() }
            ?.let { "$it/${node.displayName}" }
            ?: node.displayName
        if (node.isDirectory) {
            queue.add(DirectoryWork(node.documentId, relativePath))
        } else {
            batch.add(node.toMessage(queryGateway.authority, relativePath))
            if (batch.size == batchSize) sink.batch(batch.toList()).also { batch.clear() }
        }
    }
}
if (cancellation.isCancelled) sink.cancelled() else {
    if (batch.isNotEmpty()) sink.batch(batch.toList())
    sink.completed()
}
```

Define `ScanCancellation { val isCancelled: Boolean }` and back production cancellation with `AtomicBoolean`. Run enumeration on an `Executors.newSingleThreadExecutor()` owned by `ScanSessionRegistry`. The registry owns one `Future<*>` per scan ID, rejects duplicates, flips the cancellation flag before cancelling a future, removes terminal sessions, and shuts down during engine cleanup. EventChannel payloads contain only typed primitives and relative paths.

`StorageScanEventHandler` posts every `EventSink.success/error/endOfStream` call through `Handler(Looper.getMainLooper())`; native enumeration never invokes the Flutter binary messenger from the worker thread.

The Kotlin test file defines `FakeDocumentQueryGateway`, `RecordingScanSink`, `TestScanCancellation`, `dir`, and `file` as local fixtures. `FakeDocumentQueryGateway` returns literal child lists by parent ID and records every query; `RecordingScanSink` accumulates file batches and terminal counts; no Android framework object is used in these pure enumeration tests.

`SmallFileReader` opens the document through `ContentResolver`, reads at most `maximumBytes + 1`, returns bytes only when the count is within the requested cap, maps missing/permission errors to the existing stable codes, and closes the stream in `use`. `StorageHostApiImpl.readSmallFile` enforces `maximumBytes in 1..2_097_152` before calling it.

- [ ] **Step 5: Verify GREEN and commit**

```powershell
Push-Location apps/pocket_cinema/android
.\gradlew.bat testDebugUnitTest --tests "com.pocketcinema.app.platform.DocumentTreeEnumeratorTest"
Pop-Location
Push-Location apps/pocket_cinema
C:\dev\sdks\flutter-3.47.3\flutter\bin\flutter.bat test test/infrastructure/android/scan_event_mapper_test.dart
Pop-Location
git add apps/pocket_cinema
git commit -m "feat: stream cancellable SAF enumeration"
```

### Task 6: Probe SAF media with Android media APIs

**Files:**
- Create: `apps/pocket_cinema/android/app/src/main/kotlin/com/pocketcinema/app/platform/ProbeBackend.kt`
- Create: `apps/pocket_cinema/android/app/src/main/kotlin/com/pocketcinema/app/platform/AndroidProbeBackend.kt`
- Create: `apps/pocket_cinema/android/app/src/main/kotlin/com/pocketcinema/app/platform/MediaProbeService.kt`
- Modify: `apps/pocket_cinema/android/app/src/main/kotlin/com/pocketcinema/app/platform/StorageHostApiImpl.kt`
- Create: `apps/pocket_cinema/lib/infrastructure/android/android_media_probe.dart`
- Create: `apps/pocket_cinema/android/app/src/test/kotlin/com/pocketcinema/app/platform/MediaProbeServiceTest.kt`
- Create: `apps/pocket_cinema/test/infrastructure/android/android_media_probe_test.dart`

**Interfaces:**
- Consumes: `StorageHostApi.probeFile` and Task 2 `MediaProbe`.
- Produces: `AndroidMediaProbe` and redacted probe failure codes.

- [ ] **Step 1: Write failing probe-service tests**

```kotlin
@Test
fun `maps nullable metadata and always closes backend`() {
    val backend = FakeProbeBackend(
        retriever = RetrieverData(
            durationMs = 90_000,
            width = null,
            height = null,
            rotation = 90,
            containerMime = "video/mp4",
        ),
        tracks = listOf(
            TrackData(type = "video", mime = "video/hevc"),
            TrackData(type = "audio", mime = "audio/eac3", language = "en"),
        ),
    )

    val result = MediaProbeService { backend }.probe("content://document")

    assertEquals(90_000, result.durationMs)
    assertEquals("video/mp4", result.containerFormat)
    assertEquals("video/hevc", result.videoCodec)
    assertEquals("audio/eac3", result.audioCodecSummary)
    assertEquals(2, result.streamCount)
    assertEquals(1, backend.closeCount)
}

@Test
fun `backend failure closes once and returns probe failed`() {
    val backend = FakeProbeBackend(failure = IOException("private uri"))
    val failure = assertFailsWith<ProbeException> {
        MediaProbeService { backend }.probe("content://document")
    }
    assertEquals("PROBE_FAILED", failure.code)
    assertEquals(1, backend.closeCount)
}
```

- [ ] **Step 2: Write failing Dart failure-mapping test**

```dart
test('unsupported probe format is distinct from retryable IO failure', () async {
  final unsupportedApi = FakeStoragePlatformApi(
    probeError: PlatformException(code: 'UNSUPPORTED_PROBE_FORMAT'),
  );
  final failedApi = FakeStoragePlatformApi(
    probeError: PlatformException(
      code: 'PROBE_IO_FAILED',
      message: 'content://private/document',
    ),
  );

  final unsupported = await AndroidMediaProbe(unsupportedApi).probe(
    root: root,
    storageKey: 'provider|opaque',
    cancellationToken: CancellationController().token,
  );
  final failed = await AndroidMediaProbe(failedApi).probe(
    root: root,
    storageKey: 'provider|opaque',
    cancellationToken: CancellationController().token,
  );

  final unsupportedFailure =
      (unsupported as FailureResult<MediaProbeResult>).failure;
  final failedFailure = (failed as FailureResult<MediaProbeResult>).failure;
  expect(unsupportedFailure.code, 'PROBE_UNSUPPORTED');
  expect(unsupportedFailure.retryable, isFalse);
  expect(failedFailure.code, 'PROBE_FAILED');
  expect(failedFailure.safeDetail, isNot(contains('content://')));
});
```

- [ ] **Step 3: Verify RED**

```powershell
Push-Location apps/pocket_cinema/android
.\gradlew.bat testDebugUnitTest --tests "com.pocketcinema.app.platform.MediaProbeServiceTest"
Pop-Location
Push-Location apps/pocket_cinema
C:\dev\sdks\flutter-3.47.3\flutter\bin\flutter.bat test test/infrastructure/android/android_media_probe_test.dart
Pop-Location
```

- [ ] **Step 4: Implement retriever/extractor probing**

Resolve the document URI with `DocumentsContract.buildDocumentUriUsingTree`. Open a read-only `ParcelFileDescriptor`; give its descriptor to both `MediaMetadataRetriever.setDataSource(fd)` and `MediaExtractor.setDataSource(fd)` during the bounded operation. Read duration, width, height, and rotation keys. Iterate every extractor track, map MIME prefixes to video/audio/subtitle, and count streams. Close extractor, retriever, and descriptor with nested `use`/`finally` blocks.

Do not guess unavailable values. Map `IllegalArgumentException` for an unrecognized container to `UNSUPPORTED_PROBE_FORMAT`; `FileNotFoundException` to `FILE_UNAVAILABLE`; `SecurityException` to `PERMISSION_REVOKED`; other IO failures to `PROBE_FAILED`.

```kotlin
class MediaProbeService(private val backendFactory: () -> ProbeBackend) {
    fun probe(documentUri: String): ProbeResultMessage {
        val backend = backendFactory()
        return try {
            val retriever = backend.readRetrieverMetadata(documentUri)
            val tracks = backend.readTracks(documentUri)
            ProbeResultMessage(
                durationMs = retriever.durationMs,
                containerFormat = retriever.containerMime,
                width = retriever.width,
                height = retriever.height,
                rotationDegrees = retriever.rotation,
                videoCodec = tracks.firstOrNull { it.type == "video" }?.mime,
                audioCodecSummary = tracks.filter { it.type == "audio" }
                    .mapNotNull { it.mime }
                    .distinct()
                    .joinToString(", ")
                    .ifEmpty { null },
                streamCount = tracks.size.toLong(),
            )
        } finally {
            backend.close()
        }
    }
}
```

`ProbeBackend` extends `AutoCloseable` and exposes `readRetrieverMetadata` plus `readTracks`. The Kotlin test file defines a strict `FakeProbeBackend` returning literal `RetrieverData`/`TrackData`, counting `close()`, and throwing its configured failure before returning data.

- [ ] **Step 5: Verify GREEN and commit**

```powershell
Push-Location apps/pocket_cinema/android
.\gradlew.bat testDebugUnitTest --tests "com.pocketcinema.app.platform.MediaProbeServiceTest"
Pop-Location
Push-Location apps/pocket_cinema
C:\dev\sdks\flutter-3.47.3\flutter\bin\flutter.bat test test/infrastructure/android/android_media_probe_test.dart
Pop-Location
git add apps/pocket_cinema
git commit -m "feat: probe SAF media through Android APIs"
```

### Task 7: Add playback contracts, direct content-URI adapter, subtitles, and ordered cleanup

**Files:**
- Create: `packages/media_playback/lib/media_playback.dart`
- Create: `packages/media_playback/lib/src/playback_models.dart`
- Create: `packages/media_playback/lib/src/playback_engine.dart`
- Create: `packages/media_playback/lib/src/playback_engine_factory.dart`
- Create: `apps/pocket_cinema/lib/infrastructure/playback/media_kit_playback_engine.dart`
- Create: `apps/pocket_cinema/lib/infrastructure/playback/media_kit_playback_engine_factory.dart`
- Create: `apps/pocket_cinema/lib/features/risk_spike/playback_session_coordinator.dart`
- Modify: `apps/pocket_cinema/android/app/src/main/kotlin/com/pocketcinema/app/platform/StorageHostApiImpl.kt`
- Create: `apps/pocket_cinema/android/app/src/main/kotlin/com/pocketcinema/app/platform/PlaybackLeaseRegistry.kt`
- Create: `apps/pocket_cinema/test/features/risk_spike/playback_session_coordinator_test.dart`
- Create: `apps/pocket_cinema/test/infrastructure/playback/media_kit_failure_mapper_test.dart`
- Modify: `docs/dependencies.md`

**Interfaces:**
- Consumes: `MediaSourceLease`, `SmallFileContent`, and Task 1 results.
- Produces: `PlaybackEngine`, `PlaybackEngineFactory`, `PlaybackRequest`, `PlaybackSnapshot`, `PlaybackEvent`, `MediaKitPlaybackEngine`, and `PlaybackSessionCoordinator`.

- [ ] **Step 1: Add current compatible media packages**

Before the command, add entries to `docs/dependencies.md`: `media_kit` supplies the player API, `media_kit_video` supplies Flutter video output, and `media_kit_libs_video` supplies native libmpv binaries. Record MIT licensing, Android/desktop platform coverage, binary-size/native implications, local file access, no provider credentials, current repository activity, and the replacement boundary at `PlaybackEngine`.

```powershell
Push-Location apps/pocket_cinema
C:\dev\sdks\flutter-3.47.3\flutter\bin\flutter.bat pub add media_kit media_kit_video media_kit_libs_video
Pop-Location
```

Keep the versions selected by pub in `pubspec.yaml` and `pubspec.lock`; record them in `docs/environment.md`.

- [ ] **Step 2: Write failing cleanup and subtitle tests**

```dart
test('stop disposes player before releasing source lease', () async {
  final calls = <String>[];
  final engine = FakePlaybackEngine(onDispose: () => calls.add('dispose'));
  final storage = FakeStorageGateway(onRelease: (_) => calls.add('release'));
  final coordinator = PlaybackSessionCoordinator(
    engineFactory: FakePlaybackEngineFactory([engine]),
    storage: storage,
  );
  await coordinator.attachLease(directLease);

  await coordinator.stop();

  expect(calls, ['dispose', 'release']);
});

test('rapid source replacement closes the previous lease exactly once', () async {
  final storage = FakeStorageGateway();
  final coordinator = PlaybackSessionCoordinator(
    engineFactory: FakePlaybackEngineFactory([
      FakePlaybackEngine(),
      FakePlaybackEngine(),
    ]),
    storage: storage,
  );
  await coordinator.attachLease(firstLease);
  await coordinator.attachLease(secondLease);
  await coordinator.stop();

  expect(storage.releaseCounts[firstLease.leaseId], 1);
  expect(storage.releaseCounts[secondLease.leaseId], 1);
});

test('malformed subtitle reports warning without stopping playback', () async {
  final coordinator = PlaybackSessionCoordinator(
    engineFactory: FakePlaybackEngineFactory([
      FakePlaybackEngine(subtitleFailure: subtitleFailure),
    ]),
    storage: FakeStorageGateway(),
  );
  await coordinator.attachLease(directLease);

  final result = await coordinator.attachSubtitle(Uint8List.fromList([0xC3, 0x28]));

  expect(result, isA<FailureResult<void>>());
  expect(coordinator.snapshot.isOpen, isTrue);
});
```

- [ ] **Step 3: Verify RED**

```powershell
Push-Location apps/pocket_cinema
C:\dev\sdks\flutter-3.47.3\flutter\bin\flutter.bat test test/features/risk_spike/playback_session_coordinator_test.dart
Pop-Location
```

- [ ] **Step 4: Implement playback public API and media_kit adapter**

```dart
abstract interface class PlaybackEngine {
  Stream<PlaybackEvent> get events;
  PlaybackSnapshot get current;
  Future<AppResult<void>> initialize();
  Future<AppResult<void>> open(PlaybackRequest request);
  Future<AppResult<void>> play();
  Future<AppResult<void>> pause();
  Future<AppResult<void>> seek(Duration position);
  Future<AppResult<void>> attachSubtitleData(Uint8List bytes, {String? languageTag});
  Future<AppResult<void>> stop();
  Future<void> dispose();
}

final class PlaybackRequest {
  const PlaybackRequest({required this.sourceLease, this.autoplay = true});
  final MediaSourceLease sourceLease;
  final bool autoplay;
}

abstract interface class PlaybackEngineFactory {
  PlaybackEngine create();
}
```

`MediaKitPlaybackEngineFactory` creates a fresh `MediaKitPlaybackEngine` per playback session. The engine creates one `Player` and `VideoController`, calls `MediaKit.ensureInitialized()` from `main`, opens `Media(request.sourceLease.sourceUri)`, maps player state streams to domain events, and uses `SubtitleTrack.data(utf8.decode(bytes, allowMalformed: true), language: languageTag)` for a sibling SRT. It maps source-open errors to `PLAYBACK_SOURCE_FAILED`, codec/decoder evidence to `PLAYBACK_UNSUPPORTED`, seek errors to `PLAYBACK_SEEK_FAILED`, and strips raw paths/URIs from details.

For direct playback, `PlaybackLeaseRegistry` returns a UUID lease with the SAF document's `content://` URI and records no descriptor. Closing it is still idempotent so the same lifecycle contract applies to later strategies.

- [ ] **Step 5: Implement ordered session cleanup**

`PlaybackSessionCoordinator.attachLease()` stops an existing session, creates a fresh engine from the factory, initializes it, and opens the lease. `stop()` awaits `engine.stop()`, then `engine.dispose()`, then calls `storage.releasePlaybackSource(lease)` in `finally`. Lifecycle inactive/paused calls the same idempotent stop path. The Task 7 test file defines strict local `FakePlaybackEngine`, `FakePlaybackEngineFactory`, and `FakeStorageGateway` classes; every method records its call and unused methods fail with `StateError('Unexpected test call')`. It also defines `directLease` with lease ID `direct-1` and a redacted content URI, plus `subtitleFailure` with code `EXTERNAL_SUBTITLE_FAILED`.

```dart
Future<void> stop() async {
  final engine = _engine;
  final lease = _lease;
  if (engine == null && lease == null) return;
  _engine = null;
  _lease = null;
  try {
    if (engine != null) {
      await engine.stop();
      await engine.dispose();
    }
  } finally {
    if (lease != null) {
      await storage.releasePlaybackSource(lease);
    }
  }
}
```

- [ ] **Step 6: Verify GREEN and commit**

```powershell
Push-Location apps/pocket_cinema
C:\dev\sdks\flutter-3.47.3\flutter\bin\flutter.bat test test/features/risk_spike/playback_session_coordinator_test.dart
C:\dev\sdks\flutter-3.47.3\flutter\bin\flutter.bat test test/infrastructure/playback/media_kit_failure_mapper_test.dart
Pop-Location
git add packages/media_playback apps/pocket_cinema pubspec.lock docs/environment.md docs/dependencies.md
git commit -m "feat: add direct SAF playback adapter and lifecycle"
```

### Task 8: Build the localized diagnostic controller and tablet UI

**Files:**
- Modify: `apps/pocket_cinema/lib/main.dart`
- Create: `apps/pocket_cinema/lib/app/pocket_cinema_app.dart`
- Create: `apps/pocket_cinema/lib/app/app_theme.dart`
- Create: `apps/pocket_cinema/lib/features/risk_spike/risk_spike_state.dart`
- Create: `apps/pocket_cinema/lib/features/risk_spike/risk_spike_controller.dart`
- Create: `apps/pocket_cinema/lib/features/risk_spike/risk_spike_screen.dart`
- Create: `apps/pocket_cinema/lib/features/risk_spike/widgets/root_panel.dart`
- Create: `apps/pocket_cinema/lib/features/risk_spike/widgets/scan_panel.dart`
- Create: `apps/pocket_cinema/lib/features/risk_spike/widgets/media_list.dart`
- Create: `apps/pocket_cinema/lib/features/risk_spike/widgets/probe_panel.dart`
- Create: `apps/pocket_cinema/lib/features/risk_spike/widgets/player_panel.dart`
- Create: `apps/pocket_cinema/lib/features/risk_spike/widgets/failure_panel.dart`
- Create: `apps/pocket_cinema/l10n.yaml`
- Create: `apps/pocket_cinema/lib/l10n/app_en.arb`
- Create: `apps/pocket_cinema/test/features/risk_spike/risk_spike_controller_test.dart`
- Create: `apps/pocket_cinema/test/features/risk_spike/risk_spike_screen_test.dart`
- Create: `apps/pocket_cinema/integration_test/risk_spike_fake_flow_test.dart`

**Interfaces:**
- Consumes: `LibraryStorageGateway`, `MediaProbe`, `PlaybackSessionCoordinator`, classifier, and sidecar matcher.
- Produces: user-reachable Milestone 0 workflow with immutable `RiskSpikeState`.

- [ ] **Step 1: Add Flutter localization support**

```powershell
Push-Location apps/pocket_cinema
C:\dev\sdks\flutter-3.47.3\flutter\bin\flutter.bat pub add flutter_localizations --sdk=flutter
C:\dev\sdks\flutter-3.47.3\flutter\bin\flutter.bat pub add intl:any
Pop-Location
```

Configure `generate: true`. Put every displayed label/error/action in `app_en.arb`.

- [ ] **Step 2: Write failing controller tests**

```dart
test('failed scan retains partial count and never marks complete', () async {
  final storage = FakeStorageGateway.scan([
    StorageScanBatch('scan-1', [videoEntry]),
    StorageScanFailed('scan-1', scanFailure),
  ]);
  final controller = RiskSpikeController(storage: storage, probe: fakeProbe, playback: playback);

  await controller.scan(root);

  expect(controller.state.discoveredCount, 1);
  expect(controller.state.phase, RiskSpikePhase.failure);
  expect(controller.state.scanCompleted, isFalse);
});

test('file disappearing before playback shows recoverable failure', () async {
  final storage = FakeStorageGateway(openFailure: fileUnavailableFailure);
  final controller = RiskSpikeController(storage: storage, probe: fakeProbe, playback: playback);

  await controller.play(root, videoEntry);

  expect(controller.state.failure?.code, 'FILE_UNAVAILABLE');
  expect(controller.state.canRescan, isTrue);
});

test('grant revoked between validation and playback offers repair', () async {
  final storage = FakeStorageGateway(openFailure: permissionRevokedFailure);
  final controller = RiskSpikeController(
    storage: storage,
    probe: fakeProbe,
    playback: playback,
  );

  await controller.play(root, videoEntry);

  expect(controller.state.failure?.code, 'STORAGE_PERMISSION_REVOKED');
  expect(controller.state.canRepairRoot, isTrue);
  expect(storage.activeLeaseCount, 0);
});

test('oversized subtitle warns but opens video', () async {
  final storage = FakeStorageGateway(
    subtitleReadFailure: subtitleTooLargeFailure,
    lease: directLease,
  );
  final controller = RiskSpikeController(storage: storage, probe: fakeProbe, playback: playback);

  await controller.play(root, videoEntry, subtitle: subtitleEntry);

  expect(controller.state.subtitleWarning?.code, 'SMALL_FILE_LIMIT_EXCEEDED');
  expect(playback.openCount, 1);
});
```

- [ ] **Step 3: Write failing widget/accessibility tests**

```dart
testWidgets('permission revoked state exposes repair action', (tester) async {
  final semantics = tester.ensureSemantics();
  addTearDown(semantics.dispose);
  await tester.pumpWidget(testApp(state: permissionRevokedState));

  expect(find.text('Folder access needs repair'), findsOneWidget);
  expect(find.byKey(const Key('repair-root-button')), findsOneWidget);
  expect(
    tester.getSemantics(find.byKey(const Key('repair-root-button'))),
    matchesSemantics(label: 'Choose the media folder again', isButton: true),
  );
});

testWidgets('two hundred percent text scale keeps primary actions visible', (tester) async {
  await tester.pumpWidget(testApp(state: filesAvailableState, textScaler: const TextScaler.linear(2)));
  expect(find.byKey(const Key('scan-button')), findsOneWidget);
  expect(find.byKey(const Key('media-list')), findsOneWidget);
});
```

The widget test file defines `testApp`, `permissionRevokedState`, and `filesAvailableState` as literal fixtures. `testApp` wraps `RiskSpikeScreen` in `MaterialApp`, localization delegates, and a `MediaQuery` using the requested `TextScaler`.

- [ ] **Step 4: Verify RED**

```powershell
Push-Location apps/pocket_cinema
C:\dev\sdks\flutter-3.47.3\flutter\bin\flutter.bat test test/features/risk_spike
Pop-Location
```

- [ ] **Step 5: Implement immutable state and controller**

`RiskSpikeState` includes phase, root, entries, discovered/ignored/video/subtitle counts, selected file, probe result, playback snapshot, scan completion flag, cancellation availability, primary failure, and nonfatal subtitle warning. The controller owns one cancellation controller per scan, ignores stale scan events, classifies each batch, locates sidecars, probes independently, and acquires/releases source leases only through the coordinator.

Use a small injection root in `main.dart` rather than a global service locator. Widgets receive the controller and render state; they never import Android or `media_kit` classes.

The controller test file defines `root`, `videoEntry`, `subtitleEntry`, `directLease`, `scanFailure`, `fileUnavailableFailure`, `permissionRevokedFailure`, and `subtitleTooLargeFailure` as literal fixtures. It defines strict `FakeStorageGateway`, `FakeMediaProbe`, and `FakePlaybackSession` implementations whose unexpected calls throw. This makes each expected branch independent of production builders or mappers.

```dart
enum RiskSpikePhase {
  checkingGrant,
  noRoot,
  ready,
  choosingRoot,
  enumerating,
  filesAvailable,
  probing,
  fileReady,
  openingPlayback,
  playing,
  cancelled,
  failure,
}

Future<void> scan(AuthorizedLibraryRoot root) async {
  final scanId = _newScanId();
  final cancellation = CancellationController();
  _activeScanId = scanId;
  _scanCancellation = cancellation;
  _emit(state.startingScan(root));
  await for (final event in storage.enumerateRecursively(
    root: root.locator,
    scanId: scanId,
    cancellationToken: cancellation.token,
  )) {
    if (_activeScanId != event.scanId) continue;
    _applyScanEvent(event);
  }
}
```

- [ ] **Step 6: Implement adaptive diagnostic UI**

At width below 600, use a single scrollable column. At 600 or wider, use a two-pane layout: root/scan/media list on the left, probe/player on the right. All controls meet 48 logical-pixel targets. Provide stable keys for choose root, repair root, release test access, scan, cancel, media list, probe, play/pause, seek, ±10 seconds, and close player. Keep raw URI/document identity out of the UI.

```dart
return LayoutBuilder(
  builder: (context, constraints) {
    final panels = <Widget>[
      RootPanel(state: state, controller: controller),
      ScanPanel(state: state, controller: controller),
      MediaList(state: state, controller: controller),
      ProbePanel(state: state),
      PlayerPanel(state: state, controller: controller),
      if (state.failure != null)
        FailurePanel(failure: state.failure!, controller: controller),
    ];
    if (constraints.maxWidth < 600) {
      return ListView(children: panels);
    }
    return Row(
      children: [
        Expanded(child: ListView(children: panels.take(3).toList())),
        Expanded(child: ListView(children: panels.skip(3).toList())),
      ],
    );
  },
);
```

- [ ] **Step 7: Implement fake-backed integration flow**

The integration test launches the app with injected fakes, chooses a fake root, emits a batch containing MP4/MKV/SRT/AppleDouble entries, selects the video, returns probe data, opens fake playback, seeks, and closes. Assert AppleDouble is absent, subtitle is not a playable row, probe fields render, and the lease closes.

```dart
testWidgets('fake library scans probes plays seeks and releases', (tester) async {
  final harness = RiskSpikeTestHarness.withFixtureEntries([
    videoEntry,
    mkvEntry,
    subtitleEntry,
    appleDoubleEntry,
  ]);
  await tester.pumpWidget(harness.app);
  await tester.tap(find.byKey(const Key('choose-root-button')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('scan-button')));
  await tester.pumpAndSettle();

  expect(find.text('._Hidden.mp4'), findsNothing);
  expect(find.text('Movie.en.srt'), findsNothing);
  await tester.tap(find.text('Movie.mp4'));
  await tester.tap(find.byKey(const Key('probe-button')));
  await tester.pumpAndSettle();
  expect(find.text('video/avc'), findsOneWidget);
  await tester.tap(find.byKey(const Key('play-button')));
  await tester.tap(find.byKey(const Key('forward-10-button')));
  await tester.tap(find.byKey(const Key('close-player-button')));
  await tester.pumpAndSettle();

  expect(harness.storage.releaseCounts['direct-1'], 1);
});
```

`RiskSpikeTestHarness` is defined in this integration test file with literal fixture entries and strict fake storage/probe/playback dependencies; it never invokes the real platform bridge.

- [ ] **Step 8: Verify GREEN and commit**

```powershell
Push-Location apps/pocket_cinema
C:\dev\sdks\flutter-3.47.3\flutter\bin\flutter.bat gen-l10n
C:\dev\sdks\flutter-3.47.3\flutter\bin\flutter.bat test test/features/risk_spike
C:\dev\sdks\flutter-3.47.3\flutter\bin\flutter.bat test integration_test/risk_spike_fake_flow_test.dart -d R9TR30ABDQJ
Pop-Location
git add apps/pocket_cinema pubspec.lock
git commit -m "feat: add Milestone 0 diagnostic workflow"
```

### Task 9: Run the direct content-URI device gate

**Files:**
- Create: `docs/manual-tests/milestone-0-android.md`
- Create: `docs/adr/003-android-saf-storage-access.md`
- Create: `docs/adr/004-android-media-source-strategy.md`
- Create: `docs/adr/011-media-probing-implementation.md`
- Modify: `docs/implementation_status.md`

**Interfaces:**
- Consumes: the runnable app from Tasks 1–8 and representative user-owned MP4/MKV/SRT media on SM-T500.
- Produces: a pass/fail decision for direct content-URI playback and observed SAF/probe evidence.

- [ ] **Step 1: Build, install, and launch a clean debug app**

```powershell
Push-Location apps/pocket_cinema
C:\dev\sdks\flutter-3.47.3\flutter\bin\flutter.bat build apk --debug
Pop-Location
C:\Users\vmach\AppData\Local\Android\Sdk\platform-tools\adb.exe -s R9TR30ABDQJ install -r apps\pocket_cinema\build\app\outputs\flutter-apk\app-debug.apk
C:\Users\vmach\AppData\Local\Android\Sdk\platform-tools\adb.exe -s R9TR30ABDQJ shell monkey -p com.pocketcinema.app 1
```

- [ ] **Step 2: Execute and record the direct-source checklist**

Record file characteristics without copying filenames into normal logs:

```text
[ ] Pick root and enumerate nested entries
[ ] Force-stop and relaunch; grant restores
[ ] AppleDouble files excluded
[ ] H.264 MP4 opens, renders audio/video, seeks ±30 seconds
[ ] H.265/MKV opens, renders audio/video, seeks ±30 seconds, or the absence of a representative file is recorded
[ ] Pause/resume works
[ ] Background/foreground works
[ ] Matching SRT appears and can be selected
[ ] Probe shows duration, video codec, audio codec, stream count
[ ] Three sequential playback sessions close cleanly
[ ] `Release test access` revokes the persisted grant and produces repair state
```

Capture filtered logs during each playback session:

```powershell
C:\Users\vmach\AppData\Local\Android\Sdk\platform-tools\adb.exe -s R9TR30ABDQJ logcat -c
C:\Users\vmach\AppData\Local\Android\Sdk\platform-tools\adb.exe -s R9TR30ABDQJ shell dumpsys meminfo com.pocketcinema.app
C:\Users\vmach\AppData\Local\Android\Sdk\platform-tools\adb.exe -s R9TR30ABDQJ shell dumpsys package com.pocketcinema.app
```

Inspect logs locally for descriptor/resource errors; do not commit raw logs containing filenames or URIs.

- [ ] **Step 3: Apply the source-strategy gate**

```text
If direct URI passes MP4, MKV, seek, lifecycle, and sequential-session checks:
  - select directContentUri in ADR-004;
  - do not implement Tasks 10 or 11;
  - continue to Task 12.

If direct URI fails to open/seek for source reasons while codecs are supported:
  - record exact sanitized failure evidence in ADR-004;
  - execute Task 10.

If only a codec is unsupported:
  - record device capability accurately;
  - do not add a source fallback for a decoder failure;
  - continue to Task 12 with the limitation stated.
```

- [ ] **Step 4: Commit the observed decision**

```powershell
git add docs/manual-tests/milestone-0-android.md docs/adr docs/implementation_status.md
git commit -m "docs: record direct SAF playback validation"
```

### Task 10: Add a native file-descriptor lease only if the direct gate fails

**Execution condition:** Run this task only when Task 9 records a direct content-URI source failure rather than a codec failure.

**Files:**
- Create: `apps/pocket_cinema/android/app/src/main/kotlin/com/pocketcinema/app/platform/ParcelFileDescriptorLeaseRegistry.kt`
- Create: `apps/pocket_cinema/android/app/src/main/kotlin/com/pocketcinema/app/platform/DescriptorHandle.kt`
- Modify: `apps/pocket_cinema/android/app/src/main/kotlin/com/pocketcinema/app/platform/StorageHostApiImpl.kt`
- Modify: `apps/pocket_cinema/lib/features/risk_spike/risk_spike_controller.dart`
- Create: `apps/pocket_cinema/android/app/src/test/kotlin/com/pocketcinema/app/platform/ParcelFileDescriptorLeaseRegistryTest.kt`
- Modify: `docs/adr/004-android-media-source-strategy.md`
- Modify: `docs/manual-tests/milestone-0-android.md`

**Interfaces:**
- Consumes: existing `PlaybackSourceStrategy.fileDescriptor` and lease lifecycle.
- Produces: held read-only PFD leases exposed as `fd://<integer>` until explicit close.

- [ ] **Step 1: Write the failing exact-once lease tests**

```kotlin
@Test
fun `close releases descriptor exactly once`() {
    val descriptor = FakeDescriptorHandle(fd = 42)
    val registry = ParcelFileDescriptorLeaseRegistry { descriptor }
    val lease = registry.open("content://document")

    registry.close(lease.leaseId)
    registry.close(lease.leaseId)

    assertEquals("fd://42", lease.sourceUri)
    assertEquals(1, descriptor.closeCount)
}

@Test
fun `failed open retains no lease`() {
    val registry = ParcelFileDescriptorLeaseRegistry { throw FileNotFoundException() }
    assertFailsWith<SourceOpenException> { registry.open("content://missing") }
    assertEquals(0, registry.activeLeaseCount)
}
```

- [ ] **Step 2: Verify RED**

```powershell
Push-Location apps/pocket_cinema/android
.\gradlew.bat testDebugUnitTest --tests "com.pocketcinema.app.platform.ParcelFileDescriptorLeaseRegistryTest"
Pop-Location
```

- [ ] **Step 3: Implement held PFD sources and controller retry policy**

Open with `contentResolver.openFileDescriptor(uri, "r")`, wrap it as `DescriptorHandle`, store the handle in a `ConcurrentHashMap<String, DescriptorHandle>`, return `fd://<fd>`, and remove/close atomically. On application shutdown close all remaining descriptors. The controller retries with `fileDescriptor` only when the direct engine failure code is `PLAYBACK_SOURCE_FAILED`; it never retries a `PLAYBACK_UNSUPPORTED` decoder/codec error as a source change.

```kotlin
interface DescriptorHandle : AutoCloseable {
    val fd: Int
}

fun open(documentUri: String): PlaybackLeaseMessage {
    val handle = descriptorFactory.open(documentUri)
    val leaseId = UUID.randomUUID().toString()
    active[leaseId] = handle
    return PlaybackLeaseMessage(
        leaseId = leaseId,
        sourceUri = "fd://${handle.fd}",
        strategy = "fileDescriptor",
    )
}

fun close(leaseId: String) {
    active.remove(leaseId)?.close()
}
```

The production handle wraps `ParcelFileDescriptor`; the test's `FakeDescriptorHandle` is a plain Kotlin class that counts `close()` calls.

- [ ] **Step 4: Verify on SM-T500 and commit**

Run the same Task 9 MP4/MKV/seek/lifecycle/sequential-session checklist with the FD strategy. If it passes, select it in ADR-004. If it fails for a source reason, execute Task 11.

```powershell
git add apps/pocket_cinema docs/adr/004-android-media-source-strategy.md docs/manual-tests/milestone-0-android.md
git commit -m "feat: add Android file descriptor playback leases"
```

### Task 11: Add a loopback range proxy only if direct and FD strategies fail

**Execution condition:** Run this task only when Tasks 9 and 10 both record source failures and the representative codec is otherwise supported.

**Files:**
- Create: `apps/pocket_cinema/android/app/src/main/kotlin/com/pocketcinema/app/platform/LoopbackRangeServer.kt`
- Create: `apps/pocket_cinema/android/app/src/main/kotlin/com/pocketcinema/app/platform/HttpRange.kt`
- Create: `apps/pocket_cinema/android/app/src/test/kotlin/com/pocketcinema/app/platform/HttpRangeTest.kt`
- Create: `apps/pocket_cinema/android/app/src/test/kotlin/com/pocketcinema/app/platform/LoopbackRangeServerTest.kt`
- Modify: `apps/pocket_cinema/android/app/src/main/AndroidManifest.xml`
- Create: `apps/pocket_cinema/android/app/src/main/res/xml/network_security_config.xml`
- Modify: `apps/pocket_cinema/android/app/src/main/kotlin/com/pocketcinema/app/platform/StorageHostApiImpl.kt`
- Modify: `docs/adr/004-android-media-source-strategy.md`

**Interfaces:**
- Consumes: `PlaybackSourceStrategy.loopbackProxy` and PFD lease registry.
- Produces: tokenized `http://127.0.0.1:<port>/<token>` sources supporting HEAD/GET and one range.

- [ ] **Step 1: Write failing range/parser/security tests**

```kotlin
@Test
fun `single byte range returns inclusive bounds`() {
    assertEquals(HttpRange(100, 199), HttpRange.parse("bytes=100-199", length = 1000))
}

@Test
fun `suffix and multiple ranges are rejected`() {
    assertNull(HttpRange.parse("bytes=-100", length = 1000))
    assertNull(HttpRange.parse("bytes=0-10,20-30", length = 1000))
}

@Test
fun `unknown token returns 404 without opening descriptor`() {
    val store = FakeTokenStore()
    val response = server(store).request("GET /unknown HTTP/1.1\r\n\r\n")
    assertEquals(404, response.status)
    assertEquals(0, store.openCount)
}
```

- [ ] **Step 2: Verify RED**

```powershell
Push-Location apps/pocket_cinema/android
.\gradlew.bat testDebugUnitTest --tests "com.pocketcinema.app.platform.HttpRangeTest" --tests "com.pocketcinema.app.platform.LoopbackRangeServerTest"
Pop-Location
```

- [ ] **Step 3: Implement the minimal proxy**

Bind `ServerSocket` to `InetAddress.getLoopbackAddress()` and port 0. Generate 256-bit tokens with `SecureRandom`. Accept only `HEAD` and `GET /<token>`. For full GET return `200`; for valid single range return `206` with exact `Content-Length`, `Content-Range`, and `Accept-Ranges: bytes`; return `416` for invalid/out-of-bounds ranges. Use `FileChannel.position(start)` and write at most the selected length. Reject extra path segments, decoded separators, expired tokens, and non-loopback peers. Stop the server when its final lease closes.

The network security XML permits cleartext only to `127.0.0.1` and `localhost`; all other cleartext remains disabled.

Only this conditional task adds `android.permission.INTERNET`, because the loopback socket requires it. Tasks 1–10 keep the manifest offline and permission-minimal.

```kotlin
fun serve(token: String, method: String, rangeHeader: String?): HttpResponse {
    val lease = tokenStore.find(token) ?: return HttpResponse.notFound()
    if (method != "GET" && method != "HEAD") return HttpResponse.methodNotAllowed()
    val range = rangeHeader?.let { HttpRange.parse(it, lease.length) }
    if (rangeHeader != null && range == null) {
        return HttpResponse.rangeNotSatisfiable(lease.length)
    }
    val start = range?.start ?: 0L
    val end = range?.endInclusive ?: lease.length - 1
    return HttpResponse(
        status = if (range == null) 200 else 206,
        headers = buildMap {
            put("Accept-Ranges", "bytes")
            put("Content-Length", (end - start + 1).toString())
            put("Content-Type", lease.mimeType)
            if (range != null) put("Content-Range", "bytes $start-$end/${lease.length}")
        },
        body = if (method == "HEAD") null else lease.openRange(start, end),
    )
}
```

For a full `200` response, omit `Content-Range`; for `206`, require it. `LoopbackRangeServerTest` opens the server on loopback with a 16-byte in-memory descriptor fixture and asserts exact full, partial, HEAD, invalid-range, expired-token, and traversal responses.

- [ ] **Step 4: Verify on device and commit**

Run the complete Task 9 checklist. Record port/token redacted evidence and select or reject the proxy in ADR-004.

```powershell
git add apps/pocket_cinema docs/adr/004-android-media-source-strategy.md docs/manual-tests/milestone-0-android.md
git commit -m "feat: add loopback range playback fallback"
```

### Task 12: Finish documentation, run full verification, and inspect privacy/manifest state

**Files:**
- Modify: `README.md`
- Modify: `docs/environment.md`
- Modify: `docs/implementation_status.md`
- Modify: `docs/adr/003-android-saf-storage-access.md`
- Modify: `docs/adr/004-android-media-source-strategy.md`
- Modify: `docs/adr/011-media-probing-implementation.md`
- Modify: `docs/manual-tests/milestone-0-android.md`

**Interfaces:**
- Consumes: all Milestone 0 code and observed device evidence.
- Produces: reproducible setup/test commands and truthful final status.

- [ ] **Step 1: Complete ADRs with observed, not predicted, results**

Each ADR uses the master template: status, date, decision owners, context, decision, alternatives, consequences, validation/reversal criteria, and references. ADR-003 records picker/grant/restart/revocation behavior. ADR-004 records every attempted source strategy and selected strategy. ADR-011 records fields actually returned by Android APIs for MP4/MKV and unsupported gaps.

- [ ] **Step 2: Run formatter and generation checks**

```powershell
C:\dev\sdks\flutter-3.47.3\flutter\bin\dart.bat format --output=none --set-exit-if-changed .
powershell -ExecutionPolicy Bypass -File tool/generate.ps1
git diff --exit-code -- apps/pocket_cinema/lib/infrastructure/android/generated apps/pocket_cinema/android/app/src/main/kotlin/com/pocketcinema/app/platform/StorageApi.g.kt
```

Expected: all commands exit 0 and generated outputs are unchanged.

- [ ] **Step 3: Run full analysis and tests**

```powershell
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
Pop-Location
Push-Location apps/pocket_cinema/android
.\gradlew.bat testDebugUnitTest
Pop-Location
```

Expected: zero analyzer issues and zero test failures.

- [ ] **Step 4: Build Android and inspect permissions/exported components**

```powershell
Push-Location apps/pocket_cinema
C:\dev\sdks\flutter-3.47.3\flutter\bin\flutter.bat build apk --debug
Pop-Location
C:\Users\vmach\AppData\Local\Android\Sdk\build-tools\35.0.0\aapt.exe dump permissions apps\pocket_cinema\build\app\outputs\flutter-apk\app-debug.apk
C:\Users\vmach\AppData\Local\Android\Sdk\build-tools\35.0.0\aapt.exe dump xmltree apps\pocket_cinema\build\app\outputs\flutter-apk\app-debug.apk AndroidManifest.xml
```

If build-tools uses a different installed version, use the exact `aapt.exe` path reported by `Get-ChildItem C:\Users\vmach\AppData\Local\Android\Sdk\build-tools -Filter aapt.exe -Recurse` and record it in `docs/environment.md`. Confirm no broad storage/media permission and no unexpected exported component.

- [ ] **Step 5: Re-run the final SM-T500 checklist**

Install the freshly built APK, execute every line of `docs/manual-tests/milestone-0-android.md`, add the date and pass/fail result, and record any codec/source limitation. Do not mark a failed or unrun item as passing.

- [ ] **Step 6: Inspect the final diff and commit**

```powershell
git status --short
git diff --check
git diff --stat 25c6c35
git add README.md docs apps packages tool pubspec.yaml pubspec.lock analysis_options.yaml .gitignore
git commit -m "docs: complete Milestone 0 validation record"
```

Update `docs/implementation_status.md` as follows:

- `App scaffold`: `Complete` only when build/analyze/tests pass.
- `Android SAF root grant`: `Complete` only when picker, restart, and revocation checks pass on SM-T500.
- `SAF recursive enumeration`: `Complete` only when nested/cancelled/device checks pass.
- `Media source bridge`: `Complete` only when the selected strategy passes MP4/MKV/seek/lifecycle checks; otherwise `Spike` or `Blocked`.
- `Player/progress`: `Implemented, unvalidated` is not used for full progress semantics; this milestone validates playback only.
- `Diagnostics/export`, catalog, matching, metadata, database, and release items remain `Not started`.

## Final verification checklist

- [ ] `dart format --output=none --set-exit-if-changed .` exits 0.
- [ ] `flutter analyze` reports no issues.
- [ ] All three Dart package suites pass.
- [ ] Flutter unit/widget/fake integration suites pass.
- [ ] Kotlin unit tests pass.
- [ ] Android debug APK builds.
- [ ] Manifest inspection confirms no broad storage/media permission.
- [ ] SM-T500 grant survives force-stop/relaunch.
- [ ] Nested enumeration, cancellation, and AppleDouble exclusion pass.
- [ ] MP4 and MKV results are recorded honestly.
- [ ] Seek, pause/resume, lifecycle, sequential playback, SRT, and probing are recorded.
- [ ] Grant revocation produces repair UI.
- [ ] Player and source resources close without repeated descriptor errors.
- [ ] ADR-003, ADR-004, and ADR-011 match observed device behavior.
- [ ] No raw private URI/path or credential appears in committed logs/docs.
