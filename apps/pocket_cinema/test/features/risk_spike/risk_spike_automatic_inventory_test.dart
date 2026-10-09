import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_platform_storage/media_platform_storage.dart';
import 'package:pocket_cinema/features/risk_spike/risk_spike_controller.dart';
import 'package:pocket_cinema/features/risk_spike/risk_spike_state.dart';
import 'package:pocket_cinema/features/risk_spike/scan_inventory_store.dart';
import 'package:pocket_cinema/features/risk_spike/scan_inventory_worker.dart';

import 'risk_spike_controller_test.dart' as support;
import 'risk_spike_inventory_test.dart' as cache;

StorageEntrySnapshot copyEntry(
  StorageEntrySnapshot entry, {
  String? storageKey,
  int? sizeBytes,
}) => StorageEntrySnapshot(
  storageKey: storageKey ?? entry.storageKey,
  parentStorageKey: entry.parentStorageKey,
  relativePath: entry.relativePath,
  displayName: entry.displayName,
  isDirectory: entry.isDirectory,
  mimeType: entry.mimeType,
  sizeBytes: sizeBytes ?? entry.sizeBytes,
  modifiedAtUtc: entry.modifiedAtUtc,
  flags: Set.of(entry.flags),
);

ScanInventory copyInventory(
  ScanInventory inventory, {
  required DateTime completedAt,
  List<StorageEntrySnapshot>? videos,
  List<StorageEntrySnapshot>? artwork,
  List<StorageEntrySnapshot>? subtitles,
  int? discoveredCount,
  int? ignoredCount,
}) => ScanInventory(
  root: inventory.root,
  videos: videos ?? inventory.videos,
  artwork: artwork ?? inventory.artwork,
  subtitles: subtitles ?? inventory.subtitles,
  discoveredCount: discoveredCount ?? inventory.discoveredCount,
  ignoredCount: ignoredCount ?? inventory.ignoredCount,
  completedAtUtc: completedAt,
);

