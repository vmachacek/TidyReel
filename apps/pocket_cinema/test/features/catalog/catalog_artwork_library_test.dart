import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_platform_storage/media_platform_storage.dart';
import 'package:pocket_cinema/features/catalog/catalog_library.dart';
import 'package:pocket_cinema/features/catalog/catalog_metadata.dart';

import 'catalog_library_test.dart' as files;
import 'catalog_metadata_preferences_test.dart' as fixtures;

const poster = CatalogArtworkCandidate(
  filePath: '/poster.jpg',
  kind: CatalogArtworkKind.poster,
  width: 1000,
  height: 1500,
);
const backdrop = CatalogArtworkCandidate(
  filePath: '/backdrop.jpg',
  kind: CatalogArtworkKind.backdrop,
  width: 1920,
  height: 1080,
);

class ArtworkSource extends fixtures.FakeMetadataSource
    implements CatalogArtworkSource {
  int refreshes = 0;
  int downloads = 0;
  Completer<Uint8List>? downloadGate;
  bool artworkOffline = false;

  @override
  Future<List<CatalogArtworkCandidate>> artwork({
    required String providerId,
  }) async {
    refreshes++;
    if (artworkOffline) {
      throw const CatalogMetadataException('Artwork unavailable.');
    }
    return [poster, backdrop];
  }

  @override
  Future<Uint8List> downloadArtwork(CatalogArtworkCandidate candidate) async {
    downloads++;
    if (artworkOffline) {
      throw const CatalogMetadataException('Download failed.');
    }
    return downloadGate == null
        ? Uint8List.fromList([
            candidate.kind == CatalogArtworkKind.poster ? 2 : 3,
          ])
        : downloadGate!.future;
  }
}

class ArtworkPreferences extends fixtures.NativePreferences {
  final artwork = <String, Uint8List>{};
  int saves = 0;
  bool failSave = false;
  bool failPreferences = false;
  bool failFrame = false;
  final frameRequests = <Map<dynamic, dynamic>>[];
  Uint8List frameBytes = Uint8List.fromList([4]);
  Completer<Object?>? frameGate;
  Completer<void>? saveGate;
  Completer<void>? savingStarted;
  Completer<String?>? metadataTokenGate;
  Completer<void>? metadataTokenReadStarted;

  Map<String, Object> frameResult(int positionMs) => {
    'bytes': frameBytes,
    'durationMs': 120000,
    'positionMs': positionMs.clamp(0, 119999),
  };

