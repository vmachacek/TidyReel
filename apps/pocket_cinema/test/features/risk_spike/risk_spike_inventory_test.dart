import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_domain/media_domain.dart';
import 'package:media_platform_storage/media_platform_storage.dart';
import 'package:pocket_cinema/features/risk_spike/risk_spike_controller.dart';
import 'package:pocket_cinema/features/risk_spike/risk_spike_state.dart';
import 'package:pocket_cinema/features/risk_spike/scan_inventory_store.dart';

import 'risk_spike_controller_test.dart' as support;

const otherRoot = AuthorizedLibraryRoot(
  locator: LibraryRootLocator(
    storageKind: StorageKind.androidSaf,
    opaqueValue: 'content://redacted/tree/other',
  ),
  displayName: 'Other folder',
);

final completedAt = DateTime.utc(2026, 10, 8, 12);
final artworkEntry = StorageEntrySnapshot(
  storageKey: 'provider|poster',
  parentStorageKey: 'provider|folder',
  relativePath: 'poster.jpg',
  displayName: 'poster.jpg',
  isDirectory: false,
  mimeType: 'image/jpeg',
  sizeBytes: 256,
  modifiedAtUtc: completedAt,
  flags: const {StorageEntryFlag.supportsRead},
);

ScanInventory inventory({LibraryRootLocator? root, bool empty = false}) =>
    ScanInventory(
      root: root ?? support.root.locator,
      videos: empty ? [] : [support.videoEntry],
      artwork: empty ? [] : [artworkEntry],
      subtitles: empty ? [] : [support.subtitleEntry],
      discoveredCount: empty ? 0 : 3,
      ignoredCount: empty ? 0 : 1,
      completedAtUtc: completedAt,
    );

