import 'dart:convert';

import 'package:pocket_cinema/features/catalog/catalog_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_cinema/app/app_theme.dart';
import 'package:pocket_cinema/features/catalog/catalog_screen.dart';
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

void main() {
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

  testWidgets('Empty Home shows folder connection and links to diagnostics', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app(const RiskSpikeState()));
    await settleCatalog(tester);
    expect(find.text('Connect media folder'), findsOneWidget);
    expect(find.byKey(const Key('folder-onboarding')), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.textContaining('Astro Kid'), findsNothing);
    expect(find.textContaining('SpongeBob'), findsNothing);
    await tester.tap(find.byTooltip('Diagnostics'));
    await settleCatalog(tester);
    expect(find.byType(RiskSpikeScreen), findsOneWidget);
    await tester.tap(find.byKey(const Key('diagnostics-home-button')));
    await settleCatalog(tester);
    expect(find.text('Connect media folder'), findsOneWidget);
    expect(find.byKey(const Key('folder-onboarding')), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Home shows only scanned videos and search filters them', (
    tester,
  ) async {
    await tester.pumpWidget(app(fixtures.filesAvailableState));
    await settleCatalog(tester);
    await tester.drag(find.byType(ListView).first, const Offset(0, -500));
    await settleCatalog(tester);
    expect(find.byType(PosterCard), findsOneWidget);
    expect(find.text('Movie'), findsWidgets);
    expect(find.textContaining('Astro Kid'), findsNothing);
    await tester.drag(find.byType(ListView).first, const Offset(0, 700));
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
      scrollable: find.byType(Scrollable).first,
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
