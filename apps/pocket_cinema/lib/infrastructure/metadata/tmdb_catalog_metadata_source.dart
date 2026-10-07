import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../features/catalog/catalog_metadata.dart';
import 'catalog_metadata_http_transport.dart';

/// TMDB v3 metadata using the account's API Read Access Token.
class TmdbCatalogMetadataSource
    implements CatalogMetadataSource, CatalogArtworkSource {
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

  static const maxArtworkBytes = 8 * 1024 * 1024;

  @override
  Future<List<CatalogArtworkCandidate>> artwork({
    required String providerId,
  }) async {
    _validateShowId(providerId);
    // Omitting language returns all artwork, including text-free images. Do
    // not cache this request: opening or refreshing the picker re-fetches it.
    final json = await _getJson('/3/tv/$providerId/images', const {});
    if (_positiveInt(json['id']).toString() != providerId) {
      throw _invalidResponse;
    }
    final candidates = <CatalogArtworkCandidate>[];
    for (final kind in CatalogArtworkKind.values) {
      final results =
          json[kind == CatalogArtworkKind.poster ? 'posters' : 'backdrops'];
      if (results is! List) throw _invalidResponse;
      final paths = <String>{};
      for (final result in results) {
        if (result is! Map<String, dynamic>) throw _invalidResponse;
        final path = _requiredText(result['file_path']);
        if (!_validArtworkPath(path)) throw _invalidResponse;
        final language = _optionalText(result['iso_639_1']);
        if (language != null && !RegExp(r'^[a-z]{2}$').hasMatch(language)) {
          throw _invalidResponse;
        }
        final candidate = CatalogArtworkCandidate(
          filePath: path,
          kind: kind,
          width: _positiveInt(result['width']),
          height: _positiveInt(result['height']),
          language: language,
        );
        if (paths.add(path)) candidates.add(candidate);
      }
    }
    return List.unmodifiable(candidates);
  }

  @override
  Future<Uint8List> downloadArtwork(CatalogArtworkCandidate candidate) async {
    if (!_validArtworkPath(candidate.filePath)) {
      throw const CatalogMetadataException('The selected artwork is invalid.');
    }
    if (_disposed) {
      throw const CatalogMetadataException(
        'The metadata connection is closed.',
      );
    }
    try {
      final response = await _transport
          .get(
            uri: Uri.parse(candidate.downloadUrl),
            // The public image CDN must never receive the API bearer token.
            headers: const {'Accept': 'image/jpeg,image/png,image/webp'},
            timeout: timeout,
            maxResponseBytes: maxArtworkBytes,
          )
          .timeout(timeout);
      if (response.statusCode == 404) {
        throw const CatalogMetadataException(
          'This artwork is no longer available. Refresh and choose another.',
        );
      }
      if (response.statusCode == 429) {
        throw const CatalogMetadataException(
          'TMDB has received too many requests. Try again later.',
        );
      }
      if (response.statusCode != 200) {
        throw const CatalogMetadataException(
          'TMDB artwork is unavailable right now. Try again later.',
        );
      }
      if (response.body.length > maxArtworkBytes ||
          !_isRasterImage(response.body)) {
        throw const CatalogMetadataException(
          'TMDB returned invalid artwork. Refresh and choose another.',
        );
      }
      return Uint8List.fromList(response.body);
    } on CatalogMetadataException {
      rethrow;
    } on TimeoutException {
      throw const CatalogMetadataException(
        'The artwork download timed out. Try again.',
      );
    } on FormatException {
      throw const CatalogMetadataException(
        'The artwork could not be downloaded. Choose another image.',
      );
    } catch (_) {
      throw const CatalogMetadataException(
        'Could not download the artwork. Check your connection and try again.',
      );
    }
  }

  static void _validateShowId(String providerId) {
    final numericId = int.tryParse(providerId);
    if (!RegExp(r'^[1-9]\d*$').hasMatch(providerId) ||
        numericId == null ||
        numericId > 2147483647) {
      throw const CatalogMetadataException('The selected show is invalid.');
    }
  }

  static bool _validArtworkPath(String path) =>
      RegExp(r'^/[A-Za-z0-9_-]+\.(jpg|jpeg|png|webp)$').hasMatch(path);

  static bool _isRasterImage(List<int> bytes) {
    if (bytes.length < 12) return false;
    final jpeg = bytes[0] == 0xff && bytes[1] == 0xd8 && bytes[2] == 0xff;
    final png =
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0d &&
        bytes[5] == 0x0a &&
        bytes[6] == 0x1a &&
        bytes[7] == 0x0a;
    final webp =
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50;
    return jpeg || png || webp;
  }

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
