import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_media_hub/features/risk_spike/playback_session_coordinator.dart';
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
}

final class FakePlaybackEngine implements PlaybackEngine {
  FakePlaybackEngine({this.onDispose, this.subtitleFailure});

  final FutureOr<void> Function()? onDispose;
  final AppFailure? subtitleFailure;
  PlaybackSnapshot _current = const PlaybackSnapshot.closed();
  int stopCalls = 0;
  int subtitleCalls = 0;

  @override
  PlaybackSnapshot get current => _current;

  @override
  Stream<PlaybackEvent> get events => const Stream<PlaybackEvent>.empty();

  @override
  Future<AppResult<void>> initialize() async => const Success<void>(null);

  @override
  Future<AppResult<void>> open(PlaybackRequest request) async {
    _current = const PlaybackSnapshot(isOpen: true);
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
  Future<void> dispose() async => onDispose?.call();

  @override
  Future<AppResult<void>> pause() =>
      throw StateError('Unexpected test call: pause');

  @override
  Future<AppResult<void>> play() =>
      throw StateError('Unexpected test call: play');

  @override
  Future<AppResult<void>> seek(Duration position) =>
      throw StateError('Unexpected test call: seek');
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
