import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_cinema/infrastructure/metadata/catalog_metadata_http_transport.dart';

class FakeHeaders implements HttpHeaders {
  final values = <String, Object>{};
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeResponse extends Stream<List<int>> implements HttpClientResponse {
  FakeResponse(this.stream, {this.contentLength = -1, this.statusCode = 200});
  final Stream<List<int>> stream;
  @override
  final int contentLength;
  @override
  final int statusCode;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeRequest implements HttpClientRequest {
  FakeRequest(this.response);
  final HttpClientResponse response;
  @override
  final FakeHeaders headers = FakeHeaders();
  @override
  bool followRedirects = true;
  int abortCount = 0;

  @override
  Future<HttpClientResponse> close() async => response;
  @override
  void abort([Object? exception, StackTrace? stackTrace]) => abortCount++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeClient implements HttpClient {
  FakeClient(this.opened);
  final Future<HttpClientRequest> opened;
  final requests = <Uri>[];
  int closeCount = 0;
  bool? forced;

  @override
  Future<HttpClientRequest> getUrl(Uri uri) {
    requests.add(uri);
    return opened;
  }

  @override
  void close({bool force = false}) {
    closeCount++;
    forced = force;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<CatalogMetadataHttpResponse> get(
  IoCatalogMetadataHttpTransport transport, {
  Duration timeout = const Duration(seconds: 1),
  int maximum = 10,
}) => transport.get(
  uri: Uri.https('api.themoviedb.org', '/3/search/movie'),
  headers: {'Authorization': 'Bearer test-token'},
  timeout: timeout,
  maxResponseBytes: maximum,
);

void main() {
  test(
    'Disables redirects and supplies headers without changing response bytes',
    () async {
      final request = FakeRequest(
        FakeResponse(
          Stream.fromIterable([
            [1, 2],
            [3],
          ]),
        ),
      );
      final client = FakeClient(Future.value(request));
      final transport = IoCatalogMetadataHttpTransport(client: client);
      addTearDown(transport.dispose);
      final result = await get(transport);
      expect(request.followRedirects, isFalse);
      expect(request.headers.values['Authorization'], 'Bearer test-token');
      expect(result.body, [1, 2, 3]);
      expect(result.statusCode, 200);
    },
  );

  test(
    'Aborts before reading a response declaring an oversized body',
    () async {
      final request = FakeRequest(
        FakeResponse(const Stream.empty(), contentLength: 11),
      );
      final transport = IoCatalogMetadataHttpTransport(
        client: FakeClient(Future.value(request)),
      );
      addTearDown(transport.dispose);
      await expectLater(get(transport), throwsFormatException);
      expect(request.abortCount, 1);
    },
  );

  test('Caps streamed bytes even without a Content-Length header', () async {
    final request = FakeRequest(
      FakeResponse(
        Stream.fromIterable([
          [1, 2, 3],
          [4, 5, 6],
        ]),
      ),
    );
    final transport = IoCatalogMetadataHttpTransport(
      client: FakeClient(Future.value(request)),
    );
    addTearDown(transport.dispose);
    await expectLater(get(transport, maximum: 5), throwsFormatException);
    expect(request.abortCount, 1);
  });

  test('Aborts a request whose response body times out', () async {
    final body = StreamController<List<int>>();
    final request = FakeRequest(FakeResponse(body.stream));
    final transport = IoCatalogMetadataHttpTransport(
      client: FakeClient(Future.value(request)),
    );
    addTearDown(transport.dispose);
    await expectLater(
      get(transport, timeout: const Duration(milliseconds: 1)),
      throwsA(isA<TimeoutException>()),
    );
    expect(request.abortCount, 1);
    await body.close();
  });

  test('Aborts a connection that opens after its timeout', () async {
    final opened = Completer<HttpClientRequest>();
    final request = FakeRequest(FakeResponse(const Stream.empty()));
    final transport = IoCatalogMetadataHttpTransport(
      client: FakeClient(opened.future),
    );
    addTearDown(transport.dispose);
    await expectLater(
      get(transport, timeout: const Duration(milliseconds: 1)),
      throwsA(isA<TimeoutException>()),
    );
    opened.complete(request);
    await Future<void>.delayed(Duration.zero);
    expect(request.abortCount, 1);
    expect(request.headers.values, isEmpty);
  });

  test('Disposes once and closes all connections', () async {
    final client = FakeClient(
      Future.value(FakeRequest(FakeResponse(const Stream.empty()))),
    );
    final transport = IoCatalogMetadataHttpTransport(client: client);
    transport.dispose();
    transport.dispose();
    expect(client.closeCount, 1);
    expect(client.forced, isTrue);
    await expectLater(get(transport), throwsStateError);
    expect(client.requests, isEmpty);
  });
}
