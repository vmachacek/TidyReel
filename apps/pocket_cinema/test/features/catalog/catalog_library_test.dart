import 'package:flutter_test/flutter_test.dart';
import 'package:media_platform_storage/media_platform_storage.dart';
import 'package:pocket_cinema/features/catalog/catalog_library.dart';

StorageEntrySnapshot file(String path) => StorageEntrySnapshot(
  storageKey: 'provider|$path',
  parentStorageKey: null,
  relativePath: path,
  displayName: path.split('/').last,
  isDirectory: false,
  mimeType: 'video/mp4',
  sizeBytes: 1024,
  modifiedAtUtc: DateTime.utc(2026),
  flags: const {StorageEntryFlag.supportsRead},
);
void main() {
  test('Groups episode filenames across seasons and keeps movies separate', () {
    final titles = groupCatalog([
      file('Movies/Arrival (2016).mkv'),
      file('Shows/My.Show.S02E03.Return.mkv'),
      file('Shows/My_Show_S01E02_Visit.mp4'),
      file('Shows/My.Show.S01E01.Start.mp4'),
    ]);
    expect(titles.length, 2);
    final series = titles.singleWhere((t) => t.isSeries);
    expect(series.name, 'My Show');
    expect(series.seasons, [1, 2]);
    expect(series.videos.map((v) => v.episodeCode), [
      'S01E01',
      'S01E02',
      'S02E03',
    ]);
    expect(series.first.title, 'Start');
    expect(titles.singleWhere((t) => !t.isSeries).first.year, 2016);
  });
  test('Recognizes alternate numbering and combined files without consuming resolution', () {
    final alternate = CatalogVideo(file('The.Show.2x03.Episode.mkv'));
    expect(alternate.season, 2);
    expect(alternate.episode, 3);
    final combined = CatalogVideo(file('The.Show.S01E07-E08.Special.mp4'));
    expect(combined.episodeCode, 'S01E07-E08');
    expect(combined.title, 'Special');
    expect(CatalogVideo(file('The.Show.S01E02.1080p.mkv')).endEpisode, isNull);
  });
  test('Uses the series folder when the filename omits the show name', () {
    final episode = CatalogVideo(
      file('Shows/My Show/Season 2/S02E03.Return.mp4'),
    );
    expect(episode.series, 'My Show');
    expect(episode.title, 'Return');
  });
  test('Uses local posters and fanart in the movie or series folder', () {
    final movie = CatalogVideo(file('Movies/My Film/My Film.mkv'));
    final poster = file('Movies/My Film/poster.jpg');
    final fanart = file('Movies/My Film/fanart.jpg');
    expect(findArtwork(movie, [poster, fanart]), same(poster));
    expect(findArtwork(movie, [poster, fanart], backdrop: true), same(fanart));
    final episode = CatalogVideo(
      file('Shows/My Show/Season 2/My.Show.S02E03.mkv'),
    );
    final showPoster = file('Shows/My Show/poster.jpg');
    expect(findArtwork(episode, [showPoster]), same(showPoster));
    expect(findArtwork(episode, [showPoster], backdrop: true), isNull);
  });
  test(
    'Keeps a show together when release folders and filename prefixes vary',
    () {
      final titles = groupCatalog([
        file('TV Shows/My Show (2004)/Season 01/My.Show.S01E01.Start.mkv'),
        file(
          'TV Shows/My Show (2004)/S02 DVDRIP + TVRIP/S02 DVDRIP.My.Show.S02E01.Return.mkv',
        ),
      ]);
      expect(titles.length, 1);
      expect(titles.single.name, 'My Show');
      expect(titles.single.seasons, [1, 2]);
    },
  );
  for (final root in ['TV Shows/', '']) {
    test('Groups the real SpongeBob season releases under root "$root"', () {
      final show = '${root}SpongeBob SquarePants (1999)';
      final entries = [
        file('$show/Season 05/S05E09 - The Krusty Sponge.mkv'),
        file(
          '$show/Spongebob Squarepants Season 5 Complete WEB x264 [i_c]/SpongeBob SquarePants S05E01 Friend or Foe.mkv',
        ),
        file(
          '$show/Spongebob Squarepants Season 6 Complete WEB x264 [i_c]/Spongebob Squarepants S06E11b Spongebob Squarepants vs The Big One.mkv',
        ),
        file(
          '$show/Spongebob Squarepants Season 6 Complete WEB x264 [i_c]/S06E26B The Clash of Triton.mkv',
        ),
        file(
          '$show/Spongebob Squarepants Season 9 Complete WEB x264 [i_c]/Spongebob Squarepants S09E29 Are You Happy Now.mkv',
        ),
      ];

      final title = groupCatalog(entries).single;
      expect(title.isSeries, isTrue);
      expect(title.id, 'series:spongebob squarepants (1999)');
      expect(title.name, 'SpongeBob SquarePants');
      expect(title.seasons, [5, 6, 9]);
      expect(
        title.videos.map((v) => v.id),
        unorderedEquals(entries.map((entry) => entry.storageKey)),
      );
      expect(title.episodeCount, entries.length);
    });
  }
  test('Uses the show folder above nested episode release folders', () {
    final titles = groupCatalog([
      file('TV Shows/My Show/Release One/My.Show.S01E01.Start.mkv'),
      file('TV Shows/My Show/Release Two/My.Show.S01E02.Visit.mkv'),
      file('My Show/Season 2/Release Three/S02E01.Return.mkv'),
      file(
        'My Show/My Show Season 2 Complete WEB x264/Release Four/S02E02.Home.mkv',
      ),
    ]);
    expect(titles.single.name, 'My Show');
    expect(titles.single.seasons, [1, 2]);
    expect(titles.single.videos, hasLength(4));
  });
  test('Keeps different show years and unnumbered movies separate', () {
    final titles = groupCatalog([
      file('TV Shows/My Show (1999)/Season 1/S01E01.Start.mkv'),
      file('TV Shows/My Show (2025)/Season 1/S01E01.Start.mkv'),
      file('TV Shows/My Show (1999)/The SpongeBob SquarePants Movie.mkv'),
      file('Movies/Collection/Arrival (2016).mkv'),
      file('Movies/Collection/Interstellar (2014).mkv'),
    ]);
    expect(titles, hasLength(5));
    expect(titles.where((title) => title.isSeries).map((title) => title.id), [
      'series:my show (1999)',
      'series:my show (2025)',
    ]);
    expect(titles.where((title) => !title.isSeries), hasLength(3));
  });
}
