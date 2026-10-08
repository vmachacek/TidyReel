import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:media_domain/media_domain.dart';
import 'package:media_parser/media_parser.dart' as parser;
import 'package:media_platform_storage/media_platform_storage.dart';

import '../risk_spike/risk_spike_controller.dart';
import '../../infrastructure/metadata/tmdb_catalog_metadata_source.dart';
import 'catalog_discovery_worker.dart';
import 'catalog_matching.dart';
import 'catalog_metadata.dart';

class CatalogVideo {
  CatalogVideo(this.file)
    : onlineTitle = null,
      onlineSeries = null,
      onlineEpisode = null,
      reviewReason = null,
      parsed = parser.parseMediaName(
        fileName: file.displayName,
        relativePath: file.relativePath,
      );
  CatalogVideo.identified(
    this.file,
    this.parsed, {
    this.onlineTitle,
    this.onlineSeries,
    this.onlineEpisode,
    this.reviewReason,
  });
  final StorageEntrySnapshot file;
  final parser.ParsedMediaName parsed;
  final String? onlineTitle, onlineSeries, reviewReason;
  final int? onlineEpisode;
  String get title => onlineTitle ?? parsed.title;
  String? get series => onlineSeries ?? parsed.series;
  int? get season => parsed.season;
  int? get episode => onlineEpisode ?? parsed.episode;
  int? get endEpisode => parsed.endEpisode;
  int? get year => parsed.year;
  String get id => file.storageKey;
  bool get needsReview =>
      reviewReason != null ||
      parsed.warnings.any(
        (warning) =>
            !(warning == 'MISSING_EPISODE_NUMBER' && onlineEpisode != null) &&
            !(warning == 'MISSING_SERIES_TITLE' && onlineSeries != null),
      );
  int get episodeCount => parsed.episodes.isEmpty ? 1 : parsed.episodes.length;
  String get episodeCode {
    if (season == null) return 'Episode unidentified';
    final prefix = 'S${season.toString().padLeft(2, '0')}';
    if (episode == null) return '$prefix · Episode unidentified';
    final references = parsed.episodes;
    if (references.isEmpty) {
      return '${prefix}E${episode.toString().padLeft(2, '0')}';
    }
    String code(parser.ParsedEpisodeReference ref) =>
        'E${ref.number.toString().padLeft(2, '0')}${ref.suffix ?? ''}';
    if (endEpisode != null && references.every((r) => r.suffix == null)) {
      return '$prefix${code(references.first)}-${code(references.last)}';
    }
    return '$prefix${references.map(code).join('+')}';
  }
}

