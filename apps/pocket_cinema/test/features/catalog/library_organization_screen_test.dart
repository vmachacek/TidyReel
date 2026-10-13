import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_domain/media_domain.dart';
import 'package:media_platform_storage/media_platform_storage.dart';
import 'package:pocket_cinema/app/app_theme.dart';
import 'package:pocket_cinema/features/catalog/catalog_discovery_worker.dart';
import 'package:pocket_cinema/features/catalog/catalog_library.dart';
import 'package:pocket_cinema/features/catalog/catalog_matching.dart';
import 'package:pocket_cinema/features/catalog/catalog_metadata.dart';
import 'package:pocket_cinema/features/catalog/library_organization_screen.dart';
import 'package:pocket_cinema/features/catalog/library_organizer.dart';
import 'package:pocket_cinema/features/risk_spike/risk_spike_controller.dart';
import 'package:pocket_cinema/features/risk_spike/risk_spike_state.dart';
import 'package:pocket_cinema/features/risk_spike/scan_inventory_store.dart';
import 'package:pocket_cinema/features/risk_spike/scan_inventory_worker.dart';

import '../risk_spike/risk_spike_controller_test.dart' as support;

const _root = AuthorizedLibraryRoot(
  locator: LibraryRootLocator(
    storageKind: StorageKind.androidSaf,
    opaqueValue: 'content://provider/tree/media',
  ),
  displayName: 'Tablet media',
);
const _film = CatalogMetadataCandidate(
  providerId: '8',
  name: 'My Film',
  year: 2020,
);
const _anotherFilm = CatalogMetadataCandidate(
  providerId: '9',
  name: 'Another Film',
  year: 2019,
);
const _applyButton = Key('apply-library-organization');

StorageEntrySnapshot _file(
  String key,
  String path, {
  String parent = 'downloads',
}) => StorageEntrySnapshot(
  storageKey: key,
  parentStorageKey: parent,
  relativePath: path,
  displayName: path.split('/').last,
  isDirectory: false,
  mimeType: path.endsWith('.srt') ? 'application/x-subrip' : 'video/mp4',
  sizeBytes: 4096,
  modifiedAtUtc: DateTime.utc(2026, 10, 12),
  flags: const {StorageEntryFlag.supportsRead},
);

final _movie = _file('old:movie', 'Downloads/My.Film.2020.1080p.YIFY.mp4');
final _subtitle = _file(
  'old:subtitle',
  'Downloads/My.Film.2020.1080p.YIFY.en.srt',
);
final _unknown = _file('review', 'Downloads/Unknown.2021.1080p.mkv');
final _organized = _file(
  'organized',
  'Movies/Another Film (2019)/Another Film (2019).mkv',
  parent: 'another-film',
);

class _MemoryInventory implements ScanInventoryStore {
  ScanInventory? value;
  @override
  Future<ScanInventory?> load() async => value;
  @override
  Future<void> save(ScanInventory inventory) async => value = inventory;
  @override
  Future<void> clear() async => value = null;
}

class _Fixture {
  _Fixture({List<StorageEntrySnapshot>? entries, bool scanCompleted = true})
    : currentEntries = entries ?? [_movie, _subtitle, _unknown, _organized] {
    storage = support.FakeStorageGateway(
      onEnumerate: (id, token) {
        final override = id.startsWith('organize-preview-')
            ? previewScan
            : refreshScan;
        return override?.call(id, token) ?? _scan(id);
      },
      onChoose: () async {
        chooseCount++;
        return const Success(_root);
      },
      releaseRootSucceeds: true,
    );
    playback = support.FakePlaybackSession(allowStop: true);
    controller = RiskSpikeController(
      storage: storage,
      probe: support.FakeMediaProbe(),
      playback: playback,
      inventoryStore: inventory,
      inventoryWorker: (work) async => classifyScanInventory(work),
      initialState: RiskSpikeState(
        root: _root,
        phase: RiskSpikePhase.filesAvailable,
        entries: currentEntries
            .where((entry) => !entry.displayName.endsWith('.srt'))
            .toList(),
        scanCompleted: scanCompleted,
        videoCount: currentEntries
            .where((entry) => !entry.displayName.endsWith('.srt'))
            .length,
        lastScanCompletedAt: DateTime.utc(2026, 10, 12),
      ),
    );
    library = CatalogLibrary(
      controller,
      discoveryWorker: (request) async {
        final titles = request.entries == null
            ? request.localTitles
            : groupCatalog(
                request.entries!,
                previousTitles: request.localTitles,
              );
        return CatalogDiscoveryResult(
          localTitles: titles,
          titles: request.matching.apply(titles, request.scope),
          workerIsolateName: null,
        );
      },
    );
  }

