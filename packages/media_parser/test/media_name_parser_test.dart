import 'dart:io';

import 'package:media_parser/media_parser.dart';
import 'package:test/test.dart';

ParsedMediaName parse(String path) => parseMediaName(
  fileName: path.replaceAll('\\', '/').split('/').last,
  relativePath: path,
);

void main() {
  test('folder anchors keep nested releases together and inherit show year', () {
    for (final root in ['TV Shows/', '']) {
      for (final release in [
        'Season 05',
        'Spongebob Squarepants Season 5 Complete WEB x264 [i_c]',
      ]) {
        final result = parse(
          '${root}SpongeBob SquarePants (1999)/$release/Release One/S05E09 - The Krusty Sponge.mkv',
        );
        expect(result.series, 'SpongeBob SquarePants (1999)');
        expect(result.year, 1999);
        expect(result.season, 5);
        expect(result.episode, 9);
        expect(result.title, 'The Krusty Sponge');
      }
    }
  });

  test('explicit filename titles group without a series folder', () {
    final result = parse('Shows/My_Show_S01E02_Visit.mp4');
    expect(result.series, 'My Show');
    expect(result.title, 'Visit');
    expect(result.season, 1);
    expect(result.episode, 2);
    expect(result.needsReview, isFalse);
  });

  test('chains and ranges preserve every physical-file episode reference', () {
    final cases = <String, List<int>>{
      'S02E07E08': [7, 8],
      'S01E01E02E03': [1, 2, 3],
      'S01E01-E03': [1, 2, 3],
      'S01E01-03': [1, 2, 3],
      'S01E01 to E03': [1, 2, 3],
      'S01E01+E03': [1, 3],
      'S01E01 E02': [1, 2],
    };
    for (final entry in cases.entries) {
      final result = parse('My Show/${entry.key} - Special.mp4');
      expect(
        result.episodes.map((ref) => ref.number),
        entry.value,
        reason: entry.key,
      );
      expect(result.title, 'Special');
    }
    expect(parse('Show.S01E01+E03.mkv').endEpisode, isNull);
    expect(parse('Show.S01E01-E03.mkv').endEpisode, 3);
  });

  test('invalid or huge ranges stay bounded and require review', () {
    for (final code in ['S01E09-E03', 'S01E01-E9999']) {
      final result = parse('Show.$code.mkv');
      expect(result.episodes, hasLength(1));
      expect(result.warnings, contains('INVALID_EPISODE_RANGE'));
      expect(result.endEpisode, isNull);
    }
  });

  test('letter suffixes stay distinct and never leak into display titles', () {
    final base = parse('Shows/Show/Season 6/S06E11 The Big One.mkv');
    final a = parse('Shows/Show/Season 6/S06E11a The Big One.mkv');
    final b = parse('Shows/Show/Season 6/S06E11B The Big One.mkv');
    expect(base.episodes.first.suffix, isNull);
    expect(a.episodes.first.suffix, 'a');
    expect(b.episodes.first.suffix, 'b');
    expect(a.episodes.first, isNot(b.episodes.first));
    expect(b.title, 'The Big One');
    expect(b.warnings, contains('NON_STANDARD_EPISODE_SUFFIX'));
  });

  test('large episode numbers and season zero remain valid local claims', () {
    expect(parse('Show.S123E1001.mkv').season, 123);
    expect(parse('Show.S123E1001.mkv').episode, 1001);
    expect(parse('Show.S00E01.Special.mkv').season, 0);
  });

  test('alternate numbering keeps localized title evidence', () {
    final result = parse('Prasiatko Peppa/S01 DVDRIP/1x07 Maminka pracuje.mkv');
    expect(result.series, 'Prasiatko Peppa');
    expect(result.season, 1);
    expect(result.episode, 7);
    expect(result.title, 'Maminka pracuje');
    expect(parse('Show.02x044.Title.mkv').episode, 44);
  });

  test('natural language recognizes Unicode separators and channel noise', () {
    final result = parse(
      'Ben and Holly’s Little Kingdom ｜ Season 1 ｜ Episode 10｜ Kids Videos.mp4',
    );
    expect(result.series, "Ben and Holly's Little Kingdom");
    expect(result.season, 1);
    expect(result.episode, 10);
    expect(result.title, 'Episode 10');
    expect(parse('Show Season 2 - Ep 8 - The Visit.mp4').episode, 8);
  });

  test('title-only natural episode retains title without inventing a number', () {
    final result = parse(
      "Ben and Holly's Little Kingdom ｜ Hard Times ｜ Full Episode Season 2.mp4",
    );
    expect(result.series, "Ben and Holly's Little Kingdom");
    expect(result.season, 2);
    expect(result.episode, isNull);
    expect(result.title, 'Hard Times');
    expect(result.needsReview, isTrue);
  });

  test('season folders enable episode-only and leading-number filenames', () {
    expect(parse('Shows/My Show/Season 2/E07 - Home.mp4').episode, 7);
    expect(parse('My Show/Season 2/07 - Home.mp4').episode, 7);
    final unknown = parse('My Show/Season 2/Hard Times.mp4');
    expect(unknown.series, 'My Show');
    expect(unknown.season, 2);
    expect(unknown.episode, isNull);
    expect(unknown.title, 'Hard Times');
    expect(parse('E07 - Home.mp4').series, isNull);
    expect(parse('07 - Home.mp4').series, isNull);
    expect(parse('Season 2/07 - Home.mp4').episode, isNull);
  });

  test('a title folder alone does not classify a movie as a TV episode', () {
    final result = parse(
      'TV Shows/My Show (1999)/The SpongeBob SquarePants Movie.mkv',
    );
    expect(result.series, isNull);
    expect(result.season, isNull);
  });

  test('folder and filename season disagreements remain visible', () {
    final result = parse('Show/Season 2/S01E04 - Visit.mkv');
    expect(result.season, 1);
    expect(result.warnings, contains('CONFLICTING_FOLDER_AND_FILENAME'));
  });

  test('release cleanup preserves localized spelling and title numbers', () {
    expect(
      cleanMediaTitle('Astro.Kid.2019.1080p.BluRay.x264-[YTS.MX]'),
      'Astro Kid',
    );
    expect(parse('Astro.Kid.2019.1080p.BluRay.mp4').year, 2019);
    expect(cleanMediaTitle('Arrival (2016)'), 'Arrival');
    expect(cleanMediaTitle('Zootopia (2016) (2160p BluRay x265)'), 'Zootopia');
    expect(cleanMediaTitle('My...Show'), 'My Show');
    expect(parse('Movie 2020 1080p BluRay.mp4').year, 2020);
    expect(
      cleanMediaTitle('2001: A Space Odyssey (1968)'),
      '2001: A Space Odyssey',
    );
    expect(cleanMediaTitle('Apollo 13'), 'Apollo 13');
    expect(cleanMediaTitle('Karen 2.0'), 'Karen 2.0');
    expect(cleanMediaTitle('Krabs à la Mode'), 'Krabs à la Mode');
    expect(normalizedMediaTitle('My.Show (1999) [1080p]'), 'my show');
    expect(
      normalizedMediaTitle("Holly’s Kingdom"),
      normalizedMediaTitle("Holly's Kingdom"),
    );
    expect(parse('Show.S01E02.1080p.mkv').endEpisode, isNull);
    expect(parse('1080p 2020 07.mkv').series, isNull);
  });

  test('ambiguous special text does not invent season or episode numbers', () {
    final result = parse('Show Special 5-0.mkv');
    expect(result.season, isNull);
    expect(result.episode, isNull);
    expect(result.warnings, contains('AMBIGUOUS_SPECIAL'));
  });

  test('real SpongeBob listing keeps all files under one series and year', () {
    final lines = File('test/fixtures/spongebob-file-list-2026-10-07.txt')
        .readAsLinesSync()
        .where((line) => line.trim().isNotEmpty)
        .toList();
    expect(lines, hasLength(268));
    final results = lines.map(parse).toList();
    expect(results.map((result) => result.series).toSet(), {
      'SpongeBob SquarePants (1999)',
    });
    expect(results.map((result) => result.year).toSet(), {1999});
    expect(results.where((result) => result.episode != null), hasLength(267));
    final special = results.singleWhere((result) => result.episode == null);
    expect(special.season, 5);
    expect(
      special.title,
      'SpongeBob SquarePants Special 5-0 Atlantis Squarepantis',
    );
    expect(special.warnings, contains('AMBIGUOUS_SPECIAL'));
    expect(
      results.where((result) => result.episodes.length > 1),
      hasLength(56),
    );
    expect(
      results.where(
        (result) => result.warnings.contains('NON_STANDARD_EPISODE_SUFFIX'),
      ),
      hasLength(2),
    );
    expect(results.map((result) => result.season).toSet(), {
      1,
      2,
      3,
      4,
      5,
      6,
      7,
      8,
      9,
    });
  });
}
