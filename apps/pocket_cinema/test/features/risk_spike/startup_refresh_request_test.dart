import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_domain/media_domain.dart';
import 'package:media_platform_storage/media_platform_storage.dart';
import 'package:pocket_cinema/features/risk_spike/risk_spike_controller.dart';
import 'package:pocket_cinema/features/risk_spike/risk_spike_state.dart';
import 'package:pocket_cinema/features/risk_spike/scan_inventory_store.dart';
import 'package:pocket_cinema/features/risk_spike/scan_inventory_worker.dart';

import 'risk_spike_controller_test.dart' as support;
import 'risk_spike_inventory_test.dart' as cache;

void main() {
  var now = cache.completedAt.add(const Duration(hours: 6));

  setUp(() => now = cache.completedAt.add(const Duration(hours: 6)));

  RiskSpikeController controllerFor(
    support.FakeStorageGateway storage, {
    ScanInventory? inventory,
    cache.MemoryInventoryStore? store,
    ScanInventoryWorker? worker,
  }) => RiskSpikeController(
    storage: storage,
    probe: support.FakeMediaProbe(),
    playback: support.FakePlaybackSession(),
    inventoryStore:
        store ??
        cache.MemoryInventoryStore(saved: inventory ?? cache.inventory()),
    inventoryWorker: worker ?? (work) async => classifyScanInventory(work),
    clock: () => now,
  );

  Stream<StorageScanEvent> failedScan(String scanId, Object _) =>
      Stream.value(StorageScanFailed(scanId, support.scanFailure));

  test(
    'restoring cache leaves startup scan-free and refreshes only when due',
    () async {
      final storage = support.FakeStorageGateway(
        persistedRoots: [support.root],
        onEnumerate: failedScan,
      );
      final controller = controllerFor(storage);
      addTearDown(controller.dispose);
      now = cache.completedAt.add(const Duration(hours: 5, minutes: 59));

      await controller.initialize();
      await controller.refreshInBackground();
      expect(controller.state.entries, hasLength(1));
      expect(controller.needsBackgroundRefresh, isFalse);
      expect(storage.scanCount, 0);

      now = cache.completedAt.add(const Duration(hours: 6));
      expect(controller.needsBackgroundRefresh, isTrue);
      await controller.refreshInBackground();
      await controller.refreshInBackground();

      expect(storage.scanCount, 1);
      expect(controller.state.entries, hasLength(1));
      expect(controller.state.scanCompleted, isTrue);
      expect(controller.state.phase, RiskSpikePhase.filesAvailable);
      expect(controller.state.libraryFailure, isNull);
      expect(controller.needsBackgroundRefresh, isFalse);
      now = now.add(const Duration(minutes: 29, seconds: 59));
      expect(controller.needsBackgroundRefresh, isFalse);
      now = now.add(const Duration(seconds: 1));
      expect(controller.needsBackgroundRefresh, isTrue);
      await controller.refreshInBackground();
      expect(storage.scanCount, 2);
    },
  );

  test(
    'a successful manual scan starts the six-hour refresh interval',
    () async {
      final storage = support.FakeStorageGateway(
        persistedRoots: [support.root],
        onEnumerate: (id, token) async* {
          yield StorageScanBatch(id, [support.videoEntry]);
          yield StorageScanCompleted(id);
        },
      );
      final controller = controllerFor(storage);
      addTearDown(controller.dispose);
      await controller.initialize();

      await controller.scan(support.root);
      await controller.refreshInBackground();
      expect(storage.scanCount, 1);
      expect(controller.needsBackgroundRefresh, isFalse);
      now = now.add(const Duration(hours: 6));
      expect(controller.needsBackgroundRefresh, isTrue);
    },
  );

  test(
    'a future cache timestamp is due instead of disabling refresh',
    () async {
      now = cache.completedAt.subtract(const Duration(days: 1));
      final controller = controllerFor(
        support.FakeStorageGateway(persistedRoots: [support.root]),
      );
      addTearDown(controller.dispose);
      await controller.initialize();

      expect(controller.needsBackgroundRefresh, isTrue);
    },
  );

  test('an empty complete cache follows the same refresh interval', () async {
    final controller = controllerFor(
      support.FakeStorageGateway(persistedRoots: [support.root]),
      inventory: cache.inventory(empty: true),
    );
    addTearDown(controller.dispose);
    await controller.initialize();

    expect(controller.needsBackgroundRefresh, isTrue);
  });

  test(
    'choosing another folder invalidates the old refresh eligibility',
    () async {
      final storage = support.FakeStorageGateway(
        persistedRoots: [support.root],
        onChoose: () async => const Success(cache.otherRoot),
        onEnumerate: failedScan,
      );
      final controller = controllerFor(storage);
      addTearDown(controller.dispose);
      await controller.initialize();

      await controller.chooseRoot();
      await controller.refreshInBackground();
      expect(storage.scanCount, 0);
      expect(controller.state.root, cache.otherRoot);
      expect(controller.needsBackgroundRefresh, isFalse);
    },
  );

  test('revoked access cannot start an automatic scan', () async {
    final storage = support.FakeStorageGateway(
      persistedRoots: [support.root],
      accessState: RootAccessState.permissionRevoked,
      onEnumerate: failedScan,
    );
    final controller = controllerFor(storage);
    addTearDown(controller.dispose);
    await controller.initialize();

    await controller.refreshInBackground();
    expect(controller.needsBackgroundRefresh, isFalse);
    expect(storage.scanCount, 0);
  });

  test('disposal invalidates refresh eligibility', () async {
    final storage = support.FakeStorageGateway(
      persistedRoots: [support.root],
      onEnumerate: failedScan,
    );
    final controller = controllerFor(storage);
    await controller.initialize();

    controller.dispose();
    await controller.refreshInBackground();
    expect(storage.scanCount, 0);
    expect(controller.needsBackgroundRefresh, isFalse);
  });

  test(
    'automatic scan emits begin/end only while retaining the usable inventory',
    () async {
      final ready = Completer<void>();
      final finish = Completer<void>();
      final store = cache.MemoryInventoryStore(saved: cache.inventory());
      final storage = support.FakeStorageGateway(
        persistedRoots: [support.root],
        onEnumerate: (id, token) async* {
          for (var index = 0; index < 500; index++) {
            yield StorageScanBatch(id, [support.subtitleEntry]);
          }
          ready.complete();
          await finish.future;
          yield StorageScanCompleted(id);
        },
      );
      final controller = controllerFor(storage, store: store);
      addTearDown(controller.dispose);
      await controller.initialize();
      final previous = controller.state;
      final refreshingStates = <bool>[];
      controller.addListener(
        () => refreshingStates.add(controller.isBackgroundRefreshing),
      );

      final refreshing = controller.refreshInBackground();
      await ready.future;
      expect(controller.state, same(previous));
      expect(controller.state.canCancel, isFalse);
      expect(controller.state.canRescan, isTrue);
      expect(controller.needsBackgroundRefresh, isFalse);
      expect(refreshingStates, [true]);
      await controller.refreshInBackground();
      expect(storage.scanCount, 1);

      finish.complete();
      await refreshing;
      expect(refreshingStates, [true, false]);
      expect(controller.state.subtitleCount, 500);
      expect(controller.state.phase, RiskSpikePhase.filesAvailable);
      expect(controller.state.lastScanCompletedAt, now);
      expect(controller.needsBackgroundRefresh, isFalse);
      expect(store.saveCalls, 1);
    },
  );

  test(
    'deferring automatic work cancels it and keeps it due at the next idle',
    () async {
      final started = Completer<CancellationToken>();
      final finish = Completer<void>();
      final store = cache.MemoryInventoryStore(saved: cache.inventory());
      final controller = controllerFor(
        support.FakeStorageGateway(
          persistedRoots: [support.root],
          onEnumerate: (id, token) async* {
            started.complete(token);
            await finish.future;
            yield StorageScanCompleted(id);
          },
        ),
        store: store,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      final previousEntries = controller.state.entries;

      final refreshing = controller.refreshInBackground();
      final token = await started.future;
      controller.deferBackgroundRefresh();
      expect(token.isCancelled, isTrue);
      expect(controller.needsBackgroundRefresh, isFalse);
      finish.complete();
      await refreshing;

      expect(controller.isBackgroundRefreshing, isFalse);
      expect(controller.needsBackgroundRefresh, isTrue);
      expect(controller.state.phase, RiskSpikePhase.filesAvailable);
      expect(controller.state.entries, same(previousEntries));
      expect(controller.state.libraryFailure, isNull);
      expect(store.saveCalls, 0);
    },
  );

  test('deferring automatic work does not interrupt a manual scan', () async {
    final started = Completer<CancellationToken>();
    final finish = Completer<void>();
    final controller = controllerFor(
      support.FakeStorageGateway(
        persistedRoots: [support.root],
        onEnumerate: (id, token) async* {
          started.complete(token);
          await finish.future;
          yield StorageScanCompleted(id);
        },
      ),
    );
    addTearDown(controller.dispose);
    await controller.initialize();

    final scanning = controller.scan(support.root);
    final token = await started.future;
    controller.deferBackgroundRefresh();
    expect(token.isCancelled, isFalse);
    expect(controller.isBackgroundRefreshing, isFalse);
    expect(controller.state.canCancel, isTrue);
    finish.complete();
    await scanning;
    expect(controller.state.scanCompleted, isTrue);
  });

  test('a manual scan supersedes automatic work and rejects its late worker result', () async {
    final firstStarted = Completer<ScanInventoryWork>();
    final firstFinished = Completer<ScanInventory>();
    var calls = 0;
    final store = cache.MemoryInventoryStore(saved: cache.inventory());
    final controller = controllerFor(
      support.FakeStorageGateway(
        persistedRoots: [support.root],
        onEnumerate: (id, token) async* {
          if (id == 'scan-2') yield StorageScanBatch(id, [support.videoEntry]);
          yield StorageScanCompleted(id);
        },
      ),
      store: store,
      worker: (work) async {
        if (calls++ == 0) {
          firstStarted.complete(work);
          return firstFinished.future;
        }
        return classifyScanInventory(work);
      },
    );
    addTearDown(controller.dispose);
    await controller.initialize();

    final automatic = controller.refreshInBackground();
    final firstWork = await firstStarted.future;
    await controller.scan(support.root);
    final currentEntries = controller.state.entries;
    expect(controller.isBackgroundRefreshing, isFalse);
    firstFinished.complete(classifyScanInventory(firstWork));
    await automatic;

    expect(controller.state.entries, same(currentEntries));
    expect(
      controller.state.entries.single.storageKey,
      support.videoEntry.storageKey,
    );
    expect(store.saveCalls, 1);
  });

  test(
    'automatic classification cancelled by activity cannot replace the cache',
    () async {
      final started = Completer<ScanInventoryWork>();
      final finished = Completer<ScanInventory>();
      final store = cache.MemoryInventoryStore(saved: cache.inventory());
      final controller = controllerFor(
        support.FakeStorageGateway(
          persistedRoots: [support.root],
          onEnumerate: (id, token) async* {
            yield StorageScanCompleted(id);
          },
        ),
        store: store,
        worker: (work) {
          started.complete(work);
          return finished.future;
        },
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      final previousEntries = controller.state.entries;
      final refreshing = controller.refreshInBackground();
      final work = await started.future;
      controller.deferBackgroundRefresh();
      finished.complete(classifyScanInventory(work));
      await refreshing;

      expect(controller.state.entries, same(previousEntries));
      expect(controller.needsBackgroundRefresh, isTrue);
      expect(store.saveCalls, 0);
    },
  );

  test('concurrent playback failure stays visible without allowing duplicate automatic scans', () async {
    final events = StreamController<StorageScanEvent>();
    final storage = support.FakeStorageGateway(
      persistedRoots: [support.root],
      openFailure: support.fileUnavailableFailure,
      onEnumerate: (_, token) => events.stream,
    );
    final controller = controllerFor(storage);
    addTearDown(controller.dispose);
    await controller.initialize();
    final refreshing = controller.refreshInBackground();
    await Future<void>.delayed(Duration.zero);

    controller.selectFile(controller.state.entries.single);
    await controller.playSelected();
    expect(controller.state.failure, support.fileUnavailableFailure);
    expect(controller.isBackgroundRefreshing, isTrue);
    expect(controller.needsBackgroundRefresh, isFalse);

    events.add(const StorageScanFailed('scan-1', support.scanFailure));
    await events.close();
    await refreshing;
    expect(controller.state.failure, support.fileUnavailableFailure);
    expect(controller.state.refreshFailure, isNull);
    expect(controller.state.canRescan, isTrue);
  });
}
