import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_platform_storage/media_platform_storage.dart';
import 'package:pocket_cinema/features/catalog/catalog_library.dart';
import 'package:pocket_cinema/features/catalog/catalog_screen.dart';
import 'package:pocket_cinema/features/catalog/cinema_player.dart';
import 'package:pocket_cinema/features/risk_spike/risk_spike_state.dart';

import '../../support/catalog_discovery.dart';
import '../risk_spike/risk_spike_screen_test.dart' as fixtures;
import 'catalog_library_test.dart' as files;
import 'catalog_screen_test.dart' as screens;

class _Routes extends NavigatorObserver {
  final pushed = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
  }
}

Widget _app(RiskSpikeState state, _Routes routes) {
  final fixture = screens.app(state) as MaterialApp;
  return MaterialApp(
    theme: fixture.theme,
    localizationsDelegates: fixture.localizationsDelegates,
    supportedLocales: fixture.supportedLocales,
    navigatorObservers: [routes],
    home: fixture.home,
  );
}

Future<void> _tablet(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1200, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(CatalogLibrary.channel, (call) async {
        if (call.method == 'loadPreferences') return '{}';
        return null;
      });
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(CatalogLibrary.channel, null),
  );
}

String _selectedTitle(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('jukebox-title'))).data!;

List<String> _titleOrder(WidgetTester tester) => tester
    .widget<JukeboxHero>(find.byType(JukeboxHero))
    .titles
    .map((title) => title.name)
    .toList();

void _expectCarouselPosition(WidgetTester tester, int position, int count) {
  final title = tester
      .widget<JukeboxHero>(find.byType(JukeboxHero))
      .selectedTitle
      .name;
  expect(
    find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          widget.properties.label == 'Browse your library' &&
          widget.properties.value == '$position of $count: $title',
    ),
    findsOneWidget,
  );
}

StorageEntrySnapshot _modifiedFile(String path, int day) {
  final file = files.file(path);
  return StorageEntrySnapshot(
    storageKey: file.storageKey,
    parentStorageKey: file.parentStorageKey,
    relativePath: file.relativePath,
    displayName: file.displayName,
    isDirectory: file.isDirectory,
    mimeType: file.mimeType,
    sizeBytes: file.sizeBytes,
    modifiedAtUtc: DateTime.utc(2026, 1, day),
    flags: file.flags,
  );
}

