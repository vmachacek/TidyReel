import 'dart:convert';

import 'package:media_parser/media_parser.dart' as parser;
import 'package:media_platform_storage/media_platform_storage.dart';

import 'catalog_library.dart';
import 'catalog_matching.dart';
import 'catalog_metadata.dart';

enum _OrganizationAction { move, unchanged, review }

/// A proposed change only. Storage operations happen after the user reviews it.
class LibraryOrganizationItem {
  const LibraryOrganizationItem._(
    this.source,
    this.destinationRelativePath,
    this.reason,
    this._action,
    this.videoStorageKey,
  );

  final StorageEntrySnapshot source;
  final String? destinationRelativePath;
  final String? reason;

  /// The original video identity, allowing execution to keep pairs together.
  final String? videoStorageKey;
  final _OrganizationAction _action;

  bool get isMove => _action == _OrganizationAction.move;
  bool get isUnchanged => _action == _OrganizationAction.unchanged;
  bool get needsReview => _action == _OrganizationAction.review;
}

class LibraryOrganizationPlan {
  LibraryOrganizationPlan(Iterable<LibraryOrganizationItem> items)
    : items = List.unmodifiable(items);

  final List<LibraryOrganizationItem> items;
  int get plannedCount => items.where((item) => item.isMove).length;
  int get unchangedCount => items.where((item) => item.isUnchanged).length;
  int get reviewCount => items.where((item) => item.needsReview).length;
}

/// Builds the NormieRename layout using the catalog's verified metadata.
///
/// Uncertain identities and collisions remain at their original paths. No
/// resolution, codec, tracker or release-group tags enter the generated names.
LibraryOrganizationPlan buildLibraryOrganizationPlan({
  required List<CatalogTitle> titles,
  required Map<String, CatalogResolvedMatch> matches,
  required String scope,
  required List<StorageEntrySnapshot> sidecars,
}) {
  final items = <LibraryOrganizationItem>[];
  final videos = <CatalogVideo>[];
  final videoItems = <String, LibraryOrganizationItem>{};
  for (final title in titles) {
    final match = _matchForTitle(title, matches, scope);
    for (final video in title.videos) {
      // Merged catalog groups can reference a physical file more than once.
      if (videoItems.containsKey(video.id)) continue;
      videos.add(video);
      final item = _planVideo(title, video, match);
      items.add(item);
      videoItems[video.id] = item;
    }
  }

  final seenSidecars = <String>{};
  for (final sidecar in sidecars) {
    if (videoItems.containsKey(sidecar.storageKey) ||
        !seenSidecars.add(sidecar.storageKey)) {
      continue;
    }
    final associated = <(CatalogVideo, String)>[];
    for (final video in videos) {
      if (!_sameParent(video.file, sidecar)) continue;
      final suffix = _sidecarSuffix(
        video.file.displayName,
        sidecar.displayName,
      );
      if (suffix != null) associated.add((video, suffix));
    }
    if (associated.length != 1) {
      items.add(
        _review(sidecar, 'The sidecar cannot be paired with one video.'),
      );
      continue;
    }
    final (video, suffix) = associated.single;
    final videoItem = videoItems[video.id]!;
    final destination = videoItem.destinationRelativePath;
    if (videoItem.needsReview || destination == null) {
      items.add(
        _review(
          sidecar,
          'Its associated video needs review.',
          videoStorageKey: video.id,
        ),
      );
      continue;
    }
    items.add(
      _destination(
        sidecar,
        '${_withoutExtension(destination)}$suffix',
        videoStorageKey: video.id,
      ),
    );
  }

  // Include unchanged entries: an already-normalized file also occupies a path.
  final destinations = <String, List<int>>{};
  for (var index = 0; index < items.length; index++) {
    final destination = items[index].destinationRelativePath;
    if (destination != null) {
      destinations.putIfAbsent(destination.toLowerCase(), () => []).add(index);
    }
  }
  for (final collision in destinations.values.where(
    (group) => group.length > 1,
  )) {
    for (final index in collision) {
      items[index] = _review(
        items[index].source,
        'Several files would have the same destination. Choose their versions.',
        videoStorageKey: items[index].videoStorageKey,
      );
    }
  }
  // A sidecar must never move separately from a video blocked by a collision.
  final reviewedVideos = {
    for (final item in items)
      if (item.needsReview && videoItems.containsKey(item.source.storageKey))
        item.source.storageKey,
  };
  for (var index = 0; index < items.length; index++) {
    final item = items[index];
    if (item.needsReview || videoItems.containsKey(item.source.storageKey)) {
      continue;
    }
    if (videos.any(
      (video) =>
          reviewedVideos.contains(video.id) &&
          _sameParent(video.file, item.source) &&
          _sidecarSuffix(video.file.displayName, item.source.displayName) !=
              null,
    )) {
      items[index] = _review(
        item.source,
        'Its associated video needs review.',
        videoStorageKey: item.videoStorageKey,
      );
    }
  }
  return LibraryOrganizationPlan(items);
}

