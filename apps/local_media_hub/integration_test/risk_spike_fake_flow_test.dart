import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:local_media_hub/app/local_media_hub_app.dart';
import 'package:local_media_hub/features/risk_spike/playback_session_coordinator.dart';
import 'package:local_media_hub/features/risk_spike/risk_spike_controller.dart';
import 'package:media_domain/media_domain.dart';
import 'package:media_platform_storage/media_platform_storage.dart';
import 'package:media_playback/media_playback.dart';

const fixtureRoot = AuthorizedLibraryRoot(
  locator: LibraryRootLocator(
    storageKind: StorageKind.androidSaf,
    opaqueValue: 'content://redacted/tree/root',
  ),
  displayName: 'Test movies',
);

final videoEntry = _entry('Movie.mp4', 'video', mimeType: 'video/mp4');
final mkvEntry = _entry('Second.mkv', 'mkv', mimeType: 'video/x-matroska');
final subtitleEntry = _entry(
  'Movie.en.srt',
  'subtitle',
  mimeType: 'application/x-subrip',
);
final appleDoubleEntry = _entry(
  '._Hidden.mp4',
  'apple-double',
  mimeType: 'application/octet-stream',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('fake library scans probes plays seeks and releases', (
    tester,
  ) async {
    final harness = _RiskSpikeTestHarness.withFixtureEntries([
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
    expect(find.text('Second.mkv'), findsOneWidget);
    await tester.tap(find.text('Movie.mp4').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('probe-button')));
    await tester.pumpAndSettle();
    expect(find.text('video/avc'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('play-button')));
    await tester.tap(find.byKey(const Key('play-button')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('forward-10-button')));
    await tester.tap(find.byKey(const Key('forward-10-button')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('close-player-button')));
    await tester.tap(find.byKey(const Key('close-player-button')));
    await tester.pumpAndSettle();

    expect(harness.playback.lastSeek, const Duration(seconds: 10));
    expect(harness.playback.subtitleAttachCount, 1);
    expect(harness.playback.subtitleLanguageTag, 'en');
    expect(harness.storage.releaseCounts['direct-1'], 1);
  });
}

final class _RiskSpikeTestHarness {
  _RiskSpikeTestHarness._({
    required this.storage,
    required this.playback,
    required this.app,
  });

  factory _RiskSpikeTestHarness.withFixtureEntries(
    List<StorageEntrySnapshot> entries,
  ) {
    final storage = _HarnessStorage(entries);
    final playback = _HarnessPlayback(storage);
    final controller = RiskSpikeController(
      storage: storage,
      probe: _HarnessProbe(),
      playback: playback,
    );
    return _RiskSpikeTestHarness._(
      storage: storage,
      playback: playback,
      app: LocalMediaHubApp(controller: controller, initializeOnStart: false),
    );
  }

  final _HarnessStorage storage;
  final _HarnessPlayback playback;
  final Widget app;
}

final class _HarnessStorage implements LibraryStorageGateway {
  _HarnessStorage(this.entries);

  final List<StorageEntrySnapshot> entries;
  final Map<String, int> releaseCounts = <String, int>{};

  @override
  Future<AppResult<AuthorizedLibraryRoot>> chooseRoot() async =>
      const Success<AuthorizedLibraryRoot>(fixtureRoot);

  @override
  Stream<StorageScanEvent> enumerateRecursively({
    required LibraryRootLocator root,
    required String scanId,
    required CancellationToken cancellationToken,
  }) async* {
    yield StorageScanStarted(scanId);
    yield StorageScanBatch(scanId, entries);
    yield StorageScanCompleted(scanId);
  }

  @override
  Future<AppResult<MediaSourceLease>> openPlaybackSource({
    required LibraryRootLocator root,
    required String storageKey,
    required PlaybackSourceStrategy strategy,
  }) async => const Success<MediaSourceLease>(
    MediaSourceLease(
      leaseId: 'direct-1',
      sourceUri: 'content://redacted/document/video',
      strategy: PlaybackSourceStrategy.directContentUri,
    ),
  );

  @override
  Future<AppResult<SmallFileContent>> readSmallFile({
    required LibraryRootLocator root,
    required String storageKey,
    required int maximumBytes,
  }) async => Success<SmallFileContent>(
    SmallFileContent(
      Uint8List.fromList('1\n00:00:00,000 --> 00:00:01,000\nHello\n'.codeUnits),
    ),
  );

  @override
  Future<void> releasePlaybackSource(MediaSourceLease lease) async {
    releaseCounts.update(
      lease.leaseId,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
  }

  Never _unexpected(String call) => throw StateError('Unexpected call: $call');

  @override
  Future<AppResult<RootAccessState>> checkAccess(LibraryRootLocator root) =>
      _unexpected('checkAccess');

  @override
  Future<AppResult<List<AuthorizedLibraryRoot>>> listPersistedRoots() =>
      _unexpected('listPersistedRoots');

  @override
  Future<AppResult<void>> releaseRootPermission(LibraryRootLocator root) =>
      _unexpected('releaseRootPermission');
}

final class _HarnessProbe implements MediaProbe {
  @override
  Future<AppResult<MediaProbeResult>> probe({
    required LibraryRootLocator root,
    required String storageKey,
    required CancellationToken cancellationToken,
  }) async => const Success<MediaProbeResult>(
    MediaProbeResult(
      duration: Duration(minutes: 2),
      containerFormat: 'MPEG-4',
      width: 1920,
      height: 1080,
      videoCodec: 'video/avc',
      audioCodecSummary: 'audio/aac · stereo',
      streamCount: 2,
    ),
  );
}

final class _HarnessPlayback implements PlaybackSession {
  _HarnessPlayback(this.storage);

  final _HarnessStorage storage;
  PlaybackSnapshot _snapshot = const PlaybackSnapshot.closed();
  MediaSourceLease? _lease;
  Duration? lastSeek;
  int subtitleAttachCount = 0;
  String? subtitleLanguageTag;

  @override
  PlaybackSnapshot get snapshot => _snapshot;

  @override
  Future<AppResult<void>> attachLease(MediaSourceLease lease) async {
    _lease = lease;
    _snapshot = const PlaybackSnapshot(
      isOpen: true,
      isPlaying: true,
      duration: Duration(minutes: 2),
    );
    return const Success<void>(null);
  }

  @override
  Future<AppResult<void>> attachSubtitle(
    Uint8List bytes, {
    String? languageTag,
  }) async {
    subtitleAttachCount++;
    subtitleLanguageTag = languageTag;
    return const Success<void>(null);
  }

  @override
  Future<AppResult<void>> pause() async {
    _snapshot = _snapshot.copyWith(isPlaying: false);
    return const Success<void>(null);
  }

  @override
  Future<AppResult<void>> play() async {
    _snapshot = _snapshot.copyWith(isPlaying: true);
    return const Success<void>(null);
  }

  @override
  Future<AppResult<void>> seek(Duration position) async {
    lastSeek = position;
    _snapshot = _snapshot.copyWith(position: position);
    return const Success<void>(null);
  }

  @override
  Future<void> handleLifecycleInactive() => stop();

  @override
  Future<void> stop() async {
    final lease = _lease;
    _lease = null;
    _snapshot = const PlaybackSnapshot.closed();
    if (lease != null) {
      await storage.releasePlaybackSource(lease);
    }
  }
}

StorageEntrySnapshot _entry(
  String displayName,
  String id, {
  required String mimeType,
}) => StorageEntrySnapshot(
  storageKey: 'provider|$id',
  parentStorageKey: 'provider|folder',
  relativePath: displayName,
  displayName: displayName,
  isDirectory: false,
  mimeType: mimeType,
  sizeBytes: 1024,
  modifiedAtUtc: DateTime.utc(2026),
  flags: const {StorageEntryFlag.supportsRead},
);
