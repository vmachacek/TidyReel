import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_domain/media_domain.dart';
import 'package:media_platform_storage/media_platform_storage.dart';
import 'package:pocket_cinema/features/catalog/catalog_library.dart';
import 'package:pocket_cinema/features/catalog/catalog_matching.dart';
import 'package:pocket_cinema/features/catalog/catalog_metadata.dart';
import 'package:pocket_cinema/features/catalog/library_organization_plan.dart';
import 'package:pocket_cinema/features/catalog/library_organizer.dart';
import 'package:pocket_cinema/infrastructure/android/android_storage_gateway.dart';
import 'package:pocket_cinema/infrastructure/android/pigeon_storage_platform_api.dart';

// Set ORG_GRADLE_PROJECT_POCKET_CINEMA_ORGANIZER_SMOKE=true and run with
// flutter test --no-uninstall --dart-define=ORGANIZER_FIXTURE_NAME=<fresh-name>.
// Use only these disposable text fixtures, selecting their exact tree. The
// runtime package guard prevents this test from operating in the real app.
const _fixtureName = String.fromEnvironment('ORGANIZER_FIXTURE_NAME');
const _movieSource = 'Movie.2024.1080p-GROUP.mkv';
const _subtitleSource = 'Movie.2024.1080p-GROUP.forced.en.srt';
const _showSource = 'Show.S01E01E02.1080p-WEB.mkv';
const _collisionSource = 'Collision.2024.1080p-GROUP.mkv';
const _existingCollision = 'Movies/Collision (2024)/COLLISION (2024).MKV';
const _movieDestination = 'Movies/Movie (2024)/Movie (2024).mkv';
const _subtitleDestination = 'Movies/Movie (2024)/Movie (2024).forced.en.srt';
const _showDestination = 'TV/Show (2022)/Season 01/S01E01-E02.mkv';
const _contents = <String, String>{
  _movieSource: 'tidyreel-movie-content\n',
  _subtitleSource: '1\n00:00:00,000 --> 00:00:01,000\nFixture subtitle\n',
  _showSource: 'tidyreel-show-content\n',
  _collisionSource: 'tidyreel-collision-source\n',
  _existingCollision: 'tidyreel-existing-destination-preserved\n',
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'native organizer preserves bytes, collisions, idempotence and other grants',
    (tester) async {
      expect(
        RegExp(r'^TidyReelOrganizerCheck-[0-9]+$').hasMatch(_fixtureName),
        isTrue,
        reason: 'Supply ORGANIZER_FIXTURE_NAME for a fresh disposable fixture.',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(child: Text('Select only Download/$_fixtureName')),
          ),
        ),
      );
      await tester.runAsync(() async {
        expect(
          await LibraryOrganizer.channel.invokeMethod<String>('applicationId'),
          'com.pocketcinema.app.organizercheck',
          reason: 'Run this smoke test only in its isolated Android package.',
        );
        final storage = AndroidStorageGateway(api: PigeonStoragePlatformApi());
        final organizer = LibraryOrganizer();
        final originalRoots = _success(await storage.listPersistedRoots());
        final originalUris = {
          for (final root in originalRoots) root.locator.opaqueValue,
        };
        LibraryRootLocator? fixtureRoot;
        try {
          debugPrint('ORGANIZER_SMOKE_PICKER_READY $_fixtureName');
          final selected = _success(await storage.chooseRoot());
          final uri = Uri.parse(selected.locator.opaqueValue);
          expect(uri.authority, 'com.android.externalstorage.documents');
          expect(uri.pathSegments, ['tree', 'primary:Download/$_fixtureName']);
          expect(selected.displayName, _fixtureName);
          expect(originalUris, isNot(contains(selected.locator.opaqueValue)));
          fixtureRoot = selected.locator;
          expect(await organizer.hasWriteAccess(fixtureRoot), isTrue);

          final before = await _scan(storage, fixtureRoot, 'organizer-before');
          expect(
            before.map((file) => file.relativePath).toSet(),
            _contents.keys.toSet(),
          );
          for (final file in before) {
            expect(
              await _read(storage, fixtureRoot, file),
              _contents[file.relativePath],
            );
          }
          final plan = _plan(
            fixtureRoot,
            before
                .where(
                  (file) =>
                      {_movieSource, _showSource}.contains(file.relativePath),
                )
                .toList(),
            before
                .where((file) => file.relativePath == _subtitleSource)
                .toList(),
          );
          expect(plan.plannedCount, 3);
          expect(plan.reviewCount, 0);
          expect(
            plan.items.map((item) => item.destinationRelativePath).toSet(),
            {_movieDestination, _showDestination, _subtitleDestination},
          );
          final results = await organizer.apply(root: fixtureRoot, plan: plan);
          expect(results, hasLength(3));
          expect(
            results.every((result) => result.moved),
            isTrue,
            reason: results.map((result) => result.message).join('\n'),
          );
          expect(
            results.every(
              (result) => result.newStorageKey != result.storageKey,
            ),
            isTrue,
          );

          final after = await _scan(storage, fixtureRoot, 'organizer-after');
          final afterByPath = {
            for (final file in after) file.relativePath: file,
          };
          expect(afterByPath.keys.toSet(), {
            _movieDestination,
            _subtitleDestination,
            _showDestination,
            _collisionSource,
            _existingCollision,
          });
          for (final pair in {
            _movieDestination: _movieSource,
            _subtitleDestination: _subtitleSource,
            _showDestination: _showSource,
            _collisionSource: _collisionSource,
            _existingCollision: _existingCollision,
          }.entries) {
            expect(
              await _read(storage, fixtureRoot, afterByPath[pair.key]!),
              _contents[pair.value],
            );
          }
          for (final result in results) {
            final file = afterByPath[result.destinationRelativePath]!;
            expect(result.newStorageKey, file.storageKey);
            expect(result.newParentStorageKey, file.parentStorageKey);
            expect(result.actualRelativePath, file.relativePath);
          }

          final again = _plan(
            fixtureRoot,
            after
                .where(
                  (file) => {
                    _movieDestination,
                    _showDestination,
                  }.contains(file.relativePath),
                )
                .toList(),
            [afterByPath[_subtitleDestination]!],
          );
          expect(again.plannedCount, 0);
          expect(again.unchangedCount, 3);
          expect(again.reviewCount, 0);
          expect(
            await organizer.apply(root: fixtureRoot, plan: again),
            isEmpty,
          );

          // The planner only sees the incoming collision fixture. The provider
          // must still detect and preserve an existing differently cased file.
          final collisionPlan = _plan(fixtureRoot, [
            afterByPath[_collisionSource]!,
          ], []);
          expect(collisionPlan.plannedCount, 1);
          final collision = (await organizer.apply(
            root: fixtureRoot,
            plan: collisionPlan,
          )).single;
          expect(collision.failed, isTrue);
          expect(collision.message, contains('Nothing was overwritten'));
          final finalFiles = await _scan(
            storage,
            fixtureRoot,
            'organizer-final',
          );
          expect(
            finalFiles.map((file) => file.relativePath).toSet(),
            afterByPath.keys.toSet(),
          );
          expect(
            await _read(
              storage,
              fixtureRoot,
              finalFiles.singleWhere(
                (file) => file.relativePath == _existingCollision,
              ),
            ),
            _contents[_existingCollision],
          );
          expect(
            await _read(
              storage,
              fixtureRoot,
              finalFiles.singleWhere(
                (file) => file.relativePath == _collisionSource,
              ),
            ),
            _contents[_collisionSource],
          );
          debugPrint(
            'ORGANIZER_SMOKE_FILES_VERIFIED 3 moves, 3 unchanged, 1 protected collision',
          );
        } finally {
          // Release only the fresh, exact fixture grant after its safety checks.
          if (fixtureRoot != null) {
            _success(await storage.releaseRootPermission(fixtureRoot));
          }
          final remaining = _success(await storage.listPersistedRoots());
          expect({
            for (final root in remaining) root.locator.opaqueValue,
          }, originalUris);
          debugPrint('ORGANIZER_SMOKE_ORIGINAL_GRANTS_PRESERVED');
        }
      });
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

