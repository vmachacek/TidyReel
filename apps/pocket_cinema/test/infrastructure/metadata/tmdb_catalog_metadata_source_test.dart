import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_cinema/features/catalog/catalog_metadata.dart';
import 'package:pocket_cinema/infrastructure/metadata/catalog_metadata_http_transport.dart';
import 'package:pocket_cinema/infrastructure/metadata/tmdb_catalog_metadata_source.dart';

class FakeTransport implements CatalogMetadataHttpTransport {
  final responses = <Future<CatalogMetadataHttpResponse>>[];
  final requests = <Uri>[];
  final requestHeaders = <Map<String, String>>[];
  int disposeCount = 0;
  Duration? lastTimeout;
  int? lastMaxResponseBytes;

  void respond(Object json, {int status = 200}) {
    respondBytes(utf8.encode(jsonEncode(json)), status: status);
  }

  void respondBytes(List<int> body, {int status = 200}) {
    responses.add(
      Future.value(CatalogMetadataHttpResponse(statusCode: status, body: body)),
    );
  }

  @override
  Future<CatalogMetadataHttpResponse> get({
    required Uri uri,
    required Map<String, String> headers,
    required Duration timeout,
    required int maxResponseBytes,
  }) {
    requests.add(uri);
    requestHeaders.add(headers);
    lastTimeout = timeout;
    lastMaxResponseBytes = maxResponseBytes;
    return responses.removeAt(0);
  }

  @override
  void dispose() => disposeCount++;
}

Map<String, Object?> movie({
  Object? id = 329865,
  Object? title = 'Arrival',
  Object? date = '2016-11-10',
}) => {
  'id': id,
  'title': title,
  'original_title': 'Arrival',
  'release_date': date,
  'overview': 'A linguist learns an alien language.',
};

Map<String, Object?> page(
  List<Object?> results, {
  int current = 1,
  int total = 1,
}) => {'page': current, 'total_pages': total, 'results': results};

Map<String, Object?> episode({
  Object? id = 1,
  Object? number = 1,
  Object? season = 1,
  Object? name = 'Pilot',
  Object? showId = 1396,
}) => {
  'id': id,
  'episode_number': number,
  'season_number': season,
  'name': name,
  'show_id': showId,
};

Map<String, Object?> artworkImage({
  Object? path = '/poster123.jpg',
  Object? width = 1000,
  Object? height = 1500,
  Object? language = 'en',
}) => {
  'file_path': path,
  'width': width,
  'height': height,
  'iso_639_1': language,
};

Map<String, Object?> artworkResponse({
  Object? id = 1396,
  Object? posters = const [],
  Object? backdrops = const [],
}) => {'id': id, 'posters': posters, 'backdrops': backdrops};

const artworkCandidate = CatalogArtworkCandidate(
  filePath: '/poster123.jpg',
  kind: CatalogArtworkKind.poster,
  width: 1000,
  height: 1500,
  language: 'en',
);

const jpegBytes = [0xff, 0xd8, 0xff, 0xe0, 0, 0, 0, 0, 0, 0, 0xff, 0xd9];