CatalogResolvedMatch? _matchForTitle(
  CatalogTitle title,
  Map<String, CatalogResolvedMatch> matches,
  String scope,
) {
  final found = <CatalogResolvedMatch>[];
  for (final id in {title.id, ...title.localIds}) {
    final match = matches[jsonEncode([scope, id])];
    if (match != null &&
        (title.providerId == null ||
            title.providerId == match.candidate.providerId)) {
      found.add(match);
    }
  }
  if (found.isEmpty ||
      found.any(
        (match) =>
            match.candidate.providerId != found.first.candidate.providerId ||
            match.candidate.year != found.first.candidate.year,
      )) {
    return null;
  }
  final episodes = <String, CatalogEpisodeMetadata>{};
  for (final match in found) {
    for (final episode in match.episodes) {
      final key = '${episode.season}:${episode.number}';
      final previous = episodes[key];
      if (previous != null && previous.name != episode.name) return null;
      episodes[key] = episode;
    }
  }
  return CatalogResolvedMatch(
    found.first.candidate,
    episodes.values.toList(),
    manual: found.any((match) => match.manual),
  );
}

LibraryOrganizationItem _planVideo(
  CatalogTitle title,
  CatalogVideo video,
  CatalogResolvedMatch? match,
) {
  final source = video.file;
  if (match == null) return _review(source, 'Confirm the title match first.');
  if (match.candidate.providerId.isEmpty) {
    return _review(source, 'Confirm the title match first.');
  }
  final year = match.candidate.year;
  if (year == null || year < 1000 || year > 9999) {
    return _review(source, 'The verified release year is missing.');
  }
  if (video.year != null && video.year != year) {
    return _review(source, 'The filename year conflicts with the title match.');
  }
  final extension = _extension(source.displayName);
  if (extension == null || !_videoExtensions.contains(extension)) {
    return _review(source, 'The media container is unsupported.');
  }
  final languages = _languages(source.relativePath);
  final languageTag = languages.isEmpty ? '' : ' [${languages.join('-')}]';
  final localTitle = title.isSeries ? video.parsed.series : video.parsed.title;
  final localized = _localized(localTitle, match.candidate, languages);
  final workTitle = localized
      ? _cleanLocalTitle(localTitle!)
      : match.candidate.name.trim();
  final safeTitle = _sanitizeComponent(workTitle);
  if (safeTitle == null) {
    return _review(source, 'The title cannot form a safe filename.');
  }
  final editionTags = _editionTags(source.relativePath, match.candidate.name);
  if (editionTags.length > 1 ||
      _hasUnknownEdition(source.relativePath, match.candidate.name)) {
    return _review(source, 'Several edition labels need review.');
  }
  final variants = editionTags.isEmpty
      ? ''
      : ' ${editionTags.map((e) => '[$e]').join(' ')}';
  final folder = '$safeTitle ($year)$languageTag';

  if (!title.isSeries) {
    if (video.needsReview) {
      return _review(
        source,
        video.reviewReason ?? 'The filename needs review.',
      );
    }
    return _destination(
      source,
      'Movies/$folder/$safeTitle ($year)$variants.$extension',
    );
  }

  final season = video.season;
  final references = video.parsed.episodes;
  final multi = references.length > 1;
  var number = video.episode;
  if (!multi && number == null && season != null) {
    final named = match.episodes
        .where(
          (episode) =>
              episode.season == season &&
              normalizeCatalogMetadataTitle(episode.name) ==
                  normalizeCatalogMetadataTitle(
                    _cleanLocalTitle(video.parsed.title),
                  ),
        )
        .toList();
    if (named.length == 1) number = named.single.number;
  }
  final invalidWarnings = video.parsed.warnings.where(
    (warning) =>
        !(warning == 'MISSING_EPISODE_NUMBER' && number != null) &&
        !(warning == 'MISSING_SERIES_TITLE' && localized == false),
  );
  if (season == null ||
      season < 0 ||
      references.any((reference) => reference.suffix != null) ||
      invalidWarnings.isNotEmpty) {
    return _review(source, 'The season or episode identity needs review.');
  }
  final seasonCode = season.toString().padLeft(2, '0');
  String episodeCode(int number) => 'E${number.toString().padLeft(2, '0')}';
  String filename;
  if (multi) {
    if (references.any((reference) => reference.number < 1)) {
      return _review(source, 'The episode numbers need review.');
    }
    final contiguous = references.indexed.every(
      (pair) => pair.$2.number == references.first.number + pair.$1,
    );
    filename =
        'S$seasonCode${contiguous ? '${episodeCode(references.first.number)}-${episodeCode(references.last.number)}' : references.map((reference) => episodeCode(reference.number)).join('+')}';
  } else {
    if (number == null || number < 1) {
      return _review(source, 'The episode number is missing.');
    }
    final canonical = match.episodes
        .where(
          (episode) => episode.season == season && episode.number == number,
        )
        .toList();
    if (canonical.length != 1 || canonical.single.name.trim().isEmpty) {
      return _review(source, 'The verified episode title is missing.');
    }
    final localName = _cleanLocalTitle(video.parsed.title);
    final named = _meaningfulEpisodeTitle(localName);
    final localizedEpisode =
        named &&
        (languages.isNotEmpty || RegExp(r'[^\x00-\x7f]').hasMatch(localName));
    if (video.reviewReason != null ||
        (named &&
            !localizedEpisode &&
            normalizeCatalogMetadataTitle(localName) !=
                normalizeCatalogMetadataTitle(canonical.single.name))) {
      return _review(
        source,
        video.reviewReason ??
            'The filename title conflicts with the episode order.',
      );
    }
    final episodeTitle = _sanitizeComponent(
      localizedEpisode ? localName : canonical.single.name,
    );
    if (episodeTitle == null) {
      return _review(source, 'The episode title cannot form a safe filename.');
    }
    filename = 'S$seasonCode${episodeCode(number)} - $episodeTitle';
  }
  return _destination(
    source,
    'TV/$folder/Season $seasonCode/$filename$variants.$extension',
  );
}