LibraryOrganizationPlan _plan(
  LibraryRootLocator root,
  List<StorageEntrySnapshot> videos,
  List<StorageEntrySnapshot> sidecars,
) {
  final titles = groupCatalog(videos);
  return buildLibraryOrganizationPlan(
    titles: titles,
    matches: {
      for (final title in titles)
        jsonEncode([root.opaqueValue, title.id]): CatalogResolvedMatch(
          CatalogMetadataCandidate(
            providerId: title.isSeries ? '2' : '1',
            name: title.isSeries
                ? 'Show'
                : title.videos.first.file.relativePath.contains('Collision')
                ? 'Collision'
                : 'Movie',
            year: title.isSeries ? 2022 : 2024,
          ),
          const [],
        ),
    },
    scope: root.opaqueValue,
    sidecars: sidecars,
  );
}

T _success<T>(AppResult<T> result) => result.fold(
  onSuccess: (value) => value,
  onFailure: (failure) =>
      throw StateError('${failure.code}: ${failure.safeDetail}'),
);

Future<List<StorageEntrySnapshot>> _scan(
  AndroidStorageGateway storage,
  LibraryRootLocator root,
  String id,
) async {
  final entries = <StorageEntrySnapshot>[];
  var completed = false;
  await for (final event
      in storage
          .enumerateRecursively(
            root: root,
            scanId: id,
            cancellationToken: CancellationController().token,
          )
          .timeout(const Duration(seconds: 30))) {
    if (event is StorageScanBatch) entries.addAll(event.entries);
    if (event is StorageScanCompleted) completed = true;
    if (event is StorageScanFailed) throw StateError(event.failure.code);
  }
  expect(completed, isTrue);
  return entries;
}

Future<String> _read(
  AndroidStorageGateway storage,
  LibraryRootLocator root,
  StorageEntrySnapshot file,
) async => utf8.decode(
  _success(
    await storage.readSmallFile(
      root: root,
      storageKey: file.storageKey,
      maximumBytes: 1024,
    ),
  ).bytes,
);
