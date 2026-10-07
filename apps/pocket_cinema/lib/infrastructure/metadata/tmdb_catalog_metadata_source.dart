import 'dart:async';
import 'dart:convert';

import '../../features/catalog/catalog_metadata.dart';
import 'catalog_metadata_http_transport.dart';

/// TMDB v3 metadata using the account's API Read Access Token.
class TmdbCatalogMetadataSource implements CatalogMetadataSource {
  TmdbCatalogMetadataSource({
    required String accessToken,
    CatalogMetadataHttpTransport? transport,
    this.timeout = const Duration(seconds: 10),
    this.maxResponseBytes = 2 * 1024 * 1024,
    this.maxSearchPages = 5,
  }) : _accessToken = accessToken.trim(),
       _transport = transport ?? IoCatalogMetadataHttpTransport() {
    if (_accessToken.isEmpty ||
        _accessToken.length > 8192 ||
        RegExp(r'[\s\x00-\x1f\x7f]').hasMatch(_accessToken)) {
      throw const CatalogMetadataException(
        'Enter a valid TMDB API Read Access Token.',
      );
    }
    if (timeout <= Duration.zero ||
        maxResponseBytes <= 0 ||
        maxSearchPages < 1 ||
        maxSearchPages > 500) {
      throw ArgumentError('Metadata request limits must be positive.');
    }
  }

  final String _accessToken;
  final CatalogMetadataHttpTransport _transport;
  final Duration timeout;
  final int maxResponseBytes;
  final int maxSearchPages;
  bool _disposed = false;

  @override
  Future<List<CatalogMetadataCandidate>> search({
    required String title,
    required CatalogMediaKind kind,
    int? year,
  }) async {
    final query = title.trim();
    if (query.isEmpty) return const [];
    if (year != null && (year < 1000 || year > 9999)) {
      throw const CatalogMetadataException('The title year is invalid.');
    }
    final movie = kind == CatalogMediaKind.movie;
    final parameters = {
      'query': query,
      'language': 'en-US',
      'include_adult': 'false',
      if (year != null) movie ? 'year' : 'first_air_date_year': year.toString(),
    };
    final candidates = <CatalogMetadataCandidate>[];
    var page = 1;
    var totalPages = 1;
    do {
      final json = await _getJson('/3/search/${movie ? 'movie' : 'tv'}', {
        ...parameters,
        'page': page.toString(),
      });
      final results = json['results'];
      final returnedPage = json['page'];
      final reportedPages = json['total_pages'];
      if (results is! List ||
          returnedPage is! int ||
          returnedPage != page ||
          reportedPages is! int ||
          reportedPages < 0 ||
          (reportedPages == 0 && results.isNotEmpty)) {
        throw _invalidResponse;
      }
      if (reportedPages > maxSearchPages) {
        throw const CatalogMetadataException(
          'Too many titles match. Add a year or a more specific title.',
        );
      }
      // Never automatically select from an incomplete first page: a remake or
      // a second exact title may appear later in the search results.
      if (page > 1 && reportedPages != totalPages) throw _invalidResponse;
      totalPages = reportedPages;
      for (final result in results) {
        if (result is! Map<String, dynamic>) throw _invalidResponse;
        final id = _positiveInt(result['id']);
        final name = _requiredText(result[movie ? 'title' : 'name']);
        candidates.add(
          CatalogMetadataCandidate(
            providerId: id.toString(),
            name: name,
            originalName: _optionalText(
              result[movie ? 'original_title' : 'original_name'],
            ),
            year: _dateYear(result[movie ? 'release_date' : 'first_air_date']),
            overview: _optionalText(result['overview']),
          ),
        );
      }
      page++;
    } while (page <= totalPages);
    return List.unmodifiable(candidates);
  }

