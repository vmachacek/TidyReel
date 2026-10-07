import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:media_domain/media_domain.dart';
import 'package:media_parser/media_parser.dart' as parser;
import 'package:media_platform_storage/media_platform_storage.dart';

import '../risk_spike/risk_spike_controller.dart';
import '../../infrastructure/metadata/tmdb_catalog_metadata_source.dart';
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

List<CatalogTitle> groupCatalog(List<StorageEntrySnapshot> files) {
  final result = <CatalogTitle>[];
  final series = <String, List<CatalogVideo>>{};
  for (final file in files) {
    final video = CatalogVideo(file);
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

class CatalogLibrary extends ChangeNotifier {
  CatalogLibrary(this.controller, {CatalogMetadataSource? metadataSource})
    : matcher = CatalogMatcher(source: metadataSource),
      _injectedSource = metadataSource != null {
    matcher.addListener(_matchingChanged);
    unawaited(load());
  }
  final RiskSpikeController controller;
  final CatalogMatcher matcher;
  final bool _injectedSource;
  Future<void>? _loading;
  List<StorageEntrySnapshot>? _catalogEntries;
  List<CatalogTitle> _localTitles = const [];
  List<CatalogTitle> _presentationTitles = const [];
  bool _presentationDirty = true;
  String _catalogScope = '';
  bool metadataConfigured = false;
  String? settingsError;
  String get catalogScope => _catalogScope;
  List<CatalogTitle> get localTitles => _localTitles;
  List<CatalogTitle> get currentTitles {
    if (_presentationDirty) {
      _presentationTitles = matcher.apply(_localTitles, _catalogScope);
      _presentationDirty = false;
    }
    return _presentationTitles;
  }

  List<CatalogTitle> titlesFor(List<StorageEntrySnapshot> entries) {
    final scope = controller.state.root?.locator.opaqueValue ?? '';
    if (!identical(_catalogEntries, entries) || scope != _catalogScope) {
      _catalogEntries = entries;
      _catalogScope = scope;
      _localTitles = groupCatalog(entries);
      _presentationDirty = true;
      unawaited(
        Future<void>.microtask(() async {
          await load();
          if (!_disposed) await matcher.enrich(_localTitles, _catalogScope);
        }),
      );
    }
    return currentTitles;
  }

  void _matchingChanged() {
    if (_disposed) return;
    _presentationDirty = true;
    notifyListeners();
    unawaited(persist());
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

  bool isSaved(CatalogTitle title) =>
      saved.contains(title.id) || title.localIds.any(saved.contains);
  static const channel = MethodChannel('com.pocketcinema.app/catalog');
  final saved = <String>{};
  final positions = <String, int>{};
  final durations = <String, int>{};
  final _thumbnails = <String, Future<Uint8List?>>{};
  final _metadata = <String, Future<MediaProbeResult?>>{};
  bool _disposed = false;
  Future<void> load() => _loading ??= _load();
  Future<void> _load() async {
    try {
      final raw = await channel.invokeMethod<String>('loadPreferences');
      final data = jsonDecode(raw ?? '{}') as Map<String, dynamic>;
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
      matcher.restore((data['titleMatches'] as Map<String, dynamic>?) ?? {});
      matcher.localOnly.addAll(
        (data['localOnlyTitles'] as List<dynamic>? ?? []).whereType<String>(),
      );
      _presentationDirty = true;
      if (!_disposed) notifyListeners();
    } on Object {
      /* Preferences are optional on non-Android test hosts. */
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

  Future<void> persist() async {
    try {
      await channel.invokeMethod<void>('savePreferences', {
        'value': jsonEncode({
          'saved': saved.toList(),
          'positions': positions,
          'durations': durations,
          'titleMatches': matcher.toJson(),
          'localOnlyTitles': matcher.localOnly.toList(),
        }),
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

  Future<Uint8List?> thumbnail(CatalogVideo video, {bool backdrop = false}) {
    final root = controller.state.root;
    if (root == null) return Future.value();
    final artwork = findArtwork(
      video,
      controller.state.artworkEntries,
      backdrop: backdrop,
    );
    final key =
        '${root.locator.opaqueValue}|${video.id}|${video.file.modifiedAtUtc}|${video.file.sizeBytes}|${artwork?.storageKey}|${artwork?.modifiedAtUtc}';

    return _thumbnails.putIfAbsent(key, () async {
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
