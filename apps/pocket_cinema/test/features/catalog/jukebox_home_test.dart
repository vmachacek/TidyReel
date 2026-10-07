import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_cinema/features/catalog/catalog_library.dart';
import 'package:pocket_cinema/features/catalog/catalog_screen.dart';
import 'package:pocket_cinema/features/catalog/cinema_player.dart';
import 'package:pocket_cinema/features/risk_spike/risk_spike_state.dart';

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

void main() {
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
    await tester.pumpAndSettle();
    expect(_selectedTitle(tester), 'Zulu');
    expect(find.text('1 / 2'), findsOneWidget);

    preferences.complete(
      jsonEncode({
        'positions': {resumed.storageKey: 40},
        'durations': {resumed.storageKey: 120},
      }),
    );
    await tester.pumpAndSettle();
    expect(_selectedTitle(tester), 'Alpha');
    expect(find.text('2 / 2'), findsOneWidget);
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
    await tester.pumpAndSettle();
    expect(hero.library.isSaved(selected), isTrue);
    expect(
      hero.library.isSaved(
        hero.titles.singleWhere((title) => title.first.id == first.storageKey),
      ),
      isFalse,
    );

    await tester.tap(find.byKey(const Key('jukebox-stage')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<CatalogDetail>(find.byType(CatalogDetail)).title.id,
      selected.id,
    );
    Navigator.of(tester.element(find.byType(CatalogDetail))).pop();
    await tester.pumpAndSettle();

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
        await tester.pumpAndSettle();
        if (isSeries) {
          await tester.tap(find.byKey(const Key('jukebox-next')));
          await tester.pumpAndSettle();
        }
        final selected = tester
            .widget<JukeboxHero>(find.byType(JukeboxHero))
            .selectedTitle;
        expect(selected.isSeries, isSeries);

        await tester.tap(find.byKey(const Key('jukebox-stage')));
        await tester.pumpAndSettle();

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
          await tester.pumpAndSettle();
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
    await tester.pumpAndSettle();
    final firstTitle = tester
        .widget<JukeboxHero>(find.byType(JukeboxHero))
        .selectedTitle;
    expect(_selectedTitle(tester), 'Zulu');
    await tester.tap(find.byKey(const Key('jukebox-next')));
    await tester.pumpAndSettle();
    expect(_selectedTitle(tester), 'Alpha');
    final selectedHero = tester.widget<JukeboxHero>(find.byType(JukeboxHero));
    final selected = selectedHero.selectedTitle;

    await tester.tap(find.byKey(const Key('jukebox-watchlist')));
    await tester.pumpAndSettle();
    expect(selectedHero.library.isSaved(selected), isTrue);
    expect(selectedHero.library.isSaved(firstTitle), isFalse);

    await tester.tap(find.byKey(const Key('jukebox-details')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<CatalogDetail>(find.byType(CatalogDetail)).title.id,
      selected.id,
    );
    Navigator.of(tester.element(find.byType(CatalogDetail))).pop();
    await tester.pumpAndSettle();
    expect(_selectedTitle(tester), 'Alpha');

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
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('jukebox-next')));
      await tester.pumpAndSettle();
      expect(_selectedTitle(tester), 'Alpha');
      expect(find.text('2 / 3'), findsOneWidget);

      await tester.ensureVisible(find.text('A–Z'));
      await tester.tap(find.text('A–Z'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('jukebox-title')),
        -250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(_selectedTitle(tester), 'Alpha');
      expect(find.text('1 / 3'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Movies').hitTestable(),
        -250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Movies'));
      await tester.pumpAndSettle();
      expect(_selectedTitle(tester), 'Alpha');
      expect(find.text('1 / 2'), findsOneWidget);

      await tester.tap(find.text('TV Shows'));
      await tester.pumpAndSettle();
      expect(_selectedTitle(tester), 'My Show');
      expect(find.text('1 / 1'), findsOneWidget);
      expect(find.text('Only title'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
