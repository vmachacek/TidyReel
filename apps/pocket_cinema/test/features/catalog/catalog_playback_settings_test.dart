import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_cinema/features/catalog/catalog_library.dart';

import '../../support/catalog_discovery.dart';
import '../risk_spike/risk_spike_screen_test.dart' as fixtures;
import 'catalog_screen_test.dart' as screens;

void main() {
  for (final savedValue in <bool?>[null, false]) {
    testWidgets(
      savedValue == null
          ? 'hardware volume lock defaults on and Settings persists turning it off'
          : 'Settings restores hardware volume lock off and persists turning it on',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        var stored = jsonEncode({'lockHardwareVolumeButtons': ?savedValue});
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(CatalogLibrary.channel, (call) async {
              if (call.method == 'loadPreferences') return stored;
              if (call.method == 'savePreferences') {
                stored = (call.arguments as Map)['value'] as String;
              }
              return null;
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(CatalogLibrary.channel, null),
        );

        await tester.pumpWidget(screens.app(fixtures.filesAvailableState));
        await settleCatalog(tester);
        await tester.tap(find.text('Settings'));
        await settleCatalog(tester);

        final toggle = find.byKey(const Key('lock-hardware-volume-buttons'));
        final initialValue = savedValue ?? true;
        expect(find.text('Lock hardware volume buttons'), findsOneWidget);
        expect(tester.widget<SwitchListTile>(toggle).value, initialValue);
        await tester.ensureVisible(toggle);
        await tester.tap(toggle);
        await settleCatalog(tester);

        expect(tester.widget<SwitchListTile>(toggle).value, !initialValue);
        expect(catalogLibrary(tester).lockHardwareVolumeButtons, !initialValue);
        expect(
          (jsonDecode(stored) as Map)['lockHardwareVolumeButtons'],
          !initialValue,
        );

        // Recreate the screen and library to verify the choice survives restart.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.pumpWidget(screens.app(fixtures.filesAvailableState));
        await settleCatalog(tester);
        await tester.tap(find.text('Settings'));
        await settleCatalog(tester);

        expect(tester.widget<SwitchListTile>(toggle).value, !initialValue);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
