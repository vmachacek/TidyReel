import 'package:flutter_test/flutter_test.dart';
import 'package:media_platform_storage/media_platform_storage.dart';
import 'package:pocket_cinema/features/risk_spike/scan_inventory_worker.dart';

import 'risk_spike_controller_test.dart' as support;

StorageEntrySnapshot entry(String name, {bool directory = false}) =>
    StorageEntrySnapshot(
      storageKey: 'provider|$name',
      parentStorageKey: 'provider|folder',
      relativePath: 'folder/$name',
      displayName: name,
      isDirectory: directory,
      mimeType: null,
      sizeBytes: directory ? null : 128,
      modifiedAtUtc: DateTime.utc(2026),
      flags: const {StorageEntryFlag.supportsRead},
    );

void main() {
  test('worker classifies the full snapshot in another isolate', () async {
    final video = entry('Feature.MKV');
    final subtitle = entry('Feature.en.SRT');
    final artwork = entry('poster.JPEG');
    final completedAt = DateTime.utc(2026, 10, 8);
    final result = await computeScanInventory(
      ScanInventoryWork(
        root: support.root.locator,
        batches: [
          [video, subtitle],
          [
            artwork,
            entry('._Feature.mp4'),
            entry('notes.txt'),
            entry('folder.png', directory: true),
          ],
        ],
        completedAtUtc: completedAt,
      ),
    );

    expect(result.matchesRoot(support.root.locator), isTrue);
    expect(result.videos.single.storageKey, video.storageKey);
    // Native compute transfers these nonconstant objects across an isolate
    // boundary, demonstrating that classification did not run on this isolate.
    expect(result.videos.single, isNot(same(video)));
    expect(result.videos.single.relativePath, video.relativePath);
    expect(result.videos.single.modifiedAtUtc, video.modifiedAtUtc);
    expect(result.videos.single.flags, video.flags);
    expect(result.subtitles.single.storageKey, subtitle.storageKey);
    expect(result.artwork.single.storageKey, artwork.storageKey);
    expect(result.discoveredCount, 6);
    expect(result.ignoredCount, 4);
    expect(result.completedAtUtc, completedAt);
    expect(() => result.videos.clear(), throwsUnsupportedError);
    expect(() => result.subtitles.clear(), throwsUnsupportedError);
    expect(() => result.artwork.clear(), throwsUnsupportedError);
  });

  test('worker accepts an empty snapshot', () async {
    final result = await computeScanInventory(
      ScanInventoryWork(
        root: support.root.locator,
        batches: const [],
        completedAtUtc: DateTime.utc(2026),
      ),
    );

    expect(result.videos, isEmpty);
    expect(result.subtitles, isEmpty);
    expect(result.artwork, isEmpty);
    expect(result.discoveredCount, 0);
    expect(result.ignoredCount, 0);
  });
}
