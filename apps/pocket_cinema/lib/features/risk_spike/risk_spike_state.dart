import 'package:media_domain/media_domain.dart';
import 'package:media_platform_storage/media_platform_storage.dart';
import 'package:media_playback/media_playback.dart';

enum RiskSpikePhase {
  checkingGrant,
  noRoot,
  ready,
  choosingRoot,
  enumerating,
  filesAvailable,
  probing,
  fileReady,
  openingPlayback,
  playing,
  cancelled,
  failure,
}

final class RiskSpikeState {
  const RiskSpikeState({
    this.phase = RiskSpikePhase.noRoot,
    this.root,
    this.entries = const <StorageEntrySnapshot>[],
    this.artworkEntries = const <StorageEntrySnapshot>[],
    this.discoveredCount = 0,
    this.ignoredCount = 0,
    this.videoCount = 0,
    this.subtitleCount = 0,
    this.selectedFile,
    this.probeResult,
    this.playbackSnapshot = const PlaybackSnapshot.closed(),
    this.scanCompleted = false,
    this.canCancel = false,
    this.failure,
    this.subtitleWarning,
  });

  final RiskSpikePhase phase;
  final AuthorizedLibraryRoot? root;
  final List<StorageEntrySnapshot> entries;
  final List<StorageEntrySnapshot> artworkEntries;
  final int discoveredCount;
  final int ignoredCount;
  final int videoCount;
  final int subtitleCount;
  final StorageEntrySnapshot? selectedFile;
  final MediaProbeResult? probeResult;
  final PlaybackSnapshot playbackSnapshot;
  final bool scanCompleted;
  final bool canCancel;
  final AppFailure? failure;
  final AppFailure? subtitleWarning;

  bool get canRescan =>
      root != null &&
      phase != RiskSpikePhase.enumerating &&
      phase != RiskSpikePhase.choosingRoot;

  bool get canRepairRoot => failure?.code == 'STORAGE_PERMISSION_REVOKED';

  RiskSpikeState copyWith({
    RiskSpikePhase? phase,
    AuthorizedLibraryRoot? root,
    bool clearRoot = false,
    List<StorageEntrySnapshot>? entries,
    List<StorageEntrySnapshot>? artworkEntries,
    int? discoveredCount,
    int? ignoredCount,
    int? videoCount,
    int? subtitleCount,
    StorageEntrySnapshot? selectedFile,
    bool clearSelectedFile = false,
    MediaProbeResult? probeResult,
    bool clearProbeResult = false,
    PlaybackSnapshot? playbackSnapshot,
    bool? scanCompleted,
    bool? canCancel,
    AppFailure? failure,
    bool clearFailure = false,
    AppFailure? subtitleWarning,
    bool clearSubtitleWarning = false,
  }) => RiskSpikeState(
    phase: phase ?? this.phase,
    root: clearRoot ? null : root ?? this.root,
    entries: entries ?? this.entries,
    artworkEntries: artworkEntries ?? this.artworkEntries,
    discoveredCount: discoveredCount ?? this.discoveredCount,
    ignoredCount: ignoredCount ?? this.ignoredCount,
    videoCount: videoCount ?? this.videoCount,
    subtitleCount: subtitleCount ?? this.subtitleCount,
    selectedFile: clearSelectedFile ? null : selectedFile ?? this.selectedFile,
    probeResult: clearProbeResult ? null : probeResult ?? this.probeResult,
    playbackSnapshot: playbackSnapshot ?? this.playbackSnapshot,
    scanCompleted: scanCompleted ?? this.scanCompleted,
    canCancel: canCancel ?? this.canCancel,
    failure: clearFailure ? null : failure ?? this.failure,
    subtitleWarning: clearSubtitleWarning
        ? null
        : subtitleWarning ?? this.subtitleWarning,
  );
}
