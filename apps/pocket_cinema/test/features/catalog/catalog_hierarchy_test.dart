import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_platform_storage/media_platform_storage.dart';
import 'package:pocket_cinema/features/catalog/catalog_library.dart';

StorageEntrySnapshot _file(String path) => StorageEntrySnapshot(
  storageKey: 'fixture|$path',
  parentStorageKey: null,
  relativePath: path,
  displayName: path.replaceAll('\\', '/').split('/').last,
  isDirectory: false,
  mimeType: 'video/x-matroska',
  sizeBytes: 1024,
  modifiedAtUtc: DateTime.utc(2026),
  flags: const {StorageEntryFlag.supportsRead},
);

void main() {
  final fixture = File(
    '../../packages/media_parser/test/fixtures/spongebob-file-list-2026-10-07.txt',
  ).readAsLinesSync().where((line) => line.trim().isNotEmpty).toList();

  for (final includeLibraryPrefix in [true, false]) {
    test(
      'real listing creates show, season, episode hierarchy with library prefix $includeLibraryPrefix',
      () {
        final entries = fixture
            .map(
              (path) => includeLibraryPrefix
                  ? path
                  : path.substring(
                      path.indexOf('SpongeBob SquarePants (1999)'),
                    ),
            )
            .map(_file)
            .toList();
        final titles = groupCatalog(entries);

        expect(entries, hasLength(268));
        expect(titles, hasLength(1));
        final show = titles.single;
        expect(show.isSeries, isTrue);
        expect(show.name, 'SpongeBob SquarePants');
        expect(show.id, 'series:spongebob squarepants (1999)');
        expect(show.seasons, [1, 2, 3, 4, 5, 6, 7, 8, 9]);
        expect(show.videos, hasLength(268));
        expect(
          show.videos.map((video) => video.id),
          unorderedEquals(entries.map((entry) => entry.storageKey)),
        );
        expect(show.videos.map((video) => video.year).toSet(), {1999});
        expect(show.episodeCount, 325);
        expect(
          show.videos.where((video) => video.episodeCount > 1),
          hasLength(56),
        );
        expect(show.videos.first.episodeCode, 'S01E01-E03');

        final suffixes = show.videos.where(
          (video) =>
              video.parsed.warnings.contains('NON_STANDARD_EPISODE_SUFFIX'),
        );
        expect(
          suffixes.map((video) => video.episodeCode),
          unorderedEquals(['S06E11b', 'S06E26b']),
        );
        expect(suffixes.every((video) => video.needsReview), isTrue);

        final special = show.videos.singleWhere(
          (video) => video.episode == null,
        );
        expect(special.season, 5);
        expect(special.episodeCode, 'S05 · Episode unidentified');
        expect(special.needsReview, isTrue);
        expect(special.title, contains('Atlantis Squarepantis'));

        for (final season in show.seasons) {
          final knownNumbers = show.videos
              .where((video) => video.season == season)
              .map((video) => video.episode)
              .whereType<int>()
              .toList();
          expect(knownNumbers, orderedEquals([...knownNumbers]..sort()));
        }
      },
    );
  }

  test(
    'localized release folders keep the local series and episode spelling',
    () {
      final show = groupCatalog([
        _file('Prasiatko Peppa (2004)/S01 DVDRIP/1x07 Maminka pracuje.mkv'),
        _file('Prasiatko.Peppa.(2004).S02.x265/2x01 Pandi dvojcata.mkv'),
        _file(
          'TV Shows/Prasiatko Peppa (2004)/Season 03/Release One/S03E02 - Prázdniny.mp4',
        ),
      ]).single;

      expect(show.id, 'series:prasiatko peppa (2004)');
      expect(show.name, 'Prasiatko Peppa');
      expect(show.seasons, [1, 2, 3]);
      expect(show.videos.map((video) => video.title), [
        'Maminka pracuje',
        'Pandi dvojcata',
        'Prázdniny',
      ]);
    },
  );

  test('different translated title names await alias evidence', () {
    final titles = groupCatalog([
      _file('Prasiatko Peppa (2004)/Season 01/S01E01.mkv'),
      _file('Peppa Pig (2004)/Season 01/S01E01.mkv'),
    ]);
    expect(titles, hasLength(2));
  });

  test(
    'suffix labels distinguish local segments at the same episode number',
    () {
      final show = groupCatalog([
        _file('My Show/Season 6/S06E11a - First story.mkv'),
        _file('My Show/Season 6/S06E11b - Second story.mkv'),
      ]).single;

      expect(
        show.videos.map((video) => video.episodeCode),
        unorderedEquals(['S06E11a', 'S06E11b']),
      );
      expect(
        show.videos.map((video) => video.title),
        unorderedEquals(['First story', 'Second story']),
      );
      expect(show.videos.every((video) => video.needsReview), isTrue);
      expect(show.episodeCount, 2);
    },
  );

  test(
    'nonconsecutive files count their references instead of an inclusive range',
    () {
      final show = groupCatalog([
        _file('My Show/Season 1/S01E01+E03.mkv'),
        _file('My Show/Season 1/S01E04-E06.mkv'),
      ]).single;

      expect(show.videos.map((video) => video.episodeCode), [
        'S01E01+E03',
        'S01E04-E06',
      ]);
      expect(show.videos.map((video) => video.episodeCount), [2, 3]);
      expect(show.episodeCount, 5);
    },
  );

  test(
    'unknown episodes remain visible under their season after known episodes',
    () {
      final show = groupCatalog([
        _file('My Show/Season 2/Hard Times.mkv'),
        _file('My Show/Season 2/S02E03 - The Visit.mkv'),
      ]).single;

      expect(show.seasons, [2]);
      expect(show.videos, hasLength(2));
      expect(show.videos.first.episodeCode, 'S02E03');
      expect(show.videos.last.title, 'Hard Times');
      expect(show.videos.last.episode, isNull);
      expect(show.videos.last.episodeCode, 'S02 · Episode unidentified');
      expect(show.videos.last.needsReview, isTrue);
      expect(show.episodeCount, 2);
    },
  );

  test(
    'movies sharing a title with different release years remain separate',
    () {
      final titles = groupCatalog([
        _file('Movies/The Thing (1982)/The Thing (1982).mkv'),
        _file('Movies/The Thing (2011)/The Thing (2011).mkv'),
      ]);

      expect(titles, hasLength(2));
      expect(titles.every((title) => !title.isSeries), isTrue);
      expect(titles.map((title) => title.name), ['The Thing', 'The Thing']);
      expect(titles.map((title) => title.first.year), [1982, 2011]);
      expect(titles.map((title) => title.id).toSet(), hasLength(2));
    },
  );
}
