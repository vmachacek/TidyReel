/// Provider-independent metadata for the display catalog.
///
/// These values never change storage paths or the numbering parsed from a file.
enum CatalogMediaKind { movie, series }

class CatalogMetadataCandidate {
  const CatalogMetadataCandidate({
    required this.providerId,
    required this.name,
    this.originalName,
    this.year,
    this.overview,
  });

  final String providerId;
  final String name;
  final String? originalName;
  final int? year;
  final String? overview;
}

class CatalogEpisodeMetadata {
  const CatalogEpisodeMetadata({
    required this.season,
    required this.number,
    required this.name,
  });

  final int season;
  final int number;
  final String name;
}

abstract interface class CatalogMetadataSource {
  Future<List<CatalogMetadataCandidate>> search({
    required String title,
    required CatalogMediaKind kind,
    int? year,
  });

  Future<List<CatalogEpisodeMetadata>> episodes({
    required String providerId,
    required int season,
  });

  void dispose();
}

/// A failure safe to show in the catalog, without URLs or authentication data.
class CatalogMetadataException implements Exception {
  const CatalogMetadataException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Normalize presentation differences without dropping words or accents.
String normalizeCatalogMetadataTitle(String title) => title
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
    .trim();

/// Automatically choose only an unambiguous exact title and compatible year.
///
/// Remakes, fuzzy matches, and missing years require a user selection. A known
/// local year must equal the provider's release/first-air year. Without a local
/// year, multiple exact results remain ambiguous regardless of popularity.
CatalogMetadataCandidate? selectCatalogCandidate({
  required String title,
  int? year,
  required List<CatalogMetadataCandidate> candidates,
}) {
  final normalized = normalizeCatalogMetadataTitle(title);
  if (normalized.isEmpty) return null;

  CatalogMetadataCandidate? selected;
  for (final candidate in candidates) {
    if (candidate.providerId.isEmpty || candidate.name.trim().isEmpty) continue;
    if (year != null && candidate.year != year) continue;
    final matches =
        normalizeCatalogMetadataTitle(candidate.name) == normalized ||
        (candidate.originalName != null &&
            normalizeCatalogMetadataTitle(candidate.originalName!) ==
                normalized);
    if (!matches) continue;
    if (selected != null) return null;
    selected = candidate;
  }
  return selected;
}
