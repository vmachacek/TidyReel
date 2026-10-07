import 'package:flutter/foundation.dart';
import 'package:media_domain/media_domain.dart';
import 'package:media_platform_storage/media_platform_storage.dart';
import 'package:media_playback/media_playback.dart';

import 'playback_session_coordinator.dart';
import 'risk_spike_state.dart';

final class RiskSpikeController extends ChangeNotifier {
  RiskSpikeController({
    required this.storage,
    required this.probe,
    required this.playback,
    this.classifier = const FileClassifier(),
    this.sidecarMatcher = const SidecarMatcher(),
    RiskSpikeState initialState = const RiskSpikeState(),
  }) : _state = initialState;

  static const int maximumSubtitleBytes = 2 * 1024 * 1024;

  final LibraryStorageGateway storage;
  final MediaProbe probe;
  final PlaybackSession playback;
  final FileClassifier classifier;
  final SidecarMatcher sidecarMatcher;

  RiskSpikeState _state;
  RiskSpikeState get state => _state;

  final List<StorageEntrySnapshot> _subtitleEntries = <StorageEntrySnapshot>[];
  CancellationController? _scanCancellation;
  String? _activeScanId;
  var _scanSequence = 0;

  Future<void> initialize() async {
    _emit(_state.copyWith(phase: RiskSpikePhase.checkingGrant));
    final roots = await storage.listPersistedRoots();
    switch (roots) {
      case FailureResult<List<AuthorizedLibraryRoot>>(:final failure):
        _fail(failure);
      case Success<List<AuthorizedLibraryRoot>>(:final value):
        if (value.isEmpty) {
          _emit(const RiskSpikeState(phase: RiskSpikePhase.noRoot));
          return;
        }
        final root = value.first;
        final access = await storage.checkAccess(root.locator);
        switch (access) {
          case Success<RootAccessState>(value: RootAccessState.available):
            _emit(
              _state.copyWith(
                phase: RiskSpikePhase.ready,
                root: root,
                clearFailure: true,
              ),
            );
          case Success<RootAccessState>():
            _fail(
              const AppFailure(
                code: 'STORAGE_PERMISSION_REVOKED',
                messageKey: 'rootPermissionRevoked',
                retryable: true,
              ),
              root: root,
            );
          case FailureResult<RootAccessState>(:final failure):
            _fail(failure, root: root);
        }
    }
  }

  Future<void> chooseRoot() async {
    _emit(_state.copyWith(phase: RiskSpikePhase.choosingRoot));
    final result = await storage.chooseRoot();
    switch (result) {
      case Success<AuthorizedLibraryRoot>(:final value):
        _subtitleEntries.clear();
        _emit(RiskSpikeState(phase: RiskSpikePhase.ready, root: value));
      case FailureResult<AuthorizedLibraryRoot>(:final failure):
        if (failure.code == 'USER_CANCELLED') {
          _emit(
            _state.copyWith(
              phase: _state.root == null
                  ? RiskSpikePhase.noRoot
                  : RiskSpikePhase.ready,
            ),
          );
        } else {
          _fail(failure);
        }
    }
  }

  Future<void> repairRoot() => chooseRoot();

  Future<void> releaseRoot() async {
    final root = _state.root;
    if (root == null) {
      return;
    }
    await playback.stop();
    final result = await storage.releaseRootPermission(root.locator);
    switch (result) {
      case Success<void>():
        _subtitleEntries.clear();
        _emit(
          RiskSpikeState(
            phase: RiskSpikePhase.failure,
            root: root,
            failure: const AppFailure(
              code: 'STORAGE_PERMISSION_REVOKED',
              messageKey: 'rootPermissionRevoked',
              retryable: true,
            ),
          ),
        );
      case FailureResult<void>(:final failure):
        _fail(failure);
    }
  }

  Future<void> scan(AuthorizedLibraryRoot root) async {
    _scanCancellation?.cancel();
    final scanId = 'scan-${++_scanSequence}';
    final cancellation = CancellationController();
    _activeScanId = scanId;
    _scanCancellation = cancellation;
    _subtitleEntries.clear();
    _emit(
      RiskSpikeState(
        phase: RiskSpikePhase.enumerating,
        root: root,
        canCancel: true,
      ),
    );

    try {
      await for (final event in storage.enumerateRecursively(
        root: root.locator,
        scanId: scanId,
        cancellationToken: cancellation.token,
      )) {
        if (_activeScanId != event.scanId) {
          continue;
        }
        _applyScanEvent(event);
      }
    } on Object {
      if (_activeScanId == scanId) {
        _fail(
          const AppFailure(
            code: 'SCAN_FAILED',
            messageKey: 'scanFailed',
            retryable: true,
          ),
          root: root,
        );
      }
    } finally {
      if (_activeScanId == scanId) {
        _scanCancellation = null;
      }
    }
  }

