import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_domain/media_domain.dart';
import 'package:media_platform_storage/media_platform_storage.dart';
import 'package:media_playback/media_playback.dart';
import 'package:pocket_cinema/features/risk_spike/risk_spike_controller.dart';
import 'package:pocket_cinema/features/risk_spike/risk_spike_state.dart';
import 'package:pocket_cinema/features/risk_spike/scan_inventory_store.dart';
import 'package:pocket_cinema/features/risk_spike/scan_inventory_worker.dart';

import 'risk_spike_controller_test.dart' as support;
import 'risk_spike_inventory_test.dart' as inventory_support;

RiskSpikeState cachedState({
  RiskSpikePhase phase = RiskSpikePhase.filesAvailable,
  MediaProbeResult? probe,
  PlaybackSnapshot playback = const PlaybackSnapshot.closed(),
}) => RiskSpikeState(
  phase: phase,
  root: support.root,
  entries: [support.videoEntry],
  artworkEntries: [inventory_support.artworkEntry],
  selectedFile: phase == RiskSpikePhase.filesAvailable
      ? null
      : support.videoEntry,
  probeResult: probe,
  playbackSnapshot: playback,
  discoveredCount: 3,
  ignoredCount: 1,
  videoCount: 1,
  subtitleCount: 1,
  scanCompleted: true,
  lastScanCompletedAt: inventory_support.completedAt,
);

