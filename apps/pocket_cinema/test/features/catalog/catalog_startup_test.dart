import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_domain/media_domain.dart';
import 'package:media_platform_storage/media_platform_storage.dart';
import 'package:media_playback/media_playback.dart';
import 'package:pocket_cinema/app/app_theme.dart';
import 'package:pocket_cinema/features/catalog/catalog_library.dart';
import 'package:pocket_cinema/features/catalog/catalog_screen.dart';
import 'package:pocket_cinema/features/catalog/catalog_skeleton.dart';
import 'package:pocket_cinema/features/risk_spike/risk_spike_controller.dart';
import 'package:pocket_cinema/features/risk_spike/playback_session_coordinator.dart';
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

Future<void> _finishScan(
  WidgetTester tester,
  _ControlledStorage storage, {
  bool fail = false,
}) async {
  await tester.runAsync(() async {
    var finished = false;
    final finishing = fail ? storage.fail() : storage.complete();
    unawaited(finishing.then<void>((_) => finished = true));
    final elapsed = Stopwatch()..start();
    while (!finished) {
      if (elapsed.elapsed > const Duration(seconds: 30)) {
        throw TestFailure('Controlled scan did not finish.');
      }
      // Scan completion classifies entries in a real isolate. Pump fake-clock
      // continuations while allowing its messages to arrive in real time.
      await tester.pump();
      await Future<void>.delayed(Duration.zero);
    }
    await finishing;
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
  PlaybackSession? playback,
  ScanInventoryStore? inventoryStore,
}) => RiskSpikeController(
  storage: storage,
  probe: probe ?? controller_fixtures.FakeMediaProbe(),
  playback: playback ?? controller_fixtures.FakePlaybackSession(),
  inventoryStore: inventoryStore ?? _MemoryInventory(),
  initialState: initialState,
);

ScanInventory _inventory({bool empty = false}) => ScanInventory(
  root: fixtures.testRoot.locator,
  videos: empty ? [] : [files.file('Movies/Alpha (2016).mp4')],
  artwork: const [],
  subtitles: const [],
  discoveredCount: empty ? 0 : 1,
  ignoredCount: 0,
  completedAtUtc: DateTime.utc(2026, 10, 8),
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

  testWidgets(
    'startup refresh waits for cached presentation and leaves it interactive',
    (tester) async {
      await _surface(tester, const Size(1200, 1000));
      final preferences = Completer<String>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(CatalogLibrary.channel, (call) async {
            if (call.method == 'loadPreferences') return preferences.future;
            return null;
          });
      final storage = _ControlledStorage();
      final store = _MemoryInventory(saved: _inventory());
      final controller = _controller(storage, inventoryStore: store);
      addTearDown(controller.dispose);
      var cachedContentVisibleAtScanStart = false;
      storage.onEnumerate = () {
        cachedContentVisibleAtScanStart =
            find.byType(JukeboxHero).evaluate().isNotEmpty &&
            _loading.evaluate().isEmpty;
      };
      final initializing = controller.initialize();
      await tester.pumpWidget(_app(controller));
      storage.roots.complete(const Success([fixtures.testRoot]));
      await initializing;
      await tester.pump();

      expect(controller.state.scanCompleted, isTrue);
      expect(storage.scanCount, 0);
      expect(_loading, findsOneWidget);
      preferences.complete('{}');
      await _waitForLocalDiscovery(tester);
      await tester.pump();

      expect(storage.scanCount, 0);
      expect(_loading, findsNothing);
      final library = catalogLibrary(tester);
      final cachedTitle = library.currentTitles.single;
      final hero = tester.getRect(find.byType(JukeboxHero));
      expect(cachedTitle.name, 'Alpha');
      expect(library.isSaved(cachedTitle), isFalse);

      await tester.tap(find.byKey(const Key('jukebox-watchlist')));
      await tester.pump();
      expect(library.isSaved(cachedTitle), isTrue);
      await tester.pump(const Duration(seconds: 15));
      expect(storage.scanCount, 1);
      expect(cachedContentVisibleAtScanStart, isTrue);
      expect(controller.isBackgroundRefreshing, isTrue);
      expect(controller.state.canCancel, isFalse);
      expect(find.byTooltip('Cancel scan'), findsNothing);
      expect(find.textContaining('Refreshing library'), findsNothing);
      storage.batch([
        ...store.saved!.videos,
        files.file('Movies/Beta (2017).mp4'),
      ]);
      await _waitForLocalDiscovery(tester);

      expect(library.currentTitles, hasLength(1));
      expect(controller.state.entries, hasLength(1));
      expect(tester.getRect(find.byType(JukeboxHero)), hero);
      expect(_loading, findsNothing);

      await _finishScan(tester, storage);
      await settleCatalog(tester);

      expect(controller.state.phase, RiskSpikePhase.filesAvailable);
      expect(library.currentTitles, hasLength(2));
      expect(library.isSaved(cachedTitle), isTrue);
      expect(store.saved!.videos, hasLength(2));
      expect(tester.getRect(find.byType(JukeboxHero)), hero);
      expect(storage.scanCount, 1);
      expect(tester.takeException(), isNull);
    },
  );

  for (final empty in [false, true]) {
    testWidgets('fresh cache skips later launches (empty cache: $empty)', (
      tester,
    ) async {
      await _surface(tester, const Size(1200, 1000));
      final store = _MemoryInventory(saved: _inventory(empty: empty));
      final storage = _ControlledStorage();
      final controller = _controller(storage, inventoryStore: store);
      addTearDown(controller.dispose);
      storage.roots.complete(const Success([fixtures.testRoot]));
      await controller.initialize();
      expect(storage.scanCount, 0);

      await tester.pumpWidget(_app(controller));
      await _waitForLocalDiscovery(tester);
      expect(storage.scanCount, 0);
      await tester.pump(const Duration(seconds: 15));

      expect(storage.scanCount, 1);
      expect(controller.isBackgroundRefreshing, isTrue);
      expect(_loading, findsNothing);
      if (!empty) storage.batch(store.saved!.videos);
      await _finishScan(tester, storage);
      await settleCatalog(tester);
      await controller.initialize();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(_app(controller));
      await _waitForLocalDiscovery(tester);
      await tester.pump();

      expect(storage.scanCount, 1);
      expect(controller.state.phase, RiskSpikePhase.filesAvailable);
      expect(_loading, findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      final nextStorage = _ControlledStorage();
      final nextController = _controller(nextStorage, inventoryStore: store);
      addTearDown(nextController.dispose);
      nextStorage.roots.complete(const Success([fixtures.testRoot]));
      await nextController.initialize();
      await tester.pumpWidget(_app(nextController));
      await _waitForLocalDiscovery(tester);
      await tester.pump(const Duration(seconds: 15));

      expect(nextStorage.scanCount, 0);
      expect(nextController.isBackgroundRefreshing, isFalse);
      expect(_loading, findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('failed startup refresh preserves cached catalog without retry', (
    tester,
  ) async {
    await _surface(tester, const Size(1200, 1000));
    final cached = _inventory();
    final store = _MemoryInventory(saved: cached);
    final storage = _ControlledStorage();
    final controller = _controller(storage, inventoryStore: store);
    addTearDown(controller.dispose);
    storage.roots.complete(const Success([fixtures.testRoot]));
    await controller.initialize();
    final entries = controller.state.entries;
    await tester.pumpWidget(_app(controller));
    await _waitForLocalDiscovery(tester);
    await tester.pump(const Duration(seconds: 15));
    expect(storage.scanCount, 1);
    final library = catalogLibrary(tester);
    final title = library.currentTitles.single;
    storage.batch([files.file('Movies/Incomplete (2025).mp4')]);
    await _waitForLocalDiscovery(tester);

    expect(library.currentTitles.single.id, title.id);
    await _finishScan(tester, storage, fail: true);
    await settleCatalog(tester);

    expect(controller.state.phase, RiskSpikePhase.filesAvailable);
    expect(controller.state.libraryFailure, isNull);
    expect(controller.state.entries, same(entries));
    expect(controller.state.scanCompleted, isTrue);
    expect(library.currentTitles.single.id, title.id);
    expect(store.saved, same(cached));
    expect(_loading, findsNothing);
    expect(find.byType(JukeboxHero), findsOneWidget);
    expect(find.byKey(const Key('folder-onboarding')), findsNothing);
    final watchlist = find.byKey(const Key('jukebox-watchlist'));
    await tester.ensureVisible(watchlist);
    await tester.pump();
    expect(tester.widget<IconButton>(watchlist).onPressed, isNotNull);
    await tester.tap(watchlist);
    await tester.pump();
    expect(library.isSaved(title), isTrue);
    expect(storage.scanCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('touch, text input and scrolling defer automatic maintenance', (
    tester,
  ) async {
    await _surface(tester, const Size(1200, 1000));
    final store = _MemoryInventory(saved: _inventory());
    final storage = _ControlledStorage();
    final controller = _controller(storage, inventoryStore: store);
    addTearDown(controller.dispose);
    storage.roots.complete(const Success([fixtures.testRoot]));
    await controller.initialize();
    await tester.pumpWidget(_app(controller));
    await _waitForLocalDiscovery(tester);
    await tester.pump(const Duration(seconds: 14));

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('All')),
    );
    await tester.pump(const Duration(seconds: 8));
    expect(storage.scanCount, 0);
    await gesture.up();
    await tester.pump(const Duration(seconds: 4));
    expect(storage.scanCount, 0);
    await tester.tap(find.byTooltip('Search library'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'a');
    await tester.pump(const Duration(seconds: 4));
    expect(storage.scanCount, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(storage.scanCount, 1);

    await tester.drag(
      find.byKey(const Key('catalog-scroll')),
      const Offset(0, -150),
    );
    await tester.pumpAndSettle();
    expect(controller.isBackgroundRefreshing, isFalse);
    expect(controller.state.entries, same(store.saved!.videos));
    await tester.pump(const Duration(seconds: 5));
    expect(storage.scanCount, 2);
    storage.batch(store.saved!.videos);
    await _finishScan(tester, storage);
    await settleCatalog(tester);
    expect(tester.takeException(), isNull);
  });

  for (final covered in [false, true]) {
    testWidgets(
      'automatic refresh waits while ${covered ? 'a route covers home' : 'app is paused'}',
      (tester) async {
        await _surface(tester, const Size(1200, 1000));
        final store = _MemoryInventory(saved: _inventory());
        final storage = _ControlledStorage();
        final controller = _controller(storage, inventoryStore: store);
        addTearDown(controller.dispose);
        storage.roots.complete(const Success([fixtures.testRoot]));
        await controller.initialize();
        await tester.pumpWidget(_app(controller));
        await _waitForLocalDiscovery(tester);
        final navigator = Navigator.of(
          tester.element(find.byType(CatalogScreen)),
        );
        if (covered) {
          unawaited(
            navigator.push(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('Other screen')),
              ),
            ),
          );
          await tester.pumpAndSettle();
        } else {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.hidden,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
        }
        await tester.pump(const Duration(seconds: 20));
        expect(storage.scanCount, 0);

        if (covered) {
          navigator.pop();
          await tester.pumpAndSettle();
        } else {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.hidden,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        }
        await tester.pump(const Duration(seconds: 5));
        expect(storage.scanCount, 1);
        storage.batch(store.saved!.videos);
        await _finishScan(tester, storage);
        await settleCatalog(tester);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('an open paused player keeps background maintenance deferred', (
    tester,
  ) async {
    await _surface(tester, const Size(1200, 1000));
    final store = _MemoryInventory(saved: _inventory());
    final storage = _ControlledStorage();
    final controller = _controller(
      storage,
      inventoryStore: store,
      playback: controller_fixtures.FakePlaybackSession(
        initialSnapshot: const PlaybackSnapshot(isOpen: true),
        allowStop: true,
      ),
    );
    addTearDown(controller.dispose);
    storage.roots.complete(const Success([fixtures.testRoot]));
    await controller.initialize();
    await tester.pumpWidget(_app(controller));
    await _waitForLocalDiscovery(tester);
    await tester.pump(const Duration(seconds: 20));
    expect(storage.scanCount, 0);
    await controller.closePlayer();
    await tester.pump(const Duration(seconds: 15));
    expect(storage.scanCount, 1);
    storage.batch(store.saved!.videos);
    await _finishScan(tester, storage);
    await settleCatalog(tester);
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

      await _finishScan(tester, storage);
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

      await _finishScan(tester, storage);
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

      await _finishScan(tester, storage);
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
  _MemoryInventory({this.saved});

  ScanInventory? saved;

  @override
  Future<ScanInventory?> load() async => saved;

  @override
  Future<void> save(ScanInventory inventory) async {
    saved = inventory;
  }

  @override
  Future<void> clear() async {
    saved = null;
  }
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
  int scanCount = 0;
  VoidCallback? onEnumerate;

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
    scanCount++;
    onEnumerate?.call();
    _scanId = scanId;
    final events = _events = StreamController<StorageScanEvent>();
    unawaited(
      cancellationToken.whenCancelled.then((_) async {
        if (events.isClosed) return;
        events.add(StorageScanCancelled(scanId));
        await events.close();
      }),
    );
    return events.stream;
  }

  void batch(List<StorageEntrySnapshot> entries) =>
      _events!.add(StorageScanBatch(_scanId!, entries));

  Future<void> complete() async {
    _events!.add(StorageScanCompleted(_scanId!));
    await _events!.close();
  }

  Future<void> fail() async {
    _events!.add(StorageScanFailed(_scanId!, RiskSpikeController.scanFailed));
    await _events!.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected storage call: ${invocation.memberName}');
}
