import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'catalog_library.dart';
import 'catalog_metadata.dart';

/// Canonical records decorate local files. Numbers from local files remain evidence.
class CatalogResolvedMatch {
  const CatalogResolvedMatch(
    this.candidate,
    this.episodes, {
    this.manual = false,
  });
  final CatalogMetadataCandidate candidate;
  final List<CatalogEpisodeMetadata> episodes;
  final bool manual;

  bool hasSameMetadata(CatalogResolvedMatch other) {
    if (manual != other.manual ||
        candidate.providerId != other.candidate.providerId ||
        candidate.name != other.candidate.name ||
        candidate.originalName != other.candidate.originalName ||
        candidate.year != other.candidate.year ||
        candidate.overview != other.candidate.overview ||
        episodes.length != other.episodes.length) {
      return false;
    }
    for (var index = 0; index < episodes.length; index++) {
      final episode = episodes[index], otherEpisode = other.episodes[index];
      if (episode.season != otherEpisode.season ||
          episode.number != otherEpisode.number ||
          episode.name != otherEpisode.name) {
        return false;
      }
    }
    return true;
  }

  Map<String, Object?> toJson() => {
    'id': candidate.providerId,
    'name': candidate.name,
    'originalName': candidate.originalName,
    'year': candidate.year,
    'overview': candidate.overview,
    'manual': manual,
    'episodes': [
      for (final e in episodes)
        {'season': e.season, 'number': e.number, 'name': e.name},
    ],
  };
  static CatalogResolvedMatch fromJson(Map<String, dynamic> data) =>
      CatalogResolvedMatch(
        CatalogMetadataCandidate(
          providerId: data['id'] as String,
          name: data['name'] as String,
          originalName: data['originalName'] as String?,
          year: data['year'] as int?,
          overview: data['overview'] as String?,
        ),
        [
          for (final item in data['episodes'] as List<dynamic>)
            CatalogEpisodeMetadata(
              season: (item as Map<String, dynamic>)['season'] as int,
              number: item['number'] as int,
              name: item['name'] as String,
            ),
        ],
        manual: data['manual'] == true,
      );
}

class CatalogMatcher extends ChangeNotifier {
  CatalogMatcher({CatalogMetadataSource? source}) {
    _source = source;
  }
  CatalogMetadataSource? _source;
  final matches = <String, CatalogResolvedMatch>{};
  final candidates = <String, List<CatalogMetadataCandidate>>{};
  final failures = <String, String>{};
  final _attempted = <String>{};
  final localOnly = <String>{};
  final _keyRevisions = <String, int>{};
  Completer<void>? _idle;
  Future<void> get idle => _idle?.future ?? Future<void>.value();
  List<CatalogTitle> _queued = const [];
  String _queuedScope = '';
  bool _running = false, _disposed = false;
  int _generation = 0;
  int _presentationRevision = 0;
  int get presentationRevision => _presentationRevision;
  bool get enabled => _source != null;
  CatalogArtworkSource? get artworkSource =>
      _source is CatalogArtworkSource ? _source as CatalogArtworkSource : null;
  bool get busy => _running;
  String key(String scope, CatalogTitle title) => jsonEncode([scope, title.id]);

  void _notifyPresentationChanged() {
    _presentationRevision++;
    if (!_disposed) notifyListeners();
  }

  CatalogMatchingSnapshot snapshot() => CatalogMatchingSnapshot(
    matches: Map<String, CatalogResolvedMatch>.unmodifiable(matches),
    candidateKeys: Set<String>.unmodifiable(candidates.keys),
    failures: Map<String, String>.unmodifiable(failures),
  );

  void configure(CatalogMetadataSource? source) {
    _generation++;
    _source?.dispose();
    _source = source;
    _attempted.clear();
    candidates.clear();
    failures.clear();
    _notifyPresentationChanged();
  }

  Map<String, Object?> toJson() => {
    for (final e in matches.entries) e.key: e.value.toJson(),
  };
  void restore(Map<String, dynamic> data) {
    for (final e in data.entries) {
      try {
        final match = CatalogResolvedMatch.fromJson(
          e.value as Map<String, dynamic>,
        );
        final candidate = match.candidate;
        if (candidate.providerId.isEmpty ||
            candidate.name.trim().isEmpty ||
            (candidate.year != null &&
                (candidate.year! < 1000 || candidate.year! > 9999))) {
          continue;
        }
        final keys = <String>{};
        if (match.episodes.any(
          (episode) =>
              episode.season < 0 ||
              episode.number < 1 ||
              episode.name.trim().isEmpty ||
              !keys.add('${episode.season}:${episode.number}'),
        )) {
          continue;
        }
        matches[e.key] = match;
      } on Object {
        // A damaged cache entry cannot prevent local playback.
      }
    }
    _presentationRevision++;
  }

