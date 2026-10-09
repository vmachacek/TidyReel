import 'dart:convert';

import 'package:pocket_cinema/features/catalog/catalog_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_cinema/app/app_brand.dart';
import 'package:pocket_cinema/app/app_theme.dart';
import 'package:pocket_cinema/features/catalog/catalog_screen.dart';
import 'package:pocket_cinema/features/catalog/catalog_settings_screen.dart';
import 'package:pocket_cinema/features/risk_spike/risk_spike_screen.dart';
import 'package:pocket_cinema/features/risk_spike/risk_spike_state.dart';
import 'package:pocket_cinema/l10n/app_localizations.dart';

import '../../support/catalog_discovery.dart';
import '../risk_spike/risk_spike_screen_test.dart' as fixtures;
import 'catalog_library_test.dart' as files;

Widget app(RiskSpikeState state) {
  final fixture = fixtures.testApp(state: state) as MaterialApp;
  final diagnostic = (fixture.home! as MediaQuery).child as RiskSpikeScreen;
  return MaterialApp(
    theme: AppTheme.dark,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: CatalogScreen(controller: diagnostic.controller),
  );
}

Finder get catalogScrollable => find
    .descendant(
      of: find.byKey(const Key('catalog-scroll')),
      matching: find.byType(Scrollable),
    )
    .first;

