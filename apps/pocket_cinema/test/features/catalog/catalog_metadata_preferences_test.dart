import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_platform_storage/media_platform_storage.dart';
import 'package:pocket_cinema/features/catalog/catalog_library.dart';
import 'package:pocket_cinema/features/catalog/catalog_metadata.dart';
import 'package:pocket_cinema/features/risk_spike/risk_spike_controller.dart';
import 'package:pocket_cinema/features/risk_spike/risk_spike_screen.dart';

import '../risk_spike/risk_spike_screen_test.dart' as screen_fixtures;
import 'catalog_library_test.dart' as files;

const firstCandidate = CatalogMetadataCandidate(
  providerId: '42',
  name: 'Canonical Show',
  year: 1999,
  overview: 'The first title confirmed by the user.',
);
const secondCandidate = CatalogMetadataCandidate(
  providerId: '99',
  name: 'Corrected Show',
  year: 1999,
);

class FakeMetadataSource implements CatalogMetadataSource {
  bool offline = false;
  int searches = 0;
  int disposeCount = 0;
  final requestedEpisodes = <(String, int)>[];

  @override
  Future<List<CatalogMetadataCandidate>> search({
    required String title,
    required CatalogMediaKind kind,
    int? year,
  }) async {
    searches++;
    if (offline) throw const CatalogMetadataException('Offline');
    return const [];
  }

  @override
  Future<List<CatalogEpisodeMetadata>> episodes({
    required String providerId,
    required int season,
  }) async {
    requestedEpisodes.add((providerId, season));
    if (offline) throw const CatalogMetadataException('Offline');
    return [
      CatalogEpisodeMetadata(
        season: season,
        number: 1,
        name: 'Season $season opening',
      ),
    ];
  }

  @override
  void dispose() => disposeCount++;
}

class NativePreferences {
  String stored = '{}';
  final preferenceWrites = <String>[];
  final tokenWrites = <String>[];
  int tokenReads = 0;

  Map<String, dynamic> get decoded =>
      jsonDecode(stored) as Map<String, dynamic>;

  Future<Object?> handle(MethodCall call) async {
    switch (call.method) {
      case 'loadPreferences':
        return stored;
      case 'savePreferences':
        stored = (call.arguments as Map)['value'] as String;
        preferenceWrites.add(stored);
        return null;
      case 'loadMetadataToken':
        tokenReads++;
        return null;
      case 'saveMetadataToken':
        tokenWrites.add((call.arguments as Map)['value'] as String);
        return null;
      default:
        throw StateError('Unexpected native call: ${call.method}');
    }
  }
}

class LibraryFixture {
  LibraryFixture(
    List<StorageEntrySnapshot> entries,
    FakeMetadataSource source,
  ) {
    final app = screen_fixtures.testApp(
      state: screen_fixtures.filesAvailableState.copyWith(entries: entries),
    ) as MaterialApp;
    controller =
        ((app.home! as MediaQuery).child as RiskSpikeScreen).controller;
    library = CatalogLibrary(controller, metadataSource: source);
  }

  late final RiskSpikeController controller;
  late final CatalogLibrary library;
  bool closed = false;

  Future<void> initialize() async {
    await library.load();
    library.titlesFor(controller.state.entries);
    await library.waitForDiscovery();
    await library.matcher.enrich(library.localTitles, library.catalogScope);
    await library.matcher.idle;
    await library.waitForDiscovery();
  }

  void close() {
    if (closed) return;
    closed = true;
    library.dispose();
    controller.dispose();
  }
}

/// Token settings may construct the IO adapter, but this test must never open
/// a network connection even if the implementation later changes its timing.
class NoNetworkClient implements HttpClient {
  int requestCount = 0;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    requestCount++;
    throw StateError('Network requests are prohibited in preference tests.');
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late NativePreferences preferences;

  setUp(() {
    preferences = NativePreferences();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(CatalogLibrary.channel, preferences.handle);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(CatalogLibrary.channel, null);
  });

  LibraryFixture fixture(
    List<StorageEntrySnapshot> entries,
    FakeMetadataSource source,
  ) {
    final created = LibraryFixture(entries, source);
    addTearDown(created.close);
    return created;
  }

  final entries = [
    files.file('My Show (1999)/Season 1/S01E01.mkv'),
    files.file('Moj Serial (1999)/Season 2/S02E01.mkv'),
  ];

  test('Watchlist aliases survive canonical names, local names, correction and restart', () async {
    final first = fixture(entries, FakeMetadataSource());
    await first.initialize();
    final library = first.library;
    final locals = [...library.localTitles];
    for (final local in locals) {
      await library.matcher.select(local, library.catalogScope, firstCandidate);
    }
    await library.waitForDiscovery();
    final canonical = library.currentTitles.single;
    expect(canonical.id, 'tmdb:tv:42');
    expect(canonical.localIds, unorderedEquals(locals.map((t) => t.id)));
    library.toggleSaved(canonical.id);
    expect(library.isSaved(canonical), isTrue);
    expect(library.saved, unorderedEquals(locals.map((t) => t.id)));

    library.matcher.forget(canonical, library.catalogScope);
    await library.waitForDiscovery();
    expect(library.currentTitles, hasLength(2));
    expect(library.currentTitles.every(library.isSaved), isTrue);
    expect(library.currentTitles.every((t) => t.providerId == null), isTrue);
    for (final local in locals) {
      await library.matcher.select(
        local,
        library.catalogScope,
        secondCandidate,
      );
    }
    await library.waitForDiscovery();
    final corrected = library.currentTitles.single;
    expect(corrected.id, 'tmdb:tv:99');
    expect(library.isSaved(corrected), isTrue);
    expect(
      corrected.videos.map((video) => video.id),
      unorderedEquals(entries.map((entry) => entry.storageKey)),
    );
    await library.persist();
    expect(
      preferences.decoded['saved'],
      unorderedEquals(locals.map((t) => t.id)),
    );
    first.close();

    final offline = FakeMetadataSource()..offline = true;
    final restarted = fixture(entries, offline);
    await restarted.initialize();
    final restored = restarted.library.currentTitles.single;
    expect(restored.id, 'tmdb:tv:99');
    expect(restarted.library.isSaved(restored), isTrue);
    expect(restarted.library.saved, unorderedEquals(locals.map((t) => t.id)));
    expect(offline.searches, 0);
    expect(offline.requestedEpisodes, isEmpty);
  });

