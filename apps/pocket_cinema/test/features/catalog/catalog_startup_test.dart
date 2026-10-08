import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_domain/media_domain.dart';
import 'package:media_platform_storage/media_platform_storage.dart';
import 'package:pocket_cinema/app/app_theme.dart';
import 'package:pocket_cinema/features/catalog/catalog_library.dart';
import 'package:pocket_cinema/features/catalog/catalog_screen.dart';
import 'package:pocket_cinema/features/catalog/catalog_skeleton.dart';
import 'package:pocket_cinema/features/risk_spike/risk_spike_controller.dart';
import 'package:pocket_cinema/features/risk_spike/risk_spike_state.dart';
import 'package:pocket_cinema/features/risk_spike/scan_inventory_store.dart';
import 'package:pocket_cinema/l10n/app_localizations.dart';

import '../../support/catalog_discovery.dart';
import '../risk_spike/risk_spike_controller_test.dart' as controller_fixtures;
import '../risk_spike/risk_spike_screen_test.dart' as fixtures;
import 'catalog_library_test.dart' as files;
import 'catalog_screen_test.dart' as screens;

Finder get _loading => find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      widget.key == const Key('catalog-body') &&
      widget.properties.label == 'Loading your library',
);
const _status = Key('catalog-status-slot');
const _sort = Key('catalog-sort-controls');

Future<void> _surface(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Widget _app(
  RiskSpikeController controller, {
  TextScaler textScaler = TextScaler.noScaling,
}) => MaterialApp(
  theme: AppTheme.dark,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: textScaler),
    child: child!,
  ),
  home: CatalogScreen(controller: controller),
);

Future<void> _waitForLocalDiscovery(WidgetTester tester) async {
  final library = catalogLibrary(tester);
  await tester.runAsync(() async {
    await tester.pump();
    final elapsed = Stopwatch()..start();
    while (library.isRestoringPreferences || library.isDiscovering) {
      if (elapsed.elapsed > const Duration(seconds: 30)) {
        throw TestFailure('Local catalog discovery did not finish.');
      }
      await Future<void>.delayed(Duration.zero);
      await tester.pump();
    }
  });
  await tester.pump();
}

Future<Rect> _contentRect(WidgetTester tester, Finder finder) async {
  final scrollable = find
      .descendant(
        of: find.byKey(const Key('catalog-scroll')),
        matching: find.byType(Scrollable),
      )
      .first;
  final position = tester.state<ScrollableState>(scrollable).position;
  final originalOffset = position.pixels;
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(finder, 250, scrollable: scrollable);
    await tester.pump();
  }
  final rect = tester.getRect(finder).translate(0, position.pixels);
  position.jumpTo(originalOffset);
  await tester.pump();
  return rect;
}

RiskSpikeController _controller(
  _ControlledStorage storage, {
  RiskSpikeState initialState = const RiskSpikeState(),
  MediaProbe? probe,
}) => RiskSpikeController(
  storage: storage,
  probe: probe ?? controller_fixtures.FakeMediaProbe(),
  playback: controller_fixtures.FakePlaybackSession(),
  inventoryStore: _MemoryInventory(),
  initialState: initialState,
);

