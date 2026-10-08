import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_platform_storage/media_platform_storage.dart';
import 'package:pocket_cinema/features/risk_spike/scan_inventory_store.dart';

const root = LibraryRootLocator(
  storageKind: StorageKind.androidSaf,
  opaqueValue: 'content://provider/tree/movies',
);

final video = StorageEntrySnapshot(
  storageKey: 'provider|folder/video',
  parentStorageKey: 'provider|folder',
  relativePath: 'Movies/Movie.mp4',
  displayName: 'Movie.mp4',
  isDirectory: false,
  mimeType: 'video/mp4',
  sizeBytes: 512,
  modifiedAtUtc: DateTime.utc(2026, 10, 8),
  flags: const {
    StorageEntryFlag.supportsRead,
    StorageEntryFlag.virtualDocument,
  },
);

ScanInventory inventory({bool empty = false}) => ScanInventory(
  root: root,
  videos: empty ? [] : [video],
  artwork: [],
  subtitles: [],
  discoveredCount: empty ? 0 : 1,
  ignoredCount: 0,
  completedAtUtc: DateTime.utc(2026, 10, 8, 12),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('inventory JSON preserves playback keys and optional metadata', () {
    final encoded = inventory().encode();
    final restored = ScanInventory.decode(encoded)!;
    expect(restored.matchesRoot(root), isTrue);
    expect(restored.completedAtUtc, DateTime.utc(2026, 10, 8, 12));
    final file = restored.videos.single;
    expect(file.storageKey, video.storageKey);
    expect(file.parentStorageKey, video.parentStorageKey);
    expect(file.relativePath, video.relativePath);
    expect(file.displayName, video.displayName);
    expect(file.mimeType, video.mimeType);
    expect(file.sizeBytes, video.sizeBytes);
    expect(file.modifiedAtUtc, video.modifiedAtUtc);
    expect(file.flags, video.flags);

    final noMetadata = jsonDecode(encoded) as Map<String, dynamic>;
    final entry =
        (noMetadata['videos'] as List<dynamic>).single as Map<String, dynamic>;
    entry['sizeBytes'] = null;
    entry['mimeType'] = null;
    entry['parentStorageKey'] = null;
    entry['modifiedAtUtc'] = null;
    final restoredWithoutMetadata = ScanInventory.decode(
      jsonEncode(noMetadata),
    )!;
    expect(restoredWithoutMetadata.videos.single.sizeBytes, isNull);
    expect(restoredWithoutMetadata.videos.single.mimeType, isNull);
    expect(restoredWithoutMetadata.videos.single.parentStorageKey, isNull);
    expect(restoredWithoutMetadata.videos.single.modifiedAtUtc, isNull);
  });

  test('valid empty complete inventory round trips', () {
    final restored = ScanInventory.decode(inventory(empty: true).encode())!;
    expect(restored.videos, isEmpty);
    expect(restored.discoveredCount, 0);
  });

  test('unsupported or damaged cache is a cache miss', () {
    expect(ScanInventory.decode('not json'), isNull);
    expect(ScanInventory.decode('{}'), isNull);
    expect(ScanInventory.decode('[]'), isNull);
    for (final corrupt in <void Function(Map<String, dynamic>)>[
      (data) => data['version'] = 999,
      (data) => data['discoveredCount'] = 0,
      (data) => data['ignoredCount'] = -1,
      (data) => data['completedAtUtc'] = 'yesterday',
      (data) =>
          (data['root'] as Map<String, dynamic>)['storageKind'] = 'unknown',
      (data) => (data['root'] as Map<String, dynamic>)['opaqueValue'] = '',
      (data) => (data['videos'] as List<dynamic>).single['storageKey'] = '',
      (data) => (data['videos'] as List<dynamic>).single['sizeBytes'] = -1,
      (data) => (data['videos'] as List<dynamic>).single['flags'] = ['unknown'],
    ]) {
      final data = jsonDecode(inventory().encode()) as Map<String, dynamic>;
      corrupt(data);
      expect(ScanInventory.decode(jsonEncode(data)), isNull);
    }
  });

  test('cache root comparison includes the exact locator', () {
    expect(
      inventory().matchesRoot(
        const LibraryRootLocator(
          storageKind: StorageKind.androidSaf,
          opaqueValue: 'content://provider/tree/other',
        ),
      ),
      isFalse,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(PlatformScanInventoryStore.channel, null);
  });

  test(
    'platform store decodes inventory and treats corrupt data as missing',
    () async {
      String? raw = inventory().encode();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(PlatformScanInventoryStore.channel, (
            call,
          ) async {
            expect(call.method, 'loadScanInventory');
            return raw;
          });
      final store = PlatformScanInventoryStore();

      expect((await store.load())?.videos.single.storageKey, video.storageKey);
      raw = 'broken JSON';
      expect(await store.load(), isNull);
      raw = null;
      expect(await store.load(), isNull);
    },
  );

  test(
    'platform store serializes writes and loads after pending save',
    () async {
      final firstWrite = Completer<void>();
      final methods = <String>[];
      String? raw;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(PlatformScanInventoryStore.channel, (
            call,
          ) async {
            methods.add(call.method);
            if (call.method == 'saveScanInventory') {
              await firstWrite.future;
              raw =
                  (call.arguments as Map<dynamic, dynamic>)['value'] as String;
            }
            if (call.method == 'clearScanInventory') raw = null;
            if (call.method == 'loadScanInventory') return raw;
            return null;
          });
      final store = PlatformScanInventoryStore();
      final save = store.save(inventory());
      final clear = store.clear();
      final load = store.load();
      firstWrite.complete();
      await Future.wait([save, clear]);

      expect(await load, isNull);
      expect(methods, [
        'saveScanInventory',
        'clearScanInventory',
        'loadScanInventory',
      ]);
    },
  );

  test('later platform operations recover after a failed save', () async {
    var saveCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(PlatformScanInventoryStore.channel, (
          call,
        ) async {
          if (call.method == 'saveScanInventory' && ++saveCalls == 1) {
            throw PlatformException(code: 'STORAGE_ERROR');
          }
          return null;
        });
    final store = PlatformScanInventoryStore();

    await expectLater(
      store.save(inventory()),
      throwsA(isA<PlatformException>()),
    );
    await store.save(inventory(empty: true));
    expect(saveCalls, 2);
    await store.clear();
  });
}
