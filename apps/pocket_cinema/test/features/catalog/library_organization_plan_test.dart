import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_platform_storage/media_platform_storage.dart';
import 'package:pocket_cinema/features/catalog/catalog_library.dart';
import 'package:pocket_cinema/features/catalog/catalog_matching.dart';
import 'package:pocket_cinema/features/catalog/catalog_metadata.dart';
import 'package:pocket_cinema/features/catalog/library_organization_plan.dart';

import 'catalog_library_test.dart' as fixture;

const show = CatalogMetadataCandidate(
  providerId: '7',
  name: 'My Show',
  year: 1999,
);
const film = CatalogMetadataCandidate(
  providerId: '8',
  name: 'My Film',
  year: 2020,
);
const pilot = CatalogEpisodeMetadata(season: 1, number: 1, name: 'Pilot');

LibraryOrganizationPlan plan(
  List<String> paths, {
  CatalogMetadataCandidate? candidate = show,
  List<CatalogEpisodeMetadata> episodes = const [pilot],
  List<String> sidecars = const [],
}) {
  final titles = groupCatalog(paths.map(fixture.file).toList());
  return buildLibraryOrganizationPlan(
    titles: titles,
    matches: {
      if (candidate != null)
        for (final title in titles)
          jsonEncode(['root', title.id]): CatalogResolvedMatch(
            candidate,
            episodes,
          ),
    },
    scope: 'root',
    sidecars: sidecars.map(fixture.file).toList(),
  );
}

