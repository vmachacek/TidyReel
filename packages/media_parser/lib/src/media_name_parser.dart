/// One local episode claim. Suffixes remain distinct until metadata resolves them.
final class ParsedEpisodeReference {
  const ParsedEpisodeReference({required this.number, this.suffix});

  final int number;
  final String? suffix;

  @override
  bool operator ==(Object other) =>
      other is ParsedEpisodeReference &&
      other.number == number &&
      other.suffix == suffix;

  @override
  int get hashCode => Object.hash(number, suffix);
}

/// Local evidence only; this does not claim a canonical provider match.
final class ParsedMediaName {
  ParsedMediaName({
    required this.title,
    this.series,
    this.season,
    this.episode,
    this.endEpisode,
    this.year,
    List<ParsedEpisodeReference> episodes = const [],
    List<String> warnings = const [],
    List<String> evidence = const [],
  }) : episodes = List.unmodifiable(episodes),
       warnings = List.unmodifiable(warnings),
       evidence = List.unmodifiable(evidence);

  final String title;
  final String? series;
  final int? season;
  final int? episode;
  final int? endEpisode;
  final int? year;
  final List<ParsedEpisodeReference> episodes;
  final List<String> warnings;
  final List<String> evidence;

  bool get needsReview => warnings.isNotEmpty;
}

final _explicitEpisode = RegExp(
  r'(?:^|[\s._\-|])S(\d{1,3})[ ._-]*E(\d{1,4})(?!\d)',
  caseSensitive: false,
);
final _alternateEpisode = RegExp(
  r'(?:^|[\s._\-|])(\d{1,3})x(\d{1,4})(?!\d)',
  caseSensitive: false,
);
final _naturalEpisode = RegExp(
  r'\b(?:season|series)[ ._-]*(\d{1,3})[\s._\-|]*(?:episode|ep)[ ._-]*(\d{1,4})(?!\d)',
  caseSensitive: false,
);
final _seasonMarker = RegExp(
  r'(?:^|[\s._\-|])(?:season|series)[ ._-]*(\d{1,3})(?!\d)|(?:^|[\s._\-|])S(\d{1,3})(?![\da-z])',
  caseSensitive: false,
);
final _episodeOnly = RegExp(
  r'(?:^|[\s._\-|])(?:episode|ep|E)[ ._-]*(\d{1,4})(?!\d)',
  caseSensitive: false,
);
final _leadingNumber = RegExp(r'^\s*(\d{1,3})\s*(?:[-–]|[._])\s*');
final _releaseStart = RegExp(
  r'\b(?:480[pi]|576[pi]|720[pi]|1080[pi]|1440p|2160p|4k|uhd|web[- ]?dl|webrip|bluray|b[dr]rip|dvdrip|tvrip|hdtv|remux|x26[45]|h[ .]?26[45]|hevc|avc|av1|vp9|8bit|10bit|hdr10\+?|hdr|dolby[ .]vision|eac3|ac3|ddp(?:\d)?|dts|truehd|aac(?:\d)?|atmos)\b',
  caseSensitive: false,
);
final _releaseBracket = RegExp(
  r'\[[^\]]*(?:yts|yify|eztv|i_c|tigole|rcvr|garshasp|aglet|lazy|\d{3,4}p|bluray|web|x26[45]|hevc)[^\]]*\]',
  caseSensitive: false,
);
final _naturalTail = RegExp(
  r'(?:\s*[-|]\s*)?(?:full[ .]episode|kids[ .]videos|full[ .]episodes?|official[ .]video)\b.*',
  caseSensitive: false,
);

