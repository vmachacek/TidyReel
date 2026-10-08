import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_cinema/features/risk_spike/playback_session_coordinator.dart';
import 'package:pocket_cinema/features/risk_spike/risk_spike_controller.dart';
import 'package:pocket_cinema/features/risk_spike/risk_spike_state.dart';
import 'package:media_domain/media_domain.dart';
import 'package:media_platform_storage/media_platform_storage.dart';
import 'package:media_playback/media_playback.dart';

const root = AuthorizedLibraryRoot(
  locator: LibraryRootLocator(
    storageKind: StorageKind.androidSaf,
    opaqueValue: 'content://redacted/tree/root',
  ),
  displayName: 'Movies',
);

final videoEntry = StorageEntrySnapshot(
  storageKey: 'provider|video',
  parentStorageKey: 'provider|folder',
  relativePath: 'Movie.mp4',
  displayName: 'Movie.mp4',
  isDirectory: false,
  mimeType: 'video/mp4',
  sizeBytes: 1024,
  modifiedAtUtc: DateTime.utc(2026),
  flags: const {StorageEntryFlag.supportsRead},
);

final subtitleEntry = StorageEntrySnapshot(
  storageKey: 'provider|subtitle',
  parentStorageKey: 'provider|folder',
  relativePath: 'Movie.en.srt',
  displayName: 'Movie.en.srt',
  isDirectory: false,
  mimeType: 'application/x-subrip',
  sizeBytes: 128,
  modifiedAtUtc: DateTime.utc(2026),
  flags: const {StorageEntryFlag.supportsRead},
);

const directLease = MediaSourceLease(
  leaseId: 'direct-1',
  sourceUri: 'content://redacted/document/video',
  strategy: PlaybackSourceStrategy.directContentUri,
);

const scanFailure = AppFailure(
  code: 'SCAN_FAILED',
  messageKey: 'scanFailed',
  retryable: true,
);

const fileUnavailableFailure = AppFailure(
  code: 'FILE_UNAVAILABLE',
  messageKey: 'fileUnavailable',
  retryable: true,
);

const permissionRevokedFailure = AppFailure(
  code: 'STORAGE_PERMISSION_REVOKED',
  messageKey: 'rootPermissionRevoked',
  retryable: true,
);

const subtitleTooLargeFailure = AppFailure(
  code: 'SMALL_FILE_LIMIT_EXCEEDED',
  messageKey: 'subtitleTooLarge',
  retryable: false,
);

