import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_cinema/features/catalog/catalog_library.dart';
import 'package:pocket_cinema/features/catalog/catalog_metadata_settings.dart';
import 'package:pocket_cinema/features/catalog/catalog_screen.dart';
import 'package:pocket_cinema/features/catalog/catalog_settings_screen.dart';
import 'package:pocket_cinema/features/kill_switch/kill_switch_note.dart';

import '../../support/catalog_discovery.dart';
import '../risk_spike/risk_spike_screen_test.dart' as fixtures;
import 'catalog_screen_test.dart' as screens;

const _backKey = Key('library-settings-back');
const _scrollKey = Key('library-settings-scroll');

Future<void> _openSettings(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetViewInsets);
  await tester.pumpWidget(screens.app(fixtures.filesAvailableState));
  await settleCatalog(tester);
  await tester.tap(find.text('Settings'));
  await settleCatalog(tester);
}

Finder _settingsScrollable() => find
    .descendant(of: find.byKey(_scrollKey), matching: find.byType(Scrollable))
    .first;

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
    (name: 'small portrait', size: const Size(320, 480)),
    (name: 'short landscape', size: const Size(640, 320)),
  ]) {
    testWidgets(
      'settings has a fixed back button while long content scrolls on ${scenario.name}',
      (tester) async {
        await _openSettings(tester, scenario.size);
        expect(find.byType(CatalogSettingsScreen), findsOneWidget);
        expect(find.byType(BottomSheet), findsNothing);
        expect(find.text('Library Settings'), findsOneWidget);
        final back = find.byKey(_backKey);
        expect(back.hitTestable(), findsOneWidget);
        final backRect = tester.getRect(back);
        final scrollState = tester.state<ScrollableState>(
          _settingsScrollable(),
        );
        expect(scrollState.position.maxScrollExtent, greaterThan(0));

        await tester.scrollUntilVisible(
          find.text('Metadata credits'),
          200,
          scrollable: _settingsScrollable(),
        );
        await tester.pumpAndSettle();
        expect(find.text('Metadata credits').hitTestable(), findsOneWidget);
        expect(scrollState.position.pixels, greaterThan(0));
        expect(back.hitTestable(), findsOneWidget);
        expect(tester.getRect(back), backRect);
        expect(tester.takeException(), isNull);

        await tester.tap(back);
        await settleCatalog(tester);
        expect(find.byType(CatalogSettingsScreen), findsNothing);
        expect(find.byType(CatalogScreen).hitTestable(), findsOneWidget);
        expect(find.text('Settings').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'screen-time note is the final settings content and Back stays reachable',
    (tester) async {
      await _openSettings(tester, const Size(320, 480));
      final back = find.byKey(_backKey);
      final backRect = tester.getRect(back);
      final note = find.byKey(const Key('kill-switch-info'));
      final recovery = find.byKey(const Key('kill-switch-info-recovery'));
      final settingsContent = tester.widget<Column>(
        find
            .descendant(
              of: find.byKey(_scrollKey),
              matching: find.byType(Column),
            )
            .first,
      );
      expect(settingsContent.children.last, isA<KillSwitchNote>());
      expect(
        tester.getRect(note).top,
        greaterThanOrEqualTo(
          tester.getRect(find.byType(CatalogMetadataSettings)).bottom,
        ),
      );
      expect(
        tester.getRect(note).top,
        greaterThan(tester.getRect(find.text('Metadata credits')).bottom),
      );

      await tester.scrollUntilVisible(
        recovery,
        200,
        maxScrolls: 40,
        scrollable: _settingsScrollable(),
      );
      final scrollState = tester.state<ScrollableState>(_settingsScrollable());
      scrollState.position.jumpTo(scrollState.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(recovery.hitTestable(), findsOneWidget);
      expect(tester.getRect(note).bottom, tester.getRect(recovery).bottom);
      expect(back.hitTestable(), findsOneWidget);
      expect(tester.getRect(back), backRect);
      expect(tester.takeException(), isNull);

      await tester.tap(back);
      await settleCatalog(tester);
      expect(find.byType(CatalogSettingsScreen), findsNothing);
      expect(find.byType(CatalogScreen).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'settings back button stays reachable with a small-screen keyboard',
    (tester) async {
      await _openSettings(tester, const Size(320, 480));
      final back = find.byKey(_backKey);
      final backRect = tester.getRect(back);
      final input = find.byKey(const Key('tmdb-token'));
      await tester.scrollUntilVisible(
        input,
        150,
        scrollable: _settingsScrollable(),
      );
      await tester.pumpAndSettle();
      await tester.tap(input);
      await tester.pump();
      tester.view.viewInsets = const FakeViewPadding(bottom: 180);
      await tester.pumpAndSettle();
      await tester.enterText(input, 'test token');
      expect(back.hitTestable(), findsOneWidget);
      expect(tester.getRect(back), backRect);
      expect(tester.getRect(input).bottom, lessThanOrEqualTo(300));
      expect(tester.takeException(), isNull);

      await tester.tap(back);
      await settleCatalog(tester);
      expect(find.byType(CatalogSettingsScreen), findsNothing);
      expect(find.byType(CatalogScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('system back returns from settings to the catalog', (
    tester,
  ) async {
    await _openSettings(tester, const Size(320, 480));
    expect(find.byType(CatalogSettingsScreen), findsOneWidget);

    await tester.binding.handlePopRoute();
    await settleCatalog(tester);
    expect(find.byType(CatalogSettingsScreen), findsNothing);
    expect(find.byType(CatalogScreen).hitTestable(), findsOneWidget);
    expect(find.text('Settings').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
