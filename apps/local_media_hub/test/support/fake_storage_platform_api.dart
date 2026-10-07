import 'package:local_media_hub/infrastructure/android/storage_platform_api.dart';

final class FakeStoragePlatformApi implements StoragePlatformApi {
  FakeStoragePlatformApi({
    this.chooseResult,
    this.chooseError,
    this.probeError,
  });

  final AuthorizedRootDto? chooseResult;
  final Object? chooseError;
  final Object? probeError;

  @override
  Future<AuthorizedRootDto> chooseDirectory() async {
    if (chooseError case final error?) {
      throw error;
    }
    return chooseResult ??
        (throw StateError('Unexpected platform call: chooseDirectory'));
  }

  @override
  Future<void> startScan(String treeUri, String scanId, int batchSize) async {}

  @override
  Future<ProbeResultDto> probeFile(String treeUri, String storageKey) async {
    if (probeError case final error?) {
      throw error;
    }
    throw StateError('Unexpected platform call: probeFile');
  }

  @override
  Future<void> cancelScan(String scanId) =>
      throw StateError('Unexpected platform call: cancelScan');

  @override
  Future<RootAccessDto> checkRoot(String treeUri) =>
      throw StateError('Unexpected platform call: checkRoot');

  @override
  Future<void> closePlaybackSource(String leaseId) =>
      throw StateError('Unexpected platform call: closePlaybackSource');

  @override
  Future<List<AuthorizedRootDto>> listPersistedPermissions() =>
      throw StateError('Unexpected platform call: listPersistedPermissions');

  @override
  Future<PlaybackLeaseDto> openPlaybackSource(
    String treeUri,
    String storageKey,
    String strategy,
  ) => throw StateError('Unexpected platform call: openPlaybackSource');

  @override
  Future<SmallFileDto> readSmallFile(
    String treeUri,
    String storageKey,
    int maximumBytes,
  ) => throw StateError('Unexpected platform call: readSmallFile');

  @override
  Future<void> releasePermission(String treeUri) =>
      throw StateError('Unexpected platform call: releasePermission');
}