String cleanTitle(String value) => value
    .replaceAll(RegExp(r'[._]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
String displayTitle(String value) => parser.cleanMediaTitle(value);
bool isSeasonFolder(String value) => parser.isSeasonFolder(value);
bool isSeriesContainer(String value) => parser.isSeriesContainer(value);

class CatalogTitle {
  CatalogTitle({
    required this.id,
    required this.name,
    required this.videos,
    this.isSeries = false,
    this.localIds = const [],
    this.providerId,
    this.overview,
    this.matchStatus,
  });
  final String id, name;
  final List<CatalogVideo> videos;
  final bool isSeries;
  final List<String> localIds;
  final String? providerId, overview, matchStatus;
  CatalogVideo get first => videos.first;
  List<int> get seasons =>
      videos.map((v) => v.season).whereType<int>().toSet().toList()..sort();
  int? get sizeBytes => videos.any((v) => v.file.sizeBytes == null)
      ? null
      : videos.fold<int>(0, (sum, v) => sum + v.file.sizeBytes!);
  int get episodeCount => videos.fold(0, (sum, v) => sum + v.episodeCount);
  DateTime? get modified => videos
      .map((v) => v.file.modifiedAtUtc)
      .whereType<DateTime>()
      .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
}

List<CatalogTitle> groupCatalog(
  List<StorageEntrySnapshot> files, {
  List<CatalogTitle> previousTitles = const [],
}) {
  final result = <CatalogTitle>[];
  final series = <String, List<CatalogVideo>>{};
  final previous = {
    for (final title in previousTitles)
      for (final video in title.videos) video.id: video,
  };
  for (final file in files) {
    final cached = previous[file.storageKey];
    // Isolate messages copy objects, so unchanged names are the cache identity.
    // Reattach the new snapshot to retain updated sizes, timestamps and flags.
    final video =
        cached != null &&
            cached.file.displayName == file.displayName &&
            cached.file.relativePath == file.relativePath
        ? CatalogVideo.identified(file, cached.parsed)
        : CatalogVideo(file);
    if (video.series != null) {
      final key = video.parsed.warnings.contains('MISSING_SERIES_TITLE')
          ? 'unidentified:${video.id}'
          : '${parser.normalizedMediaTitle(video.series!)}${video.year == null ? '' : ' (${video.year})'}';
      series.putIfAbsent(key, () => []).add(video);
    } else {
      result.add(
        CatalogTitle(
          id: video.id,
          name: video.title,
          videos: [video],
          localIds: [video.id],
        ),
      );
    }
  }
  for (final entry in series.entries) {
    final group = entry.value;
    group.sort(
      (a, b) => a.season == b.season
          ? (a.episode ?? 100000).compareTo(b.episode ?? 100000)
          : (a.season ?? 0).compareTo(b.season ?? 0),
    );
    result.add(
      CatalogTitle(
        id: 'series:${entry.key}',
        name: group.first.parsed.warnings.contains('MISSING_SERIES_TITLE')
            ? 'Unidentified show'
            : displayTitle(group.first.series!),
        videos: group,
        isSeries: true,
        localIds: ['series:${entry.key}'],
      ),
    );
  }
  return result;
}

enum CatalogHomeView { carousel, cards }

class CatalogLibrary extends ChangeNotifier {
  CatalogLibrary(
    this.controller, {
    CatalogMetadataSource? metadataSource,
    CatalogDiscoveryWorker? discoveryWorker,
  }) : matcher = CatalogMatcher(source: metadataSource),
       _discoveryWorker = discoveryWorker ?? discoverCatalogInBackground,
       _injectedSource = metadataSource != null {
    matcher.addListener(_matchingChanged);
    controller.addListener(_controllerChanged);
    _controllerChanged();
    unawaited(load());
  }
  final RiskSpikeController controller;
  final CatalogMatcher matcher;
  final CatalogDiscoveryWorker _discoveryWorker;
  final bool _injectedSource;
  Future<void>? _loading;
  final _preferencesRestored = Completer<void>();
  List<StorageEntrySnapshot>? _catalogEntries;
  List<CatalogTitle> _localTitles = const [];
  List<CatalogTitle> _presentationTitles = const [];
  bool _groupingDirty = false;
  bool _discoveryRequested = false;
  bool _discoveryRunning = false;
  int _catalogRevision = 0;
  int _activeCatalogRevision = -1;
  int _matchingRevision = 0;
  int _observedMatchingRevision = 0;
  Completer<void>? _discoveryIdle;
  String _catalogScope = '';
  bool metadataConfigured = false;
  CatalogHomeView _homeView = CatalogHomeView.carousel;
  CatalogHomeView get homeView => _homeView;
  bool _lockHardwareVolumeButtons = true;
  bool get lockHardwareVolumeButtons => _lockHardwareVolumeButtons;
  String? settingsError;
  String? discoveryError;
  bool get isDiscovering =>
      !_disposed &&
      (_discoveryRequested ||
          (_discoveryRunning && _activeCatalogRevision == _catalogRevision));
  String get catalogScope => _catalogScope;
  List<CatalogTitle> get localTitles => _localTitles;
  List<CatalogTitle> get currentTitles => _presentationTitles;

  List<CatalogTitle> titlesFor(List<StorageEntrySnapshot> entries) {
    _updateCatalog(entries);
    return currentTitles;
  }

  void _controllerChanged() => _updateCatalog(controller.state.entries);

  void _updateCatalog(List<StorageEntrySnapshot> entries) {
    if (_disposed) return;
    final scope = controller.state.root?.locator.opaqueValue ?? '';
    if (!identical(_catalogEntries, entries) || scope != _catalogScope) {
      final scopeChanged = scope != _catalogScope;
      _catalogEntries = entries;
      _catalogScope = scope;
      _catalogRevision++;
      discoveryError = null;
      if (scopeChanged || entries.isEmpty) {
        _localTitles = const [];
        _presentationTitles = const [];
      }
      _groupingDirty = entries.isNotEmpty;
      _scheduleDiscovery();
    }
  }

  /// Waits for local parsing and cached metadata, without waiting on the network.
  Future<void> waitForDiscovery() async {
    while (!_disposed && _discoveryIdle != null) {
      await _discoveryIdle!.future;
    }
  }

  void retryDiscovery() {
    if (_disposed) return;
    discoveryError = null;
    _scheduleDiscovery();
  }

  void _scheduleDiscovery() {
    if (_disposed) return;
    _discoveryRequested = true;
    if (_discoveryIdle != null) return;
    _discoveryIdle = Completer<void>();
    // Calls from titlesFor/build only queue work; they never notify mid-build.
    unawaited(Future<void>.microtask(_runDiscovery));
  }

  Future<void> _runDiscovery() async {
    _discoveryRunning = true;
    try {
      while (_discoveryRequested && !_disposed) {
        _discoveryRequested = false;
        final revision = _catalogRevision;
        final matchingRevision = _matchingRevision;
        _activeCatalogRevision = revision;
        final entries = _groupingDirty ? _catalogEntries : null;
        final scope = _catalogScope;
        notifyListeners();
        if (_catalogEntries?.isEmpty ?? true) {
          _localTitles = const [];
          _presentationTitles = const [];
          _groupingDirty = false;
          discoveryError = null;
          continue;
        }
        try {
          final result = await _discoveryWorker(
            CatalogDiscoveryRequest(
              scope: scope,
              entries: entries,
              localTitles: _localTitles,
              matching: matcher.snapshot(),
            ),
          );
          if (_disposed || revision != _catalogRevision) continue;
          _localTitles = result.localTitles;
          _groupingDirty = false;
          discoveryError = null;
          if (matchingRevision == _matchingRevision) {
            _presentationTitles = result.titles;
            _persistArtworkAliases();
          } else {
            _discoveryRequested = true;
          }
          if (entries != null) unawaited(_enrichCatalog(revision));
        } on Object {
          if (_disposed ||
              revision != _catalogRevision ||
              matchingRevision != _matchingRevision) {
            continue;
          }
          discoveryError = 'Could not organize the media library. Try scanning the folder again.';
        }
      }
    } finally {
      _discoveryRunning = false;
      final completion = _discoveryIdle;
      _discoveryIdle = null;
      completion?.complete();
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _enrichCatalog(int revision) async {
    await load();
    if (!_disposed && revision == _catalogRevision) {
      await matcher.enrich(_localTitles, _catalogScope);
    }
  }

  void _persistArtworkAliases() {
    if (_disposed ||
        !_propagateArtworkAliases(_presentationTitles) ||
        _artworkChoicesPersistScheduled) {
      return;
    }
    _artworkChoicesPersistScheduled = true;
    unawaited(
      Future<void>.microtask(() async {
        _artworkChoicesPersistScheduled = false;
        if (!_disposed) await persist();
      }),
    );
  }

  void _matchingChanged() {
    if (_disposed) return;
    if (_observedMatchingRevision != matcher.presentationRevision) {
      _observedMatchingRevision = matcher.presentationRevision;
      _matchingRevision++;
      _scheduleDiscovery();
      unawaited(persist());
    }
    notifyListeners();
  }

  Future<void> setMetadataToken(String token) async {
    settingsError = null;
    CatalogMetadataSource? replacement;
    try {
      await load();
      if (_disposed) return;
      replacement = token.trim().isNotEmpty
          ? TmdbCatalogMetadataSource(accessToken: token.trim())
          : null;
      await channel.invokeMethod<void>('saveMetadataToken', {
        'value': token.trim(),
      });
      if (_disposed) {
        replacement?.dispose();
        return;
      }
      metadataConfigured = token.trim().isNotEmpty;
      matcher.configure(replacement);
      replacement = null;
      unawaited(matcher.enrich(_localTitles, _catalogScope));
    } on Object catch (error) {
      replacement?.dispose();
      settingsError = error is CatalogMetadataException
          ? error.message
          : 'Could not save the TMDB token. Please try again.';
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> retryMatching() => matcher.retry(_localTitles, _catalogScope);

  Future<void> setHomeView(CatalogHomeView value) async {
    await _preferencesRestored.future;
    if (_disposed || _homeView == value) return;
    _homeView = value;
    notifyListeners();
    await persist();
  }

  Future<void> setLockHardwareVolumeButtons(bool value) async {
    await load();
    if (_disposed || _lockHardwareVolumeButtons == value) return;
    _lockHardwareVolumeButtons = value;
    notifyListeners();
    await persist();
  }

  bool isSaved(CatalogTitle title) =>
      saved.contains(title.id) || title.localIds.any(saved.contains);
  static const channel = MethodChannel('com.pocketcinema.app/catalog');
  final saved = <String>{};
  final positions = <String, int>{};
  final durations = <String, int>{};
  final _thumbnails = <String, Future<Uint8List?>>{};
  final _chosenArtwork = <String, Future<Uint8List?>>{};
  final _artworkChoices = <String, String>{};
  int _artworkSequence = 0;
  bool _artworkChoicesPersistScheduled = false;
  final _availableArtwork =
      <
        String,
        ({
          CatalogArtworkSource source,
          List<CatalogArtworkCandidate> candidates,
        })
      >{};
  final _savingArtwork = <String>{};
  final _metadata = <String, Future<MediaProbeResult?>>{};
  bool _disposed = false;
  Future<void> load() => _loading ??= _load();
  Future<void> _load() async {
    try {
      final raw = await channel.invokeMethod<String>('loadPreferences');
      if (_disposed) return;
      final data = jsonDecode(raw ?? '{}') as Map<String, dynamic>;
      _homeView =
          CatalogHomeView.values
              .where((view) => view.name == data['homeView'])
              .firstOrNull ??
          CatalogHomeView.carousel;
      final volumeLock = data['lockHardwareVolumeButtons'];
      if (volumeLock is bool) _lockHardwareVolumeButtons = volumeLock;
      saved.addAll((data['saved'] as List<dynamic>? ?? []).cast<String>());
      positions.addAll(
        (data['positions'] as Map<String, dynamic>? ?? {}).map(
          (key, value) => MapEntry(key, (value as num).toInt()),
        ),
      );
      durations.addAll(
        (data['durations'] as Map<String, dynamic>? ?? {}).map(
          (key, value) => MapEntry(key, (value as num).toInt()),
        ),
      );
      final artworkChoices = data['artworkChoices'];
      if (artworkChoices is Map<String, dynamic>) {
        for (final entry in artworkChoices.entries) {
          final value = entry.value;
          if (value is String && value.isNotEmpty) {
            _artworkChoices[entry.key] = value;
          }
        }
      }
      matcher.restore((data['titleMatches'] as Map<String, dynamic>?) ?? {});
      matcher.localOnly.addAll(
        (data['localOnlyTitles'] as List<dynamic>? ?? []).whereType<String>(),
      );
      _observedMatchingRevision = matcher.presentationRevision;
      _matchingRevision++;
      _scheduleDiscovery();
      if (!_disposed) notifyListeners();
    } on Object {
      /* Preferences are optional on non-Android test hosts. */
    } finally {
      _preferencesRestored.complete();
    }
    if (!_injectedSource && !_disposed) {
      try {
        final token = await channel.invokeMethod<String>('loadMetadataToken');
        if (!_disposed && token != null && token.trim().isNotEmpty) {
          metadataConfigured = true;
          matcher.configure(TmdbCatalogMetadataSource(accessToken: token));
        }
      } on Object {
        // Online matching remains optional if secure storage is unavailable.
      }
    }
    if (!_disposed) {
      notifyListeners();
      await matcher.enrich(_localTitles, _catalogScope);
    }
  }

  String _preferencesJson() => jsonEncode({
    'homeView': _homeView.name,
    'lockHardwareVolumeButtons': _lockHardwareVolumeButtons,
    'saved': saved.toList(),
    'positions': positions,
    'durations': durations,
    'titleMatches': matcher.toJson(),
    'localOnlyTitles': matcher.localOnly.toList(),
    'artworkChoices': _artworkChoices,
  });

  Future<void> persist() async {
    try {
      await channel.invokeMethod<void>('savePreferences', {
        'value': _preferencesJson(),
      });
    } on Object {
      /* Playback remains usable if saving fails. */
    }
  }

  void toggleSaved(String id) {
    final title = currentTitles.where((t) => t.id == id).firstOrNull;
    if (title != null && isSaved(title)) {
      saved.remove(title.id);
      saved.removeAll(title.localIds);
    } else {
      if (title != null && title.localIds.isNotEmpty) {
        saved.addAll(title.localIds);
      } else {
        saved.contains(id) ? saved.remove(id) : saved.add(id);
      }
    }
    notifyListeners();
    unawaited(persist());
  }

  double progress(CatalogVideo video) => (durations[video.id] ?? 0) > 0
      ? ((positions[video.id] ?? 0) / (durations[video.id]!)).clamp(0, 1)
      : 0;
  bool watched(CatalogVideo video) => progress(video) >= .95;
  CatalogVideo next(CatalogTitle title) => title.videos.firstWhere(
    (v) => (positions[v.id] ?? 0) > 0 && !watched(v),
    orElse: () =>
        title.videos.firstWhere((v) => !watched(v), orElse: () => title.first),
  );
  void record(CatalogVideo video, {bool notify = true}) {
    final playback = controller.playback.snapshot;
    if (controller.state.selectedFile?.storageKey != video.id ||
        !playback.isOpen ||
        playback.duration <= Duration.zero) {
      return;
    }
    positions[video.id] = playback.position.inSeconds;
    durations[video.id] = playback.duration.inSeconds;
    if (!_disposed && notify) notifyListeners();
  }

  CatalogTitle _artworkTitle(CatalogTitle title) =>
      currentTitles
          .where(
            (current) =>
                current.id == title.id ||
                current.localIds.any(title.localIds.contains) ||
                current.videos.any((video) => video.id == title.first.id),
          )
          .firstOrNull ??
      title;

  String _artworkKey(
    CatalogTitle title,
    String scope,
    CatalogArtworkKind kind,
  ) => _artworkAliasKeys(title, scope, kind).first;

  List<String> _artworkAliasKeys(
    CatalogTitle title,
    String scope,
    CatalogArtworkKind kind,
  ) {
    final ids = title.localIds.isEmpty ? [title.id] : [...title.localIds]
      ..sort();
    return [
      for (final id in ids) jsonEncode([scope, id, kind.name]),
    ];
  }

  bool _propagateArtworkAliases(List<CatalogTitle> titles) {
    var changed = false;
    for (final title in titles.where((title) => title.isSeries)) {
      for (final kind in CatalogArtworkKind.values) {
        final aliases = _artworkAliasKeys(title, _catalogScope, kind);
        final chosen = aliases
            .map((alias) => _artworkChoices[alias])
            .whereType<String>()
            .firstOrNull;
        if (chosen == null) continue;
        for (final alias in aliases) {
          if (_artworkChoices.containsKey(alias)) continue;
          _artworkChoices[alias] = chosen;
          changed = true;
        }
      }
    }
    return changed;
  }

  String _artworkRequestKey(CatalogTitle title, String scope) => jsonEncode([
    _artworkKey(title, scope, CatalogArtworkKind.poster),
    title.providerId,
  ]);

  void _checkArtworkRequest(
    CatalogTitle title,
    String scope,
    String requestKey,
    CatalogArtworkSource source,
  ) {
    if (_disposed ||
        controller.state.root?.locator.opaqueValue != scope ||
        !identical(matcher.artworkSource, source) ||
        title.localIds.any(
          (id) =>
              matcher.matches[jsonEncode([scope, id])]?.candidate.providerId !=
              title.providerId,
        ) ||
        _artworkRequestKey(_artworkTitle(title), scope) != requestKey) {
      throw const CatalogMetadataException(
        'The show or library changed. Refresh artwork again.',
      );
    }
  }

  /// Explicit refresh always asks the provider again without replacing artwork.
  Future<List<CatalogArtworkCandidate>> refreshArtwork(
    CatalogTitle title,
  ) async {
    await load();
    final current = _artworkTitle(title);
    if (!current.isSeries) {
      throw const CatalogMetadataException(
        'Artwork refresh is available for TV shows.',
      );
    }
    final source = matcher.artworkSource;
    if (source == null) {
      throw const CatalogMetadataException(
        'Enable TMDB in Library Settings to refresh artwork.',
      );
    }
    if (current.providerId == null) {
      throw const CatalogMetadataException(
        'Review the title match before refreshing artwork.',
      );
    }
    final scope = controller.state.root?.locator.opaqueValue;
    if (scope == null) {
      throw const CatalogMetadataException('Choose a media folder first.');
    }
    final requestKey = _artworkRequestKey(current, scope);
    final candidates = await source.artwork(providerId: current.providerId!);
    _checkArtworkRequest(current, scope, requestKey, source);
    final result = List<CatalogArtworkCandidate>.unmodifiable(candidates);
    _availableArtwork[requestKey] = (source: source, candidates: result);
    return result;
  }

  /// Download and durably save first; only then change the displayed artwork.
  Future<void> selectArtwork(
    CatalogTitle title,
    CatalogArtworkCandidate candidate,
  ) async {
    final current = _artworkTitle(title);
    final scope = controller.state.root?.locator.opaqueValue;
    if (scope == null) {
      throw const CatalogMetadataException('Choose a media folder first.');
    }
    final requestKey = _artworkRequestKey(current, scope);
    final available = _availableArtwork[requestKey];
    if (available == null || !available.candidates.contains(candidate)) {
      throw const CatalogMetadataException(
        'Refresh artwork before choosing an image.',
      );
    }
    final source = available.source;
    _checkArtworkRequest(current, scope, requestKey, source);
    final key = _artworkKey(current, scope, candidate.kind);
    if (!_savingArtwork.add(key)) {
      throw const CatalogMetadataException('Artwork is already being saved.');
    }
    String? pendingBlobKey;
    final previousChoices = <String, String?>{};
    try {
      final bytes = await source.downloadArtwork(candidate);
      _checkArtworkRequest(current, scope, requestKey, source);
      if (bytes.isEmpty || bytes.length > 8 * 1024 * 1024) {
        throw const CatalogMetadataException(
          'The selected artwork could not be downloaded.',
        );
      }
      final blobKey = jsonEncode([
        key,
        DateTime.now().microsecondsSinceEpoch,
        _artworkSequence++,
      ]);
      final saved = await channel.invokeMethod<bool>('saveArtwork', {
        'key': blobKey,
        'bytes': bytes,
      });
      if (saved != true) {
        throw const CatalogMetadataException(
          'Could not save artwork on this device. Try again.',
        );
      }
      pendingBlobKey = blobKey;
      _checkArtworkRequest(current, scope, requestKey, source);
      for (final alias in _artworkAliasKeys(
        _artworkTitle(current),
        scope,
        candidate.kind,
      )) {
        previousChoices[alias] = _artworkChoices[alias];
        _artworkChoices[alias] = blobKey;
      }
      // The previous blobs stay immutable until the new references are saved.
      await channel.invokeMethod<void>('savePreferences', {
        'value': _preferencesJson(),
      });
      pendingBlobKey = null;
      _chosenArtwork[blobKey] = Future.value(bytes);
      _thumbnails.clear();
      if (!_disposed) notifyListeners();
      unawaited(
        _deleteUnusedArtwork(previousChoices.values.whereType<String>()),
      );
    } on Object catch (error) {
      // Alias propagation may have linked another name while the preference
      // write was pending. Those new links must roll back with this choice.
      if (pendingBlobKey != null) {
        for (final alias
            in _artworkChoices.entries
                .where((entry) => entry.value == pendingBlobKey)
                .map((entry) => entry.key)
                .toList()) {
          previousChoices.putIfAbsent(alias, () => null);
        }
      }
      for (final entry in previousChoices.entries) {
        if (_artworkChoices[entry.key] != pendingBlobKey) continue;
        final previous = entry.value;
        if (previous == null) {
          _artworkChoices.remove(entry.key);
        } else {
          _artworkChoices[entry.key] = previous;
        }
      }
      if (pendingBlobKey != null) {
        try {
          await channel.invokeMethod<bool>('deleteArtwork', {
            'key': pendingBlobKey,
          });
        } on Object {
          // An unused private blob is harmless if cleanup is unavailable.
        }
      }
      if (previousChoices.isNotEmpty) await persist();
      if (error is CatalogMetadataException) rethrow;
      throw const CatalogMetadataException(
        'Could not save artwork on this device. Try again.',
      );
    } finally {
      _savingArtwork.remove(key);
    }
  }

  Future<void> _deleteUnusedArtwork(Iterable<String> blobKeys) async {
    for (final key in blobKeys.toSet()) {
      if (_artworkChoices.containsValue(key)) continue;
      try {
        final deleted = await channel.invokeMethod<bool>('deleteArtwork', {
          'key': key,
        });
        if (deleted == true) _chosenArtwork.remove(key)?.ignore();
      } on Object {
        // Cleanup failure does not affect the saved selection.
      }
    }
  }

  Future<Uint8List?> _readChosenArtwork(String key) =>
      _chosenArtwork.putIfAbsent(key, () async {
        try {
          return await channel.invokeMethod<Uint8List>('readArtwork', {
            'key': key,
          });
        } on Object {
          return null;
        }
      });

  Future<Uint8List?> thumbnail(CatalogVideo video, {bool backdrop = false}) {
    final root = controller.state.root;
    if (root == null) return Future.value();
    final artwork = findArtwork(
      video,
      controller.state.artworkEntries,
      backdrop: backdrop,
    );
    final title = currentTitles
        .where(
          (title) =>
              title.isSeries && title.videos.any((v) => v.id == video.id),
        )
        .firstOrNull;
    final chosenKeys = <String>{};
    if (title != null) {
      for (final alias in _artworkAliasKeys(
        title,
        root.locator.opaqueValue,
        backdrop ? CatalogArtworkKind.backdrop : CatalogArtworkKind.poster,
      )) {
        final chosen = _artworkChoices[alias];
        if (chosen != null) chosenKeys.add(chosen);
      }
    }
    final key =
        '${root.locator.opaqueValue}|${video.id}|$backdrop|${jsonEncode(chosenKeys.toList())}|${video.file.modifiedAtUtc}|${video.file.sizeBytes}|${artwork?.storageKey}|${artwork?.modifiedAtUtc}';

    return _thumbnails.putIfAbsent(key, () async {
      for (final chosenKey in chosenKeys) {
        final chosen = await _readChosenArtwork(chosenKey);
        if (chosen != null) return chosen;
      }
      if (artwork != null) {
        try {
          final result = await controller.storage.readSmallFile(
            root: root.locator,
            storageKey: artwork.storageKey,
            maximumBytes: 2 * 1024 * 1024,
          );
          if (result is Success<SmallFileContent>) return result.value.bytes;
        } on Object {
          /* Fall back to a frame if sidecar artwork is unavailable. */
        }
      }
      try {
        return await channel.invokeMethod<Uint8List>('thumbnail', {
          'treeUri': root.locator.opaqueValue,
          'storageKey': video.id,
        });
      } on Object {
        return null;
      }
    });
  }

  Future<MediaProbeResult?> metadata(CatalogVideo video) {
    final root = controller.state.root;
    if (root == null) return Future.value();
    final key =
        '${root.locator.opaqueValue}|${video.id}|${video.file.modifiedAtUtc}|${video.file.sizeBytes}';
    return _metadata.putIfAbsent(key, () async {
      try {
        final result = await controller.probe.probe(
          root: root.locator,
          storageKey: video.id,
          cancellationToken: CancellationController().token,
        );
        return result is Success<MediaProbeResult> ? result.value : null;
      } on Object {
        return null;
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _catalogRevision++;
    controller.removeListener(_controllerChanged);
    _discoveryIdle?.complete();
    _discoveryIdle = null;
    matcher.removeListener(_matchingChanged);
    matcher.dispose();
    super.dispose();
  }
}

StorageEntrySnapshot? findArtwork(
  CatalogVideo video,
  List<StorageEntrySnapshot> images, {
  bool backdrop = false,
}) {
  final path = video.file.relativePath.replaceAll('\\', '/');
  final folders = path.split('/')..removeLast();
  final folder = folders.join('/');
  final stem = video.file.displayName.replaceFirst(RegExp(r'\.[^.]+$'), '');
  final bases = backdrop
      ? ['$stem-thumb', stem, 'fanart', 'backdrop']
      : ['$stem-poster', stem, 'poster', 'folder'];
  final directories = [folder];
  if (video.series != null &&
      folders.isNotEmpty &&
      isSeasonFolder(folders.last)) {
    directories.add(folders.take(folders.length - 1).join('/'));
  }
  for (final directory in directories) {
    for (final base in bases) {
      for (final ext in ['jpg', 'jpeg', 'png', 'webp']) {
        final candidate = '${directory.isEmpty ? '' : '$directory/'}$base.$ext'
            .toLowerCase();
        for (final image in images) {
          if (image.relativePath.replaceAll('\\', '/').toLowerCase() ==
              candidate) {
            return image;
          }
        }
      }
    }
  }
  return null;
}

String fileSize(int? bytes) {
  if (bytes == null) return 'Size unavailable';
  if (bytes >= 1073741824) {
    return '${(bytes / 1073741824).toStringAsFixed(1)} GB';
  }
  if (bytes >= 1048576) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  return '${(bytes / 1024).toStringAsFixed(0)} KB';
}

String durationText(Duration? duration) => duration == null
    ? 'Duration unavailable'
    : duration.inHours > 0
    ? '${duration.inHours}h ${duration.inMinutes % 60}m'
    : '${duration.inMinutes}m';
