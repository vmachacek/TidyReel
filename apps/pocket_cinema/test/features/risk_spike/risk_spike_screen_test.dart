import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_cinema/features/risk_spike/playback_session_coordinator.dart';
import 'package:pocket_cinema/features/risk_spike/risk_spike_controller.dart';
import 'package:pocket_cinema/features/risk_spike/risk_spike_screen.dart';
import 'package:pocket_cinema/features/risk_spike/risk_spike_state.dart';
import 'package:pocket_cinema/l10n/app_localizations.dart';
import 'package:media_domain/media_domain.dart';
import 'package:media_platform_storage/media_platform_storage.dart';
import 'package:media_playback/media_playback.dart';

const testRoot = AuthorizedLibraryRoot(
  locator: LibraryRootLocator(
    storageKind: StorageKind.androidSaf,
    opaqueValue: 'content://redacted/tree/root',
  ),
  displayName: 'Movies',
);

const permissionRevokedState = RiskSpikeState(
  phase: RiskSpikePhase.failure,
  root: testRoot,
  failure: AppFailure(
    code: 'STORAGE_PERMISSION_REVOKED',
    messageKey: 'rootPermissionRevoked',
    retryable: true,
  ),
);

final filesAvailableState = RiskSpikeState(
  phase: RiskSpikePhase.filesAvailable,
  root: testRoot,
  entries: [
    StorageEntrySnapshot(
      storageKey: 'provider|video',
      parentStorageKey: 'provider|folder',
      relativePath: 'Movie.mp4',
      displayName: 'Movie.mp4',
      isDirectory: false,
      mimeType: 'video/mp4',
      sizeBytes: 1024,
      modifiedAtUtc: DateTime.utc(2026),
      flags: const {StorageEntryFlag.supportsRead},
    ),
  ],
  discoveredCount: 1,
  videoCount: 1,
  scanCompleted: true,
);

void main() {
  testWidgets('permission revoked state exposes repair action', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(testApp(state: permissionRevokedState));

    expect(find.text('Folder access needs repair'), findsOneWidget);
    expect(find.byKey(const Key('repair-root-button')), findsOneWidget);
    expect(
      tester.getSemantics(find.byKey(const Key('repair-root-button'))),
      matchesSemantics(
        label: 'Choose the media folder again',
        isButton: true,
        hasEnabledState: true,
        hasTapAction: true,
        isEnabled: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('two hundred percent text scale keeps primary actions visible', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(
        state: filesAvailableState,
        textScaler: const TextScaler.linear(2),
      ),
    );

    expect(find.byKey(const Key('scan-button')), findsOneWidget);
    expect(find.byKey(const Key('media-list')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget testApp({
  required RiskSpikeState state,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  final controller = RiskSpikeController(
    storage: _NoOpStorage(),
    probe: _NoOpProbe(),
    playback: _NoOpPlayback(),
    initialState: state,
  );
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: MediaQuery(
      data: MediaQueryData(textScaler: textScaler),
      child: RiskSpikeScreen(controller: controller),
    ),
  );
}

final class _NoOpStorage implements LibraryStorageGateway {
  Never _unexpected(String call) => throw StateError('Unexpected call: $call');

  @override
  Future<AppResult<RootAccessState>> checkAccess(LibraryRootLocator root) =>
      _unexpected('checkAccess');

  @override
  Future<AppResult<AuthorizedLibraryRoot>> chooseRoot() =>
      _unexpected('chooseRoot');

  @override
  Stream<StorageScanEvent> enumerateRecursively({
    required LibraryRootLocator root,
    required String scanId,
    required CancellationToken cancellationToken,
  }) => _unexpected('enumerateRecursively');

  @override
  Future<AppResult<List<AuthorizedLibraryRoot>>> listPersistedRoots() =>
      _unexpected('listPersistedRoots');

  @override
  Future<AppResult<MediaSourceLease>> openPlaybackSource({
    required LibraryRootLocator root,
    required String storageKey,
    required PlaybackSourceStrategy strategy,
  }) => _unexpected('openPlaybackSource');

  @override
  Future<AppResult<SmallFileContent>> readSmallFile({
    required LibraryRootLocator root,
    required String storageKey,
    required int maximumBytes,
  }) => _unexpected('readSmallFile');

  @override
  Future<void> releasePlaybackSource(MediaSourceLease lease) =>
      _unexpected('releasePlaybackSource');

  @override
  Future<AppResult<void>> releaseRootPermission(LibraryRootLocator root) =>
      _unexpected('releaseRootPermission');
}

final class _NoOpProbe implements MediaProbe {
  @override
  Future<AppResult<MediaProbeResult>> probe({
    required LibraryRootLocator root,
    required String storageKey,
    required CancellationToken cancellationToken,
  }) => throw StateError('Unexpected call: probe');
}

final class _NoOpPlayback implements PlaybackSession {
  @override
  PlaybackSnapshot get snapshot => const PlaybackSnapshot.closed();

  Never _unexpected(String call) => throw StateError('Unexpected call: $call');

  @override
  Future<AppResult<void>> attachLease(
    MediaSourceLease lease, {
    Duration startPosition = Duration.zero,
  }) => _unexpected('attachLease');

  @override
  Future<AppResult<void>> attachSubtitle(
    Uint8List bytes, {
    String? languageTag,
  }) => _unexpected('attachSubtitle');

  @override
  Future<void> handleLifecycleInactive() =>
      _unexpected('handleLifecycleInactive');

  @override
  Future<AppResult<void>> pause() => _unexpected('pause');

  @override
  Future<AppResult<void>> play() => _unexpected('play');

  @override
  Future<AppResult<void>> seek(Duration position) => _unexpected('seek');

  @override
  Future<void> stop() => _unexpected('stop');
}