/// Parses structural TV markers before discarding release noise.
ParsedMediaName parseMediaName({
  required String fileName,
  required String relativePath,
}) {
  final stem = _normalizeSeparators(
    fileName.replaceFirst(
      RegExp(r'\.[a-z0-9]{1,8}$', caseSensitive: false),
      '',
    ),
  );
  final directories = relativePath
      .replaceAll('\\', '/')
      .split('/')
      .where((part) => part.isNotEmpty)
      .toList();
  if (directories.isNotEmpty) directories.removeLast();
  final context = _folderContext(directories);
  final warnings = <String>[];
  final evidence = <String>[];
  _EpisodeClaim? claim;

  final explicit = _explicitEpisode.firstMatch(stem);
  final alternate = _alternateEpisode.firstMatch(stem);
  final natural = _naturalEpisode.firstMatch(stem);
  if (explicit != null && _validEpisodeEnding(stem, explicit.end)) {
    claim = _readEpisodeClaim(stem, explicit, warnings, 'EXPLICIT_SXXEXX');
  } else if (alternate != null && _validEpisodeEnding(stem, alternate.end)) {
    claim = _readEpisodeClaim(stem, alternate, warnings, 'EXPLICIT_NXNN');
  } else if (natural != null && _validEpisodeEnding(stem, natural.end)) {
    claim = _readEpisodeClaim(
      stem,
      natural,
      warnings,
      'EXPLICIT_NATURAL_LANGUAGE_EPISODE',
    );
  } else if (context.season != null) {
    final episodeOnly = _episodeOnly.firstMatch(stem);
    if (episodeOnly != null && _validEpisodeEnding(stem, episodeOnly.end)) {
      claim = _readInheritedClaim(stem, episodeOnly, context.season!, warnings);
    } else if (context.series != null) {
      // A leading number is episode evidence only below an identified show/season.
      final numbered = _leadingNumber.firstMatch(stem);
      if (numbered != null) {
        claim = _EpisodeClaim(
          season: context.season!,
          episodes: [
            ParsedEpisodeReference(number: int.parse(numbered.group(1)!)),
          ],
          start: numbered.start,
          end: numbered.end,
          reason: 'SEASON_FROM_PARENT_FOLDER',
        );
      }
    }
  }

  if (claim != null) {
    evidence.add(claim.reason);
    if (claim.episodes.length > 1) {
      evidence.add(
        claim.expandedRange
            ? 'EXPLICIT_EPISODE_RANGE'
            : 'EXPLICIT_CHAINED_EPISODES',
      );
    }
    if (context.season != null && context.season != claim.season) {
      warnings.add('CONFLICTING_FOLDER_AND_FILENAME');
    }
    final prefix = _seriesIdentity(stem.substring(0, claim.start));
    final series =
        context.series ??
        (prefix.isEmpty ? _fallbackSeriesFolder(directories) : prefix);
    evidence.add(
      context.series != null
          ? 'TITLE_FROM_PARENT_FOLDER'
          : 'TITLE_FROM_FILENAME',
    );
    if (series == null) warnings.add('MISSING_SERIES_TITLE');
    final year = _yearFrom(prefix) ?? context.year;
    if (year != null) {
      evidence.add(
        _yearFrom(prefix) != null
            ? 'YEAR_FROM_FILENAME'
            : 'YEAR_FROM_PARENT_FOLDER',
      );
    }
    final title = cleanMediaTitle(stem.substring(claim.end));
    final first = claim.episodes.first.number;
    final contiguous =
        claim.episodes.every((ref) => ref.suffix == null) &&
        List.generate(
          claim.episodes.length,
          (index) => first + index,
        ).indexed.every((pair) => claim!.episodes[pair.$1].number == pair.$2);
    return ParsedMediaName(
      title: title.isEmpty ? 'Episode $first' : title,
      series: series ?? 'TV Shows',
      season: claim.season,
      episode: first,
      endEpisode: contiguous && claim.episodes.length > 1
          ? claim.episodes.last.number
          : null,
      year: year,
      episodes: claim.episodes,
      warnings: warnings,
      evidence: evidence,
    );
  }

  // A season folder, or a title-only natural-language episode, is useful partial
  // TV evidence. A title folder alone must not turn a movie into an episode.
  final localSeason = _seasonMarker.firstMatch(stem);
  final season = context.season ?? _seasonNumber(localSeason);
  if (season != null) {
    var series = context.series;
    var titleText = stem;
    if (series == null && localSeason != null) {
      final beforeSeason = stem.substring(0, localSeason.start);
      final pipe = beforeSeason.indexOf('|');
      if (pipe >= 0) {
        series = _seriesIdentity(beforeSeason.substring(0, pipe));
        titleText = beforeSeason.substring(pipe + 1);
      } else {
        series = _seriesIdentity(beforeSeason);
        titleText = '';
      }
    }
    if (series != null && series.isNotEmpty) {
      warnings.add('MISSING_EPISODE_NUMBER');
      if (RegExp(r'\bspecial\b', caseSensitive: false).hasMatch(stem)) {
        warnings.add('AMBIGUOUS_SPECIAL');
      }
      evidence.add('SEASON_FROM_PARENT_FOLDER');
      return ParsedMediaName(
        title: cleanMediaTitle(titleText).isEmpty
            ? 'Unidentified episode'
            : cleanMediaTitle(titleText),
        series: series,
        season: season,
        year: _yearFrom(series) ?? context.year,
        warnings: warnings,
        evidence: evidence,
      );
    }
  }
  if (RegExp(r'\bspecial\b', caseSensitive: false).hasMatch(stem)) {
    warnings.add('AMBIGUOUS_SPECIAL');
    evidence.add('SPECIAL_TEXT_PRESENT');
  }
  final year = _yearFrom(stem);
  if (year != null) evidence.add('YEAR_FROM_FILENAME');
  evidence.add('TITLE_FROM_FILENAME');
  return ParsedMediaName(
    title: cleanMediaTitle(stem),
    year: year,
    warnings: warnings,
    evidence: evidence,
  );
}