void main() {
  for (final width in [390.0, 600.0, 1200.0]) {
    testWidgets('catalog header keeps filters beside the logo at $width', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 1000);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(app(fixtures.filesAvailableState));
        await settleCatalog(tester);

        final brand = find.byType(AppBrand);
        final filters = find.byKey(const Key('catalog-category-filters'));
        expect(find.byKey(const Key('catalog-search-field')), findsNothing);
        expect(find.byTooltip('Search library'), findsOneWidget);
        expect(find.textContaining('LOCAL STORAGE'), findsNothing);
        if (width < 760) {
          expect(find.text('Pocket Cinema'), findsNothing);
          expect(find.bySemanticsLabel('Pocket Cinema'), findsOneWidget);
        }
        expect(
          tester.getTopLeft(filters).dx,
          greaterThanOrEqualTo(tester.getTopRight(brand).dx),
        );
        expect(
          tester.getCenter(filters).dy,
          closeTo(tester.getCenter(brand).dy, 1),
        );

        final watchlist = find.widgetWithText(ChoiceChip, 'Watchlist');
        if (watchlist.hitTestable().evaluate().isEmpty) {
          await tester.drag(filters, const Offset(-600, 0));
          await tester.pumpAndSettle();
        }
        expect(watchlist.hitTestable(), findsOneWidget);
        await tester.tap(watchlist);
        await settleCatalog(tester);
        expect(tester.widget<ChoiceChip>(watchlist).selected, isTrue);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });
  }

  testWidgets('catalog search opens focused and closing restores all titles', (
    tester,
  ) async {
    await tester.pumpWidget(app(fixtures.filesAvailableState));
    await settleCatalog(tester);
    final input = find.byKey(const Key('catalog-search-field'));
    expect(input, findsNothing);

    await tester.tap(find.byTooltip('Search library'));
    await settleCatalog(tester);
    expect(input, findsOneWidget);
    expect(
      tester
          .widget<EditableText>(
            find.descendant(of: input, matching: find.byType(EditableText)),
          )
          .focusNode
          .hasFocus,
      isTrue,
    );
    await tester.enterText(input, 'missing');
    await settleCatalog(tester);
    expect(find.text('No videos match your search.'), findsOneWidget);

    await tester.tap(find.byTooltip('Close search'));
    await settleCatalog(tester);
    expect(input, findsNothing);
    expect(find.text('No videos match your search.'), findsNothing);
    expect(find.byType(JukeboxHero), findsOneWidget);

    await tester.tap(find.byTooltip('Search library'));
    await settleCatalog(tester);
    expect(tester.widget<TextField>(input).controller!.text, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('catalog discovery keeps navigation responsive', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app(fixtures.filesAvailableState));

    expect(catalogLibrary(tester).isDiscovering, isTrue);
    expect(find.text('Organizing your library…'), findsOneWidget);
    expect(find.text('No videos found'), findsNothing);

    await tester.tap(find.text('Library').last);
    await tester.pump();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
    expect(catalogLibrary(tester).isDiscovering, isTrue);

    await settleCatalog(tester);
    expect(catalogLibrary(tester).isDiscovering, isFalse);
    expect(find.text('Organizing your library…'), findsNothing);
    expect(find.byType(PosterCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Empty Home shows folder connection and settings opens diagnostics',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(app(const RiskSpikeState()));
      await settleCatalog(tester);
      expect(find.text('Connect media folder'), findsOneWidget);
      expect(find.byKey(const Key('folder-onboarding')), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.textContaining('Astro Kid'), findsNothing);
      expect(find.textContaining('SpongeBob'), findsNothing);
      expect(find.byTooltip('Diagnostics'), findsNothing);
      expect(find.text('Diagnostics'), findsNothing);
      await tester.tap(find.byTooltip('Library settings'));
      await settleCatalog(tester);
      expect(find.byType(CatalogSettingsScreen), findsOneWidget);
      await tester.tap(find.text('Open Diagnostics'));
      await settleCatalog(tester);
      expect(find.byType(RiskSpikeScreen), findsOneWidget);
      await tester.tap(find.byKey(const Key('diagnostics-home-button')));
      await settleCatalog(tester);
      expect(find.text('Connect media folder'), findsOneWidget);
      expect(find.byKey(const Key('folder-onboarding')), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byTooltip('Diagnostics'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Home shows only scanned videos and search filters them', (
    tester,
  ) async {
    await tester.pumpWidget(app(fixtures.filesAvailableState));
    await settleCatalog(tester);
    expect(find.text('Diagnostics'), findsNothing);
    expect(find.byTooltip('Diagnostics'), findsNothing);
    await tester.scrollUntilVisible(
      find.byType(PosterCard),
      250,
      scrollable: catalogScrollable,
    );
    await settleCatalog(tester);
    expect(find.byType(PosterCard), findsOneWidget);
    expect(find.text('Movie'), findsWidgets);
    expect(find.textContaining('Astro Kid'), findsNothing);
    await tester.tap(find.byTooltip('Search library'));
    await settleCatalog(tester);
    await tester.enterText(find.byType(TextField), 'missing');
    await settleCatalog(tester);
    expect(find.text('Movie.mp4'), findsNothing);
    expect(find.text('No videos match your search.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Series cards open real seasons and episode files', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        fixtures.filesAvailableState.copyWith(
          entries: [
            files.file('Shows/My.Show.S01E01.Start.mp4'),
            files.file('Shows/My.Show.S02E01.Return.mp4'),
          ],
        ),
      ),
    );
    await settleCatalog(tester);
    await tester.scrollUntilVisible(
      find.byType(PosterCard).hitTestable(),
      300,
      scrollable: catalogScrollable,
    );
    await settleCatalog(tester);
    await tester.tap(find.byType(PosterCard));
    await settleCatalog(tester);
    expect(find.byType(CatalogDetail), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -400));
    await settleCatalog(tester);
    expect(find.text('Season 1'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    await tester.tap(find.text('Season 2'));
    await settleCatalog(tester);
    expect(find.text('Return'), findsOneWidget);
    expect(find.text('Start'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  test('Watchlist and resume positions survive a library restart', () async {
    var stored = jsonEncode({
      'saved': ['provider|video'],
      'positions': {'provider|video': 40},
      'durations': {'provider|video': 120},
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(CatalogLibrary.channel, (call) async {
          if (call.method == 'loadPreferences') return stored;
          if (call.method == 'savePreferences') {
            stored = (call.arguments as Map)['value'] as String;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(CatalogLibrary.channel, null),
    );
    final controller =
        ((app(fixtures.filesAvailableState) as MaterialApp).home!
                as CatalogScreen)
            .controller;
    final library = CatalogLibrary(controller);
    await library.load();
    final title = groupCatalog(fixtures.filesAvailableState.entries).single;
    expect(library.saved, contains(title.id));
    expect(library.progress(title.first), closeTo(1 / 3, .001));
    library.toggleSaved(title.id);
    await library.persist();
    library.dispose();
    final restarted = CatalogLibrary(controller);
    await restarted.load();
    expect(restarted.saved, isEmpty);
    expect(restarted.positions[title.first.id], 40);
    restarted.dispose();
  });
}
