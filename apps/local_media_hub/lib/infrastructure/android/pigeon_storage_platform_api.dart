import 'generated/storage_api.g.dart';
import 'storage_platform_api.dart';

final class PigeonStoragePlatformApi implements StoragePlatformApi {
  PigeonStoragePlatformApi({StorageHostApi? api})
    : _api = api ?? StorageHostApi();

  final StorageHostApi _api;

  @override
  Future<AuthorizedRootDto> chooseDirectory() async {
    final message = await _api.chooseDirectory();
    return AuthorizedRootDto(
      treeUri: message.treeUri,
      displayName: message.displayName,
    );
  }

  @override
  Future<List<AuthorizedRootDto>> listPersistedPermissions() async {
    final messages = await _api.listPersistedPermissions();
    return messages
        .map(
          (message) => AuthorizedRootDto(
            treeUri: message.treeUri,
            displayName: message.displayName,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<RootAccessDto> checkRoot(String treeUri) async {
    final message = await _api.checkRoot(treeUri);
    return RootAccessDto(state: message.state);
  }

  @override
  Future<void> startScan(String treeUri, String scanId, int batchSize) =>
      _api.startScan(treeUri, scanId, batchSize);

  @override
  Future<void> cancelScan(String scanId) => _api.cancelScan(scanId);

  @override
  Future<SmallFileDto> readSmallFile(
    String treeUri,
    String storageKey,
    int maximumBytes,
  ) async {
    final message = await _api.readSmallFile(treeUri, storageKey, maximumBytes);
    return SmallFileDto(bytes: message.bytes);
  }

  @override
  Future<PlaybackLeaseDto> openPlaybackSource(
    String treeUri,
    String storageKey,
    String strategy,
  ) async {
    final message = await _api.openPlaybackSource(
      treeUri,
      storageKey,
      strategy,
    );
    return PlaybackLeaseDto(
      leaseId: message.leaseId,
      sourceUri: message.sourceUri,
      strategy: message.strategy,
    );
  }

  @override
  Future<void> closePlaybackSource(String leaseId) =>
      _api.closePlaybackSource(leaseId);

  @override
  Future<ProbeResultDto> probeFile(String treeUri, String storageKey) async {
    final message = await _api.probeFile(treeUri, storageKey);
    return ProbeResultDto(
      durationMs: message.durationMs,
      containerFormat: message.containerFormat,
      width: message.width,
      height: message.height,
      rotationDegrees: message.rotationDegrees,
      videoCodec: message.videoCodec,
      audioCodecSummary: message.audioCodecSummary,
      streamCount: message.streamCount,
    );
  }

  @override
  Future<void> releasePermission(String treeUri) =>
      _api.releasePermission(treeUri);
}
