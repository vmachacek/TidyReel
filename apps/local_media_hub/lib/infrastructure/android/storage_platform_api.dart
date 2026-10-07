import 'dart:typed_data';

final class AuthorizedRootDto {
  const AuthorizedRootDto({required this.treeUri, required this.displayName});

  final String treeUri;
  final String displayName;
}

final class RootAccessDto {
  const RootAccessDto({required this.state});

  final String state;
}

final class SmallFileDto {
  const SmallFileDto({required this.bytes});

  final Uint8List bytes;
}

final class PlaybackLeaseDto {
  const PlaybackLeaseDto({
    required this.leaseId,
    required this.sourceUri,
    required this.strategy,
  });

  final String leaseId;
  final String sourceUri;
  final String strategy;
}

final class ProbeResultDto {
  const ProbeResultDto({
    required this.streamCount,
    this.durationMs,
    this.containerFormat,
    this.width,
    this.height,
    this.rotationDegrees,
    this.videoCodec,
    this.audioCodecSummary,
  });

  final int? durationMs;
  final String? containerFormat;
  final int? width;
  final int? height;
  final int? rotationDegrees;
  final String? videoCodec;
  final String? audioCodecSummary;
  final int streamCount;
}

abstract interface class StoragePlatformApi {
  Future<AuthorizedRootDto> chooseDirectory();

  Future<List<AuthorizedRootDto>> listPersistedPermissions();

  Future<RootAccessDto> checkRoot(String treeUri);

  Future<void> startScan(String treeUri, String scanId, int batchSize);

  Future<void> cancelScan(String scanId);

  Future<SmallFileDto> readSmallFile(
    String treeUri,
    String storageKey,
    int maximumBytes,
  );

  Future<PlaybackLeaseDto> openPlaybackSource(
    String treeUri,
    String storageKey,
    String strategy,
  );

  Future<void> closePlaybackSource(String leaseId);

  Future<ProbeResultDto> probeFile(String treeUri, String storageKey);

  Future<void> releasePermission(String treeUri);
}