  @override
  Future<List<CatalogEpisodeMetadata>> episodes({
    required String providerId,
    required int season,
  }) async {
    final numericId = int.tryParse(providerId);
    if (!RegExp(r'^[1-9]\d*$').hasMatch(providerId) ||
        numericId == null ||
        numericId > 2147483647 ||
        season < 0 ||
        season > 9999) {
      throw const CatalogMetadataException(
        'The selected show or season is invalid.',
      );
    }
    final json = await _getJson('/3/tv/$providerId/season/$season', {
      'language': 'en-US',
    });
    if (json['season_number'] is! int || json['season_number'] != season) {
      throw _invalidResponse;
    }
    final results = json['episodes'];
    if (results is! List) throw _invalidResponse;
    final episodes = <CatalogEpisodeMetadata>[];
    final numbers = <int>{};
    for (final result in results) {
      if (result is! Map<String, dynamic>) throw _invalidResponse;
      _positiveInt(result['id']);
      final number = _positiveInt(result['episode_number']);
      if (result['season_number'] is! int ||
          result['season_number'] != season ||
          !numbers.add(number)) {
        throw _invalidResponse;
      }
      final showId = result['show_id'];
      if (showId != null && _positiveInt(showId).toString() != providerId) {
        throw _invalidResponse;
      }
      episodes.add(
        CatalogEpisodeMetadata(
          season: season,
          number: number,
          name: _requiredText(result['name']),
        ),
      );
    }
    episodes.sort((a, b) => a.number.compareTo(b.number));
    return List.unmodifiable(episodes);
  }

  static const _invalidResponse = CatalogMetadataException(
    'TMDB returned invalid metadata. Try again later.',
  );

  Future<Map<String, dynamic>> _getJson(
    String path,
    Map<String, String> parameters,
  ) async {
    if (_disposed) {
      throw const CatalogMetadataException(
        'The metadata connection is closed.',
      );
    }
    try {
      final response = await _transport
          .get(
            uri: Uri.https('api.themoviedb.org', path, parameters),
            headers: {
              'Authorization': 'Bearer $_accessToken',
              'Accept': 'application/json',
            },
            timeout: timeout,
            maxResponseBytes: maxResponseBytes,
          )
          .timeout(timeout);
      switch (response.statusCode) {
        case 200:
          break;
        case 401:
        case 403:
          throw const CatalogMetadataException(
            'TMDB rejected the API Read Access Token. Check it in settings.',
          );
        case 404:
          throw const CatalogMetadataException(
            'TMDB could not find the selected title or season.',
          );
        case 429:
          throw const CatalogMetadataException(
            'TMDB has received too many requests. Try again later.',
          );
        default:
          throw const CatalogMetadataException(
            'TMDB is unavailable right now. Try again later.',
          );
      }
      if (response.body.length > maxResponseBytes) throw _invalidResponse;
      final decoded = jsonDecode(utf8.decode(response.body));
      if (decoded is! Map<String, dynamic>) throw _invalidResponse;
      return decoded;
    } on CatalogMetadataException {
      rethrow;
    } on TimeoutException {
      throw const CatalogMetadataException(
        'The metadata request timed out. Try again.',
      );
    } on FormatException {
      throw _invalidResponse;
    } catch (_) {
      throw const CatalogMetadataException(
        'Could not reach TMDB. Check your connection and try again.',
      );
    }
  }

  static int _positiveInt(Object? value) {
    if (value is! int || value <= 0 || value > 2147483647) {
      throw _invalidResponse;
    }
    return value;
  }

  static String _requiredText(Object? value) {
    if (value is! String || value.trim().isEmpty) throw _invalidResponse;
    return value.trim();
  }

  static String? _optionalText(Object? value) {
    if (value == null) return null;
    if (value is! String) throw _invalidResponse;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static int? _dateYear(Object? value) {
    if (value == null || value == '') return null;
    if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      throw _invalidResponse;
    }
    final parts = value.split('-').map(int.parse).toList();
    final date = DateTime.utc(parts[0], parts[1], parts[2]);
    if (date.year < 1000 ||
        date.year != parts[0] ||
        date.month != parts[1] ||
        date.day != parts[2]) {
      throw _invalidResponse;
    }
    return date.year;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _transport.dispose();
  }
}