void main() {
  late FakeTransport transport;
  late TmdbCatalogMetadataSource source;

  setUp(() {
    transport = FakeTransport();
    source = TmdbCatalogMetadataSource(
      accessToken: ' test-read-token ',
      transport: transport,
    );
  });
  tearDown(() => source.dispose());

  test('Refreshes TV artwork without filtering languages or caching', () async {
    transport.respond(
      artworkResponse(
        posters: [artworkImage()],
        backdrops: [
          artworkImage(
            path: '/backdrop456.png',
            width: 1920,
            height: 1080,
            language: null,
          ),
        ],
      ),
    );
    transport.respond(
      artworkResponse(posters: [artworkImage(path: '/new.jpg')]),
    );
    final first = await source.artwork(providerId: '1396');
    final second = await source.artwork(providerId: '1396');
    expect(transport.requests, hasLength(2));
    for (final uri in transport.requests) {
      expect(uri.scheme, 'https');
      expect(uri.host, 'api.themoviedb.org');
      expect(uri.path, '/3/tv/1396/images');
      expect(uri.queryParameters, isEmpty);
    }
    expect(
      transport.requestHeaders.first['Authorization'],
      'Bearer test-read-token',
    );
    expect(first.map((item) => item.kind), [
      CatalogArtworkKind.poster,
      CatalogArtworkKind.backdrop,
    ]);
    expect(first.first.width, 1000);
    expect(first.first.height, 1500);
    expect(first.first.language, 'en');
    expect(first.last.language, isNull);
    expect(
      first.first.previewUrl,
      'https://image.tmdb.org/t/p/w342/poster123.jpg',
    );
    expect(
      first.last.previewUrl,
      'https://image.tmdb.org/t/p/w780/backdrop456.png',
    );
    expect(second.single.filePath, '/new.jpg');
    expect(() => first.clear(), throwsUnsupportedError);
  });

  test('Returns no artwork and removes duplicate image choices', () async {
    transport.respond(artworkResponse());
    expect(await source.artwork(providerId: '1396'), isEmpty);
    transport.respond(
      artworkResponse(posters: [artworkImage(), artworkImage()]),
    );
    expect(await source.artwork(providerId: '1396'), hasLength(1));
  });

  test('Rejects invalid show IDs without making an artwork request', () async {
    for (final id in ['../movie/1', '0', '-1', '01396', '2147483648']) {
      await expectLater(
        source.artwork(providerId: id),
        throwsA(isA<CatalogMetadataException>()),
      );
    }
    expect(transport.requests, isEmpty);
  });

  test('Rejects malformed artwork and mismatched shows', () async {
    for (final response in [
      artworkResponse(id: 999),
      artworkResponse(id: '1396'),
      artworkResponse(posters: null),
      artworkResponse(backdrops: {}),
      artworkResponse(posters: [artworkImage(width: 0)]),
      artworkResponse(posters: [artworkImage(height: 1.5)]),
      artworkResponse(posters: [artworkImage(language: 5)]),
      artworkResponse(posters: [artworkImage(path: '')]),
      artworkResponse(posters: [artworkImage(path: '/nested/image.jpg')]),
      artworkResponse(posters: [artworkImage(path: '/../private.jpg')]),
      artworkResponse(posters: [artworkImage(path: '//example.com/image.jpg')]),
      artworkResponse(posters: [artworkImage(path: '/image.svg')]),
      artworkResponse(posters: [artworkImage(path: '/image.jpg?token=secret')]),
    ]) {
      transport.respond(response);
      await expectLater(
        source.artwork(providerId: '1396'),
        throwsA(isA<CatalogMetadataException>()),
      );
    }
  });

  test(
    'Downloads bounded artwork without sending the API token to CDN',
    () async {
      transport.respondBytes(jpegBytes);
      final bytes = await source.downloadArtwork(artworkCandidate);
      expect(bytes, jpegBytes);
      expect(
        transport.requests.single.toString(),
        'https://image.tmdb.org/t/p/w780/poster123.jpg',
      );
      expect(transport.requestHeaders.single, {
        'Accept': 'image/jpeg,image/png,image/webp',
      });
      expect(transport.lastMaxResponseBytes, 8 * 1024 * 1024);
      expect(transport.lastTimeout, const Duration(seconds: 10));
    },
  );

  test('Downloads backdrop at a bounded landscape size', () async {
    transport.respondBytes(jpegBytes);
    await source.downloadArtwork(
      const CatalogArtworkCandidate(
        filePath: '/wide.jpg',
        kind: CatalogArtworkKind.backdrop,
        width: 3840,
        height: 2160,
      ),
    );
    expect(
      transport.requests.single.toString(),
      'https://image.tmdb.org/t/p/w1280/wide.jpg',
    );
  });

  test('Refuses invalid artwork paths before making a download', () async {
    for (final path in [
      '//example.com/private.jpg',
      '/../private.jpg',
      '/image.jpg?api_key=secret',
      '/image.svg',
    ]) {
      await expectLater(
        source.downloadArtwork(
          CatalogArtworkCandidate(
            filePath: path,
            kind: CatalogArtworkKind.poster,
            width: 1000,
            height: 1500,
          ),
        ),
        throwsA(isA<CatalogMetadataException>()),
      );
    }
    expect(transport.requests, isEmpty);
  });

  test('Rejects non-image and oversized download bodies', () async {
    for (final bytes in [
      <int>[],
      utf8.encode('<html>Server failure</html>'),
      List<int>.filled(8 * 1024 * 1024 + 1, 0xff),
    ]) {
      transport.respondBytes(bytes);
      await expectLater(
        source.downloadArtwork(artworkCandidate),
        throwsA(isA<CatalogMetadataException>()),
      );
    }
  });

  test(
    'Keeps artwork failures safe and refuses downloads after disposal',
    () async {
      for (final status in [301, 401, 403, 404, 429, 500]) {
        transport.respondBytes(
          utf8.encode('test-read-token https://example.com/private'),
          status: status,
        );
        await expectLater(
          source.downloadArtwork(artworkCandidate),
          throwsA(
            isA<CatalogMetadataException>().having(
              (error) => error.message,
              'safe failure',
              allOf(
                isNot(contains('test-read-token')),
                isNot(contains('https://')),
              ),
            ),
          ),
        );
      }
      source.dispose();
      final requestCount = transport.requests.length;
      await expectLater(
        source.downloadArtwork(artworkCandidate),
        throwsA(isA<CatalogMetadataException>()),
      );
      expect(transport.requests, hasLength(requestCount));
    },
  );

  test(
    'Searches movies using HTTPS, bearer headers, and release year',
    () async {
      transport.respond(page([movie()]));
      final result = await source.search(
        title: ' Arrival ',
        kind: CatalogMediaKind.movie,
        year: 2016,
      );
      final uri = transport.requests.single;
      expect(uri.scheme, 'https');
      expect(uri.host, 'api.themoviedb.org');
      expect(uri.path, '/3/search/movie');
      expect(uri.queryParameters, {
        'query': 'Arrival',
        'language': 'en-US',
        'include_adult': 'false',
        'page': '1',
        'year': '2016',
      });
      expect(uri.toString(), isNot(contains('test-read-token')));
      expect(
        transport.requestHeaders.single['Authorization'],
        'Bearer test-read-token',
      );
      expect(transport.lastTimeout, const Duration(seconds: 10));
      expect(transport.lastMaxResponseBytes, 2 * 1024 * 1024);
      expect(result.single.providerId, '329865');
      expect(result.single.name, 'Arrival');
      expect(result.single.originalName, 'Arrival');
      expect(result.single.year, 2016);
      expect(result.single.overview, 'A linguist learns an alien language.');
    },
  );

  test(
    'Searches series by first-air year and retains original names',
    () async {
      transport.respond(
        page([
          {
            'id': 1396,
            'name': 'Breaking Bad',
            'original_name': 'Breaking Bad',
            'first_air_date': '2008-01-20',
          },
        ]),
      );
      final result = await source.search(
        title: 'Breaking Bad',
        kind: CatalogMediaKind.series,
        year: 2008,
      );
      expect(transport.requests.single.path, '/3/search/tv');
      expect(
        transport.requests.single.queryParameters['first_air_date_year'],
        '2008',
      );
      expect(
        transport.requests.single.queryParameters,
        isNot(contains('year')),
      );
      expect(result.single.year, 2008);
      expect(result.single.overview, isNull);
    },
  );

  test('Fetches later search pages so remakes remain ambiguous', () async {
    transport.respond(
      page([movie(id: 1, title: 'The Thing', date: '1982-06-25')], total: 2),
    );
    transport.respond(
      page(
        [movie(id: 2, title: 'The Thing', date: '2011-10-12')],
        current: 2,
        total: 2,
      ),
    );
    final result = await source.search(
      title: 'The Thing',
      kind: CatalogMediaKind.movie,
    );
    expect(transport.requests.map((uri) => uri.queryParameters['page']), [
      '1',
      '2',
    ]);
    expect(result, hasLength(2));
    expect(
      selectCatalogCandidate(title: 'The Thing', candidates: result),
      isNull,
    );
  });

  test('Rejects a search too large to check every result page', () async {
    transport.respond(page([movie()], total: 6));
    await expectLater(
      source.search(title: 'Arrival', kind: CatalogMediaKind.movie),
      throwsA(
        isA<CatalogMetadataException>().having(
          (error) => error.message,
          'message',
          contains('more specific'),
        ),
      ),
    );
    expect(transport.requests, hasLength(1));
  });

  test(
    'Returns empty searches and titles with an unknown release year',
    () async {
      expect(
        await source.search(title: ' ', kind: CatalogMediaKind.movie),
        isEmpty,
      );
      expect(transport.requests, isEmpty);
      transport.respond(page([], total: 0));
      expect(
        await source.search(title: 'Missing', kind: CatalogMediaKind.movie),
        isEmpty,
      );
      transport.respond(page([movie(date: '')]));
      expect(
        (await source.search(
          title: 'Arrival',
          kind: CatalogMediaKind.movie,
        )).single.year,
        isNull,
      );
    },
  );

  test(
    'Fetches and sorts numbered episodes including season zero specials',
    () async {
      transport.respond({
        'season_number': 0,
        'episodes': [
          episode(id: 2, number: 2, season: 0, name: 'Second special'),
          episode(id: 1, number: 1, season: 0, name: 'First special'),
        ],
      });
      final result = await source.episodes(providerId: '1396', season: 0);
      expect(transport.requests.single.path, '/3/tv/1396/season/0');
      expect(transport.requests.single.queryParameters, {'language': 'en-US'});
      expect(result.map((item) => item.number), [1, 2]);
      expect(result.map((item) => item.name), [
        'First special',
        'Second special',
      ]);
      expect(result.every((item) => item.season == 0), isTrue);
    },
  );

  for (final bad in [
    movie(id: '1'),
    movie(id: 1.0),
    movie(id: 0),
    movie(id: 2147483648),
    movie(title: ''),
    movie(title: 123),
    movie(date: 'not-a-date'),
    movie(date: '2023-02-29'),
    movie(date: '2024-13-01'),
    movie(date: 2016),
  ]) {
    test('Rejects malformed movie fields: $bad', () async {
      transport.respond(page([bad]));
      await expectLater(
        source.search(title: 'Arrival', kind: CatalogMediaKind.movie),
        throwsA(isA<CatalogMetadataException>()),
      );
    });
  }

  for (final bad in [
    episode(id: 0),
    episode(number: '1'),
    episode(number: 0),
    episode(number: 1.0),
    episode(season: 2),
    episode(season: 1.0),
    episode(name: ''),
    episode(showId: 999),
  ]) {
    test('Rejects malformed episode fields: $bad', () async {
      transport.respond({
        'season_number': 1,
        'episodes': [bad],
      });
      await expectLater(
        source.episodes(providerId: '1396', season: 1),
        throwsA(isA<CatalogMetadataException>()),
      );
    });
  }

  test(
    'Rejects duplicate episode numbers and incorrect response season',
    () async {
      for (final json in [
        {
          'season_number': 1,
          'episodes': [episode(), episode(id: 2)],
        },
        {
          'season_number': 2,
          'episodes': [episode()],
        },
        {
          'season_number': 1.0,
          'episodes': [episode()],
        },
      ]) {
        transport.respond(json);
        await expectLater(
          source.episodes(providerId: '1396', season: 1),
          throwsA(isA<CatalogMetadataException>()),
        );
      }
    },
  );

  test('Rejects invalid IDs before constructing a URL', () async {
    for (final id in [
      '../movie/1',
      '0',
      '-1',
      '1?api_key=secret',
      '2147483648',
    ]) {
      await expectLater(
        source.episodes(providerId: id, season: 1),
        throwsA(isA<CatalogMetadataException>()),
      );
    }
    expect(transport.requests, isEmpty);
  });

  test('Rejects malformed JSON, shapes, and invalid UTF-8 safely', () async {
    for (final body in [
      utf8.encode('{broken'),
      utf8.encode('[]'),
      utf8.encode('{"results":{}}'),
      utf8.encode('{"page":1.0,"total_pages":1,"results":[]}'),
      [0xff],
    ]) {
      transport.respondBytes(body);
      await expectLater(
        source.search(title: 'Arrival', kind: CatalogMediaKind.movie),
        throwsA(
          isA<CatalogMetadataException>().having(
            (error) => error.message,
            'message',
            contains('invalid metadata'),
          ),
        ),
      );
    }
  });

  test(
    'Enforces the response body cap even with an injected transport',
    () async {
      source.dispose();
      transport = FakeTransport();
      source = TmdbCatalogMetadataSource(
        accessToken: 'test-read-token',
        transport: transport,
        maxResponseBytes: 10,
      );
      transport.respond(page([movie()]));
      await expectLater(
        source.search(title: 'Arrival', kind: CatalogMediaKind.movie),
        throwsA(isA<CatalogMetadataException>()),
      );
    },
  );

  for (final status in [301, 401, 403, 404, 429, 500]) {
    test(
      'Reports HTTP $status without exposing server content or tokens',
      () async {
        transport.respond({
          'secret': 'test-read-token https://example.com/private',
        }, status: status);
        await expectLater(
          source.search(title: 'Arrival', kind: CatalogMediaKind.movie),
          throwsA(
            isA<CatalogMetadataException>().having(
              (error) => error.toString(),
              'safe failure',
              allOf(
                isNot(contains('test-read-token')),
                isNot(contains('https://')),
              ),
            ),
          ),
        );
      },
    );
  }

  test('Sanitizes transport exceptions that contain a URL or token', () async {
    transport.responses.add(
      Future.error(
        StateError('https://api.themoviedb.org/?token=test-read-token'),
      ),
    );
    await expectLater(
      source.search(title: 'Arrival', kind: CatalogMediaKind.movie),
      throwsA(
        isA<CatalogMetadataException>().having(
          (error) => error.toString(),
          'safe failure',
          allOf(
            isNot(contains('test-read-token')),
            isNot(contains('https://')),
          ),
        ),
      ),
    );
  });

  test('Times out a transport that does not complete', () async {
    source.dispose();
    transport = FakeTransport();
    source = TmdbCatalogMetadataSource(
      accessToken: 'test-read-token',
      transport: transport,
      timeout: const Duration(milliseconds: 1),
    );
    transport.responses.add(Completer<CatalogMetadataHttpResponse>().future);
    await expectLater(
      source.search(title: 'Arrival', kind: CatalogMediaKind.movie),
      throwsA(
        isA<CatalogMetadataException>().having(
          (error) => error.message,
          'message',
          contains('timed out'),
        ),
      ),
    );
  });

  test('Disposes once and refuses later network requests', () async {
    source.dispose();
    source.dispose();
    expect(transport.disposeCount, 1);
    await expectLater(
      source.search(title: 'Arrival', kind: CatalogMediaKind.movie),
      throwsA(isA<CatalogMetadataException>()),
    );
    expect(transport.requests, isEmpty);
  });

  test(
    'Rejects empty tokens and header injection without echoing the token',
    () {
      for (final token in [
        '',
        ' ',
        'secret\r\nX-Header: injection',
        'Bearer secret',
      ]) {
        expect(
          () => TmdbCatalogMetadataSource(
            accessToken: token,
            transport: transport,
          ),
          throwsA(
            isA<CatalogMetadataException>().having(
              (error) => error.message,
              'message',
              isNot(contains('secret')),
            ),
          ),
        );
      }
    },
  );
}
