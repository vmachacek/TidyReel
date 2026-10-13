import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_platform_storage/media_platform_storage.dart';
import 'package:pocket_cinema/features/catalog/catalog_library.dart';
import 'package:pocket_cinema/features/catalog/catalog_matching.dart';
import 'package:pocket_cinema/features/catalog/catalog_metadata.dart';
import 'package:pocket_cinema/features/catalog/library_organization_plan.dart';
import 'package:pocket_cinema/features/catalog/library_organizer.dart';

const _root = LibraryRootLocator(
  storageKind: StorageKind.androidSaf,
  opaqueValue: 'content://provider/tree/media',
);

StorageEntrySnapshot _file(
  String key,
  String path, {
  String parent = 'downloads',
}) => StorageEntrySnapshot(
  storageKey: key,
  parentStorageKey: parent,
  relativePath: path,
  displayName: path.split('/').last,
  isDirectory: false,
  mimeType: null,
  sizeBytes: 4096,
  modifiedAtUtc: DateTime.utc(2026, 10, 12),
  flags: const {StorageEntryFlag.supportsRead},
);

LibraryOrganizationPlan _plan() {
  final titles = groupCatalog([
    _file('move', 'Downloads/My.Film.2020.1080p.YIFY.mp4'),
    _file('review', 'Downloads/Unknown.2021.mkv'),
    _file('unchanged', 'Movies/Another Film (2019)/Another Film (2019).mkv'),
  ]);
  return buildLibraryOrganizationPlan(
    titles: titles,
    matches: {
      jsonEncode([_root.opaqueValue, 'move']): const CatalogResolvedMatch(
        CatalogMetadataCandidate(providerId: '8', name: 'My Film', year: 2020),
        [],
        manual: true,
      ),
      jsonEncode([_root.opaqueValue, 'unchanged']): const CatalogResolvedMatch(
        CatalogMetadataCandidate(
          providerId: '9',
          name: 'Another Film',
          year: 2019,
        ),
        [],
      ),
    },
    scope: _root.opaqueValue,
    sidecars: [_file('subtitle', 'Downloads/My.Film.2020.1080p.YIFY.en.srt')],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  Object? response;

  setUp(() {
    calls.clear();
    response = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(LibraryOrganizer.channel, (call) async {
          calls.add(call);
          if (call.method == 'checkWriteAccess') return response;
          if (call.method == 'organizeFiles') return response;
          throw StateError('Unexpected organizer method: ${call.method}');
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(LibraryOrganizer.channel, null);
  });

  test(
    'write access is scoped to the exact tree and requires a true grant',
    () async {
      final organizer = LibraryOrganizer();
      for (final grant in [null, false, true]) {
        response = grant;
        expect(await organizer.hasWriteAccess(_root), grant == true);
        expect(calls.last.method, 'checkWriteAccess');
        expect(calls.last.arguments, {'treeUri': _root.opaqueValue});
      }
      expect(calls.where((call) => call.method == 'organizeFiles'), isEmpty);
    },
  );

  test(
    'only ready moves are sent with source parent IDs and subtitle dependency',
    () async {
      final plan = _plan();
      expect(plan.plannedCount, 2);
      expect(plan.reviewCount, 1);
      expect(plan.unchangedCount, 1);
      response = {
        'items': [
          for (final item in plan.items.where((item) => item.isMove))
            {
              'storageKey': item.source.storageKey,
              'destinationRelativePath': item.destinationRelativePath,
              'status': 'moved',
              'newStorageKey': 'new:${item.source.storageKey}',
              'newParentStorageKey': 'film-folder',
            },
        ],
      };
      final results = await LibraryOrganizer().apply(root: _root, plan: plan);
      expect(calls.single.method, 'organizeFiles');
      final arguments = calls.single.arguments as Map;
      expect(arguments['treeUri'], _root.opaqueValue);
      expect(arguments['items'], [
        {
          'storageKey': 'move',
          'parentStorageKey': 'downloads',
          'sourceRelativePath': 'Downloads/My.Film.2020.1080p.YIFY.mp4',
          'destinationRelativePath': 'Movies/My Film (2020)/My Film (2020).mp4',
        },
        {
          'storageKey': 'subtitle',
          'parentStorageKey': 'downloads',
          'sourceRelativePath': 'Downloads/My.Film.2020.1080p.YIFY.en.srt',
          'destinationRelativePath':
              'Movies/My Film (2020)/My Film (2020).en.srt',
          'videoStorageKey': 'move',
        },
      ]);
      expect(results.every((result) => result.moved), isTrue);
      expect(results.map((result) => result.newStorageKey), [
        'new:move',
        'new:subtitle',
      ]);
    },
  );

  test(
    'partial native results cannot masquerade as a completed batch',
    () async {
      response = {'items': []};
      await expectLater(
        LibraryOrganizer().apply(root: _root, plan: _plan()),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'ORGANIZER_RESULT_INVALID',
          ),
        ),
      );
    },
  );

  test(
    'failed rollback result retains a verified changed ID and actual path',
    () async {
      final plan = _plan();
      final moves = plan.items.where((item) => item.isMove).toList();
      response = {
        'items': [
          for (final item in moves)
            {
              'storageKey': item.source.storageKey,
              'destinationRelativePath': item.destinationRelativePath,
              'status': 'failed',
              'message': 'Move failed; the original location was restored.',
              'newStorageKey': 'restored:${item.source.storageKey}',
              'newParentStorageKey': item.source.parentStorageKey,
              'actualRelativePath': item.source.relativePath,
            },
        ],
      };
      final results = await LibraryOrganizer().apply(root: _root, plan: plan);
      expect(results.every((result) => result.failed), isTrue);
      expect(results.first.newStorageKey, 'restored:move');
      expect(results.first.actualRelativePath, moves.first.source.relativePath);
      expect(results.first.newParentStorageKey, 'downloads');
    },
  );

  for (final badResult in [
    'duplicate ID',
    'foreign destination',
    'missing new ID',
    'unknown status',
  ]) {
    test('rejects native result with $badResult', () async {
      final plan = _plan();
      final values = [
        for (final item in plan.items.where((item) => item.isMove))
          <String, Object?>{
            'storageKey': item.source.storageKey,
            'destinationRelativePath': item.destinationRelativePath,
            'status': 'moved',
            'newStorageKey': 'new:${item.source.storageKey}',
          },
      ];
      switch (badResult) {
        case 'duplicate ID':
          values[1] = Map.of(values.first);
        case 'foreign destination':
          values.first['destinationRelativePath'] = 'Movies/Other.mkv';
        case 'missing new ID':
          values.first.remove('newStorageKey');
        case 'unknown status':
          values.first['status'] = 'success';
      }
      response = {'items': values};
      await expectLater(
        LibraryOrganizer().apply(root: _root, plan: plan),
        throwsA(isA<FormatException>()),
      );
    });
  }
}