/// Display text retains localized spelling and meaningful title numerals.
String cleanMediaTitle(String value) => _cleanTitle(value, keepYear: false);

/// A comparison key, without release noise or year (the year is a separate key).
String normalizedMediaTitle(String value) =>
    cleanMediaTitle(value)
        .toLowerCase()
        .replaceAll(RegExp(r"['’‘`´]"), '')
        .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

bool isSeasonFolder(String folder) =>
    _seasonMarker.hasMatch(_normalizeSeparators(folder));

bool isSeriesContainer(String folder) => RegExp(
  r'^(?:tv[ ._-]*shows?|television|shows?|series)$',
  caseSensitive: false,
).hasMatch(folder.trim());

String _normalizeSeparators(String value) => value
    .replaceAll('｜', '|')
    .replaceAll('Ｘ', 'X')
    .replaceAll('ｘ', 'x')
    .replaceAll('’', "'")
    .replaceAll('‘', "'")
    .replaceAll('\u00a0', ' ')
    .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ');

String _cleanTitle(String value, {required bool keepYear}) {
  var text = _normalizeSeparators(value).replaceAll(_releaseBracket, ' ');
  final release = _releaseStart.firstMatch(text);
  if (release != null) {
    text = text
        .substring(0, release.start)
        .replaceAll(RegExp(r'[\s(\[]+$'), '');
  }
  text = text.replaceFirst(_naturalTail, '');
  if (!keepYear) {
    text = text.replaceAll(RegExp(r'\s*\((?:19|20)\d{2}\)'), ' ');
    final year = _plainYear(text);
    if (year != null) text = text.replaceRange(year.start, year.end, ' ');
  }
  // Keep decimal numbers such as Karen 2.0; dots separating words are release
  // separators, while punctuation inside a numeric title can be meaningful.
  text = text.replaceAll(RegExp(r'(?<!\d)\.|\.(?!\d)'), ' ');
  return text
      .replaceAll('_', ' ')
      .replaceAll('|', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'^[\s.\-–]+|[\s.\-–]+$'), '')
      .trim();
}

String _seriesIdentity(String value) {
  var text = _normalizeSeparators(value);
  final marker = _seasonMarker.firstMatch(text);
  if (marker != null) text = text.substring(0, marker.start);
  return _cleanTitle(text, keepYear: true)
      .replaceFirst(RegExp(r'\s*[- ]?\bcomplete\b.*', caseSensitive: false), '')
      .trim();
}

RegExpMatch? _plainYear(String value) {
  // Bare numeric titles and a title's leading numeral are not release years.
  final matches = RegExp(r'(?<!\d)(?:19|20)\d{2}(?!\d)').allMatches(value);
  for (final match in matches.toList().reversed) {
    final before = value.substring(0, match.start);
    final after = value.substring(match.end).trim();
    if (RegExp(
          r'[a-z\p{L}]',
          caseSensitive: false,
          unicode: true,
        ).hasMatch(before) &&
        (after.isEmpty || RegExp(r'^[\s._\-\[()]').hasMatch(after))) {
      return match;
    }
  }
  return null;
}

int? _yearFrom(String value) {
  final bracketed = RegExp(r'\(((?:19|20)\d{2})\)').firstMatch(value);
  if (bracketed != null) return int.parse(bracketed.group(1)!);
  final release = _releaseStart.firstMatch(value);
  final stripped = release == null ? value : value.substring(0, release.start);
  final plain = _plainYear(stripped);
  return plain == null ? null : int.parse(plain.group(0)!);
}

int? _seasonNumber(RegExpMatch? match) =>
    match == null ? null : int.parse(match.group(1) ?? match.group(2)!);

_FolderContext _folderContext(List<String> directories) {
  final normalized = directories.map(_normalizeSeparators).toList();
  final seasonIndex = normalized.indexWhere(isSeasonFolder);
  int? season;
  for (final folder in normalized.reversed) {
    season ??= _seasonNumber(_seasonMarker.firstMatch(folder));
  }
  String? series;
  final container = normalized.lastIndexWhere(isSeriesContainer);
  if (container >= 0 && container + 1 < normalized.length) {
    final identity = _seriesIdentity(normalized[container + 1]);
    if (identity.isNotEmpty) series = identity;
  }
  if (series == null && seasonIndex > 0) {
    final candidate = normalized[seasonIndex - 1];
    if (!isSeriesContainer(candidate)) {
      final identity = _seriesIdentity(candidate);
      if (identity.isNotEmpty) series = identity;
    }
  }
  if (series == null && seasonIndex >= 0) {
    final identity = _seriesIdentity(normalized[seasonIndex]);
    if (identity.isNotEmpty) series = identity;
  }
  return _FolderContext(
    series,
    season,
    series == null ? null : _yearFrom(series),
  );
}

