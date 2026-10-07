import 'dart:typed_data';

import 'package:media_domain/media_domain.dart';

enum StorageKind { androidSaf }

enum RootAccessState { available, permissionRevoked, unavailable }

enum LibraryFileKind {
  video,
  subtitle,
  systemArtifact,
  ignoredOther,
  directory,
}

enum StorageEntryFlag { supportsRead, virtualDocument }

enum PlaybackSourceStrategy { directContentUri, fileDescriptor, loopbackProxy }

final class LibraryRootLocator {
  const LibraryRootLocator({
    required this.storageKind,
    required this.opaqueValue,
  });

  final StorageKind storageKind;
  final String opaqueValue;
}

final class AuthorizedLibraryRoot {
  const AuthorizedLibraryRoot({
    required this.locator,
    required this.displayName,
  });

  final LibraryRootLocator locator;
  final String displayName;
}

final class StorageEntrySnapshot {
  const StorageEntrySnapshot({
    required this.storageKey,
    required this.parentStorageKey,
    required this.relativePath,
    required this.displayName,
    required this.isDirectory,
    required this.mimeType,
    required this.sizeBytes,
    required this.modifiedAtUtc,
    required this.flags,
  });

  final String storageKey;
  final String? parentStorageKey;
  final String relativePath;
  final String displayName;
  final bool isDirectory;
  final String? mimeType;
  final int? sizeBytes;
  final DateTime? modifiedAtUtc;
  final Set<StorageEntryFlag> flags;
}

sealed class StorageScanEvent {
  const StorageScanEvent(this.scanId);

  final String scanId;
}

final class StorageScanStarted extends StorageScanEvent {
  const StorageScanStarted(super.scanId);
}

final class StorageScanBatch extends StorageScanEvent {
  const StorageScanBatch(super.scanId, this.entries);

  final List<StorageEntrySnapshot> entries;
}

final class StorageScanProgress extends StorageScanEvent {
  const StorageScanProgress(super.scanId, this.visitedEntries);

  final int visitedEntries;
}

final class StorageScanWarning extends StorageScanEvent {
  const StorageScanWarning(super.scanId, this.failure);

  final AppFailure failure;
}

final class StorageScanCompleted extends StorageScanEvent {
  const StorageScanCompleted(super.scanId);
}

final class StorageScanCancelled extends StorageScanEvent {
  const StorageScanCancelled(super.scanId);
}

final class StorageScanFailed extends StorageScanEvent {
  const StorageScanFailed(super.scanId, this.failure);

  final AppFailure failure;
}

final class SmallFileContent {
  const SmallFileContent(this.bytes);

  final Uint8List bytes;
}

final class MediaSourceLease {
  const MediaSourceLease({
    required this.leaseId,
    required this.sourceUri,
    required this.strategy,
  });

  final String leaseId;
  final String sourceUri;
  final PlaybackSourceStrategy strategy;

  @override
  String toString() => 'MediaSourceLease(strategy: ${strategy.name})';
}

final class MediaProbeResult {
  const MediaProbeResult({
    required this.streamCount,
    this.duration,
    this.containerFormat,
    this.width,
    this.height,
    this.rotationDegrees,
    this.videoCodec,
    this.audioCodecSummary,
  });

  final Duration? duration;
  final String? containerFormat;
  final int? width;
  final int? height;
  final int? rotationDegrees;
  final String? videoCodec;
  final String? audioCodecSummary;
  final int streamCount;
}