const _videoExtensions = {
  'mkv',
  'mp4',
  'm4v',
  'mov',
  'avi',
  'webm',
  'ts',
  'm2ts',
  'mpg',
  'mpeg',
  'wmv',
  'flv',
  'ogv',
};
const _sidecarExtensions = {'srt', 'ass', 'ssa', 'vtt', 'sub', 'idx', 'nfo'};

LibraryOrganizationItem _review(
  StorageEntrySnapshot source,
  String reason, {
  String? videoStorageKey,
}) => LibraryOrganizationItem._(
  source,
  null,
  reason,
  _OrganizationAction.review,
  videoStorageKey,
);

LibraryOrganizationItem _destination(
  StorageEntrySnapshot source,
  String path, {
  String? videoStorageKey,
}) {
  final components = path.split('/');
  if (components.any(
        (component) =>
            component.isEmpty ||
            component == '.' ||
            component == '..' ||
            utf8.encode(component).length > 255,
      ) ||
      path.length > 240) {
    return _review(
      source,
      'The normalized path is too long or unsafe.',
      videoStorageKey: videoStorageKey,
    );
  }
  final unchanged = source.relativePath.replaceAll('\\', '/') == path;
  return LibraryOrganizationItem._(
    source,
    path,
    null,
    unchanged ? _OrganizationAction.unchanged : _OrganizationAction.move,
    videoStorageKey,
  );
}