  void cancelScan() {
    _scanCancellation?.cancel();
  }

  void selectFile(StorageEntrySnapshot entry) {
    _emit(
      _state.copyWith(
        phase: RiskSpikePhase.fileReady,
        selectedFile: entry,
        clearProbeResult: true,
        clearFailure: true,
        clearSubtitleWarning: true,
      ),
    );
  }

  Future<void> probeSelected() async {
    final root = _state.root;
    final entry = _state.selectedFile;
    if (root == null || entry == null) {
      return;
    }
    _emit(_state.copyWith(phase: RiskSpikePhase.probing, clearFailure: true));
    final cancellation = CancellationController();
    final result = await probe.probe(
      root: root.locator,
      storageKey: entry.storageKey,
      cancellationToken: cancellation.token,
    );
    switch (result) {
      case Success<MediaProbeResult>(:final value):
        _emit(
          _state.copyWith(
            phase: RiskSpikePhase.fileReady,
            probeResult: value,
            clearFailure: true,
          ),
        );
      case FailureResult<MediaProbeResult>(:final failure):
        _fail(failure, root: root);
    }
  }

  Future<void> playSelected({Duration startPosition = Duration.zero}) async {
    final root = _state.root;
    final entry = _state.selectedFile;
    if (root == null || entry == null) {
      return;
    }
    final sidecar = sidecarMatcher.matchSrt(entry, _subtitleEntries);
    await play(
      root,
      entry,
      subtitle: sidecar?.entry,
      subtitleLanguageTag: sidecar?.languageTag,
      startPosition: startPosition,
    );
  }

  Future<void> play(
    AuthorizedLibraryRoot root,
    StorageEntrySnapshot entry, {
    StorageEntrySnapshot? subtitle,
    String? subtitleLanguageTag,
    Duration startPosition = Duration.zero,
  }) async {
    _emit(
      _state.copyWith(
        phase: RiskSpikePhase.openingPlayback,
        root: root,
        selectedFile: entry,
        clearFailure: true,
        clearSubtitleWarning: true,
      ),
    );
    final source = await storage.openPlaybackSource(
      root: root.locator,
      storageKey: entry.storageKey,
      strategy: PlaybackSourceStrategy.directContentUri,
    );
    final MediaSourceLease lease;
    switch (source) {
      case Success<MediaSourceLease>(:final value):
        lease = value;
      case FailureResult<MediaSourceLease>(:final failure):
        _fail(failure, root: root);
        return;
    }

    final opened = await playback.attachLease(
      lease,
      startPosition: startPosition,
    );
    if (opened case FailureResult<void>(:final failure)) {
      _fail(failure, root: root);
      return;
    }
    _emit(
      _state.copyWith(
        phase: RiskSpikePhase.playing,
        playbackSnapshot: playback.snapshot,
        clearFailure: true,
      ),
    );

    if (subtitle == null) {
      return;
    }
    final sidecar = await storage.readSmallFile(
      root: root.locator,
      storageKey: subtitle.storageKey,
      maximumBytes: maximumSubtitleBytes,
    );
    switch (sidecar) {
      case FailureResult<SmallFileContent>(:final failure):
        _emit(_state.copyWith(subtitleWarning: failure));
      case Success<SmallFileContent>(:final value):
        final attached = await playback.attachSubtitle(
          value.bytes,
          languageTag: subtitleLanguageTag,
        );
        if (attached case FailureResult<void>(:final failure)) {
          _emit(_state.copyWith(subtitleWarning: failure));
        }
    }
  }

  void refreshPlaybackSnapshot() {
    final current = playback.snapshot;
    if (current.isOpen &&
        (current.position != _state.playbackSnapshot.position ||
            current.duration != _state.playbackSnapshot.duration ||
            current.isPlaying != _state.playbackSnapshot.isPlaying ||
            current.isBuffering != _state.playbackSnapshot.isBuffering ||
            current.failure != _state.playbackSnapshot.failure)) {
      _emit(
        _state.copyWith(
          playbackSnapshot: current,
          failure: current.failure,
          clearFailure:
              current.failure == null &&
              _state.playbackSnapshot.failure != null,
        ),
      );
    }
  }

