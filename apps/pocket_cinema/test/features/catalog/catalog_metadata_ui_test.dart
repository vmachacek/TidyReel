import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_cinema/features/catalog/catalog_library.dart';
import 'package:pocket_cinema/features/catalog/catalog_screen.dart';

import '../risk_spike/risk_spike_screen_test.dart' as fixtures;
import 'catalog_library_test.dart' as files;
import 'catalog_screen_test.dart' as screens;

Future<void> _mobile(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void _localPreferences({Map<String, Object?> preferences = const {}}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(CatalogLibrary.channel, (call) async {
        if (call.method == 'loadPreferences') return jsonEncode(preferences);
        // The tests never configure a metadata source or expose a token.
        if (call.method == 'loadMetadataToken') return null;
        return null;
      });
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(CatalogLibrary.channel, null),
  );
}

Future<void> _openOnlyTitle(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byType(PosterCard).hitTestable(),
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(find.byType(PosterCard));
  await tester.pumpAndSettle();
  expect(find.byType(CatalogDetail), findsOneWidget);
}

void main() {
  testWidgets(
    'mobile library settings expose token control and official credits',
    (tester) async {
      await _mobile(tester);
      _localPreferences();
      await tester.pumpWidget(screens.app(fixtures.filesAvailableState));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Library Settings'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('tmdb-token')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tmdb-token')).hitTestable(), findsOneWidget);
      expect(find.text('TMDB Read Access Token'), findsOneWidget);
      expect(
        find.text(
          'Local grouping is active. Connect TMDB for online matching.',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('tmdb-token')))
            .obscureText,
        isTrue,
      );

      await tester.ensureVisible(find.text('Metadata credits'));
      await tester.pumpAndSettle();
      expect(find.text('Metadata credits').hitTestable(), findsOneWidget);
      final logo = find.byWidgetPredicate(
        (widget) =>
            widget is Image && widget.semanticLabel == 'The Movie Database',
      );
      expect(logo, findsOneWidget);
      await tester.ensureVisible(
        find.text(
          'This product uses the TMDB API but is not endorsed or certified by TMDB.',
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find
            .text(
              'This product uses the TMDB API but is not endorsed or certified by TMDB.',
            )
            .hitTestable(),
        findsOneWidget,
      );
      expect(find.text('https://www.themoviedb.org'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('title-only episode stays visible under its season on mobile', (
    tester,
  ) async {
    await _mobile(tester);
    _localPreferences();
    await tester.pumpWidget(
      screens.app(
        fixtures.filesAvailableState.copyWith(
          entries: [files.file('My Show/Season 1/Hard Times.mp4')],
          videoCount: 1,
          discoveredCount: 1,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _openOnlyTitle(tester);
    await tester.scrollUntilVisible(
      find.byType(EpisodeCard).hitTestable(),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Season 1'), findsOneWidget);
    expect(find.text('Hard Times'), findsOneWidget);
    expect(find.text('S01 · Episode unidentified'), findsOneWidget);
    expect(find.text('Episode identification needs review'), findsOneWidget);
    final card = tester.widget<EpisodeCard>(find.byType(EpisodeCard));
    expect(card.video.episode, isNull);
    expect(card.video.season, 1);
    expect(card.video.needsReview, isTrue);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.byKey(const Key('refresh-tv-artwork')).hitTestable(),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('refresh-tv-artwork')));
    await tester.pumpAndSettle();
    expect(find.text('Current artwork'), findsOneWidget);
    expect(
      find.text('Enable TMDB in Library Settings to refresh artwork.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Keep current'));
    await tester.pumpAndSettle();
    expect(find.byType(CatalogDetail), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final cachedMatch in [false, true]) {
    testWidgets(
      'review action opens local matching guidance with cached match $cachedMatch',
      (tester) async {
        await _mobile(tester);
        final cacheKey = jsonEncode([
          fixtures.testRoot.locator.opaqueValue,
          'provider|video',
        ]);
        _localPreferences(
          preferences: {
            if (cachedMatch)
              'titleMatches': {
                cacheKey: {
                  'id': '999',
                  'name': 'The Matched Movie',
                  'year': 2020,
                  'manual': true,
                  'episodes': [],
                },
              },
          },
        );
        await tester.pumpWidget(screens.app(fixtures.filesAvailableState));
        await tester.pumpAndSettle();
        await _openOnlyTitle(tester);

        await tester.ensureVisible(find.text('Review match'));
        await tester.pumpAndSettle();
        expect(
          find.text(cachedMatch ? 'TMDB · Confirmed by you' : 'Local grouping'),
          findsOneWidget,
        );
        await tester.tap(find.text('Review match'));
        await tester.pumpAndSettle();

        expect(
          find.text('Review ${cachedMatch ? 'The Matched Movie' : 'Movie'}'),
          findsOneWidget,
        );
        expect(
          find.text(
            'Enable TMDB in Library Settings to search for title matches.',
          ),
          findsOneWidget,
        );
        expect(find.text('Use local names'), findsOneWidget);
        expect(find.text('Search another title'), findsNothing);
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Use local names'));
        await tester.pumpAndSettle();
        expect(find.text('Local grouping'), findsOneWidget);
        expect(find.text('Use local names'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
