import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_domain/media_domain.dart';
import 'package:media_platform_storage/media_platform_storage.dart';
import 'package:media_playback/media_playback.dart';
import 'package:pocket_cinema/features/catalog/catalog_discovery_worker.dart';
import 'package:pocket_cinema/features/catalog/catalog_library.dart';
import 'package:pocket_cinema/features/catalog/catalog_matching.dart';
import 'package:pocket_cinema/features/catalog/catalog_metadata.dart';
import 'package:pocket_cinema/features/risk_spike/playback_session_coordinator.dart';
import 'package:pocket_cinema/features/risk_spike/risk_spike_controller.dart';
import 'package:pocket_cinema/features/risk_spike/risk_spike_state.dart';

import 'catalog_library_test.dart' as files;

const root = AuthorizedLibraryRoot(
  locator: LibraryRootLocator(
    storageKind: StorageKind.androidSaf,
    opaqueValue: 'root',
  ),
  displayName: 'Root',
);
const otherRoot = AuthorizedLibraryRoot(
  locator: LibraryRootLocator(
    storageKind: StorageKind.androidSaf,
    opaqueValue: 'other',
  ),
  displayName: 'Other root',
);

class _Storage implements LibraryStorageGateway {
  @override
  Future<AppResult<AuthorizedLibraryRoot>> chooseRoot() async =>
      const Success(otherRoot);
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected storage call: ${invocation.memberName}');
}

class _Probe implements MediaProbe {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected probe call: ${invocation.memberName}');
}

class _Playback implements PlaybackSession {
  @override
  PlaybackSnapshot get snapshot => const PlaybackSnapshot.closed();
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected playback call: ${invocation.memberName}');
}

class _PendingWorker {
  final requests = <CatalogDiscoveryRequest>[];
  final completions = <Completer<CatalogDiscoveryResult>>[];

  Future<CatalogDiscoveryResult> call(CatalogDiscoveryRequest request) {
    requests.add(request);
    final completion = Completer<CatalogDiscoveryResult>();
    completions.add(completion);
    return completion.future;
  }

  void complete(int index) {
    final request = requests[index];
    final local = request.entries == null
        ? request.localTitles
        : groupCatalog(request.entries!, previousTitles: request.localTitles);
    completions[index].complete(
      CatalogDiscoveryResult(
        localTitles: local,
        titles: request.matching.apply(local, request.scope),
        workerIsolateName: 'controlled-test-worker',
      ),
    );
  }
}