  Future<void> togglePlayPause() async {
    final result = playback.snapshot.isPlaying
        ? await playback.pause()
        : await playback.play();
    _applyPlaybackResult(result);
  }

  Future<void> seekBy(Duration delta) async {
    final current = playback.snapshot.position;
    var target = current + delta;
    if (target.isNegative) {
      target = Duration.zero;
    }
    final duration = playback.snapshot.duration;
    if (duration > Duration.zero && target > duration) {
      target = duration;
    }
    _applyPlaybackResult(await playback.seek(target));
  }

  Future<void> seekToStart() async {
    _applyPlaybackResult(await playback.seek(Duration.zero));
  }

  Future<void> closePlayer() async {
    await playback.stop();
    _emit(
      _state.copyWith(
        phase: _state.selectedFile == null
            ? RiskSpikePhase.filesAvailable
            : RiskSpikePhase.fileReady,
        playbackSnapshot: const PlaybackSnapshot.closed(),
      ),
    );
  }

  Future<void> handleLifecycleInactive() async {
    await playback.handleLifecycleInactive();
    _emit(
      _state.copyWith(
        phase: _state.selectedFile == null
            ? RiskSpikePhase.filesAvailable
            : RiskSpikePhase.fileReady,
        playbackSnapshot: const PlaybackSnapshot.closed(),
      ),
    );
  }

  void _applyScanEvent(StorageScanEvent event) {
    switch (event) {
      case StorageScanStarted():
        break;
      case StorageScanBatch(:final entries):
        final videos = <StorageEntrySnapshot>[..._state.entries];
        final artwork = <StorageEntrySnapshot>[..._state.artworkEntries];
        var ignored = _state.ignoredCount;
        var videoCount = _state.videoCount;
        var subtitleCount = _state.subtitleCount;
        for (final entry in entries) {
          if (!entry.isDirectory &&
              RegExp(
                r'\.(jpe?g|png|webp)$',
                caseSensitive: false,
              ).hasMatch(entry.displayName)) {
            artwork.add(entry);
          }
          switch (classifier
              .classify(entry.displayName, isDirectory: entry.isDirectory)
              .kind) {
            case LibraryFileKind.video:
              videos.add(entry);
              videoCount++;
            case LibraryFileKind.subtitle:
              _subtitleEntries.add(entry);
              subtitleCount++;
            case LibraryFileKind.systemArtifact ||
                LibraryFileKind.ignoredOther ||
                LibraryFileKind.directory:
              ignored++;
          }
        }
        _emit(
          _state.copyWith(
            entries: List<StorageEntrySnapshot>.unmodifiable(videos),
            artworkEntries: List<StorageEntrySnapshot>.unmodifiable(artwork),
            discoveredCount: _state.discoveredCount + entries.length,
            ignoredCount: ignored,
            videoCount: videoCount,
            subtitleCount: subtitleCount,
          ),
        );
      case StorageScanProgress():
        break;
      case StorageScanWarning():
        break;
      case StorageScanCompleted():
        _emit(
          _state.copyWith(
            phase: RiskSpikePhase.filesAvailable,
            scanCompleted: true,
            canCancel: false,
            clearFailure: true,
          ),
        );
      case StorageScanCancelled():
        _emit(
          _state.copyWith(
            phase: RiskSpikePhase.cancelled,
            scanCompleted: false,
            canCancel: false,
          ),
        );
      case StorageScanFailed(:final failure):
        _emit(
          _state.copyWith(
            phase: RiskSpikePhase.failure,
            scanCompleted: false,
            canCancel: false,
            failure: failure,
          ),
        );
    }
  }

  void _applyPlaybackResult(AppResult<void> result) {
    switch (result) {
      case Success<void>():
        _emit(
          _state.copyWith(
            phase: RiskSpikePhase.playing,
            playbackSnapshot: playback.snapshot,
            clearFailure: true,
          ),
        );
      case FailureResult<void>(:final failure):
        _fail(failure);
    }
  }

  void _fail(AppFailure failure, {AuthorizedLibraryRoot? root}) {
    _emit(
      _state.copyWith(
        phase: RiskSpikePhase.failure,
        root: root,
        canCancel: false,
        failure: failure,
      ),
    );
  }

  void _emit(RiskSpikeState next) {
    _state = next;
    notifyListeners();
  }
}