  @override
  Future<Object?> handle(MethodCall call) async {
    switch (call.method) {
      case 'loadMetadataToken':
        metadataTokenReadStarted?.complete();
        return metadataTokenGate == null
            ? super.handle(call)
            : metadataTokenGate!.future;
      case 'readArtwork':
        return artwork[(call.arguments as Map)['key']];
      case 'saveArtwork':
        if (failSave) throw PlatformException(code: 'ARTWORK_STORAGE_ERROR');
        saves++;
        final args = call.arguments as Map;
        artwork[args['key'] as String] = args['bytes'] as Uint8List;
        savingStarted?.complete();
        await saveGate?.future;
        return true;
      case 'videoFrame':
        final args = call.arguments as Map;
        frameRequests.add(Map<dynamic, dynamic>.from(args));
        if (failFrame) throw PlatformException(code: 'VIDEO_FRAME_ERROR');
        return frameGate == null
            ? frameResult(args['positionMs'] as int)
            : frameGate!.future;
      case 'thumbnail':
        return Uint8List.fromList([1]);
      case 'deleteArtwork':
        artwork.remove((call.arguments as Map)['key']);
        return true;
      case 'savePreferences':
        if (failPreferences) throw PlatformException(code: 'PREFERENCES_ERROR');
        return super.handle(call);
      default:
        return super.handle(call);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ArtworkPreferences preferences;
  late ArtworkSource source;
  late fixtures.LibraryFixture fixture;

  setUp(() async {
    preferences = ArtworkPreferences();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(CatalogLibrary.channel, preferences.handle);
    source = ArtworkSource();
    fixture = fixtures.LibraryFixture([
      files.file('Shows/My Show/Season 1/My.Show.S01E01.mp4'),
      files.file('Shows/My Show/Season 2/My.Show.S02E01.mp4'),
    ], source);
    await fixture.initialize();
    await fixture.library.matcher.select(
      fixture.library.localTitles.single,
      fixture.library.catalogScope,
      fixtures.firstCandidate,
    );
    await fixture.library.waitForDiscovery();
  });

  tearDown(() {
    fixture.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(CatalogLibrary.channel, null);
  });

  test('screenshot source selects S01E01 including a multi-episode file', () {
    final library = fixture.library;
    final title = groupCatalog([
      files.file('Selection Show/Season 0/Selection.Show.S00E01.mp4'),
      files.file('Selection Show/Season 1/Selection.Show.S01E02.mp4'),
      files.file('Selection Show/Season 2/Selection.Show.S02E01.mp4'),
      files.file('Selection Show/Season 1/Selection.Show.S01E01-E02.mp4'),
    ]).single;
    expect(
      library.artworkVideo(title)?.file.displayName,
      'Selection.Show.S01E01-E02.mp4',
    );
    final missing = groupCatalog([
      files.file('Missing Show/Season 1/Missing.Show.S01E02.mp4'),
      files.file('Missing Show/Season 2/Missing.Show.S02E01.mp4'),
    ]).single;
    expect(library.artworkVideo(missing), isNull);
    expect(
      library.artworkVideo(groupCatalog([files.file('Film.mp4')]).single),
      isNull,
    );
  });

  test(
    'frame preview works without TMDB or a match and sends the exact position',
    () async {
      final library = fixture.library;
      library.matcher.forget(
        library.currentTitles.single,
        library.catalogScope,
      );
      await library.waitForDiscovery();
      library.matcher.configure(null);
      final title = library.currentTitles.single;
      expect(title.providerId, isNull);
      final frame = await library.videoArtworkFrame(
        title,
        const Duration(milliseconds: 12345),
      );
      expect(frame.bytes, [4]);
      expect(frame.duration, const Duration(minutes: 2));
      expect(frame.position, const Duration(milliseconds: 12345));
      expect(preferences.frameRequests.single, {
        'treeUri': library.catalogScope,
        'storageKey': title.first.id,
        'positionMs': 12345,
      });
      expect(preferences.saves, 0);
      expect(source.refreshes, 0);
      expect(source.downloads, 0);
      expect(await library.thumbnail(title.first), [1]);
      await library.selectVideoArtwork(title, CatalogArtworkKind.poster, frame);
      expect(await library.thumbnail(title.videos.last), [4]);
    },
  );

  test(
    'frame preview clamps negative input and accepts the native clamped time',
    () async {
      final library = fixture.library;
      final title = library.currentTitles.single;
      final first = await library.videoArtworkFrame(
        title,
        const Duration(milliseconds: -1),
      );
      expect(preferences.frameRequests.last['positionMs'], 0);
      expect(first.position, Duration.zero);
      final last = await library.videoArtworkFrame(
        title,
        const Duration(minutes: 5),
      );
      expect(last.position, const Duration(milliseconds: 119999));
    },
  );

  test(
    'local screenshots do not wait for online metadata initialization',
    () async {
      preferences.metadataTokenGate = Completer<String?>();
      preferences.metadataTokenReadStarted = Completer<void>();
      final library = CatalogLibrary(fixture.controller);
      var fullyLoaded = false;
      unawaited(library.load().then((_) => fullyLoaded = true));
      try {
        await preferences.metadataTokenReadStarted!.future;
        await library.waitForDiscovery();
        final title = library.currentTitles.single;
        final frame = await library.videoArtworkFrame(
          title,
          const Duration(seconds: 20),
        );
        expect(fullyLoaded, isFalse);
        await library.selectVideoArtwork(
          title,
          CatalogArtworkKind.poster,
          frame,
        );
        expect(fullyLoaded, isFalse);
        expect(await library.thumbnail(title.first), [4]);
      } finally {
        preferences.metadataTokenGate!.complete(null);
        await library.load();
        library.dispose();
      }
    },
  );

  test(
    'screenshot poster and backdrop persist independently across restart',
    () async {
      final library = fixture.library;
      final title = library.currentTitles.single;
      final posterFrame = await library.videoArtworkFrame(title, Duration.zero);
      await library.selectVideoArtwork(
        title,
        CatalogArtworkKind.poster,
        posterFrame,
      );
      preferences.frameBytes = Uint8List.fromList([5]);
      final backdropFrame = await library.videoArtworkFrame(
        title,
        const Duration(seconds: 30),
      );
      await library.selectVideoArtwork(
        title,
        CatalogArtworkKind.backdrop,
        backdropFrame,
      );
      expect(await library.thumbnail(title.first), [4]);
      expect(await library.thumbnail(title.videos.last, backdrop: true), [5]);
      final entries = fixture.controller.state.entries;
      fixture.close();
      fixture = fixtures.LibraryFixture(
        entries,
        ArtworkSource()..offline = true,
      );
      await fixture.initialize();
      fixture.library.matcher.configure(null);
      final restored = fixture.library.currentTitles.single;
      expect(await fixture.library.thumbnail(restored.first), [4]);
      expect(await fixture.library.thumbnail(restored.first, backdrop: true), [
        5,
      ]);
      expect(preferences.artwork, hasLength(2));
    },
  );

  test(
    'failed screenshot save rolls back the previous durable choice',
    () async {
      final library = fixture.library;
      final title = library.currentTitles.single;
      final frame = await library.videoArtworkFrame(title, Duration.zero);
      await library.selectVideoArtwork(title, CatalogArtworkKind.poster, frame);
      preferences.frameBytes = Uint8List.fromList([5]);
      final replacement = await library.videoArtworkFrame(
        title,
        const Duration(seconds: 20),
      );
      preferences.failSave = true;
      await expectLater(
        library.selectVideoArtwork(
          title,
          CatalogArtworkKind.poster,
          replacement,
        ),
        throwsA(isA<CatalogMetadataException>()),
      );
      preferences.failSave = false;
      preferences.failPreferences = true;
      await expectLater(
        library.selectVideoArtwork(
          title,
          CatalogArtworkKind.poster,
          replacement,
        ),
        throwsA(isA<CatalogMetadataException>()),
      );
      expect(await library.thumbnail(title.first), [4]);
      expect(preferences.artwork.values.single, [4]);
      final entries = fixture.controller.state.entries;
      fixture.close();
      preferences.failPreferences = false;
      fixture = fixtures.LibraryFixture(
        entries,
        ArtworkSource()..offline = true,
      );
      await fixture.initialize();
      expect(
        await fixture.library.thumbnail(
          fixture.library.currentTitles.single.first,
        ),
        [4],
      );
    },
  );

  test(
    'missing or unreadable S01E01 cannot change the current artwork',
    () async {
      final library = fixture.library;
      final missing = groupCatalog([
        files.file('Missing Show/Season 1/Missing.Show.S01E02.mp4'),
      ]).single;
      await expectLater(
        library.videoArtworkFrame(missing, Duration.zero),
        throwsA(isA<CatalogMetadataException>()),
      );
      expect(preferences.frameRequests, isEmpty);
      preferences.failFrame = true;
      final title = library.currentTitles.single;
      await expectLater(
        library.videoArtworkFrame(title, Duration.zero),
        throwsA(isA<CatalogMetadataException>()),
      );
      expect(await library.thumbnail(title.first), [1]);
      expect(preferences.saves, 0);
    },
  );

  test('a changed title while extracting rejects the frame', () async {
    final library = fixture.library;
    final title = library.currentTitles.single;
    preferences.frameGate = Completer<Object?>();
    final rejected = expectLater(
      library.videoArtworkFrame(title, Duration.zero),
      throwsA(isA<CatalogMetadataException>()),
    );
    await Future<void>.delayed(Duration.zero);
    await library.matcher.select(
      library.localTitles.single,
      library.catalogScope,
      fixtures.secondCandidate,
    );
    preferences.frameGate!.complete(preferences.frameResult(0));
    await rejected;
    expect(preferences.saves, 0);
  });

  test('a changed title while saving deletes the pending screenshot', () async {
    final library = fixture.library;
    final title = library.currentTitles.single;
    final frame = await library.videoArtworkFrame(title, Duration.zero);
    preferences.saveGate = Completer<void>();
    preferences.savingStarted = Completer<void>();
    final rejected = expectLater(
      library.selectVideoArtwork(title, CatalogArtworkKind.poster, frame),
      throwsA(isA<CatalogMetadataException>()),
    );
    await preferences.savingStarted!.future;
    await library.matcher.select(
      library.localTitles.single,
      library.catalogScope,
      fixtures.secondCandidate,
    );
    preferences.saveGate!.complete();
    await rejected;
    expect(preferences.artwork, isEmpty);
  });

  test(
    'a frame from the previous root cannot be saved in a new root',
    () async {
      final library = fixture.library;
      final title = library.currentTitles.single;
      final frame = await library.videoArtworkFrame(title, Duration.zero);
      const otherRoot = AuthorizedLibraryRoot(
        locator: LibraryRootLocator(
          storageKind: StorageKind.androidSaf,
          opaqueValue: 'content://redacted/tree/other',
        ),
        displayName: 'Other library',
      );
      // The no-op storage cannot scan, but the root change still takes effect.
      await fixture.controller.scan(otherRoot);
      await library.waitForDiscovery();
      await expectLater(
        library.selectVideoArtwork(title, CatalogArtworkKind.poster, frame),
        throwsA(isA<CatalogMetadataException>()),
      );
      expect(preferences.saves, 0);
    },
  );

  test(
    'refresh always fetches again and never replaces current artwork',
    () async {
      final library = fixture.library;
      final title = library.currentTitles.single;
      expect(await library.thumbnail(title.first), [1]);
      expect(await library.refreshArtwork(title), [poster, backdrop]);
      await library.refreshArtwork(title);
      expect(source.refreshes, 2);
      expect(source.downloads, 0);
      expect(preferences.saves, 0);
      expect(await library.thumbnail(title.first), [1]);
    },
  );

  test('choice updates every season and keeps poster and backdrop independent', () async {
    final library = fixture.library;
    final title = library.currentTitles.single;
    // Cache the fallback first to verify invalidation after a successful save.
    expect(await library.thumbnail(title.first), [1]);
    expect(await library.thumbnail(title.first, backdrop: true), [1]);
    await library.refreshArtwork(title);
    await library.selectArtwork(title, poster);
    expect(await library.thumbnail(title.first), [2]);
    expect(await library.thumbnail(title.videos.last), [2]);
    expect(await library.thumbnail(title.first, backdrop: true), [1]);
    await library.selectArtwork(title, backdrop);
    expect(await library.thumbnail(title.first), [2]);
    expect(await library.thumbnail(title.videos.last, backdrop: true), [3]);
    expect(preferences.artwork, hasLength(2));
  });

  test(
    'failed refresh still permits choosing a previously previewed image',
    () async {
      final library = fixture.library;
      final title = library.currentTitles.single;
      await library.refreshArtwork(title);
      source.artworkOffline = true;
      await expectLater(
        library.refreshArtwork(title),
        throwsA(isA<CatalogMetadataException>()),
      );
      source.artworkOffline = false;
      await library.selectArtwork(title, poster);
      expect(await library.thumbnail(title.first), [2]);
    },
  );

  test(
    'preference save failure preserves the previous choice across restart',
    () async {
      final library = fixture.library;
      final title = library.currentTitles.single;
      await library.refreshArtwork(title);
      await library.selectArtwork(title, poster);
      preferences.failPreferences = true;
      await expectLater(
        library.selectArtwork(title, poster),
        throwsA(isA<CatalogMetadataException>()),
      );
      expect(await library.thumbnail(title.first), [2]);
      final entries = fixture.controller.state.entries;
      fixture.close();
      preferences.failPreferences = false;
      fixture = fixtures.LibraryFixture(
        entries,
        ArtworkSource()..offline = true,
      );
      await fixture.initialize();
      expect(
        await fixture.library.thumbnail(
          fixture.library.currentTitles.single.first,
        ),
        [2],
      );
      expect(preferences.artwork, hasLength(1));
    },
  );

  test(
    'merged aliases share a saved choice when the first alias is removed',
    () async {
      final library = fixture.library;
      final originalEntries = fixture.controller.state.entries;
      final original = library.currentTitles.single;
      await library.refreshArtwork(original);
      await library.selectArtwork(original, poster);
      final aliasEntries = [
        files.file('Shows/An Alias/Season 3/An.Alias.S03E01.mp4'),
      ];
      library.titlesFor([...originalEntries, ...aliasEntries]);
      await library.waitForDiscovery();
      await library.matcher.idle;
      final alias = library.localTitles.singleWhere(
        (title) => title.name == 'An Alias',
      );
      await library.matcher.select(
        alias,
        library.catalogScope,
        fixtures.firstCandidate,
      );
      await library.waitForDiscovery();
      final merged = library.currentTitles.single;
      expect(merged.localIds, hasLength(2));
      expect(await library.thumbnail(merged.videos.last), [2]);
      await library.refreshArtwork(merged);
      await library.selectArtwork(merged, backdrop);
      await library.persist();
      fixture.close();
      // Retain only the original group; the lexically earlier alias is gone.
      fixture = fixtures.LibraryFixture(
        originalEntries,
        ArtworkSource()..offline = true,
      );
      await fixture.initialize();
      final restored = fixture.library.currentTitles.single;
      expect(await fixture.library.thumbnail(restored.first), [2]);
      expect(await fixture.library.thumbnail(restored.first, backdrop: true), [
        3,
      ]);
    },
  );

  test(
    'selected images survive restart and remain available offline',
    () async {
      final library = fixture.library;
      final title = library.currentTitles.single;
      await library.refreshArtwork(title);
      await library.selectArtwork(title, poster);
      await library.selectArtwork(title, backdrop);
      await library.persist();
      final entries = fixture.controller.state.entries;
      fixture.close();
      fixture = fixtures.LibraryFixture(
        entries,
        ArtworkSource()..offline = true,
      );
      await fixture.initialize();
      fixture.library.matcher.configure(null);
      final restored = fixture.library.currentTitles.single;
      expect(await fixture.library.thumbnail(restored.first), [2]);
      expect(await fixture.library.thumbnail(restored.first, backdrop: true), [
        3,
      ]);
    },
  );

  test(
    'a newly merged alias retains artwork after the original alias is removed',
    () async {
      final library = fixture.library;
      final original = library.currentTitles.single;
      await library.refreshArtwork(original);
      await library.selectArtwork(original, poster);
      final aliasEntries = [
        files.file('Shows/An Alias/Season 3/An.Alias.S03E01.mp4'),
      ];
      library.titlesFor([...fixture.controller.state.entries, ...aliasEntries]);
      await library.waitForDiscovery();
      await library.matcher.idle;
      final alias = library.localTitles.singleWhere(
        (title) => title.name == 'An Alias',
      );
      await library.matcher.select(
        alias,
        library.catalogScope,
        fixtures.firstCandidate,
      );
      await library.waitForDiscovery();
      expect(library.currentTitles.single.localIds, hasLength(2));
      await library.persist();
      fixture.close();
      fixture = fixtures.LibraryFixture(
        aliasEntries,
        ArtworkSource()..offline = true,
      );
      await fixture.initialize();
      expect(
        await fixture.library.thumbnail(
          fixture.library.currentTitles.single.first,
        ),
        [2],
      );
    },
  );

  test('correcting the match preserves the local artwork choice', () async {
    final library = fixture.library;
    final title = library.currentTitles.single;
    await library.refreshArtwork(title);
    await library.selectArtwork(title, poster);
    await library.matcher.select(
      library.localTitles.single,
      library.catalogScope,
      fixtures.secondCandidate,
    );
    await library.waitForDiscovery();
    expect(library.currentTitles.single.providerId, '99');
    expect(await library.thumbnail(library.currentTitles.single.first), [2]);
  });

  test(
    'failed download or save preserves the previously selected image',
    () async {
      final library = fixture.library;
      final title = library.currentTitles.single;
      await library.refreshArtwork(title);
      await library.selectArtwork(title, poster);
      source.artworkOffline = true;
      await expectLater(
        library.selectArtwork(title, backdrop),
        throwsA(isA<CatalogMetadataException>()),
      );
      expect(await library.thumbnail(title.first, backdrop: true), [1]);
      source.artworkOffline = false;
      preferences.failSave = true;
      await expectLater(
        library.selectArtwork(title, poster),
        throwsA(isA<CatalogMetadataException>()),
      );
      expect(await library.thumbnail(title.first), [2]);
      expect(preferences.saves, 1);
    },
  );

  test(
    'changed match during download cannot save artwork to the wrong show',
    () async {
      final library = fixture.library;
      final title = library.currentTitles.single;
      await library.refreshArtwork(title);
      source.downloadGate = Completer<Uint8List>();
      final selecting = library.selectArtwork(title, poster);
      final rejected = expectLater(
        selecting,
        throwsA(isA<CatalogMetadataException>()),
      );
      await library.matcher.select(
        library.localTitles.single,
        library.catalogScope,
        fixtures.secondCandidate,
      );
      source.downloadGate!.complete(Uint8List.fromList([2]));
      await rejected;
      expect(preferences.saves, 0);
    },
  );

  test(
    'selection requires a refreshed candidate and an enabled source',
    () async {
      final library = fixture.library;
      final title = library.currentTitles.single;
      await expectLater(
        library.selectArtwork(title, poster),
        throwsA(isA<CatalogMetadataException>()),
      );
      await library.refreshArtwork(title);
      library.matcher.configure(null);
      await expectLater(
        library.selectArtwork(title, poster),
        throwsA(isA<CatalogMetadataException>()),
      );
      await expectLater(
        library.refreshArtwork(title),
        throwsA(isA<CatalogMetadataException>()),
      );
      expect(preferences.saves, 0);
    },
  );
}
