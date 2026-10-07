import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_cinema/features/catalog/catalog_artwork_picker.dart';
import 'package:pocket_cinema/features/catalog/catalog_library.dart';
import 'package:pocket_cinema/features/catalog/catalog_metadata.dart';
import 'package:pocket_cinema/features/risk_spike/risk_spike_screen.dart';

import '../risk_spike/risk_spike_screen_test.dart' as fixtures;
import 'catalog_library_test.dart' as files;

const poster = CatalogArtworkCandidate(
  kind: CatalogArtworkKind.poster,
  filePath: '/poster.jpg',
  width: 1000,
  height: 1500,
  language: 'en',
);
const backdrop = CatalogArtworkCandidate(
  kind: CatalogArtworkKind.backdrop,
  filePath: '/backdrop.jpg',
  width: 1920,
  height: 1080,
);

class _MetadataSource implements CatalogMetadataSource {
  @override
  Future<List<CatalogMetadataCandidate>> search({
    required String title,
    required CatalogMediaKind kind,
    int? year,
  }) async => const [];

  @override
  Future<List<CatalogEpisodeMetadata>> episodes({
    required String providerId,
    required int season,
  }) async => const [];

  @override
  void dispose() {}
}

class _PickerLibrary extends CatalogLibrary {
  _PickerLibrary(super.controller, {required bool enabled})
    : super(metadataSource: enabled ? _MetadataSource() : null);

  int refreshes = 0;
  int saveAttempts = 0;
  bool fetchFails = false;
  bool saveFails = false;
  Completer<void>? saveCompletion;
  CatalogArtworkCandidate? applied;
  List<CatalogArtworkCandidate> candidates = const [poster, backdrop];
  final thumbnailRequests = <bool>[];
  final current = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==',
  );

  @override
  Future<Uint8List?> thumbnail(
    CatalogVideo video, {
    bool backdrop = false,
  }) async {
    thumbnailRequests.add(backdrop);
    return current;
  }

  @override
  Future<List<CatalogArtworkCandidate>> refreshArtwork(
    CatalogTitle title,
  ) async {
    refreshes++;
    if (fetchFails) {
      throw const CatalogMetadataException('TMDB is offline. Try again.');
    }
    return candidates;
  }

  @override
  Future<void> selectArtwork(
    CatalogTitle title,
    CatalogArtworkCandidate candidate,
  ) async {
    saveAttempts++;
    if (saveFails) {
      throw const CatalogMetadataException(
        'The image could not be saved. Your current artwork is still in use.',
      );
    }
    await saveCompletion?.future;
    applied = candidate;
  }
}

CatalogTitle _title({bool matched = true}) => CatalogTitle(
  id: 'series:my show',
  name: 'My Show',
  isSeries: true,
  localIds: const ['series:my show'],
  providerId: matched ? '42' : null,
  videos: [CatalogVideo(files.file('My Show/Season 1/S01E01.Start.mp4'))],
);

Future<_PickerLibrary> _library({bool enabled = true}) async {
  final app =
      fixtures.testApp(state: fixtures.filesAvailableState) as MaterialApp;
  final controller =
      ((app.home! as MediaQuery).child as RiskSpikeScreen).controller;
  final library = _PickerLibrary(controller, enabled: enabled);
  await library.load();
  addTearDown(() {
    library.dispose();
    controller.dispose();
  });
  return library;
}

