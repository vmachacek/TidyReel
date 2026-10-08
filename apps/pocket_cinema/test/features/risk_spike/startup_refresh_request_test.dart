import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_domain/media_domain.dart';
import 'package:media_platform_storage/media_platform_storage.dart';
import 'package:pocket_cinema/features/risk_spike/risk_spike_controller.dart';

import 'risk_spike_controller_test.dart' as support;
import 'risk_spike_inventory_test.dart' as cache;

void main() {
  RiskSpikeController controllerFor(support.FakeStorageGateway storage) =>
      RiskSpikeController(
        storage: storage,
        probe: support.FakeMediaProbe(),
        playback: support.FakePlaybackSession(),
        inventoryStore: cache.MemoryInventoryStore(saved: cache.inventory()),
      );

  Stream<StorageScanEvent> failedScan(String scanId, Object _) =>
      Stream.value(StorageScanFailed(scanId, support.scanFailure));

  test(
    'restoring cache queues one refresh without depending on its result',
    () async {
      final storage = support.FakeStorageGateway(
        persistedRoots: [support.root],
        onEnumerate: failedScan,
      );
      final controller = controllerFor(storage);
      addTearDown(controller.dispose);

      await controller.initialize();
      expect(controller.state.entries, hasLength(1));
      expect(controller.needsStartupRefresh, isTrue);
      expect(storage.scanCount, 0);

      await controller.refreshOnStartup();
      await controller.refreshOnStartup();
      expect(storage.scanCount, 1);
      expect(controller.state.entries, hasLength(1));
      expect(controller.state.scanCompleted, isTrue);
      expect(controller.needsStartupRefresh, isFalse);
    },
  );

  test('a manual scan supersedes a queued startup refresh', () async {
    final storage = support.FakeStorageGateway(
      persistedRoots: [support.root],
      onEnumerate: failedScan,
    );
    final controller = controllerFor(storage);
    addTearDown(controller.dispose);
    await controller.initialize();

    await controller.scan(support.root);
    await controller.refreshOnStartup();
    expect(storage.scanCount, 1);
    expect(controller.needsStartupRefresh, isFalse);
  });

  test(
    'choosing another folder invalidates a queued startup refresh',
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
      await controller.refreshOnStartup();
      expect(storage.scanCount, 0);
      expect(controller.state.root, cache.otherRoot);
      expect(controller.needsStartupRefresh, isFalse);
    },
  );

  test('disposal invalidates a queued startup refresh', () async {
    final storage = support.FakeStorageGateway(
      persistedRoots: [support.root],
      onEnumerate: failedScan,
    );
    final controller = controllerFor(storage);
    await controller.initialize();

    controller.dispose();
    await controller.refreshOnStartup();
    expect(storage.scanCount, 0);
    expect(controller.needsStartupRefresh, isFalse);
  });

  test(
    'playback failure does not enable duplicate scans during refresh',
    () async {
      final events = StreamController<StorageScanEvent>();
      final storage = support.FakeStorageGateway(
        persistedRoots: [support.root],
        openFailure: support.fileUnavailableFailure,
        onEnumerate: (_, token) => events.stream,
      );
      final controller = controllerFor(storage);
      addTearDown(controller.dispose);
      await controller.initialize();
      final refreshing = controller.refreshOnStartup();
      await Future<void>.delayed(Duration.zero);

      controller.selectFile(controller.state.entries.single);
      await controller.playSelected();
      expect(controller.state.failure, support.fileUnavailableFailure);
      expect(controller.state.canCancel, isTrue);
      expect(controller.state.canRescan, isFalse);

      events.add(const StorageScanFailed('scan-1', support.scanFailure));
      await events.close();
      await refreshing;
      expect(controller.state.canCancel, isFalse);
      expect(controller.state.canRescan, isTrue);
    },
  );
}
