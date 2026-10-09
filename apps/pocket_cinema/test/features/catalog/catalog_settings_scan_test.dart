import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_platform_storage/media_platform_storage.dart';
import 'package:pocket_cinema/app/app_theme.dart';
import 'package:pocket_cinema/features/catalog/catalog_library.dart';
import 'package:pocket_cinema/features/catalog/catalog_screen.dart';
import 'package:pocket_cinema/features/risk_spike/risk_spike_controller.dart';
import 'package:pocket_cinema/features/risk_spike/scan_inventory_store.dart';
import 'package:pocket_cinema/features/risk_spike/scan_inventory_worker.dart';
import 'package:pocket_cinema/l10n/app_localizations.dart';

import '../../support/catalog_discovery.dart';
import '../risk_spike/risk_spike_controller_test.dart' as controllers;
import '../risk_spike/risk_spike_screen_test.dart' as fixtures;

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

  for (final fail in [false, true]) {
    testWidgets(
      'Settings starts an immediate manual rescan of a fresh library and allows another after ${fail ? 'failure' : 'completion'}',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final now = DateTime.utc(2026, 10, 9, 12);
        final cached = ScanInventory(
          root: fixtures.testRoot.locator,
          videos: fixtures.filesAvailableState.entries,
          artwork: const [],
          subtitles: const [],
          discoveredCount: 1,
          ignoredCount: 0,
          completedAtUtc: now.subtract(const Duration(hours: 1)),
        );
        final inventory = _MemoryInventory(cached);
        final events = StreamController<StorageScanEvent>();
        String? scanId;
        final storage = controllers.FakeStorageGateway(
          persistedRoots: const [fixtures.testRoot],
          onEnumerate: (id, _) {
            scanId = id;
            return events.stream;
          },
        );
        final controller = RiskSpikeController(
          storage: storage,
          probe: controllers.FakeMediaProbe(),
          playback: controllers.FakePlaybackSession(),
          inventoryStore: inventory,
          inventoryWorker: (work) async => classifyScanInventory(work),
          clock: () => now,
        );
        addTearDown(controller.dispose);
        await controller.initialize();
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: CatalogScreen(controller: controller),
          ),
        );
        await settleCatalog(tester);
        await tester.pump(const Duration(seconds: 20));

        expect(storage.scanCount, 0);
        expect(controller.needsBackgroundRefresh, isFalse);
        await tester.tap(find.text('Settings'));
        await settleCatalog(tester);
        final button = find.byKey(const Key('settings-rescan-library'));
        expect(find.text('Rescan library'), findsOneWidget);
        expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);

        await tester.tap(button);
        // No idle delay is advanced: the explicit request starts immediately.
        await tester.pump();
        expect(storage.scanCount, 1);
        expect(controller.isBackgroundRefreshing, isFalse);
        expect(controller.state.canCancel, isTrue);
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('Library Settings'), findsNothing);

        await tester.tap(find.text('Settings'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
        await tester.tap(button);
        await tester.pump();
        expect(storage.scanCount, 1);
        expect(find.text('Library Settings'), findsOneWidget);

        if (fail) {
          events.add(
            StorageScanFailed(scanId!, RiskSpikeController.scanFailed),
          );
        } else {
          events.add(StorageScanBatch(scanId!, cached.videos));
          events.add(StorageScanCompleted(scanId!));
        }
        await events.close();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        // The open Settings sheet must react to completion without reopening.
        expect(find.text('Library Settings'), findsOneWidget);
        expect(controller.state.canCancel, isFalse);
        expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);
        expect(controller.state.entries, cached.videos);
        expect(
          controller.state.libraryFailure,
          fail ? RiskSpikeController.scanFailed : isNull,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _MemoryInventory implements ScanInventoryStore {
  _MemoryInventory(this.saved);

  ScanInventory? saved;

  @override
  Future<ScanInventory?> load() async => saved;

  @override
  Future<void> save(ScanInventory inventory) async => saved = inventory;

  @override
  Future<void> clear() async => saved = null;
}
