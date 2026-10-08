import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_cinema/features/risk_spike/playback_session_coordinator.dart';
import 'package:media_domain/media_domain.dart';
import 'package:media_platform_storage/media_platform_storage.dart';
import 'package:media_playback/media_playback.dart';

const directLease = MediaSourceLease(
  leaseId: 'direct-1',
  sourceUri: 'content://redacted/document/video',
  strategy: PlaybackSourceStrategy.directContentUri,
);

const subtitleFailure = AppFailure(
  code: 'EXTERNAL_SUBTITLE_FAILED',
  messageKey: 'externalSubtitleFailed',
  retryable: true,
  safeDetail: 'The external subtitle could not be attached.',
);

void main() {
  test(
    'Resume position is part of opening the source, without a startup seek',
    () async {
      final engine = FakePlaybackEngine();
      final coordinator = PlaybackSessionCoordinator(
        engineFactory: FakePlaybackEngineFactory([engine]),
        storage: FakeStorageGateway(),
      );
      await coordinator.attachLease(
        directLease,
        startPosition: const Duration(minutes: 3),
      );
      expect(engine.request?.startPosition, const Duration(minutes: 3));
      expect(engine.controlCalls, isEmpty);
      await coordinator.stop();
    },
  );
  test('stop disposes player before releasing source lease', () async {
    final calls = <String>[];
    final engine = FakePlaybackEngine(
      onDispose: () async {
        await Future<void>.delayed(Duration.zero);
        calls.add('dispose');
      },
    );
    final storage = FakeStorageGateway(onRelease: (_) => calls.add('release'));
    final coordinator = PlaybackSessionCoordinator(
      engineFactory: FakePlaybackEngineFactory([engine]),
      storage: storage,
    );
    await coordinator.attachLease(directLease);

    await coordinator.stop();

    expect(calls, ['dispose', 'release']);
  });

  test(
    'rapid source replacement closes the previous lease exactly once',
    () async {
      final storage = FakeStorageGateway();
      final coordinator = PlaybackSessionCoordinator(
        engineFactory: FakePlaybackEngineFactory([
          FakePlaybackEngine(),
          FakePlaybackEngine(),
        ]),
        storage: storage,
      );
      const secondLease = MediaSourceLease(
        leaseId: 'direct-2',
        sourceUri: 'content://redacted/document/video-2',
        strategy: PlaybackSourceStrategy.directContentUri,
      );
      await coordinator.attachLease(directLease);
      await coordinator.attachLease(secondLease);
      await coordinator.stop();
      await coordinator.stop();

      expect(storage.releaseCounts[directLease.leaseId], 1);
      expect(storage.releaseCounts[secondLease.leaseId], 1);
    },
  );

  test(
    'malformed subtitle reports warning without stopping playback',
    () async {
      final engine = FakePlaybackEngine(subtitleFailure: subtitleFailure);
      final coordinator = PlaybackSessionCoordinator(
        engineFactory: FakePlaybackEngineFactory([engine]),
        storage: FakeStorageGateway(),
      );
      await coordinator.attachLease(directLease);

      final result = await coordinator.attachSubtitle(
        Uint8List.fromList([0xC3, 0x28]),
      );

      expect(result, isA<FailureResult<void>>());
      expect(coordinator.snapshot.isOpen, isTrue);
      expect(engine.stopCalls, 0);
    },
  );

  test('oversize subtitle reports warning without invoking player', () async {
    final engine = FakePlaybackEngine();
    final coordinator = PlaybackSessionCoordinator(
      engineFactory: FakePlaybackEngineFactory([engine]),
      storage: FakeStorageGateway(),
    );
    await coordinator.attachLease(directLease);

    final result = await coordinator.attachSubtitle(
      Uint8List(PlaybackSessionCoordinator.maximumSubtitleBytes + 1),
    );

    expect(result, isA<FailureResult<void>>());
    expect(coordinator.snapshot.isOpen, isTrue);
    expect(engine.subtitleCalls, 0);
  });

  test('playback controls delegate to the active engine', () async {
    final engine = FakePlaybackEngine();
    final coordinator = PlaybackSessionCoordinator(
      engineFactory: FakePlaybackEngineFactory([engine]),
      storage: FakeStorageGateway(),
    );
    await coordinator.attachLease(directLease);

    await coordinator.pause();
    await coordinator.play();
    await coordinator.seek(const Duration(seconds: 12));

    expect(engine.controlCalls, ['pause', 'play', 'seek:12000']);
  });

  test(
    'lifecycle interruption pauses without closing the player or lease',
    () async {
      final engine = FakePlaybackEngine(
        openedSnapshot: const PlaybackSnapshot(
          isOpen: true,
          isPlaying: true,
          position: Duration(minutes: 3),
          duration: Duration(minutes: 30),
        ),
      );
      final storage = FakeStorageGateway();
      final coordinator = PlaybackSessionCoordinator(
        engineFactory: FakePlaybackEngineFactory([engine]),
        storage: storage,
      );
      await coordinator.attachLease(directLease);

      await coordinator.handleLifecycleInactive();
      await coordinator.handleLifecycleInactive();

      expect(coordinator.activeEngine, same(engine));
      expect(coordinator.snapshot.isOpen, isTrue);
      expect(coordinator.snapshot.isPlaying, isFalse);
      expect(coordinator.snapshot.position, const Duration(minutes: 3));
      expect(coordinator.snapshot.duration, const Duration(minutes: 30));
      expect(engine.controlCalls, ['pause']);
      expect(engine.stopCalls, 0);
      expect(engine.disposeCalls, 0);
      expect(storage.releaseCounts, isEmpty);

      await coordinator.play();
      await coordinator.seek(const Duration(minutes: 4));
      expect(coordinator.snapshot.isPlaying, isTrue);
      expect(coordinator.snapshot.position, const Duration(minutes: 4));
      expect(engine.controlCalls, ['pause', 'play', 'seek:240000']);

      await coordinator.stop();
      await coordinator.stop();
      expect(coordinator.snapshot.isOpen, isFalse);
      expect(engine.stopCalls, 1);
      expect(engine.disposeCalls, 1);
      expect(storage.releaseCounts[directLease.leaseId], 1);
    },
  );

  test('overlapping lifecycle notifications share the same pause', () async {
    final paused = Completer<void>();
    final engine = FakePlaybackEngine(
      openedSnapshot: const PlaybackSnapshot(isOpen: true, isPlaying: true),
      onPause: () => paused.future,
    );
    final coordinator = PlaybackSessionCoordinator(
      engineFactory: FakePlaybackEngineFactory([engine]),
      storage: FakeStorageGateway(),
    );
    await coordinator.attachLease(directLease);

    final inactive = coordinator.handleLifecycleInactive();
    final background = coordinator.handleLifecycleInactive();
    expect(background, same(inactive));
    expect(engine.controlCalls, ['pause']);
    paused.complete();
    await Future.wait([inactive, background]);

    expect(coordinator.snapshot.isOpen, isTrue);
    expect(coordinator.snapshot.isPlaying, isFalse);
    await coordinator.stop();
  });

  test('lifecycle interruption without an open source is a no-op', () async {
    final engine = FakePlaybackEngine(
      openedSnapshot: const PlaybackSnapshot.closed(),
    );
    final storage = FakeStorageGateway();
    final coordinator = PlaybackSessionCoordinator(
      engineFactory: FakePlaybackEngineFactory([engine]),
      storage: storage,
    );

    await coordinator.handleLifecycleInactive();
    expect(coordinator.activeEngine, isNull);
    await coordinator.attachLease(directLease);
    await coordinator.handleLifecycleInactive();
    expect(coordinator.activeEngine, same(engine));
    expect(engine.controlCalls, isEmpty);
    expect(engine.stopCalls, 0);
    expect(storage.releaseCounts, isEmpty);
    await coordinator.stop();
  });

  test(
    'failed lifecycle pause is reported without discarding the source',
    () async {
      const failure = AppFailure(
        code: 'PLAYBACK_CONTROL_FAILED',
        messageKey: 'playbackControlFailed',
        retryable: true,
      );
      final engine = FakePlaybackEngine(
        openedSnapshot: const PlaybackSnapshot(isOpen: true, isPlaying: true),
        pauseFailure: failure,
      );
      final storage = FakeStorageGateway();
      final coordinator = PlaybackSessionCoordinator(
        engineFactory: FakePlaybackEngineFactory([engine]),
        storage: storage,
      );
      await coordinator.attachLease(directLease);

      await coordinator.handleLifecycleInactive();

      expect(coordinator.snapshot.failure, same(failure));
      expect(coordinator.snapshot.isOpen, isTrue);
      expect(coordinator.activeEngine, same(engine));
      expect(storage.releaseCounts, isEmpty);
      await coordinator.play();
      expect(coordinator.snapshot.failure, isNull);
      await coordinator.stop();
    },
  );
}

