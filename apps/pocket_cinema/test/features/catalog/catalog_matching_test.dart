import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_cinema/features/catalog/catalog_library.dart';
import 'package:pocket_cinema/features/catalog/catalog_matching.dart';
import 'package:pocket_cinema/features/catalog/catalog_metadata.dart';

import 'catalog_library_test.dart' as fixture;

const candidate = CatalogMetadataCandidate(
  providerId: '42',
  name: 'My Show',
  year: 1999,
);
CatalogEpisodeMetadata episode(int number, String name, {int season = 1}) =>
    CatalogEpisodeMetadata(season: season, number: number, name: name);
CatalogTitle title(List<String> names) =>
    groupCatalog(names.map(fixture.file).toList()).single;

class FakeSource implements CatalogMetadataSource {
  List<CatalogMetadataCandidate> found = [candidate];
  List<CatalogEpisodeMetadata> available = [
    episode(1, 'Start'),
    episode(2, 'Return'),
  ];
  Completer<List<CatalogMetadataCandidate>>? pending;
  bool fail = false;
  int searches = 0;
  final requestedSeasons = <int>[];
  @override
  Future<List<CatalogMetadataCandidate>> search({
    required String title,
    required CatalogMediaKind kind,
    int? year,
  }) async {
    searches++;
    if (fail) throw const CatalogMetadataException('Offline');
    return pending?.future ?? found;
  }

  @override
  Future<List<CatalogEpisodeMetadata>> episodes({
    required String providerId,
    required int season,
  }) async {
    requestedSeasons.add(season);
    if (fail) throw const CatalogMetadataException('Offline');
    return available.where((e) => e.season == season).toList();
  }

  @override
  void dispose() {}
}

