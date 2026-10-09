import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_cinema/features/catalog/catalog_discovery_worker.dart';
import 'package:pocket_cinema/features/catalog/catalog_library.dart';
import 'package:pocket_cinema/features/catalog/catalog_metadata.dart';
import 'package:pocket_cinema/features/catalog/catalog_metadata_settings.dart';
import 'package:pocket_cinema/features/risk_spike/risk_spike_screen.dart';

import '../../support/catalog_discovery.dart';
import '../risk_spike/risk_spike_screen_test.dart' as fixtures;
import 'catalog_library_test.dart' as files;
import 'catalog_screen_test.dart' as screens;

class _MetadataSource implements CatalogMetadataSource {
  final searches = <String>[];

  @override
  Future<List<CatalogMetadataCandidate>> search({
    required String title,
    required CatalogMediaKind kind,
    int? year,
  }) async {
    searches.add(title);
    return const [];
  }

  @override
  Future<List<CatalogEpisodeMetadata>> episodes({
    required String providerId,
    required int season,
  }) async => const [];

  @override
  void dispose() {}
}

Future<void> _surface(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetViewInsets);
}

Future<void> _keyboard(WidgetTester tester, double height) async {
  tester.view.viewInsets = FakeViewPadding(bottom: height);
  await tester.pumpAndSettle();
}

void _expectVisibleAboveKeyboard(WidgetTester tester, Finder input) {
  final rectangle = tester.getRect(input);
  final view = tester.view;
  final keyboardTop =
      (view.physicalSize.height - view.viewInsets.bottom) /
      view.devicePixelRatio;
  expect(rectangle.top, greaterThanOrEqualTo(0));
  expect(rectangle.bottom, lessThanOrEqualTo(keyboardTop));
  expect(input.hitTestable(), findsOneWidget);
  expect(tester.takeException(), isNull);
}

EditableText _editable(WidgetTester tester, Finder input) =>
    tester.widget<EditableText>(
      find.descendant(of: input, matching: find.byType(EditableText)),
    );

Future<CatalogLibrary> _openReview(
  WidgetTester tester,
  _MetadataSource source, {
  int localCount = 1,
}) async {
  final fixture = fixtures.testApp(
    state: fixtures.filesAvailableState.copyWith(
      entries: [
        for (var index = 0; index < localCount; index++)
          files.file('Movies/Movie $index (2020).mp4'),
      ],
      videoCount: localCount,
      discoveredCount: localCount,
    ),
  ) as MaterialApp;
  final controller =
      ((fixture.home! as MediaQuery).child as RiskSpikeScreen).controller;
  final library = CatalogLibrary(
    controller,
    metadataSource: source,
    discoveryWorker: (request) async {
      final local = request.entries == null
          ? request.localTitles
          : groupCatalog(request.entries!);
      return CatalogDiscoveryResult(
        localTitles: local,
        titles: request.matching.apply(local, request.scope),
        workerIsolateName: null,
      );
    },
  );
  await library.load();
  await library.waitForDiscovery();
  await library.matcher.idle;
  addTearDown(() {
    library.dispose();
    controller.dispose();
  });
  final locals = library.localTitles;
  final displayed = CatalogTitle(
    id: 'reviewed-title',
    name: 'Movie',
    videos: [for (final local in locals) ...local.videos],
    localIds: [for (final local in locals) local.id],
  );
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                unawaited(reviewCatalogMatch(context, library, displayed)),
            child: const Text('Open review'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open review'));
  await tester.pumpAndSettle();
  source.searches.clear();
  return library;
}

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

  for (final scenario in [
    (
      name: 'tablet portrait',
      size: const Size(800, 1280),
      keyboardHeights: [480.0, 560.0, 400.0, 0.0],
    ),
    (
      name: 'phone portrait',
      size: const Size(390, 844),
      keyboardHeights: [320.0, 380.0, 240.0, 0.0],
    ),
    (
      name: 'short landscape',
      size: const Size(844, 412),
      keyboardHeights: [180.0, 230.0, 150.0, 0.0],
    ),
  ]) {
    testWidgets(
      'review search stays visible as keyboard changes on ${scenario.name}',
      (tester) async {
        await _surface(tester, scenario.size);
        final source = _MetadataSource();
        await _openReview(tester, source);
        final input = find.byType(TextField);
        await tester.ensureVisible(input);
        await tester.pumpAndSettle();
        await tester.tap(input);
        await tester.pump();
        expect(_editable(tester, input).focusNode.hasFocus, isTrue);

        await _keyboard(tester, scenario.keyboardHeights.first);
        _expectVisibleAboveKeyboard(tester, input);
        await tester.enterText(input, 'Another movie');
        for (final height in scenario.keyboardHeights.skip(1)) {
          await _keyboard(tester, height);
          _expectVisibleAboveKeyboard(tester, input);
          expect(_editable(tester, input).focusNode.hasFocus, isTrue);
          expect(_editable(tester, input).controller.text, 'Another movie');
        }

        await _keyboard(tester, scenario.keyboardHeights.first);
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pumpAndSettle();
        expect(source.searches, ['Another movie']);
        expect(_editable(tester, input).controller.text, 'Another movie');
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('review keeps a later merged title input above the keyboard', (
    tester,
  ) async {
    await _surface(tester, const Size(390, 844));
    final source = _MetadataSource();
    final library = await _openReview(tester, source, localCount: 5);
    final input = find.byKey(
      ValueKey('review-match-search-${library.localTitles.last.id}'),
    );
    await tester.scrollUntilVisible(
      input,
      200,
      scrollable: find
          .descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(input);
    await tester.pump();

    await _keyboard(tester, 320);
    _expectVisibleAboveKeyboard(tester, input);
    await tester.enterText(input, 'Last alias');
    await _keyboard(tester, 380);
    _expectVisibleAboveKeyboard(tester, input);
    expect(_editable(tester, input).focusNode.hasFocus, isTrue);
    expect(_editable(tester, input).controller.text, 'Last alias');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(source.searches, ['Last alias']);
  });

  testWidgets('settings token stays visible when the keyboard opens', (
    tester,
  ) async {
    await _surface(tester, const Size(800, 1280));
    await tester.pumpWidget(screens.app(fixtures.filesAvailableState));
    await settleCatalog(tester);
    await tester.tap(find.text('Settings'));
    await settleCatalog(tester);
    final input = find.byKey(const Key('tmdb-token'));
    await tester.scrollUntilVisible(
      input,
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('library-settings-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(input);
    await tester.pump();

    await _keyboard(tester, 480);
    _expectVisibleAboveKeyboard(tester, input);
    await tester.enterText(input, 'test token');
    await _keyboard(tester, 560);
    _expectVisibleAboveKeyboard(tester, input);
    expect(_editable(tester, input).focusNode.hasFocus, isTrue);
    expect(_editable(tester, input).controller.text, 'test token');
  });
}
