import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_cinema/features/catalog/catalog_metadata.dart';

CatalogMetadataCandidate candidate(
  String id,
  String name, {
  int? year,
  String? originalName,
}) => CatalogMetadataCandidate(
  providerId: id,
  name: name,
  year: year,
  originalName: originalName,
);

void main() {
  test('Matches case and filename separators without fuzzy guessing', () {
    final match = candidate('1', 'Mr. Robot', year: 2015);
    expect(
      selectCatalogCandidate(
        title: 'mr_robot',
        year: 2015,
        candidates: [candidate('2', 'Robot'), match],
      ),
      same(match),
    );
    expect(
      selectCatalogCandidate(title: 'Mr Robto', candidates: [match]),
      isNull,
    );
    expect(selectCatalogCandidate(title: 'Robot', candidates: [match]), isNull);
  });

  test(
    'Matches the original title while retaining the provider display name',
    () {
      final match = candidate('1', 'Spirited Away', originalName: '千と千尋の神隠し');
      expect(
        selectCatalogCandidate(title: '千と千尋の神隠し', candidates: [match]),
        same(match),
      );
      expect(normalizeCatalogMetadataTitle('Amélie'), 'amélie');
      expect(
        selectCatalogCandidate(
          title: 'Amelie',
          candidates: [candidate('2', 'Amélie')],
        ),
        isNull,
      );
    },
  );

  test('Requires a provider year when the local title has a year', () {
    for (final year in [null, 2017]) {
      expect(
        selectCatalogCandidate(
          title: 'Arrival',
          year: 2016,
          candidates: [candidate('1', 'Arrival', year: year)],
        ),
        isNull,
      );
    }
  });

  test('Rejects remake ambiguity but an exact year can resolve it', () {
    final original = candidate('1', 'The Office', year: 2001);
    final remake = candidate('2', 'The Office', year: 2005);
    final candidates = [original, remake];
    expect(
      selectCatalogCandidate(title: 'The Office', candidates: candidates),
      isNull,
    );
    expect(
      selectCatalogCandidate(
        title: 'The Office',
        year: 2005,
        candidates: candidates,
      ),
      same(remake),
    );
  });

  test('Rejects duplicate and original-name ambiguity', () {
    final first = candidate('1', 'Dark', year: 2017);
    for (final other in [
      first,
      candidate('2', 'Dark', year: 2017),
      candidate('3', 'Another name', originalName: 'Dark', year: 2017),
    ]) {
      expect(
        selectCatalogCandidate(
          title: 'Dark',
          year: 2017,
          candidates: [first, other],
        ),
        isNull,
      );
    }
  });

  test('Does not match blank titles or candidates missing an identity', () {
    expect(
      selectCatalogCandidate(title: '---', candidates: [candidate('1', '---')]),
      isNull,
    );
    expect(
      selectCatalogCandidate(
        title: 'Arrival',
        candidates: [candidate('', 'Arrival')],
      ),
      isNull,
    );
  });
}
