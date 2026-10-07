import 'package:pigeon/pigeon.dart';

class AuthorizedRootMessage {
  AuthorizedRootMessage({required this.treeUri, required this.displayName});

  String treeUri;
  String displayName;
}

class RootAccessMessage {
  RootAccessMessage({required this.state});

  String state;
}

class StorageEntryMessage {
  StorageEntryMessage({
    required this.storageKey,
    required this.relativePath,
    required this.displayName,
    required this.isDirectory,
    required this.flags,
    this.parentStorageKey,
    this.mimeType,
    this.sizeBytes,
    this.modifiedAtEpochMs,
  });

  String storageKey;
  String? parentStorageKey;
  String relativePath;
  String displayName;
  bool isDirectory;
  String? mimeType;
  int? sizeBytes;
  int? modifiedAtEpochMs;
  int flags;
}

class SmallFileMessage {
  SmallFileMessage({required this.bytes});

  Uint8List bytes;
}

class PlaybackLeaseMessage {
  PlaybackLeaseMessage({
    required this.leaseId,
    required this.sourceUri,
    required this.strategy,
  });

  String leaseId;
  String sourceUri;
  String strategy;
}

class ProbeResultMessage {
  ProbeResultMessage({
    required this.streamCount,
    this.durationMs,
    this.containerFormat,
    this.width,
    this.height,
    this.rotationDegrees,
    this.videoCodec,
    this.audioCodecSummary,
  });

  int? durationMs;
  String? containerFormat;
  int? width;
  int? height;
  int? rotationDegrees;
  String? videoCodec;
  String? audioCodecSummary;
  int streamCount;
}

@HostApi()
abstract class StorageHostApi {
  @async
  AuthorizedRootMessage chooseDirectory();

  List<AuthorizedRootMessage> listPersistedPermissions();

  RootAccessMessage checkRoot(String treeUri);

  void startScan(String treeUri, String scanId, int batchSize);

  void cancelScan(String scanId);

  SmallFileMessage readSmallFile(
    String treeUri,
    String storageKey,
    int maximumBytes,
  );

  PlaybackLeaseMessage openPlaybackSource(
    String treeUri,
    String storageKey,
    String strategy,
  );

  void closePlaybackSource(String leaseId);

  ProbeResultMessage probeFile(String treeUri, String storageKey);

  void releasePermission(String treeUri);
}