String? _fallbackSeriesFolder(List<String> directories) {
  for (final folder in directories.reversed) {
    if (isSeriesContainer(folder) ||
        RegExp(
          r'^(?:movies?|collection|storage|media(?:-kids)?)$',
          caseSensitive: false,
        ).hasMatch(folder)) {
      continue;
    }
    final identity = _seriesIdentity(folder);
    if (identity.isNotEmpty) return identity;
  }
  return null;
}

bool _validEpisodeEnding(String stem, int end) {
  if (end == stem.length) return true;
  final tail = stem.substring(end);
  if (RegExp(r'^[eE]\d').hasMatch(tail)) return true;
  if (RegExp(r'^[a-z](?=$|[^a-z0-9])', caseSensitive: false).hasMatch(tail)) {
    return true;
  }
  return !RegExp(r'^[a-z0-9]', caseSensitive: false).hasMatch(tail);
}

_EpisodeClaim _readEpisodeClaim(
  String stem,
  RegExpMatch match,
  List<String> warnings,
  String reason,
) => _readSequence(
  stem: stem,
  season: int.parse(match.group(1)!),
  firstNumber: int.parse(match.group(2)!),
  start: match.start,
  end: match.end,
  warnings: warnings,
  reason: reason,
);

_EpisodeClaim _readInheritedClaim(
  String stem,
  RegExpMatch match,
  int season,
  List<String> warnings,
) => _readSequence(
  stem: stem,
  season: season,
  firstNumber: int.parse(match.group(1)!),
  start: match.start,
  end: match.end,
  warnings: warnings,
  reason: 'SEASON_FROM_PARENT_FOLDER',
);

_EpisodeClaim _readSequence({
  required String stem,
  required int season,
  required int firstNumber,
  required int start,
  required int end,
  required List<String> warnings,
  required String reason,
}) {
  var cursor = end;
  String? suffix;
  final suffixMatch = RegExp(
    r'^[a-z](?=$|[^a-z0-9])',
    caseSensitive: false,
  ).firstMatch(stem.substring(cursor));
  if (suffixMatch != null) {
    suffix = suffixMatch.group(0)!.toLowerCase();
    cursor += suffixMatch.end;
    warnings.add('NON_STANDARD_EPISODE_SUFFIX');
  }
  final episodes = [
    ParsedEpisodeReference(number: firstNumber, suffix: suffix),
  ];
  var expandedRange = false;
  while (cursor < stem.length) {
    final tail = stem.substring(cursor);
    final range = RegExp(
      r'^[ ._]*(?:[-–]|to\s+)\s*E?(\d{1,4})(?!\d)(?=$|[^a-z0-9])',
      caseSensitive: false,
    ).firstMatch(tail);
    if (range != null) {
      final last = int.parse(range.group(1)!);
      final first = episodes.last.number;
      cursor += range.end;
      if (suffix != null || last < first || last - first > 200) {
        warnings.add('INVALID_EPISODE_RANGE');
      } else {
        for (var number = first + 1; number <= last; number++) {
          episodes.add(ParsedEpisodeReference(number: number));
        }
        expandedRange = last > first;
      }
      continue;
    }
    final chained = RegExp(
      r'^[ ._+]*E(\d{1,4})(?!\d)(?=$|[^a-z0-9]|E\d)',
      caseSensitive: false,
    ).firstMatch(tail);
    if (chained == null) break;
    final number = int.parse(chained.group(1)!);
    if (!episodes.any((ref) => ref.number == number && ref.suffix == null)) {
      episodes.add(ParsedEpisodeReference(number: number));
    }
    cursor += chained.end;
  }
  return _EpisodeClaim(
    season: season,
    episodes: episodes,
    start: start,
    end: cursor,
    reason: reason,
    expandedRange: expandedRange,
  );
}

final class _EpisodeClaim {
  const _EpisodeClaim({
    required this.season,
    required this.episodes,
    required this.start,
    required this.end,
    required this.reason,
    this.expandedRange = false,
  });

  final int season;
  final List<ParsedEpisodeReference> episodes;
  final int start;
  final int end;
  final String reason;
  final bool expandedRange;
}

final class _FolderContext {
  const _FolderContext(this.series, this.season, this.year);

  final String? series;
  final int? season;
  final int? year;
}