void main() {
  test('failed scan retains partial count and never marks complete', () async {
    final storage = FakeStorageGateway.scan([
      StorageScanBatch('scan-1', [videoEntry]),
      const StorageScanFailed('scan-1', scanFailure),
    ]);
    final controller = RiskSpikeController(
      storage: storage,
      probe: FakeMediaProbe(),
      playback: FakePlaybackSession(),
    );

    await controller.scan(root);

    expect(controller.state.discoveredCount, 1);
    expect(controller.state.phase, RiskSpikePhase.failure);
    expect(controller.state.scanCompleted, isFalse);
  });

  test('file disappearing before playback shows recoverable failure', () async {
    final storage = FakeStorageGateway(openFailure: fileUnavailableFailure);
    final controller = RiskSpikeController(
      storage: storage,
      probe: FakeMediaProbe(),
      playback: FakePlaybackSession(),
    );

    await controller.play(root, videoEntry);

    expect(controller.state.failure?.code, 'FILE_UNAVAILABLE');
    expect(controller.state.canRescan, isTrue);
  });

  test('grant revoked between validation and playback offers repair', () async {
    final storage = FakeStorageGateway(openFailure: permissionRevokedFailure);
    final controller = RiskSpikeController(
      storage: storage,
      probe: FakeMediaProbe(),
      playback: FakePlaybackSession(),
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
    final playback = FakePlaybackSession();
    final controller = RiskSpikeController(
      storage: storage,
      probe: FakeMediaProbe(),
      playback: playback,
    );

    await controller.play(root, videoEntry, subtitle: subtitleEntry);

    expect(controller.state.subtitleWarning?.code, 'SMALL_FILE_LIMIT_EXCEEDED');
    expect(playback.openCount, 1);
  });

  test('releasing test access offers the folder repair action', () async {
    final storage = FakeStorageGateway(releaseRootSucceeds: true);
    final playback = FakePlaybackSession(allowStop: true);
    final controller = RiskSpikeController(
      storage: storage,
      probe: FakeMediaProbe(),
      playback: playback,
      initialState: const RiskSpikeState(
        phase: RiskSpikePhase.ready,
        root: root,
      ),
    );

    await controller.releaseRoot();

    expect(controller.state.failure?.code, 'STORAGE_PERMISSION_REVOKED');
    expect(controller.state.canRepairRoot, isTrue);
    expect(playback.stopCount, 1);
  });

  test(
    'lifecycle interruption retains playback progress and player state',
    () async {
      const playing = PlaybackSnapshot(
        isOpen: true,
        isPlaying: true,
        position: Duration(minutes: 3),
        duration: Duration(minutes: 30),
      );
      final playback = FakePlaybackSession(
        allowLifecycleInactive: true,
        initialSnapshot: playing,
      );
      final controller = RiskSpikeController(
        storage: FakeStorageGateway(),
        probe: FakeMediaProbe(),
        playback: playback,
        initialState: RiskSpikeState(
          phase: RiskSpikePhase.playing,
          root: root,
          entries: [videoEntry],
          selectedFile: videoEntry,
          playbackSnapshot: playing,
          scanCompleted: true,
          videoCount: 1,
          subtitleWarning: subtitleTooLargeFailure,
        ),
      );
      addTearDown(controller.dispose);

      await controller.handleLifecycleInactive();
      await controller.handleLifecycleInactive();

      expect(controller.state.phase, RiskSpikePhase.playing);
      expect(controller.state.playbackSnapshot.isOpen, isTrue);
      expect(controller.state.playbackSnapshot.isPlaying, isFalse);
      expect(controller.state.playbackSnapshot.position, playing.position);
      expect(controller.state.playbackSnapshot.duration, playing.duration);
      expect(controller.state.selectedFile, same(videoEntry));
      expect(controller.state.entries, [videoEntry]);
      expect(controller.state.root, same(root));
      expect(controller.state.scanCompleted, isTrue);
      expect(controller.state.videoCount, 1);
      expect(controller.state.subtitleWarning, same(subtitleTooLargeFailure));
      expect(playback.stopCount, 0);
    },
  );

  test(
    'refresh publishes completion changes even at an unchanged position',
    () {
      const pausedAtEnd = PlaybackSnapshot(
        isOpen: true,
        position: Duration(minutes: 30),
        duration: Duration(minutes: 30),
      );
      final playback = FakePlaybackSession(initialSnapshot: pausedAtEnd);
      final controller = RiskSpikeController(
        storage: FakeStorageGateway(),
        probe: FakeMediaProbe(),
        playback: playback,
        initialState: RiskSpikeState(
          phase: RiskSpikePhase.playing,
          root: root,
          selectedFile: videoEntry,
          playbackSnapshot: pausedAtEnd,
        ),
      );
      addTearDown(controller.dispose);
      var updates = 0;
      controller.addListener(() => updates++);

      controller.refreshPlaybackSnapshot();
      expect(controller.state.playbackSnapshot.isCompleted, isFalse);
      expect(updates, 0);
      playback._snapshot = pausedAtEnd.copyWith(isCompleted: true);
      controller.refreshPlaybackSnapshot();
      expect(controller.state.playbackSnapshot.isCompleted, isTrue);
      expect(updates, 1);
      controller.refreshPlaybackSnapshot();
      expect(updates, 1);
      playback._snapshot = pausedAtEnd;
      controller.refreshPlaybackSnapshot();
      expect(controller.state.playbackSnapshot.isCompleted, isFalse);
      expect(updates, 2);
    },
  );

  test(
    'lifecycle interruption while idle leaves existing state intact',
    () async {
      final initial = RiskSpikeState(
        phase: RiskSpikePhase.enumerating,
        root: root,
        entries: [videoEntry],
        discoveredCount: 1,
        canCancel: true,
        failure: scanFailure,
      );
      final controller = RiskSpikeController(
        storage: FakeStorageGateway(),
        probe: FakeMediaProbe(),
        playback: FakePlaybackSession(allowLifecycleInactive: true),
        initialState: initial,
      );
      addTearDown(controller.dispose);

      await controller.handleLifecycleInactive();

      expect(controller.state, same(initial));
    },
  );

  test(
    'lifecycle pause failure is visible while keeping the player open',
    () async {
      const failure = AppFailure(
        code: 'PLAYBACK_CONTROL_FAILED',
        messageKey: 'playbackControlFailed',
        retryable: true,
      );
      const playing = PlaybackSnapshot(isOpen: true, isPlaying: true);
      final playback = FakePlaybackSession(
        allowLifecycleInactive: true,
        initialSnapshot: playing,
        lifecycleFailure: failure,
      );
      final controller = RiskSpikeController(
        storage: FakeStorageGateway(),
        probe: FakeMediaProbe(),
        playback: playback,
        initialState: RiskSpikeState(
          phase: RiskSpikePhase.playing,
          root: root,
          selectedFile: videoEntry,
          playbackSnapshot: playing,
        ),
      );
      addTearDown(controller.dispose);

      await controller.handleLifecycleInactive();

      expect(controller.state.phase, RiskSpikePhase.playing);
      expect(controller.state.playbackSnapshot.isOpen, isTrue);
      expect(controller.state.failure, same(failure));
      expect(controller.state.playbackSnapshot.failure, same(failure));
    },
  );
}

final class FakeStorageGateway implements LibraryStorageGateway {
  FakeStorageGateway({
    this.scanEvents = const <StorageScanEvent>[],
    this.openFailure,
    this.subtitleReadFailure,
    this.lease,
    this.releaseRootSucceeds = false,
  });

  factory FakeStorageGateway.scan(List<StorageScanEvent> events) =>
      FakeStorageGateway(scanEvents: events);

  final List<StorageScanEvent> scanEvents;
  final AppFailure? openFailure;
  final AppFailure? subtitleReadFailure;
  final MediaSourceLease? lease;
  final bool releaseRootSucceeds;
  int activeLeaseCount = 0;

  @override
  Stream<StorageScanEvent> enumerateRecursively({
    required LibraryRootLocator root,
    required String scanId,
    required CancellationToken cancellationToken,
  }) async* {
    for (final event in scanEvents) {
      yield event;
    }
  }

  @override
  Future<AppResult<MediaSourceLease>> openPlaybackSource({
    required LibraryRootLocator root,
    required String storageKey,
    required PlaybackSourceStrategy strategy,
  }) async {
    final failure = openFailure;
    if (failure != null) {
      return FailureResult<MediaSourceLease>(failure);
    }
    final value = lease;
    if (value == null) {
      throw StateError('Unexpected test call: openPlaybackSource');
    }
    activeLeaseCount++;
    return Success<MediaSourceLease>(value);
  }

  @override
  Future<AppResult<SmallFileContent>> readSmallFile({
    required LibraryRootLocator root,
    required String storageKey,
    required int maximumBytes,
  }) async {
    final failure = subtitleReadFailure;
    if (failure != null) {
      return FailureResult<SmallFileContent>(failure);
    }
    throw StateError('Unexpected test call: readSmallFile');
  }

  @override
  Future<void> releasePlaybackSource(MediaSourceLease lease) async {
    activeLeaseCount--;
  }

  @override
  Future<AppResult<RootAccessState>> checkAccess(LibraryRootLocator root) =>
      throw StateError('Unexpected test call: checkAccess');

  @override
  Future<AppResult<AuthorizedLibraryRoot>> chooseRoot() =>
      throw StateError('Unexpected test call: chooseRoot');

  @override
  Future<AppResult<List<AuthorizedLibraryRoot>>> listPersistedRoots() =>
      throw StateError('Unexpected test call: listPersistedRoots');

  @override
  Future<AppResult<void>> releaseRootPermission(LibraryRootLocator root) async {
    if (releaseRootSucceeds) {
      return const Success<void>(null);
    }
    throw StateError('Unexpected test call: releaseRootPermission');
  }
}

final class FakeMediaProbe implements MediaProbe {
  @override
  Future<AppResult<MediaProbeResult>> probe({
    required LibraryRootLocator root,
    required String storageKey,
    required CancellationToken cancellationToken,
  }) => throw StateError('Unexpected test call: probe');
}

final class FakePlaybackSession implements PlaybackSession {
  FakePlaybackSession({
    this.allowStop = false,
    this.allowLifecycleInactive = false,
    this.lifecycleFailure,
    PlaybackSnapshot initialSnapshot = const PlaybackSnapshot.closed(),
  }) : _snapshot = initialSnapshot;

  final bool allowStop;
  final bool allowLifecycleInactive;
  final AppFailure? lifecycleFailure;
  PlaybackSnapshot _snapshot;
  int openCount = 0;
  int stopCount = 0;

  @override
  PlaybackSnapshot get snapshot => _snapshot;

  @override
  Future<AppResult<void>> attachLease(
    MediaSourceLease lease, {
    Duration startPosition = Duration.zero,
  }) async {
    openCount++;
    _snapshot = const PlaybackSnapshot(isOpen: true, isPlaying: true);
    return const Success<void>(null);
  }

  @override
  Future<AppResult<void>> attachSubtitle(
    Uint8List bytes, {
    String? languageTag,
  }) => throw StateError('Unexpected test call: attachSubtitle');

  @override
  Future<void> handleLifecycleInactive() async {
    if (!allowLifecycleInactive) {
      throw StateError('Unexpected test call: handleLifecycleInactive');
    }
    if (!_snapshot.isOpen) return;
    _snapshot = _snapshot.copyWith(
      isPlaying: lifecycleFailure == null ? false : _snapshot.isPlaying,
      failure: lifecycleFailure,
    );
  }

  @override
  Future<AppResult<void>> pause() =>
      throw StateError('Unexpected test call: pause');

  @override
  Future<AppResult<void>> play() =>
      throw StateError('Unexpected test call: play');

  @override
  Future<AppResult<void>> seek(Duration position) =>
      throw StateError('Unexpected test call: seek');

  @override
  Future<void> stop() async {
    if (!allowStop) {
      throw StateError('Unexpected test call: stop');
    }
    stopCount++;
    _snapshot = const PlaybackSnapshot.closed();
  }
}
