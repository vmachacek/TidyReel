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

  test(
    'Hardware volume buttons stay locked by default for older preferences',
    () async {
      preferences.stored = jsonEncode({'saved': <String>[]});
      final created = fixture();
      expect(created.library.lockHardwareVolumeButtons, isTrue);
      await created.initialize();
      expect(created.library.lockHardwareVolumeButtons, isTrue);
    },
  );

  test(
    'Invalid hardware volume preference values retain the default',
    () async {
      for (final invalid in [
        null,
        0,
        'false',
        <Object>[],
        <String, Object>{},
      ]) {
        preferences.stored = jsonEncode({'lockHardwareVolumeButtons': invalid});
        final created = fixture();
        await created.initialize();
        expect(created.library.lockHardwareVolumeButtons, isTrue);
        created.close();
      }
    },
  );

  test('Allowing hardware volume buttons persists through restart', () async {
    final first = fixture();
    await first.initialize();
    await first.library.setLockHardwareVolumeButtons(false);
    expect(first.library.lockHardwareVolumeButtons, isFalse);
    expect(preferences.decoded['lockHardwareVolumeButtons'], isFalse);
    first.close();

    final restarted = fixture();
    await restarted.initialize();
    expect(restarted.library.lockHardwareVolumeButtons, isFalse);
  });

  test(
    'Changing the hardware volume lock notifies and persists both states',
    () async {
      final created = fixture();
      await created.initialize();
      final states = <bool>[];
      created.library.addListener(() {
        states.add(created.library.lockHardwareVolumeButtons);
      });

      await created.library.setLockHardwareVolumeButtons(false);
      await created.library.setLockHardwareVolumeButtons(false);
      await created.library.setLockHardwareVolumeButtons(true);

      expect(states, [false, true]);
      expect(
        preferences.preferenceWrites.map(
          (raw) => (jsonDecode(raw) as Map)['lockHardwareVolumeButtons'],
        ),
        [false, true],
      );
      expect(preferences.decoded['lockHardwareVolumeButtons'], isTrue);
    },
  );

  test(
    'A setting change waits for restored preferences before saving',
    () async {
      preferences.stored = jsonEncode({'lockHardwareVolumeButtons': false});
      final created = fixture();
      await created.library.setLockHardwareVolumeButtons(true);
      expect(created.library.lockHardwareVolumeButtons, isTrue);
      expect(preferences.decoded['lockHardwareVolumeButtons'], isTrue);
    },
  );
}
