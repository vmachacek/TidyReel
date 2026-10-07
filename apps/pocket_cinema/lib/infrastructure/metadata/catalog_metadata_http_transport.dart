import 'dart:async';
import 'dart:io';

class CatalogMetadataHttpResponse {
  const CatalogMetadataHttpResponse({
    required this.statusCode,
    required this.body,
  });

  final int statusCode;
  final List<int> body;
}

/// Injectable so metadata tests never need the network or a real access token.
abstract interface class CatalogMetadataHttpTransport {
  Future<CatalogMetadataHttpResponse> get({
    required Uri uri,
    required Map<String, String> headers,
    required Duration timeout,
    required int maxResponseBytes,
  });

  void dispose();
}

class IoCatalogMetadataHttpTransport implements CatalogMetadataHttpTransport {
  IoCatalogMetadataHttpTransport({HttpClient? client})
    : _client = client ?? HttpClient();

  final HttpClient _client;
  bool _disposed = false;

  @override
  Future<CatalogMetadataHttpResponse> get({
    required Uri uri,
    required Map<String, String> headers,
    required Duration timeout,
    required int maxResponseBytes,
  }) async {
    if (_disposed) throw StateError('Metadata connection is closed.');
    HttpClientRequest? request;
    var completed = false;

    Future<CatalogMetadataHttpResponse> send() async {
      final opened = await _client.getUrl(uri);
      request = opened;
      if (completed) {
        opened.abort();
        throw StateError('Metadata request expired.');
      }
      // Never forward a bearer token to a redirect target.
      opened.followRedirects = false;
      headers.forEach(opened.headers.set);
      final response = await opened.close();
      if (response.contentLength > maxResponseBytes) {
        opened.abort();
        throw const FormatException('Metadata response is too large.');
      }
      final body = <int>[];
      await for (final chunk in response) {
        if (body.length + chunk.length > maxResponseBytes) {
          opened.abort();
          throw const FormatException('Metadata response is too large.');
        }
        body.addAll(chunk);
      }
      return CatalogMetadataHttpResponse(
        statusCode: response.statusCode,
        body: body,
      );
    }

    try {
      return await send().timeout(timeout);
    } on TimeoutException {
      request?.abort();
      rethrow;
    } finally {
      completed = true;
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _client.close(force: true);
  }
}
