import 'package:flutter/foundation.dart';
import 'package:media_platform_storage/media_platform_storage.dart';

import 'scan_inventory_store.dart';

/// The scan batches are accumulated once, then classified away from the UI.
final class ScanInventoryWork {
  const ScanInventoryWork({
    required this.root,
    required this.batches,
    required this.completedAtUtc,
    this.classifier = const FileClassifier(),
  });

  final LibraryRootLocator root;
  final List<List<StorageEntrySnapshot>> batches;
  final DateTime completedAtUtc;
  final FileClassifier classifier;
}

typedef ScanInventoryWorker = Future<ScanInventory> Function(ScanInventoryWork);

Future<ScanInventory> computeScanInventory(ScanInventoryWork work) =>
    compute(classifyScanInventory, work, debugLabel: 'library-inventory');

ScanInventory classifyScanInventory(ScanInventoryWork work) {
  final videos = <StorageEntrySnapshot>[];
  final artwork = <StorageEntrySnapshot>[];
  final subtitles = <StorageEntrySnapshot>[];
  final artworkExtension = RegExp(r'\.(jpe?g|png|webp)$', caseSensitive: false);
  var discoveredCount = 0;
  var ignoredCount = 0;
  for (final batch in work.batches) {
    discoveredCount += batch.length;
    for (final entry in batch) {
      if (!entry.isDirectory && artworkExtension.hasMatch(entry.displayName)) {
        artwork.add(entry);
      }
      switch (work.classifier
          .classify(entry.displayName, isDirectory: entry.isDirectory)
          .kind) {
        case LibraryFileKind.video:
          videos.add(entry);
        case LibraryFileKind.subtitle:
          subtitles.add(entry);
        case LibraryFileKind.systemArtifact ||
            LibraryFileKind.ignoredOther ||
            LibraryFileKind.directory:
          ignoredCount++;
      }
    }
  }
  return ScanInventory(
    root: work.root,
    videos: videos,
    artwork: artwork,
    subtitles: subtitles,
    discoveredCount: discoveredCount,
    ignoredCount: ignoredCount,
    completedAtUtc: work.completedAtUtc,
  );
}