void main() {
  test('matches the title and decorates unnamed numbered episodes', () async {
    final source = FakeSource(), matcher = CatalogMatcher(source: FakeSource());
    matcher.configure(source);
    addTearDown(matcher.dispose);
    final local = title([
      'My Show (1999)/Season 1/S01E01.mkv',
      'My Show (1999)/Season 1/S01E02.mkv',
    ]);
    await matcher.enrich([local], 'root');
    final result = matcher.apply([local], 'root').single;
    expect(result.id, 'tmdb:tv:42');
    expect(result.videos.map((v) => v.title), ['Start', 'Return']);
    expect(result.videos.map((v) => v.id), local.videos.map((v) => v.id));
    expect(source.searches, 1);
    await matcher.enrich([local], 'root');
    expect(source.searches, 1);
    expect(source.requestedSeasons, [1]);
  });

  test(
    'conflicting episode names and segment letters retain local names',
    () async {
      final source = FakeSource(), matcher = CatalogMatcher();
      matcher.configure(source);
      addTearDown(matcher.dispose);
      final local = title([
        'My Show (1999)/Season 1/S01E01.Different Order.mkv',
        'My Show (1999)/Season 1/S01E02b.Segment.mkv',
      ]);
      await matcher.enrich([local], 'root');
      final result = matcher.apply([local], 'root').single;
      expect(result.videos.map((v) => v.title), ['Different Order', 'Segment']);
      expect(result.videos.every((v) => v.needsReview), isTrue);
      expect(result.videos.last.episodeCode, 'S01E02b');
      expect(result.matchStatus, contains('Episodes need review'));
    },
  );

  test(
    'title-only files resolve only a unique exact name in their season',
    () async {
      final matcher = CatalogMatcher(source: FakeSource());
      addTearDown(matcher.dispose);
      final local = title([
        'My Show (1999)/Season 1/Start.mkv',
        'My Show (1999)/Season 1/Unknown Special.mkv',
      ]);
      await matcher.enrich([local], 'root');
      final videos = matcher.apply([local], 'root').single.videos;
      expect(videos.first.episode, 1);
      expect(videos.first.episodeCode, 'S01E01');
      expect(videos.first.needsReview, isFalse);
      expect(videos.last.episode, isNull);
      expect(videos.last.needsReview, isTrue);
    },
  );

  test(
    'same canonical series merges aliases while remakes remain separate',
    () async {
      final matcher = CatalogMatcher(source: FakeSource());
      addTearDown(matcher.dispose);
      final original = title(['My Show (1999)/Season 1/S01E01.mkv']);
      final localized = title(['Moj Serial (1999)/Season 2/S02E01.mkv']);
      final remake = title(['My Show (2025)/Season 1/S01E01.mkv']);
      await matcher.select(localized, 'root', candidate);
      await matcher.enrich([original, localized, remake], 'root');
      final grouped = matcher.apply([original, localized, remake], 'root');
      expect(grouped, hasLength(2));
      final canonical = grouped.singleWhere((t) => t.providerId == '42');
      expect(canonical.videos, hasLength(2));
      expect(canonical.localIds, [original.id, localized.id]);
      expect(canonical.seasons, [1, 2]);
      expect(grouped.singleWhere((t) => t.providerId == null).first.year, 2025);
    },
  );

  test(
    'cached matches restore offline including manually confirmed choices',
    () async {
      final matcher = CatalogMatcher(source: FakeSource());
      addTearDown(matcher.dispose);
      final local = title(['My Show (1999)/Season 1/S01E01.mkv']);
      await matcher.select(local, 'root', candidate);
      final restarted = CatalogMatcher();
      addTearDown(restarted.dispose);
      restarted.restore(matcher.toJson().cast<String, dynamic>());
      expect(restarted.enabled, isFalse);
      expect(restarted.apply([local], 'root').single.first.title, 'Start');
      expect(
        restarted.apply([local], 'root').single.matchStatus,
        contains('Confirmed by you'),
      );
      expect(
        restarted.apply([local], 'another root').single.providerId,
        isNull,
      );
    },
  );

  test('complete restored matches do not republish cached metadata', () async {
    final source = FakeSource(), matcher = CatalogMatcher(source: source);
    addTearDown(matcher.dispose);
    final local = title(['My Show (1999)/Season 1/S01E01.mkv']);
    final cacheKey = matcher.key('root', local);
    matcher.restore({
      cacheKey: CatalogResolvedMatch(candidate, [
        episode(1, 'Start'),
        episode(2, 'Return'),
      ], manual: true).toJson(),
    });
    final cached = matcher.matches[cacheKey];
    final revision = matcher.presentationRevision;
    var presentationChanges = 0;
    matcher.addListener(() {
      if (matcher.presentationRevision != revision) presentationChanges++;
    });

    await matcher.enrich([local], 'root');

    expect(source.searches, 0);
    expect(source.requestedSeasons, isEmpty);
    expect(matcher.matches[cacheKey], same(cached));
    expect(matcher.presentationRevision, revision);
    expect(presentationChanges, 0);
    expect(matcher.apply([local], 'root').single.first.title, 'Start');
  });

  test('unchanged cached movies do not republish metadata', () async {
    final source = FakeSource(), matcher = CatalogMatcher(source: source);
    addTearDown(matcher.dispose);
    final local = title(['My Movie (1999).mkv']);
    final cacheKey = matcher.key('root', local);
    matcher.restore({
      cacheKey: const CatalogResolvedMatch(
        CatalogMetadataCandidate(
          providerId: '99',
          name: 'My Movie',
          year: 1999,
        ),
        [],
      ).toJson(),
    });
    final cached = matcher.matches[cacheKey];
    final revision = matcher.presentationRevision;

    await matcher.enrich([local], 'root');

    expect(source.searches, 0);
    expect(source.requestedSeasons, isEmpty);
    expect(matcher.matches[cacheKey], same(cached));
    expect(matcher.presentationRevision, revision);
    expect(matcher.apply([local], 'root').single.name, 'My Movie');
  });

  test('clearing a failure republishes otherwise unchanged metadata', () async {
    final source = FakeSource(), matcher = CatalogMatcher(source: source);
    addTearDown(matcher.dispose);
    final local = title(['My Show (1999)/Season 1/S01E01.mkv']);
    final cacheKey = matcher.key('root', local);
    matcher.restore({
      cacheKey: CatalogResolvedMatch(candidate, [episode(1, 'Start')]).toJson(),
    });
    matcher.failures[cacheKey] = 'Metadata unavailable.';
    final cached = matcher.matches[cacheKey];
    final revision = matcher.presentationRevision;

    await matcher.enrich([local], 'root');

    expect(matcher.matches[cacheKey], same(cached));
    expect(matcher.failures, isEmpty);
    expect(matcher.presentationRevision, revision + 1);
    expect(
      matcher.apply([local], 'root').single.matchStatus,
      isNot(contains('unavailable')),
    );
  });

  test(
    'new seasons are fetched on a later scan without re-searching a title',
    () async {
      final source = FakeSource()
        ..available.add(episode(1, 'Season Two', season: 2));
      final matcher = CatalogMatcher(source: source);
      addTearDown(matcher.dispose);
      await matcher.enrich([
        title(['My Show (1999)/Season 1/S01E01.mkv']),
      ], 'root');
      final revision = matcher.presentationRevision;
      final rescanned = title([
        'My Show (1999)/Season 1/S01E01.mkv',
        'My Show (1999)/Season 2/S02E01.mkv',
      ]);
      await matcher.enrich([rescanned], 'root');
      expect(source.searches, 1);
      expect(source.requestedSeasons, [1, 2]);
      expect(matcher.presentationRevision, revision + 1);
      expect(
        matcher.apply([rescanned], 'root').single.videos.last.title,
        'Season Two',
      );
    },
  );

  test(
    'network failures retain every playable local file and retry is explicit',
    () async {
      final source = FakeSource()..fail = true;
      final matcher = CatalogMatcher(source: source);
      addTearDown(matcher.dispose);
      final local = title(['My Show (1999)/Season 1/S01E01.Start.mkv']);
      await matcher.enrich([local], 'root');
      expect(matcher.apply([local], 'root').single.first.id, local.first.id);
      expect(
        matcher.apply([local], 'root').single.matchStatus,
        contains('unavailable'),
      );
      source.fail = false;
      await matcher.retry([local], 'root');
      expect(matcher.apply([local], 'root').single.providerId, '42');
    },
  );

  test('manual selection made during a search cannot be overwritten', () async {
    final source = FakeSource()
      ..pending = Completer<List<CatalogMetadataCandidate>>();
    final matcher = CatalogMatcher(source: source);
    addTearDown(matcher.dispose);
    final local = title(['My Show (1999)/Season 1/S01E01.mkv']);
    final pending = matcher.enrich([local], 'root');
    const manual = CatalogMetadataCandidate(
      providerId: '99',
      name: 'Correct Show',
    );
    final selection = matcher.select(local, 'root', manual);
    source.pending!.complete([candidate]);
    await pending;
    await selection;
    final selected = matcher.matches[matcher.key('root', local)]!;
    expect(selected.candidate.providerId, '99');
    expect(selected.manual, isTrue);
  });

  test(
    'use local names during a pending request remains authoritative on retry',
    () async {
      final source = FakeSource()
        ..pending = Completer<List<CatalogMetadataCandidate>>();
      final matcher = CatalogMatcher(source: source);
      addTearDown(matcher.dispose);
      final local = title(['My Show (1999)/Season 1/S01E01.mkv']);
      final pending = matcher.enrich([local], 'root');
      matcher.forget(local, 'root');
      source.pending!.complete([candidate]);
      await pending;
      await matcher.retry([local], 'root');
      expect(matcher.apply([local], 'root').single.providerId, isNull);
      expect(source.searches, 1);
    },
  );

  test('disabling the source ignores its late response', () async {
    final source = FakeSource()
      ..pending = Completer<List<CatalogMetadataCandidate>>();
    final matcher = CatalogMatcher(source: source);
    addTearDown(matcher.dispose);
    final local = title(['My Show (1999)/Season 1/S01E01.mkv']);
    final pending = matcher.enrich([local], 'root');
    matcher.configure(null);
    source.pending!.complete([candidate]);
    await pending;
    expect(matcher.matches, isEmpty);
  });

  test('concurrent manual selections both receive season metadata', () async {
    final source = FakeSource()
      ..pending = Completer<List<CatalogMetadataCandidate>>();
    final matcher = CatalogMatcher(source: source);
    addTearDown(matcher.dispose);
    final waiting = title(['My Show (1999)/Season 1/S01E01.mkv']);
    final first = title(['First Alias/Season 1/S01E01.mkv']);
    final second = title(['Second Alias/Season 1/S01E01.mkv']);
    final request = matcher.enrich([waiting], 'root');
    final firstSelection = matcher.select(first, 'root', candidate);
    final secondSelection = matcher.select(second, 'root', candidate);
    source.pending!.complete([candidate]);
    await request;
    await firstSelection;
    await secondSelection;
    expect(matcher.matches[matcher.key('root', first)]!.episodes, hasLength(2));
    expect(
      matcher.matches[matcher.key('root', second)]!.episodes,
      hasLength(2),
    );
  });

  test(
    'bare episode files stay separate until their show is identified',
    () async {
      final source = FakeSource(), matcher = CatalogMatcher();
      matcher.configure(source);
      addTearDown(matcher.dispose);
      final titles = groupCatalog([
        fixture.file('S01E01.mkv'),
        fixture.file('S01E02.mkv'),
      ]);
      expect(titles, hasLength(2));
      await matcher.enrich(titles, 'root');
      expect(source.searches, 0);
      expect(titles.every((t) => t.name == 'Unidentified show'), isTrue);
    },
  );

  test(
    'manually identifying an orphan permits safe episode enrichment',
    () async {
      final matcher = CatalogMatcher(source: FakeSource());
      addTearDown(matcher.dispose);
      final local = title(['S01E01.mkv']);
      await matcher.select(local, 'root', candidate);
      final video = matcher.apply([local], 'root').single.first;
      expect(video.series, 'My Show');
      expect(video.title, 'Start');
      expect(video.needsReview, isFalse);
    },
  );

  test(
    'title-only resolution retains independent special ambiguity warnings',
    () async {
      final source = FakeSource()..available = [episode(1, 'Start Special')];
      final matcher = CatalogMatcher(source: source);
      addTearDown(matcher.dispose);
      final local = title(['My Show (1999)/Season 1/Start Special.mkv']);
      await matcher.enrich([local], 'root');
      final video = matcher.apply([local], 'root').single.first;
      expect(video.episode, 1);
      expect(video.parsed.warnings, contains('AMBIGUOUS_SPECIAL'));
      expect(video.needsReview, isTrue);
    },
  );

  test('rejects semantically invalid cached records', () {
    final matcher = CatalogMatcher();
    addTearDown(matcher.dispose);
    final valid = CatalogResolvedMatch(candidate, [
      episode(1, 'Start'),
    ]).toJson();
    matcher.restore({
      'empty': {...valid, 'id': ''},
      'negative': {
        ...valid,
        'episodes': [
          {'season': -1, 'number': 1, 'name': 'Wrong'},
        ],
      },
      'valid': valid,
    });
    expect(matcher.matches.keys, ['valid']);
  });
}
