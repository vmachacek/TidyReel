import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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

  @override
  Future<Object?> handle(MethodCall call) async {
    switch (call.method) {
      case 'readArtwork':
        return artwork[(call.arguments as Map)['key']];
      case 'saveArtwork':
        if (failSave) throw PlatformException(code: 'ARTWORK_STORAGE_ERROR');
        saves++;
        final args = call.arguments as Map;
        artwork[args['key'] as String] = args['bytes'] as Uint8List;
        return true;
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
  });

  tearDown(() {
    fixture.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(CatalogLibrary.channel, null);
  });

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
      await library.matcher.idle;
      final alias = library.localTitles.singleWhere(
        (title) => title.name == 'An Alias',
      );
      await library.matcher.select(
        alias,
        library.catalogScope,
        fixtures.firstCandidate,
      );
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
      await library.matcher.idle;
      final alias = library.localTitles.singleWhere(
        (title) => title.name == 'An Alias',
      );
      await library.matcher.select(
        alias,
        library.catalogScope,
        fixtures.firstCandidate,
      );
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