void main() {
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

  testWidgets('saved folder check never flashes folder onboarding', (
    tester,
  ) async {
    await _surface(tester, const Size(390, 844));
    final storage = _ControlledStorage();
    final controller = _controller(storage);
    addTearDown(controller.dispose);
    final initializing = controller.initialize();
    await tester.pumpWidget(_app(controller));
    await _waitForLocalDiscovery(tester);

    expect(_loading, findsOneWidget);
    expect(find.byKey(const Key('folder-onboarding')), findsNothing);
    expect(find.text('Connect media folder'), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Restoring your library…'), findsOneWidget);

    storage.roots.complete(const Success([]));
    await initializing;
    await tester.pumpAndSettle();

    expect(_loading, findsNothing);
    expect(find.byKey(const Key('folder-onboarding')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(390, 844), const Size(1200, 1000)]) {
    testWidgets('initial batches stay behind stable skeleton at $size', (
      tester,
    ) async {
      await _surface(tester, size);
      final storage = _ControlledStorage();
      final controller = _controller(storage);
      addTearDown(controller.dispose);
      final initializing = controller.initialize();
      await tester.pumpWidget(_app(controller));
      await _waitForLocalDiscovery(tester);
      final toolbar = tester.getRect(find.byKey(const Key('home-view-switch')));
      final appBar = tester.getRect(find.byType(AppBar));
      final navigation = size.width < 850
          ? tester.getRect(find.byType(NavigationBar))
          : null;
      final hero = tester.getRect(find.byType(CatalogHeroSkeleton));
      final status = tester.getRect(find.byKey(_status));
      final sort = await _contentRect(tester, find.byKey(_sort));

      storage.roots.complete(const Success([fixtures.testRoot]));
      await initializing;
      storage.batch([files.file('Movies/Alpha (2016).mp4')]);
      await _waitForLocalDiscovery(tester);

      expect(controller.state.entries, hasLength(1));
      expect(controller.state.scanCompleted, isFalse);
      expect(catalogLibrary(tester).currentTitles, hasLength(1));
      expect(_loading, findsOneWidget);
      expect(find.byType(JukeboxHero), findsNothing);
      expect(find.byType(PosterCard), findsNothing);
      expect(find.text('Alpha'), findsNothing);
      expect(find.byKey(const Key('folder-onboarding')), findsNothing);
      expect(tester.getRect(find.byType(CatalogHeroSkeleton)), hero);
      expect(tester.getRect(find.byKey(_status)), status);
      expect(await _contentRect(tester, find.byKey(_sort)), sort);
      expect(
        tester.getRect(find.byKey(const Key('home-view-switch'))),
        toolbar,
      );

      await storage.complete();
      await settleCatalog(tester);

      expect(_loading, findsNothing);
      expect(find.byType(CatalogHeroSkeleton), findsNothing);
      expect(find.byType(JukeboxHero), findsOneWidget);
      expect(tester.getRect(find.byType(JukeboxHero)), hero);
      expect(tester.getRect(find.byKey(_status)), status);
      expect(await _contentRect(tester, find.byKey(_sort)), sort);
      expect(tester.getRect(find.byType(AppBar)), appBar);
      expect(
        tester.getRect(find.byKey(const Key('home-view-switch'))),
        toolbar,
      );
      if (navigation != null) {
        expect(tester.getRect(find.byType(NavigationBar)), navigation);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('refresh leaves catalog and layout in place at $size', (
      tester,
    ) async {
      await _surface(tester, size);
      final storage = _ControlledStorage();
      final controller = _controller(
        storage,
        initialState: fixtures.filesAvailableState,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(_app(controller));
      await settleCatalog(tester);
      final hero = tester.getRect(find.byType(JukeboxHero));
      final sort = await _contentRect(tester, find.byKey(_sort));
      final status = tester.getRect(find.byKey(_status));
      final refresh = controller.scan(fixtures.testRoot);
      await tester.pump();
      storage.batch([
        ...fixtures.filesAvailableState.entries,
        files.file('Movies/New Movie (2025).mp4'),
      ]);
      await _waitForLocalDiscovery(tester);

      expect(_loading, findsNothing);
      expect(find.byType(JukeboxHero), findsOneWidget);
      expect(tester.getRect(find.byType(JukeboxHero)), hero);
      expect(await _contentRect(tester, find.byKey(_sort)), sort);
      expect(tester.getRect(find.byKey(_status)), status);
      expect(find.byTooltip('Cancel scan'), findsOneWidget);
      expect(
        tester.widget<JukeboxHero>(find.byType(JukeboxHero)).titles,
        hasLength(1),
      );

      await storage.complete();
      await refresh;
      await settleCatalog(tester);
      expect(
        tester.widget<JukeboxHero>(find.byType(JukeboxHero)).titles,
        hasLength(2),
      );
      expect(tester.getRect(find.byType(JukeboxHero)), hero);
      expect(await _contentRect(tester, find.byKey(_sort)), sort);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'saved cards layout waits for preferences before showing a hero',
    (tester) async {
      await _surface(tester, const Size(390, 844));
      final preferences = Completer<String>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(CatalogLibrary.channel, (call) async {
            if (call.method == 'loadPreferences') return preferences.future;
            return null;
          });
      await tester.pumpWidget(
        screens.app(
          fixtures.filesAvailableState.copyWith(
            phase: RiskSpikePhase.enumerating,
            scanCompleted: false,
          ),
        ),
      );

      expect(_loading, findsOneWidget);
      expect(find.byType(CatalogHeroSkeleton), findsNothing);
      expect(find.byType(JukeboxHero), findsNothing);
      preferences.complete('{"homeView":"cards"}');
      await _waitForLocalDiscovery(tester);

      expect(catalogLibrary(tester).homeView, CatalogHomeView.cards);
      expect(find.byType(CatalogHeroSkeleton), findsNothing);
      expect(find.byKey(const Key('catalog-skeleton-grid')), findsOneWidget);
      expect(find.byType(PosterCard), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'scrolling during the first scan retains the viewport on completion',
    (tester) async {
      await _surface(tester, const Size(390, 844));
      final storage = _ControlledStorage();
      final controller = _controller(
        storage,
        initialState: const RiskSpikeState(
          phase: RiskSpikePhase.ready,
          root: fixtures.testRoot,
        ),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(_app(controller));
      storage.batch([
        files.file('Movies/Alpha (2016).mp4'),
        files.file('Movies/Beta (2017).mp4'),
        files.file('Movies/Gamma (2018).mp4'),
      ]);
      await _waitForLocalDiscovery(tester);
      final scrollable = find
          .descendant(
            of: find.byKey(const Key('catalog-scroll')),
            matching: find.byType(Scrollable),
          )
          .first;
      final position = tester.state<ScrollableState>(scrollable).position;
      expect(position.maxScrollExtent, greaterThan(180));
      position.jumpTo(180);
      await tester.pump();
      expect(_loading, findsOneWidget);

      await storage.complete();
      await settleCatalog(tester);

      final restoredPosition = tester
          .state<ScrollableState>(scrollable)
          .position;
      expect(restoredPosition.pixels, 180);
      expect(_loading, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(390, 844), const Size(1200, 1000)]) {
    testWidgets('large text and delayed metadata keep hero geometry at $size', (
      tester,
    ) async {
      await _surface(tester, size);
      final probe = _DelayedProbe();
      final controller = _controller(
        _ControlledStorage(),
        initialState: fixtures.filesAvailableState.copyWith(
          entries: [files.file('Movies/Alpha (2016).mp4')],
        ),
        probe: probe,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _app(controller, textScaler: const TextScaler.linear(2)),
      );
      await settleCatalog(tester);
      final hero = tester.getRect(find.byType(JukeboxHero));
      final metadata = tester.getRect(
        find.byKey(const Key('jukebox-metadata-slot')),
      );
      const audio =
          'DTS-HD Master Audio 7.1, Dolby TrueHD Atmos, AAC stereo and commentary';
      probe.result.complete(
        const Success(
          MediaProbeResult(
            streamCount: 12,
            duration: Duration(hours: 3, minutes: 42),
            audioCodecSummary: audio,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(tester.getRect(find.byType(JukeboxHero)), hero);
      expect(
        tester.getRect(find.byKey(const Key('jukebox-metadata-slot'))),
        metadata,
      );
      final audioRect = tester.getRect(find.byTooltip(audio));
      expect(audioRect.top, greaterThanOrEqualTo(metadata.top));
      expect(audioRect.bottom, lessThanOrEqualTo(metadata.bottom));
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.all(size.width < 600 ? 16 : 32),
              child: const CatalogHeroSkeleton(),
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byType(CatalogHeroSkeleton)), hero.size);
      expect(tester.takeException(), isNull);
    });
  }

  for (final size in [const Size(320, 640), const Size(1200, 1000)]) {
    testWidgets('skeleton fits compact and tablet layouts at $size', (
      tester,
    ) async {
      await _surface(tester, size);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: const SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: Column(
                children: [CatalogHeroSkeleton(), CatalogShelfSkeleton()],
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('catalog-skeleton-grid')), findsOneWidget);
      final grid = tester.widget<GridView>(
        find.byKey(const Key('catalog-skeleton-grid')),
      );
      final delegate =
          grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      expect(delegate.crossAxisCount, size.width < 500 ? 2 : 5);
      expect(delegate.childAspectRatio, .60);
    });
  }
}

class _MemoryInventory implements ScanInventoryStore {
  @override
  Future<ScanInventory?> load() async => null;

  @override
  Future<void> save(ScanInventory inventory) async {}

  @override
  Future<void> clear() async {}
}

class _DelayedProbe implements MediaProbe {
  final result = Completer<AppResult<MediaProbeResult>>();

  @override
  Future<AppResult<MediaProbeResult>> probe({
    required LibraryRootLocator root,
    required String storageKey,
    required CancellationToken cancellationToken,
  }) => result.future;
}

class _ControlledStorage implements LibraryStorageGateway {
  final roots = Completer<AppResult<List<AuthorizedLibraryRoot>>>();
  StreamController<StorageScanEvent>? _events;
  String? _scanId;

  @override
  Future<AppResult<List<AuthorizedLibraryRoot>>> listPersistedRoots() =>
      roots.future;

  @override
  Future<AppResult<RootAccessState>> checkAccess(
    LibraryRootLocator root,
  ) async => const Success(RootAccessState.available);

  @override
  Stream<StorageScanEvent> enumerateRecursively({
    required LibraryRootLocator root,
    required String scanId,
    required CancellationToken cancellationToken,
  }) {
    _scanId = scanId;
    _events = StreamController<StorageScanEvent>();
    return _events!.stream;
  }

  void batch(List<StorageEntrySnapshot> entries) =>
      _events!.add(StorageScanBatch(_scanId!, entries));

  Future<void> complete() async {
    _events!.add(StorageScanCompleted(_scanId!));
    await _events!.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected storage call: ${invocation.memberName}');
}