void main() {
  test('moves TV to canonical season directories and removes release junk', () {
    final result = plan([
      'Downloads/My.Show.S01E01.Pilot.1080p.WEB-DL.x264-GROUP.MKV',
    ]);
    expect(
      result.items.single.destinationRelativePath,
      'TV/My Show (1999)/Season 01/S01E01 - Pilot.mkv',
    );
    expect(result.plannedCount, 1);
    expect(result.unchangedCount, 0);
    expect(result.reviewCount, 0);
  });

  test('puts movies in title and release year folders', () {
    final result = plan([
      'TV Shows/My.Film.2020.2160p.YIFY.MP4',
    ], candidate: film);
    expect(
      result.items.single.destinationRelativePath,
      'Movies/My Film (2020)/My Film (2020).mp4',
    );
  });

  test('already normalized paths are unchanged', () {
    final result = plan(['TV/My Show (1999)/Season 01/S01E01 - Pilot.mkv']);
    expect(result.items.single.isUnchanged, isTrue);
    expect(result.plannedCount, 0);
    expect(result.unchangedCount, 1);
  });

  test('requires a verified title and year', () {
    expect(
      plan([
        'My.Show.S01E01.Pilot.mkv',
      ], candidate: null).items.single.needsReview,
      isTrue,
    );
    expect(
      plan(
        ['My.Show.S01E01.Pilot.mkv'],
        candidate: const CatalogMetadataCandidate(
          providerId: '7',
          name: 'My Show',
        ),
      ).items.single.needsReview,
      isTrue,
    );
  });

  test('a mismatched local year remains in review', () {
    final result = plan(['My.Show.2005.S01E01.Pilot.mkv']);
    expect(result.items.single.needsReview, isTrue);
    expect(result.items.single.reason, contains('year conflicts'));
  });

  test('single episodes need a canonical title and agreeing local title', () {
    expect(
      plan(['My.Show.S01E01.mkv'], episodes: []).items.single.needsReview,
      isTrue,
    );
    expect(
      plan(['My.Show.S01E01.Wrong.Order.mkv']).items.single.needsReview,
      isTrue,
    );
    expect(
      plan(['My.Show.S01E01.mkv']).items.single.destinationRelativePath,
      'TV/My Show (1999)/Season 01/S01E01 - Pilot.mkv',
    );
  });

  test('resolves a unique title-only episode in the verified season', () {
    final result = plan(['My Show/Season 1/Pilot.mkv']);
    expect(
      result.items.single.destinationRelativePath,
      'TV/My Show (1999)/Season 01/S01E01 - Pilot.mkv',
    );
    final ambiguous = plan(
      ['My Show/Season 1/Pilot.mkv'],
      episodes: [
        pilot,
        const CatalogEpisodeMetadata(season: 1, number: 2, name: 'Pilot'),
      ],
    );
    expect(ambiguous.items.single.needsReview, isTrue);
  });

  test('explicit multi-episode chains never require episode titles', () {
    final result = plan([
      'My.Show.S01E01E02E03.1080p.WEB-DL.mkv',
      'My.Show.S01E04+E06.Two.Titles.mp4',
    ], episodes: []);
    expect(result.items.map((item) => item.destinationRelativePath), [
      'TV/My Show (1999)/Season 01/S01E01-E03.mkv',
      'TV/My Show (1999)/Season 01/S01E04+E06.mp4',
    ]);
  });

  test('segment letters and conflicting season evidence remain in review', () {
    expect(
      plan(['My.Show.S01E01b.Pilot.mkv']).items.single.needsReview,
      isTrue,
    );
    expect(
      plan(['My Show/Season 1/S02E01.Pilot.mkv']).items.single.needsReview,
      isTrue,
    );
    expect(plan(['My.Show.S01E03-E01.mkv']).items.single.needsReview, isTrue);
  });

  test('preserves specials and episode numbers greater than 99', () {
    final result = plan(
      ['My.Show.S00E101.Pilot.mkv'],
      episodes: const [
        CatalogEpisodeMetadata(season: 0, number: 101, name: 'Pilot'),
      ],
    );
    expect(
      result.items.single.destinationRelativePath,
      'TV/My Show (1999)/Season 00/S00E101 - Pilot.mkv',
    );
  });

  test('keeps source language and puts language tags on the work folder', () {
    final result = plan(
      ['Prasiatko Peppa [CZ]/Season 1/S01E01 - Cuník.mkv'],
      candidate: const CatalogMetadataCandidate(
        providerId: '9',
        name: 'Peppa Pig',
        year: 2004,
      ),
      episodes: const [
        CatalogEpisodeMetadata(season: 1, number: 1, name: 'Muddy Puddles'),
      ],
    );
    expect(
      result.items.single.destinationRelativePath,
      'TV/Prasiatko Peppa (2004) [CZ]/Season 01/S01E01 - Cuník.mkv',
    );
  });

  test('preserves localized movie titles and multiple explicit languages', () {
    final result = plan(['Neuveriteľní.2020.CZ-SK.1080p.mkv'], candidate: film);
    expect(
      result.items.single.destinationRelativePath,
      'Movies/Neuveriteľní (2020) [CZ-SK]/Neuveriteľní (2020).mkv',
    );
  });

  test('does not guess a source language from accented spelling alone', () {
    final result = plan(
      ['Amélie.2001.mkv'],
      candidate: const CatalogMetadataCandidate(
        providerId: '10',
        name: 'Amelie',
        year: 2001,
      ),
    );
    expect(
      result.items.single.destinationRelativePath,
      'Movies/Amélie (2001)/Amélie (2001).mkv',
    );
  });

  test(
    'preserves explicit editions and reviews contradictory edition labels',
    () {
      final result = plan([
        'My.Film.2020.Directors.Cut.1080p.mkv',
      ], candidate: film);
      expect(
        result.items.single.destinationRelativePath,
        "Movies/My Film (2020)/My Film (2020) [Director's Cut].mkv",
      );
      expect(
        plan([
          'My.Film.2020.Extended.Final.Cut.mkv',
        ], candidate: film).items.single.needsReview,
        isTrue,
      );
    },
  );

  test('a phrase in the official movie title is not an edition label', () {
    final result = plan(
      ['The.Final.Cut.2004.mkv'],
      candidate: const CatalogMetadataCandidate(
        providerId: '11',
        name: 'The Final Cut',
        year: 2004,
      ),
    );
    expect(
      result.items.single.destinationRelativePath,
      'Movies/The Final Cut (2004)/The Final Cut (2004).mkv',
    );
  });

  test(
    'unrecognized editions are reviewed without discarding their identity',
    () {
      final result = plan([
        'My.Film.2020.Collectors.Edition.mkv',
      ], candidate: film);
      expect(result.items.single.needsReview, isTrue);
      expect(result.items.single.destinationRelativePath, isNull);
    },
  );

  test('moves all exact sidecars and preserves language and accessibility suffixes', () {
    const video = 'Downloads/My.Show.S01E01.Pilot.mkv';
    final result = plan(
      [video],
      sidecars: [
        'Downloads/My.Show.S01E01.Pilot.en.SRT',
        'Downloads/My.Show.S01E01.Pilot.forced.en-US.ass',
        'Downloads/My.Show.S01E01.Pilot.sdh.cs.ssa',
        'Downloads/My.Show.S01E01.Pilot.vtt',
        'Downloads/My.Show.S01E01.Pilot.sub',
        'Downloads/My.Show.S01E01.Pilot.idx',
        'Downloads/My.Show.S01E01.Pilot.nfo',
      ],
    );
    expect(result.plannedCount, 8);
    expect(result.items.skip(1).map((item) => item.destinationRelativePath), [
      'TV/My Show (1999)/Season 01/S01E01 - Pilot.en.srt',
      'TV/My Show (1999)/Season 01/S01E01 - Pilot.forced.en-us.ass',
      'TV/My Show (1999)/Season 01/S01E01 - Pilot.sdh.cs.ssa',
      'TV/My Show (1999)/Season 01/S01E01 - Pilot.vtt',
      'TV/My Show (1999)/Season 01/S01E01 - Pilot.sub',
      'TV/My Show (1999)/Season 01/S01E01 - Pilot.idx',
      'TV/My Show (1999)/Season 01/S01E01 - Pilot.nfo',
    ]);
    expect(
      result.items
          .skip(1)
          .every((item) => item.videoStorageKey == 'provider|$video'),
      isTrue,
    );
  });

  test(
    'unmatched sidecars and same basenames in other directories are reviewed',
    () {
      final result = plan(
        ['A/My.Show.S01E01.Pilot.mkv'],
        sidecars: [
          'B/My.Show.S01E01.Pilot.en.srt',
          'A/Unknown.srt',
          'A/My.Show.S01E01.Pilot.advertisement.nfo',
        ],
      );
      expect(result.plannedCount, 1);
      expect(result.reviewCount, 3);
    },
  );

  test('ambiguous sidecar association to two containers is reviewed', () {
    final result = plan(
      ['A/My.Show.S01E01.Pilot.mkv', 'A/My.Show.S01E01.Pilot.mp4'],
      sidecars: ['A/My.Show.S01E01.Pilot.en.srt'],
    );
    expect(result.plannedCount, 2);
    expect(result.items.last.needsReview, isTrue);
  });

  test('collisions review every version and its associated subtitles', () {
    final result = plan(
      ['A/My.Show.S01E01.Pilot.1080p.mkv', 'B/My.Show.S01E01.Pilot.720p.mkv'],
      sidecars: ['A/My.Show.S01E01.Pilot.1080p.en.srt'],
    );
    expect(result.reviewCount, 3);
    expect(result.plannedCount, 0);
  });

  test('an unchanged destination participates in collisions', () {
    final result = plan([
      'TV/My Show (1999)/Season 01/S01E01 - Pilot.mkv',
      'Downloads/My.Show.S01E01.Pilot.MKV',
    ]);
    expect(result.reviewCount, 2);
    expect(result.unchangedCount, 0);
  });

  test('sanitizes portable names without dropping official title numerals', () {
    final result = plan(
      ['Film.1968.mkv'],
      candidate: const CatalogMetadataCandidate(
        providerId: '12',
        name: '2001: A Space Odyssey',
        year: 1968,
      ),
    );
    expect(
      result.items.single.destinationRelativePath,
      'Movies/2001 - A Space Odyssey (1968)/2001 - A Space Odyssey (1968).mkv',
    );
    final reserved = plan(
      ['Film.2020.mp4'],
      candidate: const CatalogMetadataCandidate(
        providerId: '13',
        name: 'CON',
        year: 2020,
      ),
    );
    expect(
      reserved.items.single.destinationRelativePath,
      'Movies/_CON (2020)/_CON (2020).mp4',
    );
  });

  test('unsafe or excessively long paths stay in review', () {
    final long = plan(
      ['Film.2020.mkv'],
      candidate: CatalogMetadataCandidate(
        providerId: '14',
        name: List.filled(200, 'A').join(),
        year: 2020,
      ),
    );
    expect(long.items.single.needsReview, isTrue);
    final empty = plan(
      ['Film.2020.mkv'],
      candidate: const CatalogMetadataCandidate(
        providerId: '15',
        name: '..',
        year: 2020,
      ),
    );
    expect(empty.items.single.needsReview, isTrue);
  });

  test('merged display groups resolve metadata using retained local IDs', () {
    final local = groupCatalog([fixture.file('My.Show.S01E01.Pilot.mkv')])
        .single;
    final matched = CatalogTitle(
      id: 'tmdb:tv:7',
      name: 'My Show',
      videos: local.videos,
      isSeries: true,
      localIds: [local.id],
      providerId: '7',
    );
    final result = buildLibraryOrganizationPlan(
      titles: [matched],
      matches: {
        jsonEncode(['root', local.id]): const CatalogResolvedMatch(show, [
          pilot,
        ]),
      },
      scope: 'root',
      sidecars: <StorageEntrySnapshot>[],
    );
    expect(result.plannedCount, 1);
  });
}