void main() {
  testWidgets(
    'bookmarked movies and shows lead both sorts and filtered carousels',
    (tester) async {
      await _tablet(tester);
      final alpha = _modifiedFile('Movies/Alpha (2016).mp4', 2);
      final beta = _modifiedFile('Shows/Beta.Show.S01E01.Start.mp4', 1);
      final gamma = _modifiedFile('Shows/Gamma.Show.S01E01.Start.mp4', 4);
      final zulu = _modifiedFile('Movies/Zulu (2020).mp4', 3);
      final entries = [alpha, beta, gamma, zulu];
      final betaTitle = groupCatalog(entries)
          .singleWhere((title) => title.name == 'Beta Show');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(CatalogLibrary.channel, (call) async {
            if (call.method == 'loadPreferences') {
              return jsonEncode({
                'saved': [zulu.storageKey, betaTitle.id],
                'positions': {gamma.storageKey: 40},
                'durations': {gamma.storageKey: 120},
              });
            }
            return null;
          });
      await tester.pumpWidget(
        _app(
          fixtures.filesAvailableState.copyWith(entries: entries),
          _Routes(),
        ),
      );
      await settleCatalog(tester);

      expect(_titleOrder(tester), ['Zulu', 'Beta Show', 'Gamma Show', 'Alpha']);
      expect(_selectedTitle(tester), 'Zulu');
      _expectCarouselPosition(tester, 1, 4);
      await tester.tap(find.byKey(const Key('jukebox-next')));
      await settleCatalog(tester);
      expect(_selectedTitle(tester), 'Beta Show');

      await tester.ensureVisible(find.text('A–Z'));
      await tester.tap(find.text('A–Z'));
      await settleCatalog(tester);
      await tester.scrollUntilVisible(
        find.byKey(const Key('jukebox-title')),
        -250,
        scrollable: find.byType(Scrollable).first,
      );
      await settleCatalog(tester);
      expect(_titleOrder(tester), ['Beta Show', 'Zulu', 'Alpha', 'Gamma Show']);
      expect(_selectedTitle(tester), 'Beta Show');
      _expectCarouselPosition(tester, 1, 4);

      await tester.scrollUntilVisible(
        find.text('Movies').hitTestable(),
        -250,
        scrollable: find.byType(Scrollable).first,
      );
      await settleCatalog(tester);
      await tester.tap(find.text('Movies'));
      await settleCatalog(tester);
      expect(_titleOrder(tester), ['Zulu', 'Alpha']);
      expect(_selectedTitle(tester), 'Zulu');
      _expectCarouselPosition(tester, 1, 2);
      await tester.tap(find.text('TV Shows'));
      await settleCatalog(tester);
      expect(_titleOrder(tester), ['Beta Show', 'Gamma Show']);
      expect(_selectedTitle(tester), 'Beta Show');
      await tester.tap(find.text('Watchlist'));
      await settleCatalog(tester);
      expect(_titleOrder(tester), ['Beta Show', 'Zulu']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('delayed bookmarks move saved shows to the start', (
    tester,
  ) async {
    await _tablet(tester);
    final preferences = Completer<String>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(CatalogLibrary.channel, (call) async {
          if (call.method == 'loadPreferences') return preferences.future;
          return null;
        });
    final unsaved = files.file('Movies/Zulu (2020).mp4');
    final show = files.file('Shows/My.Show.S01E01.Start.mp4');
    final entries = [unsaved, show];
    final savedTitle = groupCatalog(entries)
        .singleWhere((title) => title.isSeries);
    await tester.pumpWidget(
      _app(fixtures.filesAvailableState.copyWith(entries: entries), _Routes()),
    );
    await settleCatalog(tester);
    expect(_selectedTitle(tester), 'Zulu');

    preferences.complete(
      jsonEncode({
        'saved': [savedTitle.id],
        'positions': {unsaved.storageKey: 40},
        'durations': {unsaved.storageKey: 120},
      }),
    );
    await settleCatalog(tester);
    expect(_titleOrder(tester), ['My Show', 'Zulu']);
    expect(_selectedTitle(tester), 'My Show');
    _expectCarouselPosition(tester, 1, 2);
    expect(
      tester.widget<PageView>(find.byType(PageView)).controller!.page,
      closeTo(0, .001),
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('jukebox-watchlist')))
          .tooltip,
      'Remove from watchlist',
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('jukebox-play')),
        matching: find.text('Play Episode'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('jukebox-stage')));
    await settleCatalog(tester);
    expect(
      tester.widget<CatalogDetail>(find.byType(CatalogDetail)).title.id,
      savedTitle.id,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('delayed resume preferences align the cover, title and actions', (
    tester,
  ) async {
    await _tablet(tester);
    final preferences = Completer<String>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(CatalogLibrary.channel, (call) async {
          if (call.method == 'loadPreferences') return preferences.future;
          return null;
        });
    final first = files.file('Movies/Zulu (2020).mp4');
    final resumed = files.file('Movies/Alpha (2016).mp4');
    final routes = _Routes();
    await tester.pumpWidget(
      _app(
        fixtures.filesAvailableState.copyWith(entries: [first, resumed]),
        routes,
      ),
    );
    await settleCatalog(tester);
    expect(_selectedTitle(tester), 'Zulu');
    _expectCarouselPosition(tester, 1, 2);

    preferences.complete(
      jsonEncode({
        'positions': {resumed.storageKey: 40},
        'durations': {resumed.storageKey: 120},
      }),
    );
    await settleCatalog(tester);
    expect(_selectedTitle(tester), 'Alpha');
    _expectCarouselPosition(tester, 2, 2);
    expect(
      tester.widget<PageView>(find.byType(PageView)).controller!.page,
      closeTo(1, .001),
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('jukebox-play')),
        matching: find.text('Resume'),
      ),
      findsOneWidget,
    );
    final hero = tester.widget<JukeboxHero>(find.byType(JukeboxHero));
    final selected = hero.selectedTitle;
    await tester.tap(find.byKey(const Key('jukebox-watchlist')));
    await settleCatalog(tester);
    expect(hero.library.isSaved(selected), isTrue);
    expect(
      hero.library.isSaved(
        hero.titles.singleWhere((title) => title.first.id == first.storageKey),
      ),
      isFalse,
    );

    await tester.tap(find.byKey(const Key('jukebox-stage')));
    await settleCatalog(tester);
    expect(
      tester.widget<CatalogDetail>(find.byType(CatalogDetail)).title.id,
      selected.id,
    );
    Navigator.of(tester.element(find.byType(CatalogDetail))).pop();
    await settleCatalog(tester);

    final playContext = tester.element(find.byKey(const Key('jukebox-play')));
    await tester.tap(find.byKey(const Key('jukebox-play')));
    final route = routes.pushed.last as MaterialPageRoute<void>;
    final player = route.builder(playContext) as CinemaPlayer;
    expect(player.video.id, resumed.storageKey);
    expect(player.queue.map((video) => video.id), [resumed.storageKey]);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  for (final isSeries in [false, true]) {
    testWidgets(
      'tapping the center cover opens ${isSeries ? 'show' : 'movie'} details',
      (tester) async {
        await _tablet(tester);
        await tester.pumpWidget(
          _app(
            fixtures.filesAvailableState.copyWith(
              entries: [
                files.file('Movies/Alpha (2016).mp4'),
                files.file('Shows/My.Show.S01E01.Start.mp4'),
                files.file('Shows/My.Show.S02E01.Return.mp4'),
              ],
            ),
            _Routes(),
          ),
        );
        await settleCatalog(tester);
        if (isSeries) {
          await tester.tap(find.byKey(const Key('jukebox-next')));
          await settleCatalog(tester);
        }
        final selected = tester
            .widget<JukeboxHero>(find.byType(JukeboxHero))
            .selectedTitle;
        expect(selected.isSeries, isSeries);

        await tester.tap(find.byKey(const Key('jukebox-stage')));
        await settleCatalog(tester);

        final detail = tester.widget<CatalogDetail>(find.byType(CatalogDetail));
        expect(detail.title.id, selected.id);
        expect(detail.title.isSeries, isSeries);
        if (isSeries) {
          expect(detail.title.seasons, [1, 2]);
          expect(detail.title.episodeCount, 2);
          await tester.scrollUntilVisible(
            find.text('Season 2'),
            250,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.tap(find.text('Season 2'));
          await settleCatalog(tester);
          expect(find.text('Return'), findsOneWidget);
          expect(find.text('Start'), findsNothing);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('title, watchlist, details and play follow carousel selection', (
    tester,
  ) async {
    await _tablet(tester);
    final routes = _Routes();
    await tester.pumpWidget(
      _app(
        fixtures.filesAvailableState.copyWith(
          entries: [
            files.file('Movies/Zulu (2020).mp4'),
            files.file('Movies/Alpha (2016).mp4'),
          ],
        ),
        routes,
      ),
    );
    await settleCatalog(tester);
    final firstTitle = tester
        .widget<JukeboxHero>(find.byType(JukeboxHero))
        .selectedTitle;
    expect(_selectedTitle(tester), 'Zulu');
    await tester.tap(find.byKey(const Key('jukebox-next')));
    await settleCatalog(tester);
    expect(_selectedTitle(tester), 'Alpha');
    final selectedHero = tester.widget<JukeboxHero>(find.byType(JukeboxHero));
    final selected = selectedHero.selectedTitle;

    await tester.tap(find.byKey(const Key('jukebox-watchlist')));
    await settleCatalog(tester);
    expect(selectedHero.library.isSaved(selected), isTrue);
    expect(selectedHero.library.isSaved(firstTitle), isFalse);
    expect(_titleOrder(tester), ['Alpha', 'Zulu']);
    expect(_selectedTitle(tester), 'Alpha');
    _expectCarouselPosition(tester, 1, 2);
    expect(
      tester.widget<PageView>(find.byType(PageView)).controller!.page,
      closeTo(0, .001),
    );

    await tester.tap(find.byKey(const Key('jukebox-details')));
    await settleCatalog(tester);
    expect(
      tester.widget<CatalogDetail>(find.byType(CatalogDetail)).title.id,
      selected.id,
    );
    Navigator.of(tester.element(find.byType(CatalogDetail))).pop();
    await settleCatalog(tester);
    expect(_selectedTitle(tester), 'Alpha');

    await tester.tap(find.byKey(const Key('jukebox-watchlist')));
    await settleCatalog(tester);
    expect(selectedHero.library.isSaved(selected), isFalse);
    expect(_titleOrder(tester), ['Zulu', 'Alpha']);
    expect(_selectedTitle(tester), 'Alpha');
    _expectCarouselPosition(tester, 2, 2);
    expect(
      tester.widget<PageView>(find.byType(PageView)).controller!.page,
      closeTo(1, .001),
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('jukebox-watchlist')))
          .tooltip,
      'Add to watchlist',
    );

    final playContext = tester.element(find.byKey(const Key('jukebox-play')));
    await tester.tap(find.byKey(const Key('jukebox-play')));
    // Check the playback route's requested media before platform playback starts.
    final route = routes.pushed.last as MaterialPageRoute<void>;
    final player = route.builder(playContext) as CinemaPlayer;
    expect(player.video.id, selected.first.id);
    expect(player.queue.map((video) => video.id), [selected.first.id]);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'sorting and filters retain or replace the selected title safely',
    (tester) async {
      await _tablet(tester);
      await tester.pumpWidget(
        _app(
          fixtures.filesAvailableState.copyWith(
            entries: [
              files.file('Movies/Zulu (2020).mp4'),
              files.file('Movies/Alpha (2016).mp4'),
              files.file('Shows/My.Show.S01E01.Start.mp4'),
            ],
          ),
          _Routes(),
        ),
      );
      await settleCatalog(tester);
      await tester.tap(find.byKey(const Key('jukebox-next')));
      await settleCatalog(tester);
      expect(_selectedTitle(tester), 'Alpha');
      _expectCarouselPosition(tester, 2, 3);

      await tester.ensureVisible(find.text('A–Z'));
      await tester.tap(find.text('A–Z'));
      await settleCatalog(tester);
      await tester.scrollUntilVisible(
        find.byKey(const Key('jukebox-title')),
        -250,
        scrollable: find.byType(Scrollable).first,
      );
      await settleCatalog(tester);
      expect(_selectedTitle(tester), 'Alpha');
      _expectCarouselPosition(tester, 1, 3);

      await tester.scrollUntilVisible(
        find.text('Movies').hitTestable(),
        -250,
        scrollable: find.byType(Scrollable).first,
      );
      await settleCatalog(tester);
      await tester.tap(find.text('Movies'));
      await settleCatalog(tester);
      expect(_selectedTitle(tester), 'Alpha');
      _expectCarouselPosition(tester, 1, 2);

      await tester.tap(find.text('TV Shows'));
      await settleCatalog(tester);
      expect(_selectedTitle(tester), 'My Show');
      _expectCarouselPosition(tester, 1, 1);
      expect(find.text('Only title'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