  test(
    'Manual title and episode cache restore without contacting a source',
    () async {
      final first = fixture([entries.first], FakeMetadataSource());
      await first.initialize();
      final library = first.library;
      final local = library.localTitles.single;
      await library.matcher.select(local, library.catalogScope, firstCandidate);
      await library.persist();
      final key = library.matcher.key(library.catalogScope, local);
      final cached = (preferences.decoded['titleMatches'] as Map)[key] as Map;
      expect(cached['id'], '42');
      expect(cached['manual'], isTrue);
      expect(cached['episodes'], [
        {'season': 1, 'number': 1, 'name': 'Season 1 opening'},
      ]);
      first.close();

      final offline = FakeMetadataSource()..offline = true;
      final restarted = fixture([entries.first], offline);
      await restarted.initialize();
      final restored = restarted.library.currentTitles.single;
      expect(restored.name, 'Canonical Show');
      expect(restored.overview, firstCandidate.overview);
      expect(restored.first.title, 'Season 1 opening');
      expect(restored.first.episodeCode, 'S01E01');
      expect(restored.matchStatus, contains('Confirmed by you'));
      expect(restarted.library.matcher.matches[key]!.manual, isTrue);
      expect(offline.searches, 0);
      expect(offline.requestedEpisodes, isEmpty);
    },
  );

  test(
    'Use local names persists through restart and background retries',
    () async {
      final first = fixture([entries.first], FakeMetadataSource());
      await first.initialize();
      final library = first.library;
      final local = library.localTitles.single;
      await library.matcher.select(local, library.catalogScope, firstCandidate);
      await library.waitForDiscovery();
      library.matcher.forget(
        library.currentTitles.single,
        library.catalogScope,
      );
      final key = library.matcher.key(library.catalogScope, local);
      await library.persist();
      expect(preferences.decoded['localOnlyTitles'], [key]);
      expect(preferences.decoded['titleMatches'], isEmpty);
      first.close();

      final source = FakeMetadataSource();
      final restarted = fixture([entries.first], source);
      await restarted.initialize();
      await restarted.library.retryMatching();
      await restarted.library.waitForDiscovery();
      final restored = restarted.library.currentTitles.single;
      expect(restored.id, local.id);
      expect(restored.name, 'My Show');
      expect(restored.providerId, isNull);
      expect(restarted.library.matcher.localOnly, contains(key));
      expect(source.searches, 0);
      expect(source.requestedEpisodes, isEmpty);
    },
  );

  test(
    'The token uses its dedicated native method and never ordinary preferences',
    () async {
      final client = NoNetworkClient();
      await HttpOverrides.runZoned(() async {
        final created = fixture(const [], FakeMetadataSource());
        await created.initialize();
        const token = 'test-read-access-token-only';
        await created.library.setMetadataToken(token);
        await created.library.matcher.idle;
        await created.library.persist();
        expect(created.library.settingsError, isNull);
        expect(created.library.metadataConfigured, isTrue);
        expect(preferences.tokenWrites, [token]);
        expect(preferences.preferenceWrites, isNotEmpty);
        expect(
          preferences.preferenceWrites.every((raw) => !raw.contains(token)),
          isTrue,
        );
        expect(preferences.decoded.keys, isNot(contains('token')));
        expect(preferences.tokenReads, 0);
        expect(client.requestCount, 0);
        created.close();
      }, createHttpClient: (_) => client);
    },
  );

  test('An invalid token is rejected before storage and preserves the current source', () async {
    final client = NoNetworkClient();
    await HttpOverrides.runZoned(() async {
      final source = FakeMetadataSource();
      final created = fixture([entries.first], source);
      await created.initialize();
      const invalid = 'invalid token with whitespace';
      await created.library.setMetadataToken(invalid);
      expect(
        created.library.settingsError,
        contains('valid TMDB API Read Access Token'),
      );
      expect(created.library.settingsError, isNot(contains(invalid)));
      expect(preferences.tokenWrites, isEmpty);
      expect(source.disposeCount, 0);
      expect(created.library.matcher.enabled, isTrue);
      await created.library.retryMatching();
      expect(source.searches, 2);
      await created.library.persist();
      expect(
        preferences.preferenceWrites.every((raw) => !raw.contains(invalid)),
        isTrue,
      );
      expect(preferences.tokenReads, 0);
      expect(client.requestCount, 0);
      created.close();
      expect(source.disposeCount, 1);
    }, createHttpClient: (_) => client);
  });
}
