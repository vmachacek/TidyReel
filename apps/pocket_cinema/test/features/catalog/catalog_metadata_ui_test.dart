import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_cinema/features/catalog/catalog_library.dart';
import 'package:pocket_cinema/features/catalog/catalog_metadata.dart';
import 'package:pocket_cinema/features/catalog/catalog_screen.dart';

import '../../support/catalog_discovery.dart';
import '../risk_spike/risk_spike_screen_test.dart' as fixtures;
import 'catalog_library_test.dart' as files;
import 'catalog_screen_test.dart' as screens;

class _MetadataSource implements CatalogMetadataSource {
  final searches = <String>[];
  final searchKinds = <CatalogMediaKind>[];
  List<CatalogMetadataCandidate> found = const [];
  Completer<List<CatalogMetadataCandidate>>? pending;

  @override
  Future<List<CatalogMetadataCandidate>> search({
    required String title,
    required CatalogMediaKind kind,
    int? year,
  }) async {
    searches.add(title);
    searchKinds.add(kind);
    return pending?.future ?? found;
  }

  @override
  Future<List<CatalogEpisodeMetadata>> episodes({
    required String providerId,
    required int season,
  }) async => const [];

  @override
  void dispose() {}
}

Future<void> _mobile(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void _localPreferences({Map<String, Object?> preferences = const {}}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(CatalogLibrary.channel, (call) async {
        if (call.method == 'loadPreferences') return jsonEncode(preferences);
        // The tests use in-memory metadata sources and never expose a token.
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
    scrollable: screens.catalogScrollable,
  );
  await tester.tap(find.byType(PosterCard));
  await settleCatalog(tester);
  expect(find.byType(CatalogDetail), findsOneWidget);
}

Future<CatalogLibrary> _openOnlineReview(
  WidgetTester tester,
  _MetadataSource source,
) async {
  _localPreferences();
  await tester.pumpWidget(screens.app(fixtures.filesAvailableState));
  await settleCatalog(tester);
  final library = catalogLibrary(tester);
  library.matcher.configure(source);
  await settleCatalog(tester);
  await _openOnlyTitle(tester);
  await tester.ensureVisible(find.text('Review match'));
  await settleCatalog(tester);
  await tester.tap(find.text('Review match'));
  await settleCatalog(tester);
  source.searches.clear();
  source.searchKinds.clear();
  return library;
}

void main() {
  testWidgets(
    'mobile library settings expose token control and official credits',
    (tester) async {
      await _mobile(tester);
      _localPreferences();
      await tester.pumpWidget(screens.app(fixtures.filesAvailableState));
      await settleCatalog(tester);

      await tester.tap(find.text('Settings'));
      await settleCatalog(tester);
      expect(find.text('Library Settings'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('tmdb-token')));
      await settleCatalog(tester);
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
      await settleCatalog(tester);
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
      await settleCatalog(tester);
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
    await settleCatalog(tester);
    await _openOnlyTitle(tester);
    await tester.scrollUntilVisible(
      find.byType(EpisodeCard).hitTestable(),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await settleCatalog(tester);

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
    await settleCatalog(tester);
    await tester.tap(find.byKey(const Key('refresh-tv-artwork')));
    await settleCatalog(tester);
    expect(find.text('Current artwork'), findsOneWidget);
    expect(find.byKey(const Key('artwork-screen')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Enable TMDB in Library Settings to refresh artwork.'),
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('artwork-screen')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await settleCatalog(tester);
    expect(
      find.text('Enable TMDB in Library Settings to refresh artwork.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Keep current'));
    await settleCatalog(tester);
    expect(find.byType(CatalogDetail), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final enabled in [false, true]) {
    testWidgets('movie artwork action opens the picker with TMDB $enabled', (
      tester,
    ) async {
      await _mobile(tester);
      _localPreferences();
      await tester.pumpWidget(screens.app(fixtures.filesAvailableState));
      await settleCatalog(tester);
      if (enabled) {
        catalogLibrary(tester).matcher.configure(_MetadataSource());
        await settleCatalog(tester);
      }
      await _openOnlyTitle(tester);
      expect(
        tester.widget<CatalogDetail>(find.byType(CatalogDetail)).title.isSeries,
        isFalse,
      );
      final refresh = find.byKey(const Key('refresh-movie-artwork'));
      await tester.ensureVisible(refresh);
      await settleCatalog(tester);
      expect(refresh.hitTestable(), findsOneWidget);

      await tester.tap(refresh);
      await settleCatalog(tester);
      expect(find.byKey(const Key('artwork-screen')), findsOneWidget);
      expect(find.text('Current artwork'), findsOneWidget);
      expect(find.text('Movie screenshot'), findsOneWidget);
      expect(catalogLibrary(tester).matcher.enabled, enabled);

      await tester.tap(find.text('Keep current'));
      await settleCatalog(tester);
      expect(find.byType(CatalogDetail), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final size in [const Size(390, 844), const Size(1280, 800)]) {
    testWidgets('review submits a typed title with Search at $size', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final source = _MetadataSource();
      final library = await _openOnlineReview(tester, source);
      final local = library.localTitles.single;
      final input = find.byKey(ValueKey('review-match-search-${local.id}'));
      final submit = find.byKey(ValueKey('review-match-submit-${local.id}'));
      source.found = const [
        CatalogMetadataCandidate(
          providerId: '11303',
          name: 'Rebel Ridge',
          year: 2024,
        ),
      ];

      expect(find.text('Search').hitTestable(), findsOneWidget);
      await tester.enterText(input, '  Rebel Ridge  ');
      await tester.pumpAndSettle();
      expect(submit.hitTestable(), findsOneWidget);
      await tester.tap(submit);
      await settleCatalog(tester);

      expect(source.searches, ['Rebel Ridge']);
      expect(source.searchKinds, [CatalogMediaKind.movie]);
      expect(find.text('Rebel Ridge (2024)'), findsOneWidget);
      expect(
        tester.widget<TextField>(input).controller!.text,
        '  Rebel Ridge  ',
      );

      await tester.enterText(input, 'Rebel Ridge alternate');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await settleCatalog(tester);
      expect(source.searches, ['Rebel Ridge', 'Rebel Ridge alternate']);
      expect(
        tester.widget<TextField>(input).controller!.text,
        'Rebel Ridge alternate',
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'review keeps its query after scrolling through title candidates',
    (tester) async {
      await _mobile(tester);
      final source = _MetadataSource();
      final library = await _openOnlineReview(tester, source);
      final local = library.localTitles.single;
      final input = find.byKey(ValueKey('review-match-search-${local.id}'));
      final submit = find.byKey(ValueKey('review-match-submit-${local.id}'));
      final scrollable = find
          .descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(Scrollable),
          )
          .first;
      source.found = [
        for (var index = 0; index < 30; index++)
          CatalogMetadataCandidate(
            providerId: '$index',
            name: 'Title candidate $index',
          ),
      ];

      await tester.enterText(input, 'Rebel Ridge');
      await tester.pumpAndSettle();
      await tester.tap(submit);
      await settleCatalog(tester);
      expect(source.searches, ['Rebel Ridge']);

      await tester.scrollUntilVisible(
        find.text('Use local names').hitTestable(),
        300,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();
      expect(find.text('Use local names').hitTestable(), findsOneWidget);
      expect(input.hitTestable(), findsNothing);
      await tester.scrollUntilVisible(
        input.hitTestable(),
        -300,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();

      expect(tester.widget<TextField>(input).controller!.text, 'Rebel Ridge');
      expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
      await tester.tap(submit);
      await settleCatalog(tester);
      expect(source.searches, ['Rebel Ridge', 'Rebel Ridge']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'review Search ignores blank input and duplicate pending submits',
    (tester) async {
      await _mobile(tester);
      final source = _MetadataSource();
      final library = await _openOnlineReview(tester, source);
      final local = library.localTitles.single;
      final input = find.byKey(ValueKey('review-match-search-${local.id}'));
      final submit = find.byKey(ValueKey('review-match-submit-${local.id}'));

      expect(tester.widget<FilledButton>(submit).onPressed, isNull);
      await tester.enterText(input, '   ');
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(source.searches, isEmpty);

      final completion = Completer<List<CatalogMetadataCandidate>>();
      source.pending = completion;
      await tester.enterText(input, 'Rebel Ridge');
      await tester.pumpAndSettle();
      await tester.tap(submit);
      await tester.pump();
      expect(source.searches, ['Rebel Ridge']);
      expect(find.text('Searching…'), findsOneWidget);
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);
      expect(
        find.descendant(
          of: submit,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );

      await tester.enterText(input, 'Another title');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(source.searches, ['Rebel Ridge']);
      completion.complete(const []);
      await settleCatalog(tester);
      expect(find.text('Searching…'), findsNothing);
      expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
      expect(tester.widget<TextField>(input).controller!.text, 'Another title');
      expect(
        find.text('No title candidates yet. Enter a title and tap Search.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

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
        await settleCatalog(tester);
        await _openOnlyTitle(tester);

        await tester.ensureVisible(find.text('Review match'));
        await settleCatalog(tester);
        expect(
          find.text(cachedMatch ? 'TMDB · Confirmed by you' : 'Local grouping'),
          findsOneWidget,
        );
        await tester.tap(find.text('Review match'));
        await settleCatalog(tester);

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
        await settleCatalog(tester);
        expect(find.text('Local grouping'), findsOneWidget);
        expect(find.text('Use local names'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
