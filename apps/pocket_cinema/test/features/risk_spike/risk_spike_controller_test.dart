import 'dart:async';
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
  test(
    'blocking playback pauses, preserves progress and prevents controls',
    () async {
      const playing = PlaybackSnapshot(
        isOpen: true,
        isPlaying: true,
        position: Duration(minutes: 3),
        duration: Duration(minutes: 30),
      );
      final playback = FakePlaybackSession(
        allowControls: true,
        initialSnapshot: playing,
      );
      final storage = FakeStorageGateway(lease: directLease);
      final controller = RiskSpikeController(
        storage: storage,
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
      final observedBlocks = <bool>[];
      controller.addListener(
        () => observedBlocks.add(controller.playbackBlocked),
      );

      controller.setPlaybackBlocked(true);
      expect(controller.playbackBlocked, isTrue);
      expect(observedBlocks.first, isTrue);
      await Future<void>.delayed(Duration.zero);
      await controller.togglePlayPause();
      await controller.seekBy(const Duration(seconds: 10));
      await controller.seekToStart();
      await controller.playSelected();
      await controller.play(root, videoEntry);

      expect(playback.controlCalls, ['pause']);
      expect(playback.snapshot.isOpen, isTrue);
      expect(playback.snapshot.isPlaying, isFalse);
      expect(playback.snapshot.position, playing.position);
      expect(playback.snapshot.duration, playing.duration);
      expect(controller.state.playbackSnapshot.position, playing.position);
      expect(playback.stopCount, 0);
      expect(storage.openCount, 0);
      controller.setPlaybackBlocked(false);
      await Future<void>.delayed(Duration.zero);
      expect(playback.controlCalls, ['pause']);
      expect(playback.snapshot.isPlaying, isFalse);
      await controller.togglePlayPause();
      expect(playback.controlCalls, ['pause', 'play']);
      expect(playback.snapshot.position, playing.position);
    },
  );

  test('blocking playback stops the source if pausing fails', () async {
    final playback = FakePlaybackSession(
      allowControls: true,
      allowStop: true,
      pauseFailure: fileUnavailableFailure,
      initialSnapshot: const PlaybackSnapshot(isOpen: true, isPlaying: true),
    );
    final controller = RiskSpikeController(
      storage: FakeStorageGateway(),
      probe: FakeMediaProbe(),
      playback: playback,
    );
    addTearDown(controller.dispose);

    controller.setPlaybackBlocked(true);
    await Future<void>.delayed(Duration.zero);

    expect(playback.controlCalls, ['pause']);
    expect(playback.stopCount, 1);
    expect(controller.state.playbackSnapshot.isOpen, isFalse);
  });

  test('late playback updates are paused again while blocked', () async {
    final playback = FakePlaybackSession(
      allowControls: true,
      initialSnapshot: const PlaybackSnapshot(isOpen: true, isPlaying: true),
    );
    final controller = RiskSpikeController(
      storage: FakeStorageGateway(),
      probe: FakeMediaProbe(),
      playback: playback,
    );
    addTearDown(controller.dispose);

    controller.setPlaybackBlocked(true);
    await Future<void>.delayed(Duration.zero);
    playback._snapshot = playback.snapshot.copyWith(isPlaying: true);
    controller.refreshPlaybackSnapshot();
    await Future<void>.delayed(Duration.zero);

    expect(playback.controlCalls, ['pause', 'pause']);
    expect(controller.state.playbackSnapshot.isPlaying, isFalse);
  });

  for (final clearBeforeOpen in [false, true]) {
    test(
      'source opening interrupted by a block finishes paused (clear: $clearBeforeOpen)',
      () async {
        final opening = Completer<void>();
        final playback = FakePlaybackSession(allowControls: true);
        final storage = FakeStorageGateway(
          lease: directLease,
          onOpen: () => opening.future,
        );
        final controller = RiskSpikeController(
          storage: storage,
          probe: FakeMediaProbe(),
          playback: playback,
        );
        addTearDown(controller.dispose);

        final started = controller.play(
          root,
          videoEntry,
          startPosition: const Duration(minutes: 3),
        );
        controller.setPlaybackBlocked(true);
        if (clearBeforeOpen) controller.setPlaybackBlocked(false);
        opening.complete();
        await started;

        expect(playback.openCount, 1);
        expect(playback.snapshot.isPlaying, isFalse);
        expect(playback.snapshot.position, const Duration(minutes: 3));
        expect(playback.controlCalls, ['pause']);
        expect(storage.activeLeaseCount, 1);
      },
    );
  }

  test(
    'a block during attaching playback leaves the new source paused',
    () async {
      final attaching = Completer<void>();
      final playback = FakePlaybackSession(
        allowControls: true,
        onAttach: () => attaching.future,
      );
      final controller = RiskSpikeController(
        storage: FakeStorageGateway(lease: directLease),
        probe: FakeMediaProbe(),
        playback: playback,
      );
      addTearDown(controller.dispose);

      final started = controller.play(root, videoEntry);
      await Future<void>.delayed(Duration.zero);
      controller.setPlaybackBlocked(true);
      controller.setPlaybackBlocked(false);
      attaching.complete();
      await started;

      expect(playback.snapshot.isOpen, isTrue);
      expect(playback.snapshot.isPlaying, isFalse);
      expect(playback.controlCalls, ['pause']);
    },
  );

  test('a delayed play command cannot resume after a block clears', () async {
    final playing = Completer<void>();
    final playback = FakePlaybackSession(
      allowControls: true,
      onPlay: () => playing.future,
      initialSnapshot: const PlaybackSnapshot(isOpen: true),
    );
    final controller = RiskSpikeController(
      storage: FakeStorageGateway(),
      probe: FakeMediaProbe(),
      playback: playback,
    );
    addTearDown(controller.dispose);

    final started = controller.togglePlayPause();
    await Future<void>.delayed(Duration.zero);
    controller.setPlaybackBlocked(true);
    controller.setPlaybackBlocked(false);
    playing.complete();
    await started;

    expect(playback.controlCalls, ['play', 'pause']);
    expect(playback.snapshot.isPlaying, isFalse);
  });

  test(
    'a pending play gesture is cancelled if a block starts and clears',
    () async {
      final playback = FakePlaybackSession(
        allowControls: true,
        initialSnapshot: const PlaybackSnapshot(isOpen: true),
      );
      final controller = RiskSpikeController(
        storage: FakeStorageGateway(),
        probe: FakeMediaProbe(),
        playback: playback,
      );
      addTearDown(controller.dispose);

      final started = controller.togglePlayPause();
      controller.setPlaybackBlocked(true);
      controller.setPlaybackBlocked(false);
      await started;

      expect(playback.controlCalls, isEmpty);
      expect(playback.snapshot.isPlaying, isFalse);
    },
  );

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
    this.onOpen,
    this.persistedRoots = const [],
    this.accessState = RootAccessState.available,
    this.onChoose,
    this.onEnumerate,
    this.subtitleContent,
  });

  factory FakeStorageGateway.scan(List<StorageScanEvent> events) =>
      FakeStorageGateway(scanEvents: events);

  final List<StorageScanEvent> scanEvents;
  final AppFailure? openFailure;
  final AppFailure? subtitleReadFailure;
  final MediaSourceLease? lease;
  final bool releaseRootSucceeds;
  final Future<void> Function()? onOpen;
  final List<AuthorizedLibraryRoot> persistedRoots;
  final RootAccessState accessState;
  final Future<AppResult<AuthorizedLibraryRoot>> Function()? onChoose;
  final Stream<StorageScanEvent> Function(String, CancellationToken)?
  onEnumerate;
  final SmallFileContent? subtitleContent;
  int activeLeaseCount = 0;
  int openCount = 0;
  int scanCount = 0;
  final checkedRoots = <LibraryRootLocator>[];
  final readKeys = <String>[];

  @override
  Stream<StorageScanEvent> enumerateRecursively({
    required LibraryRootLocator root,
    required String scanId,
    required CancellationToken cancellationToken,
  }) async* {
    scanCount++;
    if (onEnumerate != null) {
      yield* onEnumerate!(scanId, cancellationToken);
      return;
    }
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
    openCount++;
    await onOpen?.call();
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
    readKeys.add(storageKey);
    final failure = subtitleReadFailure;
    if (failure != null) {
      return FailureResult<SmallFileContent>(failure);
    }
    if (subtitleContent != null) {
      return Success<SmallFileContent>(subtitleContent!);
    }
    throw StateError('Unexpected test call: readSmallFile');
  }

  @override
  Future<void> releasePlaybackSource(MediaSourceLease lease) async {
    activeLeaseCount--;
  }

  @override
  Future<AppResult<RootAccessState>> checkAccess(
    LibraryRootLocator root,
  ) async {
    checkedRoots.add(root);
    return Success<RootAccessState>(accessState);
  }

  @override
  Future<AppResult<AuthorizedLibraryRoot>> chooseRoot() =>
      onChoose?.call() ??
      (throw StateError('Unexpected test call: chooseRoot'));

  @override
  Future<AppResult<List<AuthorizedLibraryRoot>>> listPersistedRoots() async =>
      Success<List<AuthorizedLibraryRoot>>(persistedRoots);

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
    this.allowControls = false,
    this.pauseFailure,
    this.onAttach,
    this.onPlay,
    this.allowSubtitle = false,
    PlaybackSnapshot initialSnapshot = const PlaybackSnapshot.closed(),
  }) : _snapshot = initialSnapshot;

  final bool allowStop;
  final bool allowLifecycleInactive;
  final AppFailure? lifecycleFailure;
  final bool allowControls;
  final AppFailure? pauseFailure;
  final Future<void> Function()? onAttach;
  final Future<void> Function()? onPlay;
  final bool allowSubtitle;
  final subtitleLanguages = <String?>[];
  PlaybackSnapshot _snapshot;
  int openCount = 0;
  int stopCount = 0;
  final controlCalls = <String>[];

  @override
  PlaybackSnapshot get snapshot => _snapshot;

  @override
  Future<AppResult<void>> attachLease(
    MediaSourceLease lease, {
    Duration startPosition = Duration.zero,
  }) async {
    openCount++;
    await onAttach?.call();
    _snapshot = PlaybackSnapshot(
      isOpen: true,
      isPlaying: true,
      position: startPosition,
    );
    return const Success<void>(null);
  }

  @override
  Future<AppResult<void>> attachSubtitle(
    Uint8List bytes, {
    String? languageTag,
  }) async {
    if (!allowSubtitle) {
      throw StateError('Unexpected test call: attachSubtitle');
    }
    subtitleLanguages.add(languageTag);
    return const Success<void>(null);
  }

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
  Future<AppResult<void>> pause() async {
    if (!allowControls) throw StateError('Unexpected test call: pause');
    controlCalls.add('pause');
    final failure = pauseFailure;
    if (failure != null) return FailureResult<void>(failure);
    _snapshot = _snapshot.copyWith(isPlaying: false);
    return const Success<void>(null);
  }

  @override
  Future<AppResult<void>> play() async {
    if (!allowControls) throw StateError('Unexpected test call: play');
    controlCalls.add('play');
    await onPlay?.call();
    _snapshot = _snapshot.copyWith(isPlaying: true);
    return const Success<void>(null);
  }

  @override
  Future<AppResult<void>> seek(Duration position) async {
    if (!allowControls) throw StateError('Unexpected test call: seek');
    controlCalls.add('seek');
    _snapshot = _snapshot.copyWith(position: position);
    return const Success<void>(null);
  }

  @override
  Future<void> stop() async {
    if (!allowStop) {
      throw StateError('Unexpected test call: stop');
    }
    stopCount++;
    _snapshot = const PlaybackSnapshot.closed();
  }
}