  List<StorageEntrySnapshot> currentEntries;
  late final support.FakeStorageGateway storage;
  late final support.FakePlaybackSession playback;
  late final RiskSpikeController controller;
  late final CatalogLibrary library;
  final inventory = _MemoryInventory();
  Stream<StorageScanEvent> Function(String, CancellationToken)? previewScan,
      refreshScan;
  int chooseCount = 0;

  Stream<StorageScanEvent> _scan(String id) async* {
    // Every scan reads the current provider IDs, including post-move IDs.
    yield StorageScanBatch(id, List.of(currentEntries));
    yield StorageScanCompleted(id);
  }

  Future<void> initialize({bool verified = true}) async {
    await library.load();
    if (verified) {
      library.matcher.matches[jsonEncode([
        _root.locator.opaqueValue,
        _movie.storageKey,
      ])] = const CatalogResolvedMatch(
        _film,
        [],
        manual: true,
      );
      library.matcher.matches[jsonEncode([
        _root.locator.opaqueValue,
        _organized.storageKey,
      ])] = const CatalogResolvedMatch(
        _anotherFilm,
        [],
      );
      library.retryDiscovery();
    }
    await library.waitForDiscovery();
  }

  void dispose() {
    library.dispose();
    controller.dispose();
  }
}

class _NativeOrganizer {
  bool writeAccess = true, failMoves = false, restoreWithChangedIds = false;
  final calls = <MethodCall>[];
  List<Map<Object?, Object?>> submitted = [];
  Completer<void>? applyGate;
  _Fixture? fixture;

  Future<Object?> handle(MethodCall call) async {
    calls.add(call);
    if (call.method == 'checkWriteAccess') return writeAccess;
    if (call.method != 'organizeFiles') {
      throw StateError('Unexpected method ${call.method}');
    }
    submitted = ((call.arguments as Map)['items'] as List)
        .map((item) => Map<Object?, Object?>.from(item as Map))
        .toList();
    await applyGate?.future;
    final replacements = <String, StorageEntrySnapshot>{};
    final results = [
      for (final item in submitted)
        <String, Object?>{
          'storageKey': item['storageKey'],
          'destinationRelativePath': item['destinationRelativePath'],
          'status': failMoves ? 'failed' : 'moved',
          if (failMoves) 'message': 'A file with this name already exists in the destination. Review the files and try again.',
          if (!failMoves || restoreWithChangedIds)
            'newStorageKey':
                '${failMoves ? 'restored' : 'new'}:${item['storageKey']}',
          if (!failMoves || restoreWithChangedIds)
            'newParentStorageKey': failMoves
                ? item['parentStorageKey']
                : 'new:movie-folder',
          if (restoreWithChangedIds)
            'actualRelativePath': item['sourceRelativePath'],
        },
    ];
    if (!failMoves || restoreWithChangedIds) {
      for (final item in submitted) {
        final key = item['storageKey'] as String;
        replacements[key] = _file(
          '${failMoves ? 'restored' : 'new'}:$key',
          item[failMoves ? 'sourceRelativePath' : 'destinationRelativePath']
              as String,
          parent: failMoves
              ? item['parentStorageKey'] as String
              : 'new:movie-folder',
        );
      }
      final current = fixture;
      if (current != null) {
        current.currentEntries = [
          for (final entry in current.currentEntries)
            replacements[entry.storageKey] ?? entry,
        ];
      }
    }
    return {'items': results};
  }

  int get applyCount =>
      calls.where((call) => call.method == 'organizeFiles').length;
}

