import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_domain/media_domain.dart';
import 'package:media_platform_storage/media_platform_storage.dart';
import 'package:media_playback/media_playback.dart';

import 'playback_session_coordinator.dart';
import 'risk_spike_state.dart';
import 'scan_inventory_store.dart';
import 'scan_inventory_worker.dart';

final class RiskSpikeController extends ChangeNotifier {
  RiskSpikeController({
    required this.storage,
    required this.probe,
    required this.playback,
    this.classifier = const FileClassifier(),
    this.sidecarMatcher = const SidecarMatcher(),
    ScanInventoryStore? inventoryStore,
    ScanInventoryWorker? inventoryWorker,
    DateTime Function()? clock,
    RiskSpikeState initialState = const RiskSpikeState(),
  }) : _inventoryStore = inventoryStore ?? PlatformScanInventoryStore(),
       _inventoryWorker = inventoryWorker ?? computeScanInventory,
       _clock = clock ?? DateTime.now,
       _state = initialState;

  static const int maximumSubtitleBytes = 2 * 1024 * 1024;
  static const backgroundRefreshInterval = Duration(hours: 6);
  static const backgroundRetryInterval = Duration(minutes: 30);

  final LibraryStorageGateway storage;
  final MediaProbe probe;
  final PlaybackSession playback;
  final FileClassifier classifier;
  final SidecarMatcher sidecarMatcher;
  final ScanInventoryStore _inventoryStore;
  final ScanInventoryWorker _inventoryWorker;
  final DateTime Function() _clock;

  RiskSpikeState _state;
  RiskSpikeState get state => _state;

  bool _playbackBlocked = false;
  int _playbackBlockGeneration = 0;
  Future<void>? _playbackBlockPause;
  bool _disposed = false;

  bool get playbackBlocked => _playbackBlocked;

  void setPlaybackBlocked(bool blocked) {
    if (_playbackBlocked == blocked) return;
    _playbackBlocked = blocked;
    if (blocked) _playbackBlockGeneration++;
    if (playback case final PlaybackSessionCoordinator coordinator) {
      coordinator.setPlaybackBlocked(blocked);
    }
    notifyListeners();
    if (blocked) unawaited(_pauseForPlaybackBlock());
  }

  Future<void> _pauseForPlaybackBlock() {
    final pending = _playbackBlockPause;
    if (pending != null) {
      return pending.then((_) {
        if (playback.snapshot.isPlaying) return _pauseForPlaybackBlock();
      });
    }
    if (!playback.snapshot.isOpen || !playback.snapshot.isPlaying) {
      return Future<void>.value();
    }
    late final Future<void> operation;
    operation = _pauseOrStopPlayback().whenComplete(() {
      if (identical(_playbackBlockPause, operation)) _playbackBlockPause = null;
    });
    _playbackBlockPause = operation;
    return operation;
  }

  Future<void> _pauseOrStopPlayback() async {
    var shouldStop = false;
    try {
      final result = await playback.pause();
      shouldStop = result is FailureResult<void> || playback.snapshot.isPlaying;
    } on Object {
      shouldStop = true;
    }
    if (shouldStop) {
      try {
        await playback.stop();
      } on Object catch (error) {
        debugPrint('Could not finish stopping blocked playback: $error');
      }
    }
    if (!_disposed) {
      _emit(_state.copyWith(playbackSnapshot: playback.snapshot));
    }
  }

  final List<StorageEntrySnapshot> _subtitleEntries = <StorageEntrySnapshot>[];
  CancellationController? _scanCancellation;
  String? _activeScanId;
  var _scanSequence = 0;
  var _rootGeneration = 0;
  RiskSpikeState? _pendingScanState;
  RiskSpikeState? _previousInventory;
  final _pendingSubtitleEntries = <StorageEntrySnapshot>[];
  final _pendingEntryBatches = <List<StorageEntrySnapshot>>[];
  final _scanProgressClock = Stopwatch();
  var _pendingRefreshDiscoveredCount = 0;
  var _lastScanProgressMillis = 0;
  Future<void>? _initialization;
  bool _isBackgroundRefreshing = false;
  DateTime? _lastAutomaticFailureAt;
  ScanInventory? _pendingAutomaticInventory;
  Future<void> _inventoryWrite = Future<void>.value();