void main() {
  RiskSpikeController controllerFor(
    support.FakeStorageGateway storage,
    inventory_support.MemoryInventoryStore store, {
    required ScanInventoryWorker worker,
    RiskSpikeState? initialState,
  }) {
    final controller = RiskSpikeController(
      storage: storage,
      probe: support.FakeMediaProbe(),
      playback: support.FakePlaybackSession(),
      inventoryStore: store,
      inventoryWorker: worker,
      initialState: initialState ?? cachedState(),
    );
    addTearDown(controller.dispose);
    return controller;
  }

  test(
    'cached refresh publishes bounded progress and one complete swap',
    () async {
      final started = Completer<ScanInventoryWork>();
      final classified = Completer<ScanInventory>();
      final store = inventory_support.MemoryInventoryStore();
      final batch = [support.subtitleEntry];
      final controller = controllerFor(
        support.FakeStorageGateway(
          onEnumerate: (id, token) async* {
            for (var index = 0; index < 500; index++) {
              yield StorageScanBatch(id, batch);
            }
            yield StorageScanCompleted(id);
          },
        ),
        store,
        worker: (work) {
          started.complete(work);
          return classified.future;
        },
      );
      final previousEntries = controller.state.entries;
      final previousArtwork = controller.state.artworkEntries;
      var updates = 0;
      controller.addListener(() => updates++);

      final scanning = controller.scan(support.root);
      final work = await started.future;

      expect(work.batches, hasLength(500));
      expect(work.batches.first, orderedEquals(batch));
      expect(() => work.batches.first.clear(), throwsUnsupportedError);
      expect(controller.state.entries, same(previousEntries));
      expect(controller.state.artworkEntries, same(previousArtwork));
      expect(controller.state.videoCount, 1);
      expect(controller.state.subtitleCount, 1);
      expect(controller.state.canCancel, isTrue);
      expect(controller.state.canRescan, isFalse);
      expect(updates, lessThan(20));
      expect(store.saveCalls, 0);

      classified.complete(classifyScanInventory(work));
      await scanning;

      expect(controller.state.entries, isEmpty);
      expect(controller.state.videoCount, 0);
      expect(controller.state.subtitleCount, 500);
      expect(controller.state.discoveredCount, 500);
      expect(controller.state.canCancel, isFalse);
      expect(controller.state.canRescan, isTrue);
      expect(store.saveCalls, 1);
    },
  );

  for (final phase in [
    RiskSpikePhase.fileReady,
    RiskSpikePhase.probing,
    RiskSpikePhase.openingPlayback,
    RiskSpikePhase.playing,
  ]) {
    test('refresh preserves interactive state during $phase', () async {
      const probe = MediaProbeResult(streamCount: 2, width: 1920, height: 1080);
      const playback = PlaybackSnapshot(
        isOpen: true,
        isPlaying: true,
        position: Duration(minutes: 3),
      );
      final started = Completer<ScanInventoryWork>();
      final classified = Completer<ScanInventory>();
      final controller = controllerFor(
        support.FakeStorageGateway(
          onEnumerate: (id, token) async* {
            yield StorageScanBatch(id, [support.videoEntry]);
            yield StorageScanCompleted(id);
          },
        ),
        inventory_support.MemoryInventoryStore(),
        worker: (work) {
          started.complete(work);
          return classified.future;
        },
        initialState: cachedState(
          phase: phase,
          probe: probe,
          playback: playback,
        ),
      );

      final scanning = controller.scan(support.root);
      final work = await started.future;
      expect(controller.state.phase, phase);
      expect(controller.state.selectedFile, same(support.videoEntry));
      expect(controller.state.probeResult, same(probe));
      expect(controller.state.playbackSnapshot, same(playback));
      expect(controller.state.canCancel, isTrue);

      classified.complete(classifyScanInventory(work));
      await scanning;

      expect(controller.state.phase, phase);
      expect(controller.state.selectedFile, same(support.videoEntry));
      expect(controller.state.probeResult, same(probe));
      expect(controller.state.playbackSnapshot, same(playback));
      expect(controller.state.canCancel, isFalse);
    });
  }

  for (final cancelled in [false, true]) {
    test(
      'unsuccessful held refresh leaves healthy playback intact (cancelled: $cancelled)',
      () async {
        const playback = PlaybackSnapshot(
          isOpen: true,
          isPlaying: true,
          position: Duration(minutes: 3),
          duration: Duration(minutes: 30),
        );
        final started = Completer<void>();
        final finish = Completer<void>();
        final store = inventory_support.MemoryInventoryStore();
        final controller = controllerFor(
          support.FakeStorageGateway(
            onEnumerate: (id, token) async* {
              yield StorageScanBatch(id, [support.subtitleEntry]);
              started.complete();
              await finish.future;
              yield cancelled
                  ? StorageScanCancelled(id)
                  : StorageScanFailed(id, support.scanFailure);
            },
          ),
          store,
          worker: (work) async => classifyScanInventory(work),
          initialState: cachedState(
            phase: RiskSpikePhase.playing,
            playback: playback,
          ),
        );
        final previousEntries = controller.state.entries;
        final scanning = controller.scan(support.root);
        await started.future;

        expect(controller.state.phase, RiskSpikePhase.playing);
        expect(controller.state.playbackSnapshot, same(playback));
        expect(controller.state.selectedFile, same(support.videoEntry));
        expect(controller.state.failure, isNull);
        expect(controller.state.canCancel, isTrue);

        finish.complete();
        await scanning;

        expect(controller.state.phase, RiskSpikePhase.playing);
        expect(controller.state.playbackSnapshot, same(playback));
        expect(controller.state.selectedFile, same(support.videoEntry));
        expect(controller.state.entries, same(previousEntries));
        expect(controller.state.failure, isNull);
        expect(
          controller.state.refreshFailure,
          cancelled ? isNull : same(support.scanFailure),
        );
        expect(
          controller.state.libraryFailure,
          cancelled ? isNull : same(support.scanFailure),
        );
        expect(controller.state.scanCompleted, isTrue);
        expect(controller.state.canCancel, isFalse);
        expect(store.saveCalls, 0);
      },
    );
  }

  test(
    'successful classification preserves a concurrent playback failure',
    () async {
      final started = Completer<ScanInventoryWork>();
      final classified = Completer<ScanInventory>();
      final store = inventory_support.MemoryInventoryStore();
      final controller = controllerFor(
        support.FakeStorageGateway(
          openFailure: support.fileUnavailableFailure,
          onEnumerate: (id, token) async* {
            yield StorageScanBatch(id, [support.videoEntry]);
            yield StorageScanCompleted(id);
          },
        ),
        store,
        worker: (work) {
          started.complete(work);
          return classified.future;
        },
        initialState: cachedState(phase: RiskSpikePhase.fileReady),
      );
      final scanning = controller.scan(support.root);
      final work = await started.future;

      await controller.playSelected();
      expect(controller.state.phase, RiskSpikePhase.failure);
      expect(controller.state.failure, same(support.fileUnavailableFailure));
      expect(controller.state.canCancel, isTrue);

      classified.complete(classifyScanInventory(work));
      await scanning;

      expect(controller.state.phase, RiskSpikePhase.failure);
      expect(controller.state.failure, same(support.fileUnavailableFailure));
      expect(
        controller.state.libraryFailure,
        same(support.fileUnavailableFailure),
      );
      expect(controller.state.refreshFailure, isNull);
      expect(controller.state.selectedFile, same(support.videoEntry));
      expect(controller.state.scanCompleted, isTrue);
      expect(controller.state.canCancel, isFalse);
      expect(store.saveCalls, 1);
    },
  );

  test('revoked access invalidates a pending classification result', () async {
    final started = Completer<ScanInventoryWork>();
    final classified = Completer<ScanInventory>();
    final store = inventory_support.MemoryInventoryStore();
    final controller = controllerFor(
      support.FakeStorageGateway(
        openFailure: support.permissionRevokedFailure,
        onEnumerate: (id, token) async* {
          yield StorageScanCompleted(id);
        },
      ),
      store,
      worker: (work) {
        started.complete(work);
        return classified.future;
      },
      initialState: cachedState(phase: RiskSpikePhase.fileReady),
    );
    final previousEntries = controller.state.entries;
    final scanning = controller.scan(support.root);
    final work = await started.future;

    await controller.playSelected();
    expect(controller.state.failure, same(support.permissionRevokedFailure));
    expect(controller.state.canCancel, isFalse);
    expect(controller.state.canRepairRoot, isTrue);

    classified.complete(classifyScanInventory(work));
    await scanning;

    expect(controller.state.phase, RiskSpikePhase.failure);
    expect(controller.state.failure, same(support.permissionRevokedFailure));
    expect(controller.state.refreshFailure, isNull);
    expect(controller.state.entries, same(previousEntries));
    expect(controller.state.canRepairRoot, isTrue);
    expect(store.saveCalls, 0);
  });

  test(
    'cancelling during classification rejects the late worker result',
    () async {
      final started = Completer<ScanInventoryWork>();
      final classified = Completer<ScanInventory>();
      final store = inventory_support.MemoryInventoryStore();
      final controller = controllerFor(
        support.FakeStorageGateway(
          onEnumerate: (id, token) async* {
            yield StorageScanCompleted(id);
          },
        ),
        store,
        worker: (work) {
          started.complete(work);
          return classified.future;
        },
      );
      final previousEntries = controller.state.entries;
      final scanning = controller.scan(support.root);
      final work = await started.future;

      controller.cancelScan();
      classified.complete(classifyScanInventory(work));
      await scanning;

      expect(controller.state.phase, RiskSpikePhase.cancelled);
      expect(controller.state.entries, same(previousEntries));
      expect(controller.state.discoveredCount, 3);
      expect(
        controller.state.lastScanCompletedAt,
        inventory_support.completedAt,
      );
      expect(controller.state.canCancel, isFalse);
      expect(store.saveCalls, 0);
    },
  );

  test('a newer scan rejects an older classification result', () async {
    final firstStarted = Completer<ScanInventoryWork>();
    final firstClassified = Completer<ScanInventory>();
    final store = inventory_support.MemoryInventoryStore();
    var workerCalls = 0;
    final controller = controllerFor(
      support.FakeStorageGateway(
        onEnumerate: (id, token) async* {
          if (id == 'scan-2') {
            yield StorageScanBatch(id, [support.videoEntry]);
          }
          yield StorageScanCompleted(id);
        },
      ),
      store,
      worker: (work) async {
        workerCalls++;
        if (workerCalls == 1) {
          firstStarted.complete(work);
          return firstClassified.future;
        }
        return classifyScanInventory(work);
      },
    );
    final firstScan = controller.scan(support.root);
    final firstWork = await firstStarted.future;

    await controller.scan(support.root);
    final currentEntries = controller.state.entries;
    firstClassified.complete(classifyScanInventory(firstWork));
    await firstScan;

    expect(workerCalls, 2);
    expect(controller.state.entries, same(currentEntries));
    expect(
      controller.state.entries.single.storageKey,
      support.videoEntry.storageKey,
    );
    expect(controller.state.discoveredCount, 1);
    expect(controller.state.scanCompleted, isTrue);
    expect(
      store.saved?.videos.single.storageKey,
      support.videoEntry.storageKey,
    );
    expect(store.saveCalls, 1);
  });

  test(
    'switching folders during classification rejects the old result',
    () async {
      final started = Completer<ScanInventoryWork>();
      final classified = Completer<ScanInventory>();
      final store = inventory_support.MemoryInventoryStore();
      final controller = controllerFor(
        support.FakeStorageGateway(
          onChoose: () async =>
              const Success<AuthorizedLibraryRoot>(inventory_support.otherRoot),
          onEnumerate: (id, token) async* {
            yield StorageScanCompleted(id);
          },
        ),
        store,
        worker: (work) {
          started.complete(work);
          return classified.future;
        },
      );
      final scanning = controller.scan(support.root);
      final work = await started.future;

      await controller.chooseRoot();
      classified.complete(classifyScanInventory(work));
      await scanning;

      expect(controller.state.root, same(inventory_support.otherRoot));
      expect(controller.state.entries, isEmpty);
      expect(controller.state.phase, RiskSpikePhase.ready);
      expect(controller.state.scanCompleted, isFalse);
      expect(store.saveCalls, 0);
    },
  );

  test(
    'disposing during classification rejects the late worker result',
    () async {
      final started = Completer<ScanInventoryWork>();
      final classified = Completer<ScanInventory>();
      final store = inventory_support.MemoryInventoryStore();
      final controller = RiskSpikeController(
        storage: support.FakeStorageGateway(
          onEnumerate: (id, token) async* {
            yield StorageScanCompleted(id);
          },
        ),
        probe: support.FakeMediaProbe(),
        playback: support.FakePlaybackSession(),
        inventoryStore: store,
        inventoryWorker: (work) {
          started.complete(work);
          return classified.future;
        },
        initialState: cachedState(),
      );
      final scanning = controller.scan(support.root);
      final work = await started.future;

      controller.dispose();
      classified.complete(classifyScanInventory(work));
      await scanning;

      expect(store.saveCalls, 0);
    },
  );
}
