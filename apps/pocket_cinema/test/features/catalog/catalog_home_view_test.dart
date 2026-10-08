import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_platform_storage/media_platform_storage.dart';
import 'package:pocket_cinema/features/catalog/catalog_library.dart';
import 'package:pocket_cinema/features/catalog/catalog_screen.dart';

import '../../support/catalog_discovery.dart';
import '../risk_spike/risk_spike_screen_test.dart' as fixtures;
import 'catalog_library_test.dart' as files;
import 'catalog_metadata_preferences_test.dart' as preferences;
import 'catalog_screen_test.dart' as screens;

Future<void> _surface(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Future<void> _show(
  WidgetTester tester,
  List<StorageEntrySnapshot> entries,
) async {
  await tester.pumpWidget(
    screens.app(fixtures.filesAvailableState.copyWith(entries: entries)),
  );
  await settleCatalog(tester);
}

Future<void> _reveal(
  WidgetTester tester,
  Finder finder, {
  double delta = -250,
}) async {
  await tester.scrollUntilVisible(
    finder,
    delta,
    scrollable: find.byType(Scrollable).first,
  );
  await settleCatalog(tester);
}

Future<void> _switch(WidgetTester tester, CatalogHomeView view) async {
  final button = find.byKey(Key('home-view-${view.name}'));
  await _reveal(tester, button);
  await tester.tap(button);
  await settleCatalog(tester);
}

Future<void> _filter(WidgetTester tester, String label) async {
  final filter = find.widgetWithText(ChoiceChip, label);
  await _reveal(tester, filter);
  await tester.tap(filter);
  await settleCatalog(tester);
}

Finder _card(String name) => find.byWidgetPredicate(
  (widget) => widget is PosterCard && widget.title.name == name,
);

SegmentedButton<CatalogHomeView> _viewSwitch(WidgetTester tester) =>
    tester.widget<SegmentedButton<CatalogHomeView>>(
      find.byKey(const Key('home-view-switch')),
    );

void main() {
  late preferences.NativePreferences stored;

  setUp(() {
    stored = preferences.NativePreferences();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(CatalogLibrary.channel, stored.handle);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(CatalogLibrary.channel, null);
  });

  for (final surface in [const Size(390, 844), const Size(1200, 1000)]) {
    testWidgets('Home switches between carousel and cards at $surface', (
      tester,
    ) async {
      await _surface(tester, surface);
      await _show(tester, [files.file('Movies/Alpha (2016).mp4')]);

      expect(
        find.byType(NavigationBar),
        surface.width < 850 ? findsOneWidget : findsNothing,
      );
      expect(_viewSwitch(tester).selected, {CatalogHomeView.carousel});
      await _reveal(tester, find.byType(JukeboxHero), delta: 250);
      expect(find.byType(JukeboxHero), findsOneWidget);

      await _switch(tester, CatalogHomeView.cards);
      expect(_viewSwitch(tester).selected, {CatalogHomeView.cards});
      expect(find.byType(JukeboxHero), findsNothing);
      await _reveal(tester, _card('Alpha'), delta: 250);
      expect(_card('Alpha'), findsOneWidget);
      expect(find.byTooltip('List view'), findsNothing);

      await _switch(tester, CatalogHomeView.carousel);
      expect(_viewSwitch(tester).selected, {CatalogHomeView.carousel});
      await _reveal(tester, find.byType(JukeboxHero), delta: 250);
      expect(find.byType(JukeboxHero), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Switching views retains the featured carousel title', (
    tester,
  ) async {
    await _surface(tester, const Size(1200, 1000));
    await _show(tester, [
      files.file('Movies/Zulu (2020).mp4'),
      files.file('Movies/Alpha (2016).mp4'),
    ]);
    await _reveal(tester, find.byKey(const Key('jukebox-next')), delta: 250);
    await tester.tap(find.byKey(const Key('jukebox-next')));
    await settleCatalog(tester);
    expect(
      tester.widget<JukeboxHero>(find.byType(JukeboxHero)).selectedTitle.name,
      'Alpha',
    );

    await _switch(tester, CatalogHomeView.cards);
    await _switch(tester, CatalogHomeView.carousel);
    await _reveal(tester, find.byType(JukeboxHero), delta: 250);
    expect(
      tester.widget<JukeboxHero>(find.byType(JukeboxHero)).selectedTitle.name,
      'Alpha',
    );
    expect(find.text('2 / 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Cards share filters, sorting, search and title details', (
    tester,
  ) async {
    await _surface(tester, const Size(1200, 1000));
    await _show(tester, [
      files.file('Movies/Zulu (2020).mp4'),
      files.file('Movies/Alpha (2016).mp4'),
      files.file('Shows/My.Show.S01E01.Start.mp4'),
    ]);
    await _switch(tester, CatalogHomeView.cards);
    await _filter(tester, 'Movies');
    await _reveal(tester, _card('Alpha'), delta: 250);
    expect(_card('Alpha'), findsOneWidget);
    expect(_card('Zulu'), findsOneWidget);
    expect(_card('My Show'), findsNothing);

    await _filter(tester, 'A–Z');
    await _reveal(tester, _card('Alpha'), delta: 250);
    expect(
      tester
          .widgetList<PosterCard>(find.byType(PosterCard))
          .map((card) => card.title.name),
      ['Alpha', 'Zulu'],
    );

    await _filter(tester, 'TV Shows');
    await _reveal(tester, _card('My Show'), delta: 250);
    expect(_card('My Show'), findsOneWidget);
    expect(_card('Alpha'), findsNothing);
    expect(_card('Zulu'), findsNothing);
    await tester.tap(_card('My Show'));
    await settleCatalog(tester);
    final detail = tester.widget<CatalogDetail>(find.byType(CatalogDetail));
    expect(detail.title.name, 'My Show');
    expect(detail.title.isSeries, isTrue);
    Navigator.of(tester.element(find.byType(CatalogDetail))).pop();
    await settleCatalog(tester);

    await _filter(tester, 'All');
    await _reveal(tester, find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'Alpha');
    await settleCatalog(tester);
    await _reveal(tester, _card('Alpha'), delta: 250);
    expect(_card('Alpha'), findsOneWidget);
    expect(_card('Zulu'), findsNothing);
    expect(_card('My Show'), findsNothing);

    await _reveal(tester, find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'missing');
    await settleCatalog(tester);
    expect(find.byType(PosterCard), findsNothing);
    expect(find.text('No videos match your search.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('The selected Home view survives screen recreation', (
    tester,
  ) async {
    await _surface(tester, const Size(1200, 1000));
    final entries = [files.file('Movies/Alpha (2016).mp4')];
    await _show(tester, entries);
    await _switch(tester, CatalogHomeView.cards);
    expect(stored.decoded['homeView'], 'cards');

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await _show(tester, entries);
    expect(_viewSwitch(tester).selected, {CatalogHomeView.cards});
    expect(find.byType(JukeboxHero), findsNothing);
    await _reveal(tester, _card('Alpha'), delta: 250);
    expect(_card('Alpha'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home Cards preserve the Library list preference', (
    tester,
  ) async {
    await _surface(tester, const Size(390, 844));
    await _show(tester, [files.file('Movies/Alpha (2016).mp4')]);
    await tester.tap(find.text('Library').last);
    await settleCatalog(tester);
    expect(find.byKey(const Key('home-view-switch')), findsNothing);
    await _reveal(tester, find.byTooltip('List view'), delta: 250);
    await tester.tap(find.byTooltip('List view'));
    await settleCatalog(tester);
    expect(find.byTooltip('Poster view'), findsOneWidget);

    await tester.tap(find.text('Home').last);
    await settleCatalog(tester);
    await _switch(tester, CatalogHomeView.cards);
    await _reveal(tester, _card('Alpha'), delta: 250);
    expect(_card('Alpha'), findsOneWidget);
    expect(find.byTooltip('Poster view'), findsNothing);

    await tester.tap(find.text('Library').last);
    await settleCatalog(tester);
    expect(find.byKey(const Key('home-view-switch')), findsNothing);
    await _reveal(tester, find.byTooltip('Poster view'), delta: 250);
    expect(find.byTooltip('Poster view'), findsOneWidget);
    expect(find.byType(PosterCard), findsNothing);

    await tester.tap(find.text('Home').last);
    await settleCatalog(tester);
    await _reveal(tester, find.byKey(const Key('home-view-switch')));
    expect(_viewSwitch(tester).selected, {CatalogHomeView.cards});
    await _reveal(tester, _card('Alpha'), delta: 250);
    expect(_card('Alpha'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