  bool get isBackgroundRefreshing => _isBackgroundRefreshing;

  bool get needsBackgroundRefresh {
    if (_disposed ||
        _activeScanId != null ||
        _state.root == null ||
        !_state.scanCompleted ||
        _state.canRepairRoot ||
        _state.phase == RiskSpikePhase.checkingGrant ||
        _state.phase == RiskSpikePhase.choosingRoot) {
      return false;
    }
    final now = _clock().toUtc();
    final lastFailure = _lastAutomaticFailureAt;
    if (lastFailure != null &&
        !lastFailure.isAfter(now) &&
        now.difference(lastFailure) < backgroundRetryInterval) {
      return false;
    }
    final completedAt = _state.lastScanCompletedAt;
    return completedAt == null ||
        completedAt.isAfter(now) ||
        now.difference(completedAt) >= backgroundRefreshInterval;
  }

  /// The UI schedules this only when startup and user interactions are idle.
  Future<void> refreshInBackground() async {
    if (!needsBackgroundRefresh) return;
    await _scan(_state.root!, automatic: true);
  }

  /// Automatic work yields to user activity without interrupting a manual scan.
  void deferBackgroundRefresh() {
    if (_isBackgroundRefreshing) _scanCancellation?.cancel();
  }

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    final generation = ++_rootGeneration;
    _emit(_state.copyWith(phase: RiskSpikePhase.checkingGrant));
    final roots = await storage.listPersistedRoots();
    if (!_isCurrentRootOperation(generation)) return;
    switch (roots) {
      case FailureResult<List<AuthorizedLibraryRoot>>(:final failure):
        _fail(failure);
      case Success<List<AuthorizedLibraryRoot>>(:final value):
        if (value.isEmpty) {
          _emit(const RiskSpikeState(phase: RiskSpikePhase.noRoot));
          return;
        }
        final inventory = await _loadInventory();
        if (!_isCurrentRootOperation(generation)) return;
        final root =
            value
                .where((root) => inventory?.matchesRoot(root.locator) ?? false)
                .firstOrNull ??
            value.first;
        final access = await storage.checkAccess(root.locator);
        if (!_isCurrentRootOperation(generation)) return;
        switch (access) {
          case Success<RootAccessState>(value: RootAccessState.available):
            _setAuthorizedRoot(root, inventory);
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
    final generation = ++_rootGeneration;
    final previous = _previousInventory ?? _state;
    _invalidateScan();
    _emit(_state.copyWith(phase: RiskSpikePhase.choosingRoot));
    final result = await storage.chooseRoot();
    if (!_isCurrentRootOperation(generation)) return;
    switch (result) {
      case Success<AuthorizedLibraryRoot>(:final value):
        final inventory = await _loadInventory();
        if (!_isCurrentRootOperation(generation)) return;
        _setAuthorizedRoot(value, inventory);
      case FailureResult<AuthorizedLibraryRoot>(:final failure):
        if (failure.code == 'USER_CANCELLED') {
          _emit(
            previous.copyWith(
              phase: previous.root == null
                  ? RiskSpikePhase.noRoot
                  : previous.scanCompleted
                  ? RiskSpikePhase.filesAvailable
                  : RiskSpikePhase.ready,
              canCancel: false,
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
    final generation = ++_rootGeneration;
    _invalidateScan();
    await playback.stop();
    if (!_isCurrentRootOperation(generation)) return;
    final result = await storage.releaseRootPermission(root.locator);
    if (!_isCurrentRootOperation(generation)) return;
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
        try {
          await _inventoryWrite;
          if (!_isCurrentRootOperation(generation)) return;
          await _inventoryStore.clear();
        } on Object {
          // Access checks still prevent a released grant from being restored.
        }
      case FailureResult<void>(:final failure):
        _fail(failure);
    }
  }

  Future<void> scan(AuthorizedLibraryRoot root) => _scan(root);

  Future<void> _scan(
    AuthorizedLibraryRoot root, {
    bool automatic = false,
  }) async {
    if (_disposed) return;
    _scanCancellation?.cancel();
    final scanId = 'scan-${++_scanSequence}';
    final cancellation = CancellationController();
    _activeScanId = scanId;
    _scanCancellation = cancellation;
    _isBackgroundRefreshing = automatic;
    _pendingAutomaticInventory = null;
    _previousInventory =
        _state.scanCompleted && _sameRoot(_state.root?.locator, root.locator)
        ? _state
        : null;
    _pendingScanState = RiskSpikeState(root: root);
    _pendingSubtitleEntries.clear();
    _pendingEntryBatches.clear();
    _pendingRefreshDiscoveredCount = 0;
    _lastScanProgressMillis = 0;
    _scanProgressClock
      ..reset()
      ..start();
    if (_previousInventory == null) _subtitleEntries.clear();
    _emit(
      automatic
          ? _state
          : (_previousInventory ?? RiskSpikeState(root: root)).copyWith(
              phase: _refreshPhase(RiskSpikePhase.enumerating),
              canCancel: true,
              clearFailure: _previousInventory == null,
              clearRefreshFailure: true,
              clearSelectedFile: _previousInventory == null,
              clearProbeResult: _previousInventory == null,
              clearSubtitleWarning: _previousInventory == null,
            ),
    );

    var terminalReceived = false;
    try {
      if (_activeScanId != scanId) return;
      if (cancellation.token.isCancelled) {
        _finishUnsuccessfulScan(RiskSpikePhase.cancelled);
        return;
      }
      await for (final event in storage.enumerateRecursively(
        root: root.locator,
        scanId: scanId,
        cancellationToken: cancellation.token,
      )) {
        if (_activeScanId != scanId ||
            event.scanId != scanId ||
            terminalReceived) {
          continue;
        }
        terminalReceived =
            event is StorageScanCompleted ||
            event is StorageScanCancelled ||
            event is StorageScanFailed;
        await _applyScanEvent(event);
      }
      if (_activeScanId == scanId && !terminalReceived) {
        _finishUnsuccessfulScan(RiskSpikePhase.failure, scanFailed);
      }
    } on Object {
      if (_activeScanId == scanId) {
        _finishUnsuccessfulScan(RiskSpikePhase.failure, scanFailed);
      }
    } finally {
      if (_activeScanId == scanId) {
        final inventory = _pendingAutomaticInventory;
        if (automatic &&
            inventory != null &&
            !cancellation.token.isCancelled &&
            _sameRoot(_state.root?.locator, inventory.root)) {
          _publishInventory(inventory);
        }
        _scanCancellation = null;
        _activeScanId = null;
        _pendingScanState = null;
        _previousInventory = null;
        _pendingEntryBatches.clear();
        _pendingAutomaticInventory = null;
        _scanProgressClock.stop();
        if (automatic) {
          _isBackgroundRefreshing = false;
          if (!_disposed) notifyListeners();
        }
      }
    }
  }

  void cancelScan() {
    _scanCancellation?.cancel();
  }

  static const scanFailed = AppFailure(
    code: 'SCAN_FAILED',
    messageKey: 'scanFailed',
    retryable: true,
  );

  bool _isCurrentRootOperation(int generation) =>
      !_disposed && generation == _rootGeneration;

  static bool _sameRoot(LibraryRootLocator? left, LibraryRootLocator right) =>
      left?.storageKind == right.storageKind &&
      left?.opaqueValue == right.opaqueValue;

  Future<ScanInventory?> _loadInventory() async {
    try {
      return await _inventoryStore.load();
    } on Object {
      return null;
    }
  }

  void _setAuthorizedRoot(
    AuthorizedLibraryRoot root,
    ScanInventory? inventory,
  ) {
    _lastAutomaticFailureAt = null;
    _subtitleEntries.clear();
    if (inventory == null || !inventory.matchesRoot(root.locator)) {
      _emit(RiskSpikeState(phase: RiskSpikePhase.ready, root: root));
      return;
    }
    _subtitleEntries.addAll(inventory.subtitles);
    _emit(
      RiskSpikeState(
        phase: RiskSpikePhase.filesAvailable,
        root: root,
        entries: inventory.videos,
        artworkEntries: inventory.artwork,
        discoveredCount: inventory.discoveredCount,
        ignoredCount: inventory.ignoredCount,
        videoCount: inventory.videos.length,
        subtitleCount: inventory.subtitles.length,
        scanCompleted: true,
        lastScanCompletedAt: inventory.completedAtUtc,
      ),
    );
  }

  void _invalidateScan() {
    _scanCancellation?.cancel();
    _scanCancellation = null;
    _activeScanId = null;
    _pendingScanState = null;
    _previousInventory = null;
    _pendingSubtitleEntries.clear();
    _pendingEntryBatches.clear();
    _scanProgressClock.stop();
    _isBackgroundRefreshing = false;
    _pendingAutomaticInventory = null;
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
    if (_playbackBlocked) return;
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
    if (_playbackBlocked) return;
    final blockGeneration = _playbackBlockGeneration;
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

    final opened = await switch (playback) {
      final PlaybackSessionCoordinator coordinator => coordinator.attachLease(
        lease,
        startPosition: startPosition,
        autoplay:
            !_playbackBlocked && blockGeneration == _playbackBlockGeneration,
      ),
      final session => session.attachLease(lease, startPosition: startPosition),
    };
    if (opened case FailureResult<void>(:final failure)) {
      _fail(failure, root: root);
      return;
    }
    if (_playbackBlocked || blockGeneration != _playbackBlockGeneration) {
      await _pauseForPlaybackBlock();
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
    if (_playbackBlocked && current.isPlaying) {
      unawaited(_pauseForPlaybackBlock());
    }
    if (current.isOpen &&
        (current.position != _state.playbackSnapshot.position ||
            current.duration != _state.playbackSnapshot.duration ||
            current.isPlaying != _state.playbackSnapshot.isPlaying ||
            current.isBuffering != _state.playbackSnapshot.isBuffering ||
            current.isCompleted != _state.playbackSnapshot.isCompleted ||
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
    if (_playbackBlocked) return;
    final blockGeneration = _playbackBlockGeneration;
    await _playbackBlockPause;
    if (_playbackBlocked || blockGeneration != _playbackBlockGeneration) return;
    final result = playback.snapshot.isPlaying
        ? await playback.pause()
        : await playback.play();
    if (_playbackBlocked || blockGeneration != _playbackBlockGeneration) {
      await _pauseForPlaybackBlock();
      return;
    }
    _applyPlaybackResult(result);
  }

  Future<void> seekBy(Duration delta) async {
    if (_playbackBlocked) return;
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
    if (_playbackBlocked) return;
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
    refreshPlaybackSnapshot();
  }

  Future<void> _applyScanEvent(StorageScanEvent event) async {
    final pending = _pendingScanState;
    if (pending == null) return;
    switch (event) {
      case StorageScanStarted():
        break;
      case StorageScanBatch(:final entries):
        if (_scanCancellation?.token.isCancelled ?? true) break;
        if (_previousInventory != null) {
          _pendingEntryBatches.add(List.unmodifiable(entries));
          _pendingRefreshDiscoveredCount += entries.length;
          final elapsed = _scanProgressClock.elapsedMilliseconds;
          if (!_isBackgroundRefreshing &&
              elapsed - _lastScanProgressMillis >= 150) {
            _lastScanProgressMillis = elapsed;
            _emit(
              _state.copyWith(discoveredCount: _pendingRefreshDiscoveredCount),
            );
          }
          break;
        }
        final videos = <StorageEntrySnapshot>[...pending.entries];
        final artwork = <StorageEntrySnapshot>[...pending.artworkEntries];
        var ignored = pending.ignoredCount;
        var videoCount = pending.videoCount;
        var subtitleCount = pending.subtitleCount;
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
              _pendingSubtitleEntries.add(entry);
              subtitleCount++;
            case LibraryFileKind.systemArtifact ||
                LibraryFileKind.ignoredOther ||
                LibraryFileKind.directory:
              ignored++;
          }
        }
        final next = pending.copyWith(
          entries: List<StorageEntrySnapshot>.unmodifiable(videos),
          artworkEntries: List<StorageEntrySnapshot>.unmodifiable(artwork),
          discoveredCount: pending.discoveredCount + entries.length,
          ignoredCount: ignored,
          videoCount: videoCount,
          subtitleCount: subtitleCount,
        );
        _pendingScanState = next;
        if (_previousInventory == null) {
          _subtitleEntries
            ..clear()
            ..addAll(_pendingSubtitleEntries);
        }
        _emit(
          _state.copyWith(
            entries: _previousInventory == null ? next.entries : null,
            artworkEntries: _previousInventory == null
                ? next.artworkEntries
                : null,
            discoveredCount: next.discoveredCount,
            ignoredCount: next.ignoredCount,
            videoCount: next.videoCount,
            subtitleCount: next.subtitleCount,
          ),
        );
      case StorageScanProgress():
        break;
      case StorageScanWarning():
        break;
      case StorageScanCompleted():
        if (_scanCancellation?.token.isCancelled ?? true) {
          _finishUnsuccessfulScan(RiskSpikePhase.cancelled);
          return;
        }
        final completedAt = _clock().toUtc();
        final root = pending.root!.locator;
        final cancellation = _scanCancellation;
        final inventory = _previousInventory == null
            ? ScanInventory(
                root: root,
                videos: pending.entries,
                artwork: pending.artworkEntries,
                subtitles: _pendingSubtitleEntries,
                discoveredCount: pending.discoveredCount,
                ignoredCount: pending.ignoredCount,
                completedAtUtc: completedAt,
              )
            : await _inventoryWorker(
                ScanInventoryWork(
                  root: root,
                  batches: List.unmodifiable(_pendingEntryBatches),
                  classifier: classifier,
                  completedAtUtc: completedAt,
                ),
              );
        if (_disposed ||
            _activeScanId != event.scanId ||
            !_sameRoot(_state.root?.locator, root)) {
          return;
        }
        if (cancellation?.token.isCancelled ?? true) {
          _finishUnsuccessfulScan(RiskSpikePhase.cancelled);
          return;
        }
        final automatic = _isBackgroundRefreshing;
        if (!automatic) _publishInventory(inventory);
        if (_activeScanId != event.scanId) return;
        await _saveInventory(inventory, event.scanId);
        if (automatic &&
            !_disposed &&
            _activeScanId == event.scanId &&
            !(cancellation?.token.isCancelled ?? true) &&
            _sameRoot(_state.root?.locator, root)) {
          _pendingAutomaticInventory = inventory;
        }
      case StorageScanCancelled():
        _finishUnsuccessfulScan(RiskSpikePhase.cancelled);
      case StorageScanFailed(:final failure):
        _finishUnsuccessfulScan(RiskSpikePhase.failure, failure);
    }
  }

  void _finishUnsuccessfulScan(RiskSpikePhase phase, [AppFailure? failure]) {
    if (_scanCancellation?.token.isCancelled ?? false) {
      phase = RiskSpikePhase.cancelled;
      failure = null;
    }
    final previous = _previousInventory;
    if (_isBackgroundRefreshing) {
      if (failure != null) _lastAutomaticFailureAt = _clock().toUtc();
      return;
    }
    _emit(
      _state.copyWith(
        phase: _refreshPhase(phase),
        entries: previous?.entries,
        artworkEntries: previous?.artworkEntries,
        discoveredCount: previous?.discoveredCount,
        ignoredCount: previous?.ignoredCount,
        videoCount: previous?.videoCount,
        subtitleCount: previous?.subtitleCount,
        scanCompleted: previous != null,
        lastScanCompletedAt: previous?.lastScanCompletedAt,
        canCancel: false,
        failure: previous == null ? failure : null,
        clearFailure: previous == null && failure == null,
        refreshFailure: previous != null ? failure : null,
        clearRefreshFailure: previous == null || failure == null,
      ),
    );
  }

  Future<void> _saveInventory(ScanInventory inventory, String scanId) {
    // A slow older write must finish before a newer scan replaces its cache.
    final writing = _inventoryWrite.then((_) async {
      if (_disposed ||
          _activeScanId != scanId ||
          (_scanCancellation?.token.isCancelled ?? true) ||
          !_sameRoot(_state.root?.locator, inventory.root)) {
        return;
      }
      try {
        await _inventoryStore.save(inventory);
      } on Object {
        // A cache write failure must not discard a successful live scan.
      }
    });
    _inventoryWrite = writing;
    return writing;
  }

  void _publishInventory(ScanInventory inventory) {
    final unchanged = _sameInventory(inventory);
    if (!unchanged) {
      _subtitleEntries
        ..clear()
        ..addAll(inventory.subtitles);
    }
    _lastAutomaticFailureAt = null;
    _emitScanResult(
      _state.copyWith(
        phase: _isBackgroundRefreshing
            ? _state.phase
            : _refreshPhase(RiskSpikePhase.filesAvailable),
        entries: unchanged ? null : inventory.videos,
        artworkEntries: unchanged ? null : inventory.artwork,
        discoveredCount: inventory.discoveredCount,
        ignoredCount: inventory.ignoredCount,
        videoCount: inventory.videos.length,
        subtitleCount: inventory.subtitles.length,
        scanCompleted: true,
        lastScanCompletedAt: inventory.completedAtUtc,
        canCancel: false,
        clearFailure: _previousInventory == null,
        clearRefreshFailure: true,
      ),
    );
  }

  void _emitScanResult(RiskSpikeState next) {
    if (_isBackgroundRefreshing) {
      if (!_disposed) _state = next;
    } else {
      _emit(next);
    }
  }

  bool _sameInventory(ScanInventory inventory) {
    final previous = _previousInventory;
    return previous != null &&
        previous.discoveredCount == inventory.discoveredCount &&
        previous.ignoredCount == inventory.ignoredCount &&
        previous.videoCount == inventory.videos.length &&
        previous.subtitleCount == inventory.subtitles.length &&
        _sameEntries(previous.entries, inventory.videos) &&
        _sameEntries(previous.artworkEntries, inventory.artwork) &&
        _sameEntries(_subtitleEntries, inventory.subtitles);
  }

  static bool _sameEntries(
    List<StorageEntrySnapshot> previous,
    List<StorageEntrySnapshot> current,
  ) {
    if (previous.length != current.length) return false;
    final byKey = <String, List<StorageEntrySnapshot>>{};
    for (final entry in previous) {
      (byKey[entry.storageKey] ??= []).add(entry);
    }
    for (final entry in current) {
      final candidates = byKey[entry.storageKey];
      if (candidates == null) return false;
      final index = candidates.indexWhere((other) => _sameEntry(other, entry));
      if (index < 0) return false;
      candidates.removeAt(index);
      if (candidates.isEmpty) byKey.remove(entry.storageKey);
    }
    return byKey.isEmpty;
  }

  static bool _sameEntry(
    StorageEntrySnapshot left,
    StorageEntrySnapshot right,
  ) =>
      left.storageKey == right.storageKey &&
      left.parentStorageKey == right.parentStorageKey &&
      left.relativePath == right.relativePath &&
      left.displayName == right.displayName &&
      left.isDirectory == right.isDirectory &&
      left.mimeType == right.mimeType &&
      left.sizeBytes == right.sizeBytes &&
      left.modifiedAtUtc == right.modifiedAtUtc &&
      setEquals(left.flags, right.flags);

  RiskSpikePhase _refreshPhase(RiskSpikePhase scanPhase) =>
      _previousInventory != null &&
          ((_state.phase == RiskSpikePhase.failure && _state.failure != null) ||
              const {
                RiskSpikePhase.fileReady,
                RiskSpikePhase.probing,
                RiskSpikePhase.openingPlayback,
                RiskSpikePhase.playing,
              }.contains(_state.phase))
      ? _state.phase
      : scanPhase;

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
    final grantRevoked = failure.code == 'STORAGE_PERMISSION_REVOKED';
    if (grantRevoked) {
      _rootGeneration++;
      _invalidateScan();
    }
    _emit(
      _state.copyWith(
        phase: RiskSpikePhase.failure,
        root: root,
        canCancel: grantRevoked ? false : _state.canCancel,
        failure: failure,
      ),
    );
  }

  void _emit(RiskSpikeState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _rootGeneration++;
    _invalidateScan();
    super.dispose();
  }
}