final class FakePlaybackEngine implements PlaybackEngine {
  FakePlaybackEngine({
    this.onDispose,
    this.subtitleFailure,
    this.openedSnapshot = const PlaybackSnapshot(isOpen: true),
    this.onPause,
    this.pauseFailure,
  });

  final FutureOr<void> Function()? onDispose;
  final AppFailure? subtitleFailure;
  final PlaybackSnapshot openedSnapshot;
  final Future<void> Function()? onPause;
  final AppFailure? pauseFailure;
  PlaybackSnapshot _current = const PlaybackSnapshot.closed();
  int stopCalls = 0;
  int disposeCalls = 0;
  int subtitleCalls = 0;
  PlaybackRequest? request;
  final List<String> controlCalls = <String>[];

  @override
  PlaybackSnapshot get current => _current;

  @override
  Stream<PlaybackEvent> get events => const Stream<PlaybackEvent>.empty();

  @override
  Future<AppResult<void>> initialize() async => const Success<void>(null);

  @override
  Future<AppResult<void>> open(PlaybackRequest request) async {
    this.request = request;
    _current = openedSnapshot;
    return const Success<void>(null);
  }

  @override
  Future<AppResult<void>> attachSubtitleData(
    Uint8List bytes, {
    String? languageTag,
  }) async {
    subtitleCalls++;
    final failure = subtitleFailure;
    return failure == null
        ? const Success<void>(null)
        : FailureResult<void>(failure);
  }