  Future<void> enrich(List<CatalogTitle> titles, String scope) async {
    if (_disposed || !enabled) return;
    _queued = scope == _queuedScope
        ? {
            for (final t in _queued) t.id: t,
            for (final t in titles) t.id: t,
          }.values.toList()
        : titles;
    _queuedScope = scope;
    if (_running) return _idle!.future;
    _running = true;
    final completion = Completer<void>();
    _idle = completion;
    notifyListeners();
    try {
      while (_queued.isNotEmpty && !_disposed && enabled) {
        final batch = _queued, batchScope = _queuedScope;
        _queued = const [];
        for (final title in batch) {
          if (_disposed || !enabled) break;
          final cacheKey = key(batchScope, title);
          if (localOnly.contains(cacheKey)) continue;
          final attemptKey = '$cacheKey|${title.seasons.join(',')}';
          if (!_attempted.add(attemptKey)) continue;
          final source = _source!, generation = _generation;
          if (title.first.parsed.warnings.contains('MISSING_SERIES_TITLE') &&
              matches[cacheKey] == null) {
            continue;
          }
          final revision = _keyRevisions[cacheKey] ?? 0;
          bool stale() =>
              _disposed ||
              generation != _generation ||
              revision != (_keyRevisions[cacheKey] ?? 0);
          try {
            var match = matches[cacheKey];
            if (match == null) {
              final found = await source.search(
                title: title.name,
                kind: title.isSeries
                    ? CatalogMediaKind.series
                    : CatalogMediaKind.movie,
                year: title.first.year,
              );
              if (stale()) continue;
              candidates[cacheKey] = found;
              final selected = selectCatalogCandidate(
                title: title.name,
                year: title.first.year,
                candidates: found,
              );
              if (selected == null) {
                _notifyPresentationChanged();
                continue;
              }
              match = CatalogResolvedMatch(selected, const []);
              matches[cacheKey] = match;
              _notifyPresentationChanged();
            }
            final episodes = [...match.episodes];
            if (title.isSeries) {
              for (final season in title.seasons) {
                if (episodes.any((e) => e.season == season)) continue;
                episodes.addAll(
                  await source.episodes(
                    providerId: match.candidate.providerId,
                    season: season,
                  ),
                );
                if (stale()) break;
              }
            }
            if (stale()) continue;
            // Preserve a manual selection made while this request was running.
            if (matches[cacheKey]?.manual == true &&
                matches[cacheKey]?.candidate.providerId !=
                    match.candidate.providerId) {
              continue;
            }
            final resolved = CatalogResolvedMatch(
              match.candidate,
              episodes,
              manual: match.manual || matches[cacheKey]?.manual == true,
            );
            final previous = matches[cacheKey];
            final changed =
                previous == null || !previous.hasSameMetadata(resolved);
            final clearedFailure = failures.remove(cacheKey) != null;
            // Complete cached records should not regroup the entire catalog or
            // rewrite preferences simply because enrichment ran after startup.
            if (changed) matches[cacheKey] = resolved;
            if (changed || clearedFailure) _notifyPresentationChanged();
          } on Object {
            if (stale()) continue;
            failures[cacheKey] =
                'Metadata unavailable. Local files are ready to play.';
            _notifyPresentationChanged();
          }
        }
      }
    } finally {
      _running = false;
      if (!completion.isCompleted) completion.complete();
      _idle = null;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> select(
    CatalogTitle title,
    String scope,
    CatalogMetadataCandidate candidate,
  ) async {
    final cacheKey = key(scope, title);
    _keyRevisions.update(cacheKey, (v) => v + 1, ifAbsent: () => 1);
    localOnly.remove(cacheKey);
    matches[cacheKey] = CatalogResolvedMatch(candidate, const [], manual: true);
    failures.remove(cacheKey);
    _attempted.removeWhere((k) => k.startsWith('$cacheKey|'));
    _notifyPresentationChanged();
    await enrich([title], scope);
  }

  void forget(CatalogTitle title, String scope) {
    for (final id in title.localIds.isEmpty ? [title.id] : title.localIds) {
      final cacheKey = jsonEncode([scope, id]);
      _keyRevisions.update(cacheKey, (v) => v + 1, ifAbsent: () => 1);
      matches.remove(cacheKey);
      candidates.remove(cacheKey);
      failures.remove(cacheKey);
      // A user's local-name preference survives automatic retries.
      localOnly.add(cacheKey);
    }
    _notifyPresentationChanged();
  }

  Future<void> retry(List<CatalogTitle> titles, String scope) {
    _attempted.clear();
    failures.clear();
    _notifyPresentationChanged();
    return enrich(titles, scope);
  }

  Future<void> search(CatalogTitle title, String scope, String query) async {
    if (_disposed || !enabled || query.trim().isEmpty) return;
    final cacheKey = key(scope, title);
    final revision = _keyRevisions.update(
      cacheKey,
      (v) => v + 1,
      ifAbsent: () => 1,
    );
    final generation = _generation;
    try {
      final found = await _source!.search(
        title: query.trim(),
        kind: title.isSeries ? CatalogMediaKind.series : CatalogMediaKind.movie,
      );
      if (_disposed ||
          generation != _generation ||
          revision != _keyRevisions[cacheKey]) {
        return;
      }
      candidates[cacheKey] = found;
      failures.remove(cacheKey);
    } on Object {
      if (_disposed ||
          generation != _generation ||
          revision != _keyRevisions[cacheKey]) {
        return;
      }
      failures[cacheKey] = 'Metadata search is unavailable. Please try again.';
    }
    _notifyPresentationChanged();
  }

  List<CatalogTitle> apply(List<CatalogTitle> local, String scope) =>
      snapshot().apply(local, scope);

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _source?.dispose();
    super.dispose();
  }
}

/// Only transferable model data crosses the catalog worker boundary.
class CatalogMatchingSnapshot {
  const CatalogMatchingSnapshot({
    this.matches = const {},
    this.candidateKeys = const {},
    this.failures = const {},
  });

