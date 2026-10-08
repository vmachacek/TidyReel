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

const _previewPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==';

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
  bool frameFails = false;
  Completer<void>? saveCompletion;
  CatalogArtworkCandidate? applied;
  CatalogArtworkFrame? appliedFrame;
  CatalogArtworkKind? appliedFrameKind;
  List<CatalogArtworkCandidate> candidates = const [poster, backdrop];
  final thumbnailRequests = <bool>[];
  final frameRequests = <Duration>[];
  final pendingFrames = <Duration, Completer<void>>{};
  int activeCaptures = 0;
  int maximumActiveCaptures = 0;
  final current = base64Decode(_previewPng);

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

  @override
  Future<CatalogArtworkFrame> videoArtworkFrame(
    CatalogTitle title,
    Duration position,
  ) async {
    frameRequests.add(position);
    activeCaptures++;
    if (activeCaptures > maximumActiveCaptures) {
      maximumActiveCaptures = activeCaptures;
    }
    try {
      await pendingFrames[position]?.future;
      if (frameFails) {
        throw const CatalogMetadataException(
          'The video frame could not be read.',
        );
      }
      return await super.videoArtworkFrame(title, position);
    } finally {
      activeCaptures--;
    }
  }

  @override
  Future<void> selectVideoArtwork(
    CatalogTitle title,
    CatalogArtworkKind kind,
    CatalogArtworkFrame frame,
  ) async {
    saveAttempts++;
    if (saveFails) {
      throw const CatalogMetadataException(
        'The screenshot could not be saved. Your current artwork is still in use.',
      );
    }
    await saveCompletion?.future;
    appliedFrame = frame;
    appliedFrameKind = kind;
  }
}

CatalogTitle _title({bool matched = true, bool hasFirstEpisode = true}) =>
    CatalogTitle(
      id: 'series:my show',
      name: 'My Show',
      isSeries: true,
      localIds: const ['series:my show'],
      providerId: matched ? '42' : null,
      videos: [
        CatalogVideo(
          files.file(
            hasFirstEpisode
                ? 'My Show/Season 1/S01E01.Start.mp4'
                : 'My Show/Season 1/S01E02.Next.mp4',
          ),
        ),
      ],
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
  bool hasFirstEpisode = true,
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
              _title(matched: matched, hasFirstEpisode: hasFirstEpisode),
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
  await _reveal(tester, option);
  await tester.pumpAndSettle();
  await tester.tap(option);
  await tester.pumpAndSettle();
}