void main() {
  final now = cache.completedAt.add(const Duration(hours: 6));

  RiskSpikeController controllerFor(
    support.FakeStorageGateway storage, {
    cache.MemoryInventoryStore? store,
    ScanInventoryWorker? worker,
  }) => RiskSpikeController(
    storage: storage,
    probe: support.FakeMediaProbe(),
    playback: support.FakePlaybackSession(),
    inventoryStore:
        store ?? cache.MemoryInventoryStore(saved: cache.inventory()),
    inventoryWorker: worker ?? (work) async => classifyScanInventory(work),
    clock: () => now,
  );

  Stream<StorageScanEvent> completedScan(String id, Object _) =>
      Stream.value(StorageScanCompleted(id));

  test(
    'unchanged inventory retains existing lists despite new objects and order',
    () async {
      final inventory = copyInventory(
        cache.inventory(),
        completedAt: cache.completedAt,
        videos: [
          support.videoEntry,
          copyEntry(support.videoEntry, storageKey: 'provider|second-video'),
        ],
        discoveredCount: 4,
      );
      final store = cache.MemoryInventoryStore(saved: inventory);
      final controller = controllerFor(
        support.FakeStorageGateway(
          persistedRoots: [support.root],
          onEnumerate: completedScan,
        ),
        store: store,
        worker: (work) async => copyInventory(
          inventory,
          completedAt: work.completedAtUtc,
          videos: inventory.videos.reversed.map(copyEntry).toList(),
          artwork: inventory.artwork.map(copyEntry).toList(),
          subtitles: inventory.subtitles.map(copyEntry).toList(),
        ),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      final previousEntries = controller.state.entries;
      final previousArtwork = controller.state.artworkEntries;

      await controller.refreshInBackground();

      expect(controller.state.entries, same(previousEntries));
      expect(controller.state.artworkEntries, same(previousArtwork));
      expect(controller.state.lastScanCompletedAt, now);
      expect(store.saved?.completedAtUtc, now);
      expect(store.saveCalls, 1);
      expect(controller.needsBackgroundRefresh, isFalse);
    },
  );

  for (final changedKind in ['video', 'artwork', 'subtitle', 'counts']) {
    test('$changedKind changes publish a new complete inventory', () async {
      final inventory = cache.inventory();
      final controller = controllerFor(
        support.FakeStorageGateway(
          persistedRoots: [support.root],
          onEnumerate: completedScan,
        ),
        worker: (work) async => copyInventory(
          inventory,
          completedAt: work.completedAtUtc,
          videos: changedKind == 'video'
              ? [copyEntry(support.videoEntry, sizeBytes: 99)]
              : null,
          artwork: changedKind == 'artwork'
              ? [copyEntry(cache.artworkEntry, sizeBytes: 99)]
              : null,
          subtitles: changedKind == 'subtitle'
              ? [copyEntry(support.subtitleEntry, sizeBytes: 99)]
              : null,
          discoveredCount: changedKind == 'counts' ? 4 : null,
          ignoredCount: changedKind == 'counts' ? 2 : null,
        ),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      final previousEntries = controller.state.entries;

      await controller.refreshInBackground();

      expect(controller.state.entries, isNot(same(previousEntries)));
      expect(controller.state.scanCompleted, isTrue);
      expect(controller.state.lastScanCompletedAt, now);
    });
  }

  test(
    'activity during cache persistence cannot publish automatic results',
    () async {
      final saving = Completer<void>();
      final saved = Completer<void>();
      final store = cache.MemoryInventoryStore(
        saved: cache.inventory(),
        onSave: () {
          saving.complete();
          return saved.future;
        },
      );
      final controller = controllerFor(
        support.FakeStorageGateway(
          persistedRoots: [support.root],
          onEnumerate: completedScan,
        ),
        store: store,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      final previous = controller.state;

      final refreshing = controller.refreshInBackground();
      await saving.future;
      expect(controller.state, same(previous));
      controller.deferBackgroundRefresh();
      controller.selectFile(controller.state.entries.single);
      expect(controller.state.entries, same(previous.entries));
      saved.complete();
      await refreshing;

      expect(controller.state.entries, same(previous.entries));
      expect(
        controller.state.lastScanCompletedAt,
        previous.lastScanCompletedAt,
      );
      expect(controller.state.selectedFile, same(support.videoEntry));
      expect(controller.state.phase, RiskSpikePhase.fileReady);
      expect(controller.needsBackgroundRefresh, isTrue);
    },
  );

  test(
    'newer manual inventory is saved after an in-flight automatic write',
    () async {
      final saving = Completer<void>();
      final saved = Completer<void>();
      var writeCount = 0;
      final store = cache.MemoryInventoryStore(
        saved: cache.inventory(),
        onSave: () {
          if (writeCount++ == 0) {
            saving.complete();
            return saved.future;
          }
          return Future<void>.value();
        },
      );
      final controller = controllerFor(
        support.FakeStorageGateway(
          persistedRoots: [support.root],
          onEnumerate: (id, token) async* {
            if (id == 'scan-2') {
              yield StorageScanBatch(id, [support.videoEntry]);
            }
            yield StorageScanCompleted(id);
          },
        ),
        store: store,
      );
      addTearDown(controller.dispose);
      await controller.initialize();

      final automatic = controller.refreshInBackground();
      await saving.future;
      final manual = controller.scan(support.root);
      await Future<void>.delayed(Duration.zero);
      expect(store.saveCalls, 1);
      saved.complete();
      await Future.wait([automatic, manual]);

      expect(store.saveCalls, 2);
      expect(
        store.saved?.videos.single.storageKey,
        support.videoEntry.storageKey,
      );
      expect(
        controller.state.entries.single.storageKey,
        support.videoEntry.storageKey,
      );
      expect(controller.isBackgroundRefreshing, isFalse);
    },
  );

  test(
    'deferring in the begin listener prevents native scan startup',
    () async {
      final storage = support.FakeStorageGateway(
        persistedRoots: [support.root],
        onEnumerate: completedScan,
      );
      final controller = controllerFor(storage);
      addTearDown(controller.dispose);
      await controller.initialize();
      controller.addListener(() {
        if (controller.isBackgroundRefreshing) {
          controller.deferBackgroundRefresh();
        }
      });

      await controller.refreshInBackground();

      expect(storage.scanCount, 0);
      expect(controller.isBackgroundRefreshing, isFalse);
      expect(controller.needsBackgroundRefresh, isTrue);
    },
  );
}