String? _sanitizeComponent(String value) {
  final sanitized = value
      .replaceAll(RegExp(r'[\\/]'), ' - ')
      .replaceAll(':', ' -')
      .replaceAll('"', "'")
      .replaceAll(RegExp(r'[\x00-\x1f\x7f*?<>|]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceFirst(RegExp(r'[. ]+$'), '');
  if (sanitized.isEmpty || sanitized == '.' || sanitized == '..') return null;
  return RegExp(
        r'^(?:con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)',
        caseSensitive: false,
      ).hasMatch(sanitized)
      ? '_$sanitized'
      : sanitized;
}

String? _extension(String value) {
  final dot = value.lastIndexOf('.');
  return dot < 0 || dot == value.length - 1
      ? null
      : value.substring(dot + 1).toLowerCase();
}

String _withoutExtension(String value) {
  final dot = value.lastIndexOf('.');
  return dot < 0 ? value : value.substring(0, dot);
}

bool _sameParent(StorageEntrySnapshot first, StorageEntrySnapshot second) {
  if (first.parentStorageKey != null && second.parentStorageKey != null) {
    return first.parentStorageKey == second.parentStorageKey;
  }
  String parent(String path) {
    final normalized = path.replaceAll('\\', '/');
    final slash = normalized.lastIndexOf('/');
    return slash < 0 ? '' : normalized.substring(0, slash);
  }

  return parent(first.relativePath) == parent(second.relativePath);
}

String? _sidecarSuffix(String videoName, String sidecarName) {
  final extension = _extension(sidecarName);
  if (!_sidecarExtensions.contains(extension)) return null;
  final videoStem = _withoutExtension(videoName);
  final sidecarStem = _withoutExtension(sidecarName);
  if (!sidecarStem.toLowerCase().startsWith(videoStem.toLowerCase())) {
    return null;
  }
  final suffix = sidecarStem.substring(videoStem.length);
  if (suffix.isEmpty) return '.$extension';
  // Metadata sidecars must have the exact video basename.
  if (extension == 'nfo') return null;
  if (!suffix.startsWith('.')) return null;
  final markers = suffix.substring(1).split('.');
  if (markers.any(
    (marker) => !RegExp(
      r'^(?:forced|sdh|default|cc|[a-z]{2,3}(?:[-_][a-z]{2,4})?)$',
      caseSensitive: false,
    ).hasMatch(marker),
  )) {
    return null;
  }
  return '.${markers.map((marker) => marker.toLowerCase().replaceAll('_', '-')).join('.')}.$extension';
}

List<String> _languages(String path) {
  final languages = <String>{};
  for (final match in RegExp(
    r'(?:^|[\s._\[\]()\\/+-])(CZ|CS|SK)(?=$|[\s._\[\]()\\/+-])',
    caseSensitive: false,
  ).allMatches(path)) {
    languages.add(match.group(1)!.toUpperCase() == 'SK' ? 'SK' : 'CZ');
  }
  return languages.toList()..sort();
}

bool _localized(
  String? local,
  CatalogMetadataCandidate candidate,
  List<String> languages,
) {
  if (local == null || _cleanLocalTitle(local).isEmpty) return false;
  if (languages.isNotEmpty || RegExp(r'[^\x00-\x7f]').hasMatch(local)) {
    return true;
  }
  return candidate.originalName != null &&
      normalizeCatalogMetadataTitle(_cleanLocalTitle(local)) ==
          normalizeCatalogMetadataTitle(candidate.originalName!) &&
      normalizeCatalogMetadataTitle(candidate.originalName!) !=
          normalizeCatalogMetadataTitle(candidate.name);
}

String _cleanLocalTitle(String value) {
  var result = parser
      .cleanMediaTitle(value)
      .replaceAll(
        RegExp(
          r'[\[(]\s*(?:CZ|CS|SK)(?:[- ](?:CZ|CS|SK))*\s*[\])]',
          caseSensitive: false,
        ),
        ' ',
      )
      .replaceAll(
        RegExp(r'\s+(?:CZ|CS|SK)(?:[- ](?:CZ|CS|SK))*$', caseSensitive: false),
        ' ',
      );
  for (final edition in _editionPatterns.entries) {
    result = result.replaceAll(edition.value, ' ');
  }
  return result
      .replaceAll(RegExp(r'\[\s*\]|\(\s*\)'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

final _editionPatterns = <String, RegExp>{
  "Director's Cut": RegExp(
    r"\bdirector['’s]*[ ._-]*cut\b",
    caseSensitive: false,
  ),
  'Extended Edition': RegExp(
    r'\bextended(?:[ ._-]+edition|[ ._-]+cut)?\b',
    caseSensitive: false,
  ),
  'Final Cut': RegExp(r'\bfinal[ ._-]+cut\b', caseSensitive: false),
  'Theatrical Cut': RegExp(
    r'\btheatrical(?:[ ._-]+edition|[ ._-]+cut)\b',
    caseSensitive: false,
  ),
  'Unrated': RegExp(r'\bunrated\b', caseSensitive: false),
  'Special Edition': RegExp(r'\bspecial[ ._-]+edition\b', caseSensitive: false),
  'Remastered': RegExp(r'\bremastered\b', caseSensitive: false),
};

List<String> _editionTags(String path, String canonicalTitle) => [
  for (final edition in _editionPatterns.entries)
    if (edition.value.hasMatch(path) && !edition.value.hasMatch(canonicalTitle))
      edition.key,
];

bool _hasUnknownEdition(String path, String canonicalTitle) {
  var remainder = path
      .replaceAll(RegExp(r'[._]'), ' ')
      .replaceAll(
        RegExp(RegExp.escape(canonicalTitle), caseSensitive: false),
        ' ',
      );
  for (final pattern in _editionPatterns.values) {
    remainder = remainder.replaceAll(pattern, ' ');
  }
  return RegExp(
    r'\b(?:edition|(?:ultimate|alternate|fan)[ ._-]+cut|uncut|imax|open[ ._-]+matte)\b',
    caseSensitive: false,
  ).hasMatch(remainder);
}

bool _meaningfulEpisodeTitle(String value) =>
    value.isNotEmpty &&
    value != 'Unidentified episode' &&
    !RegExp(r'^Episodes?\s+[\d\s+–—-]+$', caseSensitive: false).hasMatch(value);