  @override
  Future<AppResult<void>> stop() async {
    stopCalls++;
    _current = const PlaybackSnapshot.closed();
    return const Success<void>(null);
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
    await onDispose?.call();
  }

  @override
  Future<AppResult<void>> pause() async {
    controlCalls.add('pause');
    await onPause?.call();
    final failure = pauseFailure;
    if (failure != null) return FailureResult<void>(failure);
    _current = _current.copyWith(isPlaying: false);
    return const Success<void>(null);
  }

  @override
  Future<AppResult<void>> play() async {
    controlCalls.add('play');
    _current = _current.copyWith(isPlaying: true);
    return const Success<void>(null);
  }

  @override
  Future<AppResult<void>> seek(Duration position) async {
    controlCalls.add('seek:${position.inMilliseconds}');
    _current = _current.copyWith(position: position);
    return const Success<void>(null);
  }
}

final class FakePlaybackEngineFactory implements PlaybackEngineFactory {
  FakePlaybackEngineFactory(this.engines);

  final List<PlaybackEngine> engines;
  var _index = 0;

  @override
  PlaybackEngine create() {
    if (_index >= engines.length) {
      throw StateError('Unexpected test call: create');
    }
    return engines[_index++];
  }
}

final class FakeStorageGateway implements LibraryStorageGateway {
  FakeStorageGateway({this.onRelease});

  final void Function(MediaSourceLease lease)? onRelease;
  final Map<String, int> releaseCounts = <String, int>{};

  @override
  Future<void> releasePlaybackSource(MediaSourceLease lease) async {
    releaseCounts.update(
      lease.leaseId,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    onRelease?.call(lease);
  }

  @override
  Future<AppResult<RootAccessState>> checkAccess(LibraryRootLocator root) =>
      throw StateError('Unexpected test call: checkAccess');

  @override
  Future<AppResult<AuthorizedLibraryRoot>> chooseRoot() =>
      throw StateError('Unexpected test call: chooseRoot');

  @override
  Stream<StorageScanEvent> enumerateRecursively({
    required LibraryRootLocator root,
    required String scanId,
    required CancellationToken cancellationToken,
  }) => throw StateError('Unexpected test call: enumerateRecursively');

  @override
  Future<AppResult<List<AuthorizedLibraryRoot>>> listPersistedRoots() =>
      throw StateError('Unexpected test call: listPersistedRoots');

  @override
  Future<AppResult<MediaSourceLease>> openPlaybackSource({
    required LibraryRootLocator root,
    required String storageKey,
    required PlaybackSourceStrategy strategy,
  }) => throw StateError('Unexpected test call: openPlaybackSource');

  @override
  Future<AppResult<SmallFileContent>> readSmallFile({
    required LibraryRootLocator root,
    required String storageKey,
    required int maximumBytes,
  }) => throw StateError('Unexpected test call: readSmallFile');

  @override
  Future<AppResult<void>> releaseRootPermission(LibraryRootLocator root) =>
      throw StateError('Unexpected test call: releaseRootPermission');
}
