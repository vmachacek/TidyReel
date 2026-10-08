import 'dart:isolate';

import 'package:media_platform_storage/media_platform_storage.dart';

import 'catalog_library.dart';
import 'catalog_matching.dart';

typedef CatalogDiscoveryWorker = Future<CatalogDiscoveryResult> Function(
  CatalogDiscoveryRequest request,
);

class CatalogDiscoveryRequest {
  const CatalogDiscoveryRequest({
    required this.scope,
    required this.localTitles,
    required this.matching,
    this.entries,
  });

  final String scope;
  final List<StorageEntrySnapshot>? entries;
  final List<CatalogTitle> localTitles;
  final CatalogMatchingSnapshot matching;
}

class CatalogDiscoveryResult {
  const CatalogDiscoveryResult({
    required this.localTitles,
    required this.titles,
    required this.workerIsolateName,
  });

  final List<CatalogTitle> localTitles;
  final List<CatalogTitle> titles;
  final String? workerIsolateName;
}

/// Isolate.run spawns a real worker even when called from Flutter's UI isolate.
/// The callback captures only this request, never the library or its channels.
Future<CatalogDiscoveryResult> discoverCatalogInBackground(
  CatalogDiscoveryRequest request,
) => Isolate.run(
  () => _discoverCatalog(request),
  debugName: 'catalog-discovery',
);

CatalogDiscoveryResult _discoverCatalog(CatalogDiscoveryRequest request) {
  final entries = request.entries;
  final local = entries == null
      ? request.localTitles
      : List<CatalogTitle>.unmodifiable(
          groupCatalog(entries, previousTitles: request.localTitles),
        );
  return CatalogDiscoveryResult(
    localTitles: local,
    titles: List<CatalogTitle>.unmodifiable(
      request.matching.apply(local, request.scope),
    ),
    workerIsolateName: Isolate.current.debugName,
  );
}