Future<void> _tick() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(CatalogLibrary.channel, (call) async {
          if (call.method == 'loadPreferences') return '{}';
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(CatalogLibrary.channel, null);
  });

  CatalogLibrary library(
    List<StorageEntrySnapshot> entries,
    _PendingWorker worker,
  ) {
    final controller = RiskSpikeController(
      storage: _Storage(),
      probe: _Probe(),
      playback: _Playback(),
      initialState: RiskSpikeState(root: root, entries: entries),
    );
    final result = CatalogLibrary(controller, discoveryWorker: worker.call);
    addTearDown(() {
      result.dispose();
      controller.dispose();
    });
    return result;
  }

  test(
    'first discovery uses restored preferences and cached matches',
    () async {
      final restored = Completer<String>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(CatalogLibrary.channel, (call) async {
            if (call.method == 'loadPreferences') return restored.future;
            return null;
          });
      final worker = _PendingWorker();
      final catalog = library([
        files.file('My Show/Season 1/S01E01.mkv'),
      ], worker);
      expect(catalog.isRestoringPreferences, isTrue);
      await _tick();
      expect(worker.requests, isEmpty);
      expect(catalog.currentTitles, isEmpty);

      restored.complete(
        jsonEncode({
          'homeView': 'cards',
          'saved': ['series:my show'],
          'positions': {'video': 42},
          'titleMatches': {
            '["root","series:my show"]': const CatalogResolvedMatch(
              CatalogMetadataCandidate(providerId: '42', name: 'Cached Show'),
              [],
            ).toJson(),
          },
        }),
      );
      await catalog.load();
      await _tick();
      expect(catalog.isRestoringPreferences, isFalse);
      expect(catalog.homeView, CatalogHomeView.cards);
      expect(catalog.saved, {'series:my show'});
      expect(catalog.positions, {'video': 42});
      expect(worker.requests, hasLength(1));
      expect(worker.requests.single.matching.matches, hasLength(1));
      worker.complete(0);
      await catalog.waitForDiscovery();
      expect(catalog.currentTitles.single.name, 'Cached Show');
      expect(worker.requests, hasLength(1));
    },
  );

  test(
    'optional credential loading does not hold the first presentation',
    () async {
      final tokenRequested = Completer<void>();
      final token = Completer<String?>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(CatalogLibrary.channel, (call) async {
            if (call.method == 'loadPreferences') return '{}';
            if (call.method == 'loadMetadataToken') {
              tokenRequested.complete();
              return token.future;
            }
            return null;
          });
      final worker = _PendingWorker();
      final catalog = library([files.file('Movie.mkv')], worker);
      await tokenRequested.future;
      await _tick();
      expect(catalog.isRestoringPreferences, isFalse);
      expect(worker.requests, hasLength(1));
      worker.complete(0);
      await catalog.waitForDiscovery();
      expect(catalog.currentTitles.single.name, 'Movie');
      token.complete(null);
      await catalog.load();
    },
  );

  test('parsing and canonical grouping run on a separate isolate', () async {
    final entries = [
      files.file('My Show/Season 1/S01E02.mkv'),
      files.file('My Show/Season 1/S01E01.mkv'),
      files.file('Alias/Season 2/S02E01.mkv'),
    ];
    const candidate = CatalogMetadataCandidate(
      providerId: '42',
      name: 'Canonical Show',
    );
    final request = CatalogDiscoveryRequest(
      scope: 'root',
      entries: entries,
      localTitles: const [],
      matching: const CatalogMatchingSnapshot(
        matches: {
          '["root","series:my show"]': CatalogResolvedMatch(candidate, [
            CatalogEpisodeMetadata(season: 1, number: 1, name: 'Start'),
            CatalogEpisodeMetadata(season: 1, number: 2, name: 'Return'),
          ]),
          '["root","series:alias"]': CatalogResolvedMatch(candidate, [
            CatalogEpisodeMetadata(season: 2, number: 1, name: 'Next Season'),
          ]),
        },
      ),
    );
    final result = await discoverCatalogInBackground(request);
    expect(result.workerIsolateName, 'catalog-discovery');
    expect(result.workerIsolateName, isNot(Isolate.current.debugName));
    expect(result.localTitles, hasLength(2));
    expect(result.titles, hasLength(1));
    expect(result.titles.single.localIds, hasLength(2));
    expect(result.titles.single.seasons, [1, 2]);
    expect(result.titles.single.videos.map((video) => video.title), [
      'Start',
      'Return',
      'Next Season',
    ]);
    expect(
      result.titles.single.videos.map((video) => video.id),
      unorderedEquals(entries.map((entry) => entry.storageKey)),
    );
  });

  test(
    'empty libraries skip worker startup and reject late nonempty results',
    () async {
      final worker = _PendingWorker();
      final catalog = library(const [], worker);
      await catalog.load();
      await catalog.waitForDiscovery();
      expect(worker.requests, isEmpty);
      expect(catalog.currentTitles, isEmpty);
      expect(catalog.isDiscovering, isFalse);
      catalog.titlesFor([files.file('Movie.mkv')]);
      await _tick();
      expect(worker.requests, hasLength(1));
      catalog.titlesFor(const []);
      worker.complete(0);
      await catalog.waitForDiscovery();
      expect(worker.requests, hasLength(1));
      expect(catalog.currentTitles, isEmpty);
      expect(catalog.localTitles, isEmpty);
      expect(catalog.isDiscovering, isFalse);
      expect(catalog.discoveryError, isNull);
    },
  );

  test(
    'titlesFor returns immediately and coalesces newer scan batches',
    () async {
      final first = [files.file('First.mkv')];
      final latest = [...first, files.file('Latest.mkv')];
      final worker = _PendingWorker();
      final catalog = library(first, worker);
      await catalog.load();
      await _tick();
      expect(worker.requests, hasLength(1));
      expect(catalog.titlesFor(first), isEmpty);
      expect(catalog.isDiscovering, isTrue);
      for (var batch = 0; batch < 20; batch++) {
        catalog.titlesFor([files.file('Intermediate $batch.mkv')]);
      }
      catalog.titlesFor(latest);
      worker.complete(0);
      await _tick();
      expect(catalog.currentTitles, isEmpty);
      expect(worker.requests, hasLength(2));
      expect(worker.requests.last.entries, same(latest));
      worker.complete(1);
      await catalog.waitForDiscovery();
      expect(catalog.currentTitles.map((title) => title.name), [
        'First',
        'Latest',
      ]);
      expect(catalog.isDiscovering, isFalse);
      final cached = catalog.currentTitles;
      expect(catalog.titlesFor(latest), same(cached));
      await _tick();
      expect(worker.requests, hasLength(2));
    },
  );

  test(
    'a root change rejects a pending discovery and clears old titles',
    () async {
      final worker = _PendingWorker();
      final catalog = library([files.file('Old Root.mkv')], worker);
      await catalog.load();
      await _tick();
      await catalog.controller.chooseRoot();
      final latest = [files.file('New Root.mkv')];
      catalog.titlesFor(latest);
      worker.complete(0);
      await _tick();
      expect(catalog.catalogScope, 'other');
      expect(catalog.currentTitles, isEmpty);
      expect(worker.requests.last.localTitles, isEmpty);
      expect(worker.requests.last.scope, 'other');
      worker.complete(1);
      await catalog.waitForDiscovery();
      expect(catalog.currentTitles.single.name, 'New Root');
    },
  );

  test(
    'a metadata change reuses parsed titles and rejects old presentation',
    () async {
      final entries = [files.file('Show/Season 1/S01E01.mkv')];
      final worker = _PendingWorker();
      final catalog = library(entries, worker);
      await catalog.load();
      await _tick();
      const candidate = CatalogMetadataCandidate(
        providerId: '42',
        name: 'Correct',
      );
      await catalog.matcher.select(
        groupCatalog(entries).single,
        'root',
        candidate,
      );
      worker.complete(0);
      await _tick();
      expect(catalog.currentTitles, isEmpty);
      expect(worker.requests, hasLength(2));
      expect(worker.requests.last.entries, isNull);
      expect(worker.requests.last.localTitles, hasLength(1));
      worker.complete(1);
      await catalog.waitForDiscovery();
      expect(catalog.currentTitles.single.name, 'Correct');
      expect(catalog.currentTitles.single.providerId, '42');
    },
  );

  test(
    'an older worker failure cannot replace the latest catalog state',
    () async {
      final worker = _PendingWorker();
      final catalog = library([files.file('Old.mkv')], worker);
      await catalog.load();
      await _tick();
      catalog.titlesFor([files.file('New.mkv')]);
      worker.completions.first.completeError(StateError('Old scan failed'));
      await _tick();
      expect(catalog.discoveryError, isNull);
      worker.complete(1);
      await catalog.waitForDiscovery();
      expect(catalog.currentTitles.single.name, 'New');
    },
  );

  test(
    'worker failures expose a retryable error and leave the UI responsive',
    () async {
      final worker = _PendingWorker();
      final catalog = library([files.file('Movie.mkv')], worker);
      await catalog.load();
      await _tick();
      expect(worker.requests, hasLength(1));
      worker.completions.last.completeError(StateError('Worker unavailable'));
      await catalog.waitForDiscovery();
      expect(catalog.isDiscovering, isFalse);
      expect(catalog.discoveryError, contains('Try scanning'));
      catalog.retryDiscovery();
      expect(catalog.discoveryError, isNull);
      await _tick();
      worker.complete(worker.requests.length - 1);
      await catalog.waitForDiscovery();
      expect(catalog.currentTitles.single.name, 'Movie');
    },
  );

  test(
    'disposing completes waiters and ignores a late worker result',
    () async {
      final worker = _PendingWorker();
      final controller = RiskSpikeController(
        storage: _Storage(),
        probe: _Probe(),
        playback: _Playback(),
        initialState: RiskSpikeState(
          root: root,
          entries: [files.file('Movie.mkv')],
        ),
      );
      final catalog = CatalogLibrary(controller, discoveryWorker: worker.call);
      await catalog.load();
      await _tick();
      var notifications = 0;
      catalog.addListener(() => notifications++);
      final pending = catalog.waitForDiscovery();
      catalog.dispose();
      await pending;
      worker.complete(0);
      await _tick();
      controller.selectFile(files.file('Another.mkv'));
      expect(notifications, 0);
      expect(catalog.currentTitles, isEmpty);
      controller.dispose();
    },
  );

  test(
    'incremental grouping retains parsing after isolate snapshot copies',
    () {
      final first = files.file('My Show/Season 1/S01E01.mkv');
      final previous = groupCatalog([first]);
      final updated = groupCatalog([
        files.file('My Show/Season 1/S01E01.mkv'),
        files.file('My Show/Season 2/S02E01.mkv'),
      ], previousTitles: previous);
      expect(updated.single.first.parsed, same(previous.single.first.parsed));
      expect(updated.single.seasons, [1, 2]);
    },
  );
}