void main() {
  RiskSpikeController controllerFor(
    support.FakeStorageGateway storage,
    MemoryInventoryStore store, {
    support.FakePlaybackSession? playback,
  }) {
    final controller = RiskSpikeController(
      storage: storage,
      probe: support.FakeMediaProbe(),
      playback: playback ?? support.FakePlaybackSession(),
      inventoryStore: store,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  test(
    'startup restores complete inventory and cached subtitle matching',
    () async {
      final store = MemoryInventoryStore(saved: inventory());
      final storage = support.FakeStorageGateway(
        persistedRoots: [support.root],
        lease: support.directLease,
        subtitleContent: SmallFileContent(Uint8List.fromList([1, 2])),
      );
      final playback = support.FakePlaybackSession(allowSubtitle: true);
      final controller = controllerFor(storage, store, playback: playback);
      final phases = <RiskSpikePhase>[];
      controller.addListener(() => phases.add(controller.state.phase));

      await controller.initialize();

      expect(phases, [
        RiskSpikePhase.checkingGrant,
        RiskSpikePhase.filesAvailable,
      ]);
      expect(controller.state.scanCompleted, isTrue);
      expect(controller.state.canRescan, isTrue);
      expect(controller.state.lastScanCompletedAt, completedAt);
      expect(
        controller.state.entries.single.storageKey,
        support.videoEntry.storageKey,
      );
      expect(
        controller.state.artworkEntries.single.storageKey,
        artworkEntry.storageKey,
      );
      expect(controller.state.discoveredCount, 3);
      expect(controller.state.videoCount, 1);
      expect(controller.state.subtitleCount, 1);
      expect(controller.state.ignoredCount, 1);
      expect(storage.scanCount, 0);
      controller.selectFile(controller.state.entries.single);
      await controller.playSelected();
      expect(storage.readKeys, [support.subtitleEntry.storageKey]);
      expect(playback.subtitleLanguages, ['en']);
    },
  );

  test(
    'valid empty inventory is complete and needs no automatic rescan',
    () async {
      final store = MemoryInventoryStore(saved: inventory(empty: true));
      final storage = support.FakeStorageGateway(
        persistedRoots: [support.root],
      );
      final controller = controllerFor(storage, store);

      await controller.initialize();

      expect(controller.state.phase, RiskSpikePhase.filesAvailable);
      expect(controller.state.scanCompleted, isTrue);
      expect(controller.state.entries, isEmpty);
      expect(storage.scanCount, 0);
    },
  );

  for (final loadFails in [false, true]) {
    test(
      'missing or inaccessible cache falls back to ready ($loadFails)',
      () async {
        final store = MemoryInventoryStore(loadFails: loadFails);
        final controller = controllerFor(
          support.FakeStorageGateway(persistedRoots: [support.root]),
          store,
        );

        await controller.initialize();

        expect(controller.state.phase, RiskSpikePhase.ready);
        expect(controller.state.scanCompleted, isFalse);
        expect(controller.state.failure, isNull);
      },
    );
  }

  test('cached folder is selected only from still-authorized grants', () async {
    final store = MemoryInventoryStore(
      saved: inventory(root: otherRoot.locator),
    );
    final storage = support.FakeStorageGateway(
      persistedRoots: [support.root, otherRoot],
    );
    final controller = controllerFor(storage, store);

    await controller.initialize();

    expect(controller.state.root, same(otherRoot));
    expect(controller.state.scanCompleted, isTrue);
    expect(
      storage.checkedRoots.single.opaqueValue,
      otherRoot.locator.opaqueValue,
    );
  });

  test(
    'cache from an ungranted folder cannot populate the active library',
    () async {
      final store = MemoryInventoryStore(
        saved: inventory(root: otherRoot.locator),
      );
      final storage = support.FakeStorageGateway(
        persistedRoots: [support.root],
      );
      final controller = controllerFor(storage, store);

      await controller.initialize();

      expect(controller.state.root, same(support.root));
      expect(controller.state.phase, RiskSpikePhase.ready);
      expect(controller.state.entries, isEmpty);
      expect(controller.state.scanCompleted, isFalse);
    },
  );

  test('revoked folder access blocks cache restoration', () async {
    final controller = controllerFor(
      support.FakeStorageGateway(
        persistedRoots: [support.root],
        accessState: RootAccessState.permissionRevoked,
      ),
      MemoryInventoryStore(saved: inventory()),
    );

    await controller.initialize();

    expect(controller.state.canRepairRoot, isTrue);
    expect(controller.state.entries, isEmpty);
    expect(controller.state.scanCompleted, isFalse);
  });

  test('complete scan is saved before its future completes', () async {
    final writing = Completer<void>();
    final store = MemoryInventoryStore(onSave: () => writing.future);
    final storage = support.FakeStorageGateway.scan([
      StorageScanBatch('scan-1', [
        support.videoEntry,
        support.subtitleEntry,
        artworkEntry,
      ]),
      const StorageScanCompleted('scan-1'),
    ]);
    final controller = controllerFor(storage, store);
    var returned = false;
    final scanning = controller.scan(support.root).then((_) => returned = true);
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.scanCompleted, isTrue);
    expect(returned, isFalse);
    expect(store.saveCalls, 1);
    writing.complete();
    await scanning;

    expect(
      store.saved?.videos.single.storageKey,
      support.videoEntry.storageKey,
    );
    expect(
      store.saved?.subtitles.single.storageKey,
      support.subtitleEntry.storageKey,
    );
    expect(store.saved?.artwork.single.storageKey, artworkEntry.storageKey);
    expect(store.saved?.discoveredCount, 3);
    expect(store.saved?.completedAtUtc.isUtc, isTrue);
  });

  test('cache write failure leaves the successful live scan usable', () async {
    final controller = controllerFor(
      support.FakeStorageGateway.scan([
        StorageScanBatch('scan-1', [support.videoEntry]),
        const StorageScanCompleted('scan-1'),
      ]),
      MemoryInventoryStore(saveFails: true),
    );

    await controller.scan(support.root);

    expect(controller.state.scanCompleted, isTrue);
    expect(controller.state.phase, RiskSpikePhase.filesAvailable);
    expect(controller.state.failure, isNull);
  });

  for (final terminal in [
    const StorageScanFailed('scan-1', support.scanFailure),
    const StorageScanCancelled('scan-1'),
  ]) {
    test(
      'unsuccessful refresh retains previous complete inventory (${terminal.runtimeType})',
      () async {
        final oldInventory = inventory();
        final store = MemoryInventoryStore(saved: oldInventory);
        final storage = support.FakeStorageGateway(
          persistedRoots: [support.root],
          scanEvents: [
            StorageScanBatch('scan-1', [support.videoEntry]),
            terminal,
          ],
        );
        final controller = controllerFor(storage, store);
        await controller.initialize();
        final previousEntries = controller.state.entries;

        await controller.scan(support.root);

        expect(controller.state.entries, same(previousEntries));
        expect(controller.state.scanCompleted, isTrue);
        expect(controller.state.discoveredCount, 3);
        expect(controller.state.subtitleCount, 1);
        expect(controller.state.lastScanCompletedAt, completedAt);
        expect(store.saved, same(oldInventory));
        expect(store.saveCalls, 0);
        expect(controller.state.canRescan, isTrue);
      },
    );
  }

  test(
    'refresh swaps complete inventories without showing batches of new entries',
    () async {
      final complete = Completer<void>();
      final batchReceived = Completer<void>();
      final store = MemoryInventoryStore(saved: inventory());
      final storage = support.FakeStorageGateway(
        persistedRoots: [support.root],
        onEnumerate: (scanId, token) async* {
          yield StorageScanBatch(scanId, [artworkEntry]);
          batchReceived.complete();
          await complete.future;
          yield StorageScanCompleted(scanId);
        },
      );
      final controller = controllerFor(storage, store);
      await controller.initialize();
      final previousEntries = controller.state.entries;
      final scanning = controller.scan(support.root);
      await batchReceived.future;

      expect(controller.state.phase, RiskSpikePhase.enumerating);
      expect(controller.state.entries, same(previousEntries));
      expect(controller.state.scanCompleted, isTrue);
      complete.complete();
      await scanning;

      expect(controller.state.entries, isEmpty);
      expect(
        controller.state.artworkEntries.single.storageKey,
        artworkEntry.storageKey,
      );
      expect(controller.state.discoveredCount, 1);
      expect(store.saveCalls, 1);
    },
  );

  test(
    'stream ending without a terminal event cannot replace the cache',
    () async {
      final oldInventory = inventory();
      final store = MemoryInventoryStore(saved: oldInventory);
      final controller = controllerFor(
        support.FakeStorageGateway(
          persistedRoots: [support.root],
          scanEvents: [
            StorageScanBatch('scan-1', [support.videoEntry]),
          ],
        ),
        store,
      );
      await controller.initialize();

      await controller.scan(support.root);

      expect(controller.state.phase, RiskSpikePhase.failure);
      expect(controller.state.scanCompleted, isTrue);
      expect(controller.state.discoveredCount, 3);
      expect(store.saved, same(oldInventory));
      expect(store.saveCalls, 0);
    },
  );

  test('explicit cancellation rejects a late completed event', () async {
    final resume = Completer<void>();
    final started = Completer<void>();
    final store = MemoryInventoryStore();
    final controller = controllerFor(
      support.FakeStorageGateway(
        onEnumerate: (id, token) async* {
          started.complete();
          await resume.future;
          yield StorageScanCompleted(id);
        },
      ),
      store,
    );
    final scanning = controller.scan(support.root);
    await started.future;
    controller.cancelScan();
    resume.complete();
    await scanning;

    expect(controller.state.phase, RiskSpikePhase.cancelled);
    expect(controller.state.scanCompleted, isFalse);
    expect(store.saveCalls, 0);
  });

  test('changing folders prevents a pending startup cache read from restoring the old folder', () async {
    final loaded = Completer<ScanInventory?>();
    final store = MemoryInventoryStore(onLoad: () => loaded.future);
    final controller = controllerFor(
      support.FakeStorageGateway(
        persistedRoots: [support.root],
        onChoose: () async => const Success<AuthorizedLibraryRoot>(otherRoot),
      ),
      store,
    );
    final initializing = controller.initialize();
    await Future<void>.delayed(Duration.zero);
    final choosing = controller.chooseRoot();
    loaded.complete(inventory());
    await Future.wait([initializing, choosing]);

    expect(controller.state.root, same(otherRoot));
    expect(controller.state.phase, RiskSpikePhase.ready);
    expect(controller.state.entries, isEmpty);
  });

  test(
    'changing folders invalidates scan events and their cache writes',
    () async {
      final resume = Completer<void>();
      final started = Completer<void>();
      final store = MemoryInventoryStore();
      final controller = controllerFor(
        support.FakeStorageGateway(
          onChoose: () async => const Success<AuthorizedLibraryRoot>(otherRoot),
          onEnumerate: (id, token) async* {
            started.complete();
            await resume.future;
            yield StorageScanBatch(id, [support.videoEntry]);
            yield StorageScanCompleted(id);
          },
        ),
        store,
      );
      final scanning = controller.scan(support.root);
      await started.future;
      await controller.chooseRoot();
      resume.complete();
      await scanning;

      expect(controller.state.root, same(otherRoot));
      expect(controller.state.entries, isEmpty);
      expect(store.saveCalls, 0);
    },
  );

  test('releasing a folder removes its saved inventory', () async {
    final store = MemoryInventoryStore(saved: inventory());
    final controller = controllerFor(
      support.FakeStorageGateway(
        persistedRoots: [support.root],
        releaseRootSucceeds: true,
      ),
      store,
      playback: support.FakePlaybackSession(allowStop: true),
    );
    await controller.initialize();

    await controller.releaseRoot();

    expect(store.saved, isNull);
    expect(store.clearCalls, 1);
    expect(controller.state.entries, isEmpty);
    expect(controller.state.canRepairRoot, isTrue);
  });

  test('disposing prevents pending cache restoration from emitting', () async {
    final loaded = Completer<ScanInventory?>();
    final controller = RiskSpikeController(
      storage: support.FakeStorageGateway(persistedRoots: [support.root]),
      probe: support.FakeMediaProbe(),
      playback: support.FakePlaybackSession(),
      inventoryStore: MemoryInventoryStore(onLoad: () => loaded.future),
    );
    final initializing = controller.initialize();
    await Future<void>.delayed(Duration.zero);
    controller.dispose();
    loaded.complete(inventory());
    await initializing;

    expect(controller.state.phase, RiskSpikePhase.checkingGrant);
  });
}

final class MemoryInventoryStore implements ScanInventoryStore {
  MemoryInventoryStore({
    this.saved,
    this.loadFails = false,
    this.saveFails = false,
    this.onLoad,
    this.onSave,
  });
  ScanInventory? saved;
  final bool loadFails, saveFails;
  final Future<ScanInventory?> Function()? onLoad;
  final Future<void> Function()? onSave;
  int saveCalls = 0, clearCalls = 0;

  @override
  Future<ScanInventory?> load() async {
    if (loadFails) throw StateError('Storage unavailable');
    return onLoad == null ? saved : await onLoad!();
  }

  @override
  Future<void> save(ScanInventory inventory) async {
    saveCalls++;
    await onSave?.call();
    if (saveFails) throw StateError('Storage unavailable');
    saved = inventory;
  }

  @override
  Future<void> clear() async {
    clearCalls++;
    saved = null;
  }
}