Future<void> _open(
  WidgetTester tester,
  _Fixture fixture, {
  Size size = const Size(800, 800),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Builder(
        builder: (context) => Scaffold(
          body: FilledButton(
            key: const Key('open-organizer'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    LibraryOrganizationScreen(library: fixture.library),
              ),
            ),
            child: const Text('Open organizer'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open-organizer')));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _NativeOrganizer native;
  String preferences = '{}';

  setUp(() {
    preferences = '{}';
    native = _NativeOrganizer();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(LibraryOrganizer.channel, native.handle);
    messenger.setMockMethodCallHandler(CatalogLibrary.channel, (call) async {
      if (call.method == 'loadPreferences') return preferences;
      if (call.method == 'savePreferences') {
        preferences = (call.arguments as Map)['value'] as String;
      }
      return null;
    });
  });
  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(LibraryOrganizer.channel, null);
    messenger.setMockMethodCallHandler(CatalogLibrary.channel, null);
  });

  Future<_Fixture> fixture({
    bool verified = true,
    bool scanCompleted = true,
  }) async {
    final value = _Fixture(scanCompleted: scanCompleted);
    addTearDown(value.dispose);
    native.fixture = value;
    await value.initialize(verified: verified);
    return value;
  }

  testWidgets('preview scans fresh SAF entries and never mutates files', (
    tester,
  ) async {
    final value = await fixture();
    final fresh = _file('fresh', 'Downloads/Fresh.Unknown.2022.mkv');
    value.currentEntries.add(fresh);
    await _open(tester, value, size: const Size(320, 480));
    expect(value.storage.scanCount, 1);
    expect(native.applyCount, 0);
    expect(native.calls.single.arguments, {
      'treeUri': _root.locator.opaqueValue,
    });
    expect(
      find.text('2 to move · 1 already organized · 2 need review'),
      findsOneWidget,
    );
    expect(value.controller.libraryOrganizationActive, isTrue);
    expect(
      tester.widget<FilledButton>(find.byKey(_applyButton)).onPressed,
      isNotNull,
    );
    await tester.scrollUntilVisible(
      find.text(fresh.relativePath),
      160,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text(fresh.relativePath).hitTestable(), findsOneWidget);
    expect(native.applyCount, 0);
    expect(tester.takeException(), isNull);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(value.controller.libraryOrganizationActive, isFalse);
    expect(native.applyCount, 0);
  });

  testWidgets(
    'apply only ready video and subtitle, rescans new IDs and persists user state',
    (tester) async {
      final value = await fixture();
      value.library.positions[_movie.storageKey] = 120;
      value.library.durations[_movie.storageKey] = 600;
      value.library.saved.add(_movie.storageKey);
      await _open(tester, value);
      await tester.tap(find.byKey(_applyButton));
      await tester.pumpAndSettle();
      expect(native.applyCount, 1);
      expect(native.submitted.map((item) => item['storageKey']), [
        _movie.storageKey,
        _subtitle.storageKey,
      ]);
      expect(value.playback.stopCount, 1);
      expect(value.storage.scanCount, 2);
      expect(find.text('2 moved · 0 failed'), findsOneWidget);
      final newMovie = 'new:${_movie.storageKey}';
      expect(
        value.controller.state.entries.map((entry) => entry.storageKey),
        containsAll([newMovie, _unknown.storageKey, _organized.storageKey]),
      );
      expect(
        value.controller.state.entries.map((entry) => entry.storageKey),
        isNot(contains(_movie.storageKey)),
      );
      expect(
        value.inventory.value?.subtitles.single.storageKey,
        'new:${_subtitle.storageKey}',
      );
      expect(value.library.positions[newMovie], 120);
      expect(value.library.durations[newMovie], 600);
      expect(value.library.positions, isNot(contains(_movie.storageKey)));
      expect(value.library.saved, contains(newMovie));
      final local = value.library.localTitles.singleWhere(
        (title) => title.id == newMovie,
      );
      final match = value
          .library
          .matcher
          .matches[value.library.matcher.key(_root.locator.opaqueValue, local)];
      expect(match?.manual, isTrue);
      expect(match?.candidate.providerId, '8');
      expect(
        value.library.isSaved(
          value.library.currentTitles.singleWhere(
            (title) => title.providerId == '8',
          ),
        ),
        isTrue,
      );
      expect(value.library.progress(local.first), .2);
      final persisted = jsonDecode(preferences) as Map;
      expect((persisted['positions'] as Map)[newMovie], 120);
      expect(persisted['saved'], contains(newMovie));
      expect(
        (persisted['titleMatches'] as Map)[jsonEncode([
          _root.locator.opaqueValue,
          newMovie,
        ])]['manual'],
        isTrue,
      );
      expect(
        value.inventory.value?.videos.map((entry) => entry.storageKey),
        contains(newMovie),
      );
      expect(value.controller.libraryOrganizationActive, isTrue);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(value.controller.libraryOrganizationActive, isFalse);

      final restored = _Fixture(entries: value.currentEntries);
      addTearDown(restored.dispose);
      await restored.initialize(verified: false);
      final restoredMovie = restored.library.localTitles.singleWhere(
        (title) => title.id == newMovie,
      );
      expect(restored.library.progress(restoredMovie.first), .2);
      expect(
        restored
            .library
            .matcher
            .matches[restored.library.matcher.key(
              _root.locator.opaqueValue,
              restoredMovie,
            )]
            ?.manual,
        isTrue,
      );
      expect(
        restored.library.isSaved(
          restored.library.currentTitles.singleWhere(
            (title) => title.providerId == '8',
          ),
        ),
        isTrue,
      );
    },
  );

  testWidgets(
    'read-only grant blocks apply and folder repair instructions scroll on 320x480',
    (tester) async {
      final value = await fixture();
      native.writeAccess = false;
      await _open(tester, value, size: const Size(320, 480));
      expect(find.textContaining('read access only'), findsOneWidget);
      expect(find.textContaining('Change media folder'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byKey(_applyButton)).onPressed,
        isNull,
      );
      await tester.tap(find.byKey(_applyButton));
      await tester.pumpAndSettle();
      expect(native.applyCount, 0);
      await tester.scrollUntilVisible(
        find.textContaining('For missing metadata'),
        120,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('For missing metadata').hitTestable(),
        findsOneWidget,
      );
      expect(find.byKey(_applyButton).hitTestable(), findsOneWidget);
      expect(find.byType(BackButton).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final terminal in ['incomplete', 'warning', 'failure']) {
    testWidgets('$terminal preview cannot apply any move', (tester) async {
      final value = await fixture();
      value.previewScan = (id, token) async* {
        yield StorageScanBatch(id, [_movie]);
        if (terminal == 'warning') {
          yield StorageScanWarning(id, RiskSpikeController.scanFailed);
          yield StorageScanCompleted(id);
        } else if (terminal == 'failure') {
          yield StorageScanFailed(id, RiskSpikeController.scanFailed);
        }
      };
      await _open(tester, value, size: const Size(320, 480));
      expect(find.byKey(const Key('organization-error')), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byKey(_applyButton)).onPressed,
        isNull,
      );
      expect(native.applyCount, 0);
      expect(value.controller.state.entries, contains(_movie));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'move failures stay reviewable on a small screen and rescan untouched IDs',
    (tester) async {
      final value = await fixture();
      native.failMoves = true;
      await _open(tester, value, size: const Size(320, 480));
      await tester.tap(find.byKey(_applyButton));
      await tester.pumpAndSettle();
      expect(find.text('0 moved · 2 failed'), findsOneWidget);
      expect(
        value.controller.state.entries.map((entry) => entry.storageKey),
        contains(_movie.storageKey),
      );
      await tester.scrollUntilVisible(
        find.textContaining('A file with this name').first,
        120,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('A file with this name').first.hitTestable(),
        findsOneWidget,
      );
      expect(find.text('Done').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'apply holds the route and blocks folder changes and external refreshes',
    (tester) async {
      final value = await fixture();
      native.applyGate = Completer<void>();
      await _open(tester, value);
      await tester.tap(find.byKey(_applyButton));
      await tester.pump();
      expect(native.applyCount, 1);
      expect(find.text('Renaming and moving…'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byKey(_applyButton)).onPressed,
        isNull,
      );
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.tap(find.byType(BackButton));
      await tester.pump();
      expect(find.byType(LibraryOrganizationScreen), findsOneWidget);
      await value.controller.chooseRoot();
      await value.controller.releaseRoot();
      await value.controller.scan(_root);
      await value.controller.refreshInBackground();
      expect(value.chooseCount, 0);
      expect(value.controller.state.root, _root);
      expect(value.storage.scanCount, 1);
      expect(value.controller.libraryOrganizationActive, isTrue);
      native.applyGate!.complete();
      await tester.pumpAndSettle();
      expect(value.storage.scanCount, 2);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(value.controller.libraryOrganizationActive, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed move with changed rollback ID keeps progress even when rescan fails',
    (tester) async {
      final value = await fixture();
      native.failMoves = true;
      native.restoreWithChangedIds = true;
      value.library.positions[_movie.storageKey] = 90;
      value.library.durations[_movie.storageKey] = 600;
      value.library.saved.add(_movie.storageKey);
      value.refreshScan = (id, token) async* {
        yield StorageScanFailed(id, RiskSpikeController.scanFailed);
      };
      await _open(tester, value, size: const Size(320, 480));
      await tester.tap(find.byKey(_applyButton));
      await tester.pumpAndSettle();
      final restoredId = 'restored:${_movie.storageKey}';
      final restored = value.controller.state.entries.singleWhere(
        (entry) => entry.storageKey == restoredId,
      );
      expect(restored.relativePath, _movie.relativePath);
      expect(restored.parentStorageKey, _movie.parentStorageKey);
      expect(
        value.controller.state.entries.map((entry) => entry.storageKey),
        isNot(contains(_movie.storageKey)),
      );
      expect(value.library.positions[restoredId], 90);
      expect(value.library.durations[restoredId], 600);
      expect(value.library.saved, contains(restoredId));
      expect(
        value
            .library
            .matcher
            .matches[jsonEncode([_root.locator.opaqueValue, restoredId])]
            ?.manual,
        isTrue,
      );
      expect(
        value.inventory.value?.videos.map((entry) => entry.storageKey),
        contains(restoredId),
      );
      expect(find.text('0 moved · 2 failed'), findsOneWidget);
      expect(find.textContaining('the library rescan failed'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('organization-error')),
        120,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('organization-error')).hitTestable(),
        findsOneWidget,
      );
      expect(find.text('Done').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'an unfinished library scan cannot acquire the organization lock',
    (tester) async {
      final value = await fixture(scanCompleted: false);
      await _open(tester, value);
      expect(find.textContaining('Wait for the library scan'), findsOneWidget);
      expect(value.controller.libraryOrganizationActive, isFalse);
      expect(value.storage.scanCount, 0);
      expect(native.calls, isEmpty);
      expect(
        tester.widget<FilledButton>(find.byKey(_applyButton)).onPressed,
        isNull,
      );
    },
  );

  test('same-provider series aliases keep both seasons and manual match after organization', () async {
    final seasonOne = _file('old:s1', 'Local Show/Season 1/S01E01.mkv');
    final seasonTwo = _file('old:s2', 'Alternate Show/Season 2/S02E01.mkv');
    final value = _Fixture(entries: [seasonOne, seasonTwo]);
    addTearDown(value.dispose);
    await value.initialize(verified: false);
    final previous = groupCatalog([seasonOne, seasonTwo]);
    expect(previous, hasLength(2));
    const candidate = CatalogMetadataCandidate(
      providerId: '42',
      name: 'Canonical Show',
      year: 1999,
    );
    final first = previous.singleWhere(
      (title) => title.first.id == seasonOne.storageKey,
    );
    final second = previous.singleWhere(
      (title) => title.first.id == seasonTwo.storageKey,
    );
    value.library.matcher.matches[value.library.matcher.key(
      _root.locator.opaqueValue,
      first,
    )] = const CatalogResolvedMatch(candidate, [
      CatalogEpisodeMetadata(season: 1, number: 1, name: 'Pilot'),
    ], manual: true);
    value.library.matcher.matches[value.library.matcher.key(
      _root.locator.opaqueValue,
      second,
    )] = const CatalogResolvedMatch(candidate, [
      CatalogEpisodeMetadata(season: 2, number: 1, name: 'Return'),
    ]);
    value.library.saved.add(first.id);
    value.library.positions[seasonOne.storageKey] = 180;
    value.library.durations[seasonOne.storageKey] = 600;
    final replacements = {
      seasonOne.storageKey: _file(
        'new:s1',
        'TV/Canonical Show (1999)/Season 01/S01E01 - Pilot.mkv',
        parent: 'season1',
      ),
      seasonTwo.storageKey: _file(
        'new:s2',
        'TV/Canonical Show (1999)/Season 02/S02E01 - Return.mkv',
        parent: 'season2',
      ),
    };
    final after = groupCatalog(replacements.values.toList());
    expect(after, hasLength(1));
    await value.library.migrateOrganizedFiles(
      scope: _root.locator.opaqueValue,
      previousTitles: previous,
      replacements: replacements,
    );
    final match =
        value.library.matcher.matches[value.library.matcher.key(
          _root.locator.opaqueValue,
          after.single,
        )];
    expect(match?.manual, isTrue);
    expect(
      match?.episodes.map((episode) => (episode.season, episode.number)),
      unorderedEquals([(1, 1), (2, 1)]),
    );
    expect(value.library.saved, contains(after.single.id));
    value.currentEntries = replacements.values.toList();
    expect(value.controller.beginLibraryOrganization(), isTrue);
    await value.controller.refreshAfterLibraryOrganization(_root, replacements);
    await value.library.waitForDiscovery();
    value.controller.endLibraryOrganization();
    expect(value.library.currentTitles, hasLength(1));
    final series = value.library.currentTitles.single;
    expect(series.seasons, [1, 2]);
    expect(series.videos.map((video) => video.title), ['Pilot', 'Return']);
    expect(value.library.isSaved(series), isTrue);
    expect(value.library.progress(series.first), .3);
    final persisted = jsonDecode(preferences) as Map;
    final savedMatch =
        (persisted['titleMatches'] as Map)[value.library.matcher.key(
              _root.locator.opaqueValue,
              after.single,
            )]
            as Map;
    expect(savedMatch['manual'], isTrue);
    expect(savedMatch['episodes'], hasLength(2));
  });
}
