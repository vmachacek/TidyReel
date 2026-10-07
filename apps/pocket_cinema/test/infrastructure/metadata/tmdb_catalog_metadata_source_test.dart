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
