import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:media_platform_storage/media_platform_storage.dart';

/// A complete inventory is scoped to the exact folder grant it came from.
final class ScanInventory {
  ScanInventory({
    required this.root,
    required List<StorageEntrySnapshot> videos,
    required List<StorageEntrySnapshot> artwork,
    required List<StorageEntrySnapshot> subtitles,
    required this.discoveredCount,
    required this.ignoredCount,
    required this.completedAtUtc,
  }) : videos = List.unmodifiable(videos),
       artwork = List.unmodifiable(artwork),
       subtitles = List.unmodifiable(subtitles);

  final LibraryRootLocator root;
  final List<StorageEntrySnapshot> videos, artwork, subtitles;
  final int discoveredCount, ignoredCount;
  final DateTime completedAtUtc;

  bool matchesRoot(LibraryRootLocator other) =>
      root.storageKind == other.storageKind &&
      root.opaqueValue == other.opaqueValue;

  String encode() => jsonEncode({
    'version': 1,
    'root': {
      'storageKind': root.storageKind.name,
      'opaqueValue': root.opaqueValue,
    },
    'completedAtUtc': completedAtUtc.toUtc().toIso8601String(),
    'discoveredCount': discoveredCount,
    'ignoredCount': ignoredCount,
    'videos': videos.map(_encodeEntry).toList(),
    'artwork': artwork.map(_encodeEntry).toList(),
    'subtitles': subtitles.map(_encodeEntry).toList(),
  });

  static ScanInventory? decode(String raw) {
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (data['version'] != 1) return null;
      final root = data['root'] as Map<String, dynamic>;
      final kind = StorageKind.values.byName(root['storageKind'] as String);
      final locator = root['opaqueValue'] as String;
      if (locator.isEmpty) return null;
      final videos = _decodeEntries(data['videos']);
      final artwork = _decodeEntries(data['artwork']);
      final subtitles = _decodeEntries(data['subtitles']);
      final discoveredCount = data['discoveredCount'] as int;
      final ignoredCount = data['ignoredCount'] as int;
      if (ignoredCount < 0 ||
          discoveredCount != videos.length + subtitles.length + ignoredCount) {
        return null;
      }
      return ScanInventory(
        root: LibraryRootLocator(storageKind: kind, opaqueValue: locator),
        videos: videos,
        artwork: artwork,
        subtitles: subtitles,
        discoveredCount: discoveredCount,
        ignoredCount: ignoredCount,
        completedAtUtc: DateTime.parse(data['completedAtUtc'] as String)
            .toUtc(),
      );
    } on Object {
      // An old or damaged cache is a cache miss, never a broken library.
      return null;
    }
  }

  static Map<String, Object?> _encodeEntry(StorageEntrySnapshot entry) => {
    'storageKey': entry.storageKey,
    'parentStorageKey': entry.parentStorageKey,
    'relativePath': entry.relativePath,
    'displayName': entry.displayName,
    'isDirectory': entry.isDirectory,
    'mimeType': entry.mimeType,
    'sizeBytes': entry.sizeBytes,
    'modifiedAtUtc': entry.modifiedAtUtc?.toUtc().toIso8601String(),
    'flags': entry.flags.map((flag) => flag.name).toList(),
  };

  static List<StorageEntrySnapshot> _decodeEntries(Object? value) =>
      (value as List<dynamic>).map((item) {
        final entry = item as Map<String, dynamic>;
        final storageKey = entry['storageKey'] as String;
        final displayName = entry['displayName'] as String;
        final sizeBytes = entry['sizeBytes'] as int?;
        if (storageKey.isEmpty ||
            displayName.isEmpty ||
            (sizeBytes != null && sizeBytes < 0)) {
          throw const FormatException('Invalid inventory entry');
        }
        final modified = entry['modifiedAtUtc'] as String?;
        return StorageEntrySnapshot(
          storageKey: storageKey,
          parentStorageKey: entry['parentStorageKey'] as String?,
          relativePath: entry['relativePath'] as String,
          displayName: displayName,
          isDirectory: entry['isDirectory'] as bool,
          mimeType: entry['mimeType'] as String?,
          sizeBytes: sizeBytes,
          modifiedAtUtc: modified == null
              ? null
              : DateTime.parse(modified).toUtc(),
          flags: Set.unmodifiable(
            (entry['flags'] as List<dynamic>).map(
              (flag) => StorageEntryFlag.values.byName(flag as String),
            ),
          ),
        );
      }).toList();
}

abstract interface class ScanInventoryStore {
  Future<ScanInventory?> load();
  Future<void> save(ScanInventory inventory);
  Future<void> clear();
}

final class PlatformScanInventoryStore implements ScanInventoryStore {
  static const channel = MethodChannel('com.pocketcinema.app/catalog');
  Future<void> _pendingWrite = Future<void>.value();

  @override
  Future<ScanInventory?> load() async {
    await _pendingWrite;
    final raw = await channel.invokeMethod<String>('loadScanInventory');
    if (raw == null) return null;
    return compute(ScanInventory.decode, raw);
  }

  @override
  Future<void> save(ScanInventory inventory) => _write(() async {
    final value = await compute(_encodeInventory, inventory);
    await channel.invokeMethod<void>('saveScanInventory', {'value': value});
  });

  @override
  Future<void> clear() =>
      _write(() => channel.invokeMethod<void>('clearScanInventory'));

  Future<void> _write(Future<void> Function() operation) {
    final write = _pendingWrite.then((_) => operation());
    // Keep later operations usable after a storage error. The original caller
    // still receives that error and decides whether it affects its workflow.
    _pendingWrite = write.catchError((Object _) {});
    return write;
  }
}

String _encodeInventory(ScanInventory inventory) => inventory.encode();