  final Map<String, CatalogResolvedMatch> matches;
  final Set<String> candidateKeys;
  final Map<String, String> failures;

  String key(String scope, CatalogTitle title) => jsonEncode([scope, title.id]);

  List<CatalogTitle> apply(List<CatalogTitle> local, String scope) {
    final grouped = <String, CatalogTitle>{};
    for (final title in local) {
      final cacheKey = key(scope, title), match = matches[key(scope, title)];
      final videos = match == null
          ? title.videos
          : title.videos
                .map(
                  (v) => title.isSeries
                      ? _identify(
                          v,
                          match.episodes,
                          seriesName: match.candidate.name,
                        )
                      : CatalogVideo.identified(
                          v.file,
                          v.parsed,
                          onlineTitle: match.candidate.name,
                        ),
                )
                .toList();
      final identity = match == null
          ? title.id
          : 'tmdb:${title.isSeries ? 'tv' : 'movie'}:${match.candidate.providerId}';
      final previous = grouped[identity];
      final merged = [...?previous?.videos, ...videos]..sort(_compareVideos);
      final review = merged.any((v) => v.needsReview);
      grouped[identity] = CatalogTitle(
        id: identity,
        name: match?.candidate.name ?? title.name,
        isSeries: title.isSeries,
        videos: merged,
        localIds: [...?previous?.localIds, ...title.localIds],
        providerId: match?.candidate.providerId,
        overview: match?.candidate.overview,
        matchStatus:
            failures[cacheKey] ??
            (match != null
                ? review
                      ? 'TMDB title matched · Episodes need review'
                      : match.manual
                      ? 'TMDB · Confirmed by you'
                      : 'TMDB · Matched'
                : candidateKeys.contains(cacheKey)
                ? 'Review title match'
                : review
                ? 'Local grouping · Episodes need review'
                : 'Local grouping'),
      );
    }
    return grouped.values.toList();
  }

  CatalogVideo _identify(
    CatalogVideo video,
    List<CatalogEpisodeMetadata> episodes, {
    required String seriesName,
  }) {
    CatalogVideo identified({String? name, int? number, String? review}) =>
        CatalogVideo.identified(
          video.file,
          video.parsed,
          onlineSeries: seriesName,
          onlineTitle: name,
          onlineEpisode: number,
          reviewReason: review,
        );
    final season = episodes.where((e) => e.season == video.season).toList();
    if (video.parsed.episodes.any((e) => e.suffix != null)) {
      return identified(
        review: 'Segment letters require an episode-order review.',
      );
    }
    if (video.episode == null) {
      final named = season
          .where(
            (e) =>
                normalizeCatalogMetadataTitle(e.name) ==
                normalizeCatalogMetadataTitle(video.title),
          )
          .toList();
      if (named.length == 1) {
        return identified(name: named.single.name, number: named.single.number);
      }
      return identified();
    }
    final references = video.parsed.episodes;
    final selected = <CatalogEpisodeMetadata>[];
    for (final ref in references) {
      final found = season.where((e) => e.number == ref.number).toList();
      if (found.length != 1) {
        return identified(
          review: 'Local episode numbers are unavailable in this TMDB season.',
        );
      }
      selected.add(found.single);
    }
    if (selected.isEmpty) return identified();
    final name = selected.map((e) => e.name).join(' / ');
    final unnamed = RegExp(
      r'^Episodes?\s+[\d\s+–—-]+$',
      caseSensitive: false,
    ).hasMatch(video.title);
    if (!unnamed &&
        normalizeCatalogMetadataTitle(name) !=
            normalizeCatalogMetadataTitle(video.title)) {
      return identified(
        review:
            'The filename title differs from TMDB. Check the episode order.',
      );
    }
    return identified(name: name);
  }

  int _compareVideos(CatalogVideo a, CatalogVideo b) {
    final season = (a.season ?? 0).compareTo(b.season ?? 0);
    if (season != 0) return season;
    final episode = (a.episode ?? 100000).compareTo(b.episode ?? 100000);
    return episode != 0
        ? episode
        : a.episodeCode.compareTo(b.episodeCode) != 0
        ? a.episodeCode.compareTo(b.episodeCode)
        : a.id.compareTo(b.id);
  }
}