Future<void> _open(
  WidgetTester tester,
  _PickerLibrary library, {
  bool matched = true,
  VoidCallback? onReviewMatch,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => openCatalogArtworkPicker(
              context,
              library,
              _title(matched: matched),
              onReviewMatch: onReviewMatch,
            ),
            child: const Text('Open artwork'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open artwork'));
  await tester.pumpAndSettle();
}

Future<void> _select(WidgetTester tester, CatalogArtworkKind kind) async {
  if (kind == CatalogArtworkKind.backdrop) {
    await _switchKind(tester, kind);
  }
  final option = find.byKey(Key('artwork-candidate-${kind.name}-0'));
  await tester.ensureVisible(option);
  await tester.pumpAndSettle();
  await tester.tap(option);
  await tester.pumpAndSettle();
}

Future<void> _switchKind(WidgetTester tester, CatalogArtworkKind kind) async {
  final chip = find.byKey(Key('artwork-kind-${kind.name}'));
  await tester.ensureVisible(chip);
  await tester.pumpAndSettle();
  await tester.tap(chip);
  await tester.pumpAndSettle();
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

  testWidgets('fetch, selection and cancellation retain current artwork', (
    tester,
  ) async {
    final library = await _library();
    await _open(tester, library);
    expect(library.refreshes, 1);
    expect(find.text('Current artwork'), findsOneWidget);
    expect(find.text('Selected artwork'), findsOneWidget);
    expect(library.applied, isNull);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('artwork-use-selected')))
          .onPressed,
      isNull,
    );

    await _select(tester, CatalogArtworkKind.poster);
    expect(find.text('1000 × 1500 · en'), findsOneWidget);
    expect(library.saveAttempts, 0);
    await tester.tap(find.text('Keep current'));
    await tester.pumpAndSettle();
    expect(find.byType(CatalogArtworkPicker), findsNothing);
    expect(library.applied, isNull);
    expect(library.saveAttempts, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected artwork is saved before the picker closes', (
    tester,
  ) async {
    final library = await _library();
    library.saveCompletion = Completer<void>();
    await _open(tester, library);
    await _select(tester, CatalogArtworkKind.poster);
    await tester.tap(find.text('Use selected'));
    await tester.pump();
    expect(find.text('Saving…'), findsOneWidget);
    expect(find.byType(CatalogArtworkPicker), findsOneWidget);
    expect(library.applied, isNull);

    library.saveCompletion!.complete();
    await tester.pumpAndSettle();
    expect(library.applied, same(poster));
    expect(library.saveAttempts, 1);
    expect(find.byType(CatalogArtworkPicker), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'download failure retains selection and current image for retry',
    (tester) async {
      final library = await _library();
      library.saveFails = true;
      await _open(tester, library);
      await _select(tester, CatalogArtworkKind.poster);
      await tester.tap(find.text('Use selected'));
      await tester.pumpAndSettle();
      expect(find.byType(CatalogArtworkPicker), findsOneWidget);
      expect(
        find.text(
          'The image could not be saved. Your current artwork is still in use.',
        ),
        findsOneWidget,
      );
      expect(library.applied, isNull);

      library.saveFails = false;
      await tester.tap(find.text('Use selected'));
      await tester.pumpAndSettle();
      expect(library.applied, same(poster));
      expect(library.saveAttempts, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('offline fetch can retry and refresh again without replacement', (
    tester,
  ) async {
    final library = await _library();
    library.fetchFails = true;
    await _open(tester, library);
    expect(find.text('TMDB is offline. Try again.'), findsOneWidget);
    expect(library.applied, isNull);
    library.fetchFails = false;
    await tester.ensureVisible(find.text('Retry'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(library.refreshes, 2);
    expect(find.text('1 posters from TMDB'), findsOneWidget);
    expect(find.text('TMDB is offline. Try again.'), findsNothing);
    await _select(tester, CatalogArtworkKind.poster);
    await tester.ensureVisible(find.text('Refresh again'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Refresh again'));
    await tester.pumpAndSettle();
    expect(library.refreshes, 3);
    expect(library.applied, isNull);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('artwork-use-selected')))
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'poster and backdrop compare independently and use the chosen type',
    (tester) async {
      final library = await _library();
      await _open(tester, library);
      await _select(tester, CatalogArtworkKind.poster);
      await _select(tester, CatalogArtworkKind.backdrop);
      expect(find.text('1 backdrops from TMDB'), findsOneWidget);
      expect(find.text('1920 × 1080 · No language'), findsOneWidget);
      expect(find.byKey(const Key('artwork-current-backdrop')), findsOneWidget);
      expect(library.thumbnailRequests, [false, true]);
    await _switchKind(tester, CatalogArtworkKind.poster);
      expect(find.text('1000 × 1500 · en'), findsOneWidget);
    await _switchKind(tester, CatalogArtworkKind.backdrop);
      await tester.tap(find.text('Use selected'));
      await tester.pumpAndSettle();
      expect(library.applied, same(backdrop));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('disabled TMDB shows settings guidance without an API fetch', (
    tester,
  ) async {
    final library = await _library(enabled: false);
    await _open(tester, library);
    expect(
      find.text('Enable TMDB in Library Settings to refresh artwork.'),
      findsOneWidget,
    );
    expect(library.refreshes, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing TMDB match offers review before an API fetch', (
    tester,
  ) async {
    final library = await _library();
    var reviewed = false;
    await _open(
      tester,
      library,
      matched: false,
      onReviewMatch: () => reviewed = true,
    );
    expect(
      find.text('Choose a TMDB match for this show before refreshing artwork.'),
      findsOneWidget,
    );
    expect(library.refreshes, 0);
    await tester.ensureVisible(find.text('Review match'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review match'));
    await tester.pumpAndSettle();
    expect(reviewed, isTrue);
    expect(find.byType(CatalogArtworkPicker), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty artwork is explained and narrow layout remains usable', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final library = await _library();
    library.candidates = const [];
    await _open(tester, library);
    await tester.ensureVisible(
      find.text(
        'TMDB has no posters for this show. Your current artwork is still in use.',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Keep current').hitTestable(), findsOneWidget);
    expect(find.text('Use selected').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Keep current'));
    await tester.pumpAndSettle();
    expect(library.applied, isNull);
  });
}
