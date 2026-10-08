import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_cinema/features/catalog/catalog_library.dart';

import 'catalog_metadata_preferences_test.dart' as fixtures;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late fixtures.NativePreferences preferences;

  setUp(() {
    preferences = fixtures.NativePreferences();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(CatalogLibrary.channel, preferences.handle);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(CatalogLibrary.channel, null);
  });

  fixtures.LibraryFixture fixture() {
    final created = fixtures.LibraryFixture(
      const [],
      fixtures.FakeMetadataSource(),
    );
    addTearDown(created.close);
    return created;
  }

  test('Home view defaults to carousel for older preferences', () async {
    preferences.stored = jsonEncode({'saved': <String>[]});
    final created = fixture();
    expect(created.library.homeView, CatalogHomeView.carousel);
    await created.initialize();
    expect(created.library.homeView, CatalogHomeView.carousel);
  });

  test(
    'Invalid home view preferences retain carousel and other data',
    () async {
      for (final invalid in [
        null,
        0,
        false,
        'tiles',
        'Cards',
        <Object>[],
        <String, Object>{},
      ]) {
        preferences.stored = jsonEncode({
          'homeView': invalid,
          'saved': ['saved-title'],
        });
        final created = fixture();
        await created.initialize();
        expect(created.library.homeView, CatalogHomeView.carousel);
        expect(created.library.saved, {'saved-title'});
        created.close();
      }
    },
  );

  test(
    'Cards restore and switching to carousel persists through restart',
    () async {
      preferences.stored = jsonEncode({'homeView': 'cards'});
      final first = fixture();
      await first.initialize();
      expect(first.library.homeView, CatalogHomeView.cards);

      await first.library.setHomeView(CatalogHomeView.carousel);
      expect(first.library.homeView, CatalogHomeView.carousel);
      expect(preferences.decoded['homeView'], 'carousel');
      first.close();

      final restarted = fixture();
      await restarted.initialize();
      expect(restarted.library.homeView, CatalogHomeView.carousel);
    },
  );

  test('Switching to cards persists through restart', () async {
    final first = fixture();
    await first.initialize();
    await first.library.setHomeView(CatalogHomeView.cards);
    expect(first.library.homeView, CatalogHomeView.cards);
    expect(preferences.decoded['homeView'], 'cards');
    first.close();

    final restarted = fixture();
    await restarted.initialize();
    expect(restarted.library.homeView, CatalogHomeView.cards);
  });

  test(
    'Home view changes notify and persist only when the value changes',
    () async {
      final created = fixture();
      await created.initialize();
      final states = <CatalogHomeView>[];
      created.library.addListener(() {
        states.add(created.library.homeView);
      });

      await created.library.setHomeView(CatalogHomeView.carousel);
      await created.library.setHomeView(CatalogHomeView.cards);
      await created.library.setHomeView(CatalogHomeView.cards);
      await created.library.setHomeView(CatalogHomeView.carousel);

      expect(states, [CatalogHomeView.cards, CatalogHomeView.carousel]);
      expect(
        preferences.preferenceWrites.map(
          (raw) => (jsonDecode(raw) as Map)['homeView'],
        ),
        ['cards', 'carousel'],
      );
    },
  );

  test(
    'Home view changes wait for preferences and preserve saved data',
    () async {
      final loaded = Completer<String>();
      preferences.stored = jsonEncode({
        'homeView': 'cards',
        'lockHardwareVolumeButtons': false,
        'saved': ['saved-title'],
        'positions': {'video': 42},
        'durations': {'video': 120},
        'localOnlyTitles': ['local-title'],
        'artworkChoices': {'poster-key': 'poster-file'},
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(CatalogLibrary.channel, (call) async {
            if (call.method == 'loadPreferences') return loaded.future;
            return preferences.handle(call);
          });
      final created = fixture();
      final change = created.library.setHomeView(CatalogHomeView.carousel);
      await Future<void>.delayed(Duration.zero);
      expect(preferences.preferenceWrites, isEmpty);

      loaded.complete(preferences.stored);
      await change;
      await created.initialize();

      expect(created.library.homeView, CatalogHomeView.carousel);
      expect(preferences.decoded, {
        'homeView': 'carousel',
        'lockHardwareVolumeButtons': false,
        'saved': ['saved-title'],
        'positions': {'video': 42},
        'durations': {'video': 120},
        'titleMatches': <String, dynamic>{},
        'localOnlyTitles': ['local-title'],
        'artworkChoices': {'poster-key': 'poster-file'},
      });
    },
  );

  test('A home view change after disposal does not save preferences', () async {
    final created = fixture();
    await created.initialize();
    created.close();
    await created.library.setHomeView(CatalogHomeView.cards);
    expect(preferences.preferenceWrites, isEmpty);
  });

  test(
    'Cards can be selected while metadata token restoration is pending',
    () async {
      final created = fixture();
      await created.initialize();
      final tokenRequested = Completer<void>();
      final token = Completer<String?>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(CatalogLibrary.channel, (call) async {
            if (call.method == 'loadMetadataToken') {
              tokenRequested.complete();
              return token.future;
            }
            return preferences.handle(call);
          });
      final library = CatalogLibrary(created.controller);
      var loadingFinished = false;
      final loading = library.load().then((_) => loadingFinished = true);
      Future<void>? selection;
      try {
        await tokenRequested.future;
        selection = library.setHomeView(CatalogHomeView.cards);
        await selection.timeout(const Duration(seconds: 2));

        expect(loadingFinished, isFalse);
        expect(library.homeView, CatalogHomeView.cards);
        expect(preferences.decoded['homeView'], 'cards');
      } finally {
        token.complete(null);
        await loading;
        await selection;
        await library.waitForDiscovery();
        library.dispose();
      }
    },
  );
}