Future<void> _switchKind(WidgetTester tester, CatalogArtworkKind kind) async {
  final chip = find.byKey(Key('artwork-kind-${kind.name}'));
  await _reveal(tester, chip, delta: -200);
  await tester.pumpAndSettle();
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

Future<void> _switchSource(WidgetTester tester, String source) async {
  final chip = find.byKey(Key('artwork-source-$source'));
  await _reveal(tester, chip, delta: -200);
  await tester.pumpAndSettle();
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

Future<void> _switchRange(
  WidgetTester tester,
  String range, {
  bool settle = true,
}) async {
  final chip = find.byKey(Key('artwork-range-$range'));
  await _reveal(tester, chip);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
  await tester.tap(chip);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> _reveal(
  WidgetTester tester,
  Finder target, {
  double delta = 200,
}) async {
  if (target.evaluate().isEmpty) {
    final scrollable = find
        .descendant(
          of: find.byKey(const Key('artwork-screen')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(target, delta, scrollable: scrollable);
  }
  await tester.ensureVisible(target);
}

FilledButton _saveButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(const Key('artwork-use-selected')));

Slider _slider(WidgetTester tester) =>
    tester.widget<Slider>(find.byKey(const Key('artwork-video-slider')));

void main() {
  var videoDurationMs = 120000;
  setUp(() {
    videoDurationMs = 120000;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(CatalogLibrary.channel, (call) async {
          if (call.method == 'loadPreferences') return '{}';
          if (call.method == 'videoFrame') {
            final arguments = call.arguments as Map;
            return {
              'bytes': base64Decode(_previewPng),
              'durationMs': videoDurationMs,
              'positionMs': arguments['positionMs'],
            };
          }
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(CatalogLibrary.channel, null);
  });

  testWidgets('artwork opens as a dedicated screen with back navigation', (
    tester,
  ) async {
    final library = await _library();
    await _open(tester, library);

    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(AppBar), findsOneWidget);
    expect(
      tester.getSize(find.byType(CatalogArtworkPicker)),
      tester.view.physicalSize / tester.view.devicePixelRatio,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(CatalogArtworkPicker), findsNothing);
    expect(find.text('Open artwork'), findsOneWidget);
    expect(library.saveAttempts, 0);
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
    await _reveal(tester, find.text('TMDB is offline. Try again.'));
    await tester.pumpAndSettle();
    expect(find.text('TMDB is offline. Try again.'), findsOneWidget);
    expect(library.applied, isNull);
    library.fetchFails = false;
    await _reveal(tester, find.text('Retry'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(library.refreshes, 2);
    expect(find.text('1 posters from TMDB'), findsOneWidget);
    expect(find.text('TMDB is offline. Try again.'), findsNothing);
    await _select(tester, CatalogArtworkKind.poster);
    await _reveal(tester, find.text('Refresh again'));
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
    await _switchSource(tester, 'tmdb');
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
    await _switchSource(tester, 'tmdb');
    expect(
      find.text('Choose a TMDB match for this show before refreshing artwork.'),
      findsOneWidget,
    );
    expect(library.refreshes, 0);
    await _reveal(tester, find.text('Review match'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review match'));
    await tester.pumpAndSettle();
    expect(reviewed, isTrue);
    expect(find.byType(CatalogArtworkPicker), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('offline screenshot seeks on release and saves the chosen type', (
    tester,
  ) async {
    final library = await _library(enabled: false);
    library.saveCompletion = Completer<void>();
    await _open(tester, library, matched: false);
    expect(library.refreshes, 0);
    expect(library.frameRequests, [Duration.zero]);
    expect(find.byKey(const Key('artwork-video-preview')), findsOneWidget);
    expect(library.saveAttempts, 0);

    await _switchKind(tester, CatalogArtworkKind.backdrop);
    final sliderFinder = find.byKey(const Key('artwork-video-slider'));
    await _reveal(tester, sliderFinder);
    await tester.pumpAndSettle();
    const seekValue = 45000.0;
    _slider(tester).onChanged!(seekValue);
    await tester.pump();
    expect(library.frameRequests, [Duration.zero]);
    expect(find.byKey(const Key('artwork-video-preview')), findsNothing);
    expect(_saveButton(tester).onPressed, isNull);

    _slider(tester).onChangeEnd!(seekValue);
    await tester.pumpAndSettle();
    expect(library.frameRequests, [Duration.zero, const Duration(seconds: 45)]);
    expect(find.byKey(const Key('artwork-video-preview')), findsOneWidget);
    expect(_saveButton(tester).onPressed, isNotNull);
    expect(library.saveAttempts, 0);
    await tester.tap(find.text('Use screenshot'));
    await tester.pump();
    expect(find.text('Saving…'), findsOneWidget);
    expect(find.byType(CatalogArtworkPicker), findsOneWidget);
    expect(library.appliedFrame, isNull);

    library.saveCompletion!.complete();
    await tester.pumpAndSettle();
    expect(library.appliedFrameKind, CatalogArtworkKind.backdrop);
    expect(library.appliedFrame!.position, const Duration(seconds: 45));
    expect(library.saveAttempts, 1);
    expect(find.byType(CatalogArtworkPicker), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('screenshot slider starts with the first minute selected', (
    tester,
  ) async {
    final library = await _library(enabled: false);
    await _open(tester, library, matched: false);
    await _reveal(tester, find.byKey(const Key('artwork-range-start')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const Key('artwork-range-start')))
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const Key('artwork-range-whole')))
          .selected,
      isFalse,
    );
    expect(find.text('Start (first minute)'), findsOneWidget);
    expect(find.text('Whole video'), findsOneWidget);
    expect(_slider(tester).max, 60000);
    expect(find.text('1:00'), findsOneWidget);
    expect(library.frameRequests, [Duration.zero]);
    expect(library.saveAttempts, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'whole video preserves a selected frame and allows a later save',
    (tester) async {
      final library = await _library(enabled: false);
      await _open(tester, library, matched: false);
      await _reveal(tester, find.byKey(const Key('artwork-video-slider')));
      await tester.pumpAndSettle();
      _slider(tester).onChanged!(45000);
      _slider(tester).onChangeEnd!(45000);
      await tester.pumpAndSettle();

      await _switchRange(tester, 'whole');
      expect(_slider(tester).max, 119999);
      expect(_slider(tester).value, 45000);
      expect(_saveButton(tester).onPressed, isNotNull);
      expect(library.frameRequests, [
        Duration.zero,
        const Duration(seconds: 45),
      ]);
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(const Key('artwork-range-whole')))
            .selected,
        isTrue,
      );

      _slider(tester).onChanged!(90000);
      _slider(tester).onChangeEnd!(90000);
      await tester.pumpAndSettle();
      expect(library.saveAttempts, 0);
      await tester.tap(find.text('Use screenshot'));
      await tester.pumpAndSettle();
      expect(library.appliedFrame!.position, const Duration(seconds: 90));
      expect(library.saveAttempts, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'returning to Start recaptures a frame at the first minute limit',
    (tester) async {
      final library = await _library(enabled: false);
      await _open(tester, library, matched: false);
      await _switchRange(tester, 'whole');
      _slider(tester).onChanged!(90000);
      _slider(tester).onChangeEnd!(90000);
      await tester.pumpAndSettle();
      final clampedFrame = Completer<void>();
      library.pendingFrames[const Duration(seconds: 60)] = clampedFrame;

      await _switchRange(tester, 'start', settle: false);
      expect(_slider(tester).max, 60000);
      expect(_slider(tester).value, 60000);
      expect(find.byKey(const Key('artwork-video-preview')), findsNothing);
      expect(_saveButton(tester).onPressed, isNull);
      expect(library.frameRequests, [
        Duration.zero,
        const Duration(seconds: 90),
        const Duration(seconds: 60),
      ]);

      clampedFrame.complete();
      await tester.pumpAndSettle();
      expect(_saveButton(tester).onPressed, isNotNull);
      expect(library.saveAttempts, 0);
      await tester.tap(find.text('Use screenshot'));
      await tester.pumpAndSettle();
      expect(library.appliedFrame!.position, const Duration(seconds: 60));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Start queues its clamped frame when a later capture is running',
    (tester) async {
      final library = await _library(enabled: false);
      await _open(tester, library, matched: false);
      await _switchRange(tester, 'whole');
      final oldFrame = Completer<void>();
      final clampedFrame = Completer<void>();
      library.pendingFrames[const Duration(seconds: 90)] = oldFrame;
      library.pendingFrames[const Duration(seconds: 60)] = clampedFrame;
      _slider(tester).onChanged!(90000);
      _slider(tester).onChangeEnd!(90000);
      await tester.pump();

      await _switchRange(tester, 'start', settle: false);
      expect(_slider(tester).max, 60000);
      expect(_slider(tester).value, 60000);
      expect(library.frameRequests, [
        Duration.zero,
        const Duration(seconds: 90),
      ]);
      oldFrame.complete();
      await tester.pump();
      expect(library.frameRequests, [
        Duration.zero,
        const Duration(seconds: 90),
        const Duration(seconds: 60),
      ]);
      expect(find.byKey(const Key('artwork-video-preview')), findsNothing);
      expect(_saveButton(tester).onPressed, isNull);
      expect(library.maximumActiveCaptures, 1);

      clampedFrame.complete();
      await tester.pumpAndSettle();
      expect(_slider(tester).value, 60000);
      expect(library.saveAttempts, 0);
      await tester.tap(find.text('Use screenshot'));
      await tester.pumpAndSettle();
      expect(library.appliedFrame!.position, const Duration(seconds: 60));
      expect(library.saveAttempts, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('short videos keep both ranges within the available duration', (
    tester,
  ) async {
    videoDurationMs = 30000;
    final library = await _library(enabled: false);
    await _open(tester, library, matched: false);
    await _reveal(tester, find.byKey(const Key('artwork-video-slider')));
    await tester.pumpAndSettle();
    expect(_slider(tester).max, 29999);
    expect(find.text('0:30'), findsOneWidget);

    await _switchRange(tester, 'whole');
    expect(_slider(tester).max, 29999);
    _slider(tester).onChanged!(_slider(tester).max);
    _slider(tester).onChangeEnd!(_slider(tester).max);
    await tester.pumpAndSettle();
    await _switchRange(tester, 'start');
    expect(_slider(tester).max, 29999);
    expect(_slider(tester).value, 29999);
    expect(library.frameRequests, [
      Duration.zero,
      const Duration(milliseconds: 29999),
    ]);
    expect(_saveButton(tester).onPressed, isNotNull);
    expect(library.saveAttempts, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'moving again rejects a frame captured for the previous position',
    (tester) async {
      final library = await _library(enabled: false);
      await _open(tester, library, matched: false);
      await _switchRange(tester, 'whole');
      await _reveal(tester, find.byKey(const Key('artwork-video-slider')));
      await tester.pumpAndSettle();
      final oldFrame = Completer<void>();
      library.pendingFrames[const Duration(seconds: 30)] = oldFrame;
      const firstValue = 30000.0;
      _slider(tester).onChanged!(firstValue);
      _slider(tester).onChangeEnd!(firstValue);
      await tester.pump();
      expect(library.frameRequests.last, const Duration(seconds: 30));

      const nextValue = 90000.0;
      _slider(tester).onChanged!(nextValue);
      await tester.pump();
      oldFrame.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('artwork-video-preview')), findsNothing);
      expect(_saveButton(tester).onPressed, isNull);
      expect(library.saveAttempts, 0);

      _slider(tester).onChangeEnd!(nextValue);
      await tester.pumpAndSettle();
      expect(library.frameRequests.last, const Duration(seconds: 90));
      await tester.tap(find.text('Use screenshot'));
      await tester.pumpAndSettle();
      expect(library.appliedFrame!.position, const Duration(seconds: 90));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('rapid releases queue only the latest screenshot position', (
    tester,
  ) async {
    final library = await _library(enabled: false);
    await _open(tester, library, matched: false);
    await _switchRange(tester, 'whole');
    await _reveal(tester, find.byKey(const Key('artwork-video-slider')));
    await tester.pumpAndSettle();
    final oldFrame = Completer<void>();
    final newFrame = Completer<void>();
    library.pendingFrames[const Duration(seconds: 30)] = oldFrame;
    library.pendingFrames[const Duration(seconds: 90)] = newFrame;

    const firstValue = 30000.0;
    _slider(tester).onChanged!(firstValue);
    _slider(tester).onChangeEnd!(firstValue);
    await tester.pump();
    const intermediateValue = 60000.0;
    _slider(tester).onChanged!(intermediateValue);
    _slider(tester).onChangeEnd!(intermediateValue);
    await tester.pump();
    const nextValue = 90000.0;
    _slider(tester).onChanged!(nextValue);
    _slider(tester).onChangeEnd!(nextValue);
    await tester.pump();
    expect(library.frameRequests, [Duration.zero, const Duration(seconds: 30)]);
    expect(library.maximumActiveCaptures, 1);
    oldFrame.complete();
    await tester.pump();
    expect(library.frameRequests, [
      Duration.zero,
      const Duration(seconds: 30),
      const Duration(seconds: 90),
    ]);
    expect(find.byKey(const Key('artwork-video-preview')), findsNothing);
    expect(_saveButton(tester).onPressed, isNull);
    expect(library.maximumActiveCaptures, 1);
    newFrame.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('artwork-video-preview')), findsOneWidget);
    await tester.tap(find.text('Use screenshot'));
    await tester.pumpAndSettle();
    expect(library.appliedFrame!.position, const Duration(seconds: 90));
    expect(library.saveAttempts, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed screenshot capture retries without changing artwork', (
    tester,
  ) async {
    final library = await _library(enabled: false);
    library.frameFails = true;
    await _open(tester, library, matched: false);
    await _reveal(tester, find.text('The video frame could not be read.'));
    await tester.pumpAndSettle();
    expect(find.text('The video frame could not be read.'), findsOneWidget);
    expect(_saveButton(tester).onPressed, isNull);
    expect(library.saveAttempts, 0);

    library.frameFails = false;
    final retry = find.byKey(const Key('artwork-video-retry'));
    await _reveal(tester, retry);
    await tester.pumpAndSettle();
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(library.frameRequests, [Duration.zero, Duration.zero]);
    expect(find.byKey(const Key('artwork-video-preview')), findsOneWidget);
    expect(_saveButton(tester).onPressed, isNotNull);
    expect(library.saveAttempts, 0);
    await tester.tap(find.text('Keep current'));
    await tester.pumpAndSettle();
    expect(library.appliedFrame, isNull);
    expect(library.saveAttempts, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed screenshot save retains the frame for retry', (
    tester,
  ) async {
    final library = await _library(enabled: false);
    library.saveFails = true;
    await _open(tester, library, matched: false);
    await tester.tap(find.text('Use screenshot'));
    await tester.pumpAndSettle();
    expect(find.byType(CatalogArtworkPicker), findsOneWidget);
    expect(
      find.text(
        'The screenshot could not be saved. Your current artwork is still in use.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('artwork-video-preview')), findsOneWidget);
    expect(library.appliedFrame, isNull);

    library.saveFails = false;
    await tester.tap(find.text('Use screenshot'));
    await tester.pumpAndSettle();
    expect(library.appliedFrame, isNotNull);
    expect(library.appliedFrameKind, CatalogArtworkKind.poster);
    expect(library.saveAttempts, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'missing first episode explains why screenshots are unavailable',
    (tester) async {
      final library = await _library();
      await _open(tester, library, hasFirstEpisode: false);
      await _switchSource(tester, 'video');
      expect(find.byKey(const Key('artwork-video-slider')), findsNothing);
      expect(find.byKey(const Key('artwork-video-preview')), findsNothing);
      expect(
        find.text(
          'S01E01 is not in this library. Add the first episode to capture a screenshot.',
        ),
        findsOneWidget,
      );
      expect(_saveButton(tester).onPressed, isNull);
      expect(library.frameRequests, isEmpty);
      expect(library.saveAttempts, 0);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [
    const Size(320, 568),
    const Size(640, 360),
    const Size(1024, 600),
  ]) {
    testWidgets('screenshot controls fit the artwork screen at $size', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final library = await _library(enabled: false);
      await _open(tester, library, matched: false);
      final slider = find.byKey(const Key('artwork-video-slider'));
      await _reveal(tester, slider);
      await tester.pumpAndSettle();
      expect(slider.hitTestable(), findsOneWidget);
      expect(find.text('Keep current').hitTestable(), findsOneWidget);
      expect(find.text('Use screenshot').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Keep current'));
      await tester.pumpAndSettle();
      expect(library.saveAttempts, 0);
    });
  }

  testWidgets('empty artwork is explained and narrow layout remains usable', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final library = await _library();
    library.candidates = const [];
    await _open(tester, library);
    await _reveal(
      tester,
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
