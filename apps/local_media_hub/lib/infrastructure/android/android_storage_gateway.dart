import 'dart:async';

import 'package:flutter/services.dart';
import 'package:media_domain/media_domain.dart';
import 'package:media_platform_storage/media_platform_storage.dart';

import 'storage_platform_api.dart';

const storageScanEventChannelName =
    'com.tidyreel.local_media_hub/storage_scan_events';

final class AndroidStorageGateway implements LibraryStorageGateway {
  factory AndroidStorageGateway({
    required StoragePlatformApi api,
    Stream<Map<Object?, Object?>>? scanEvents,
  }) => AndroidStorageGateway._(
    api,
    scanEvents ??
        const EventChannel(storageScanEventChannelName)
            .receiveBroadcastStream()
            .cast<Map<Object?, Object?>>(),
  );

  AndroidStorageGateway._(this._api, this._scanEvents);

  static const int _scanBatchSize = 128;

  final StoragePlatformApi _api;
  final Stream<Map<Object?, Object?>> _scanEvents;

  @override
  Future<AppResult<AuthorizedLibraryRoot>> chooseRoot() async {
    try {
      final root = await _api.chooseDirectory();
      return Success<AuthorizedLibraryRoot>(_authorizedRoot(root));
    } on PlatformException catch (error) {
      return FailureResult<AuthorizedLibraryRoot>(mapPlatformFailure(error));
    } on Object {
      return const FailureResult<AuthorizedLibraryRoot>(
        AppFailure(
          code: 'STORAGE_OPERATION_FAILED',
          messageKey: 'storageOperationFailed',
          retryable: true,
          safeDetail: 'Android storage operation failed unexpectedly.',
        ),
      );
    }
  }

  @override
  Future<AppResult<List<AuthorizedLibraryRoot>>> listPersistedRoots() async {
    try {
      final roots = await _api.listPersistedPermissions();
      return Success<List<AuthorizedLibraryRoot>>(
        roots.map(_authorizedRoot).toList(growable: false),
      );
    } on PlatformException catch (error) {
      return FailureResult<List<AuthorizedLibraryRoot>>(
        mapPlatformFailure(error),
      );
    } on Object {
      return const FailureResult<List<AuthorizedLibraryRoot>>(
        AppFailure(
          code: 'STORAGE_OPERATION_FAILED',
          messageKey: 'storageOperationFailed',
          retryable: true,
          safeDetail: 'Android storage operation failed unexpectedly.',
        ),
      );
    }
  }

  @override
  Future<AppResult<RootAccessState>> checkAccess(
    LibraryRootLocator root,
  ) async {
    try {
      final access = await _api.checkRoot(root.opaqueValue);
      return Success<RootAccessState>(_rootAccessState(access.state));
    } on PlatformException catch (error) {
      return FailureResult<RootAccessState>(mapPlatformFailure(error));
    } on Object {
      return const FailureResult<RootAccessState>(
        AppFailure(
          code: 'STORAGE_OPERATION_FAILED',
          messageKey: 'storageOperationFailed',
          retryable: true,
          safeDetail: 'Android storage operation failed unexpectedly.',
        ),
      );
    }
  }

  @override
  Stream<StorageScanEvent> enumerateRecursively({
    required LibraryRootLocator root,
    required String scanId,
    required CancellationToken cancellationToken,
  }) async* {
    var terminal = false;
    try {
      await _api.startScan(root.opaqueValue, scanId, _scanBatchSize);
      unawaited(
        cancellationToken.whenCancelled.then((_) async {
          if (!terminal) {
            try {
              await _api.cancelScan(scanId);
            } on Object {
              // The native terminal event remains the source of scan state.
            }
          }
        }),
      );

      await for (final raw in _scanEvents) {
        if (terminal || raw['scanId'] != scanId) {
          continue;
        }
        final event = _mapScanEvent(raw, scanId);
        if (event == null) {
          continue;
        }
        yield event;
        terminal =
            event is StorageScanCompleted ||
            event is StorageScanCancelled ||
            event is StorageScanFailed;
        if (terminal) {
          break;
        }
      }
    } on PlatformException catch (error) {
      if (!terminal) {
        yield StorageScanFailed(scanId, mapPlatformFailure(error));
      }
    } on Object {
      if (!terminal) {
        yield StorageScanFailed(
          scanId,
          const AppFailure(
            code: 'STORAGE_OPERATION_FAILED',
            messageKey: 'storageOperationFailed',
            retryable: true,
            safeDetail: 'Android storage operation failed unexpectedly.',
          ),
        );
      }
    } finally {
      terminal = true;
    }
  }

  @override
  Future<AppResult<SmallFileContent>> readSmallFile({
    required LibraryRootLocator root,
    required String storageKey,
    required int maximumBytes,
  }) async {
    try {
      final file = await _api.readSmallFile(
        root.opaqueValue,
        storageKey,
        maximumBytes,
      );
      return Success<SmallFileContent>(SmallFileContent(file.bytes));
    } on PlatformException catch (error) {
      return FailureResult<SmallFileContent>(mapPlatformFailure(error));
    } on Object {
      return const FailureResult<SmallFileContent>(
        AppFailure(
          code: 'STORAGE_OPERATION_FAILED',
          messageKey: 'storageOperationFailed',
          retryable: true,
          safeDetail: 'Android storage operation failed unexpectedly.',
        ),
      );
    }
  }

  @override
  Future<AppResult<MediaSourceLease>> openPlaybackSource({
    required LibraryRootLocator root,
    required String storageKey,
    required PlaybackSourceStrategy strategy,
  }) async {
    try {
      final lease = await _api.openPlaybackSource(
        root.opaqueValue,
        storageKey,
        strategy.name,
      );
      return Success<MediaSourceLease>(
        MediaSourceLease(
          leaseId: lease.leaseId,
          sourceUri: lease.sourceUri,
          strategy: _playbackStrategy(lease.strategy),
        ),
      );
    } on PlatformException catch (error) {
      return FailureResult<MediaSourceLease>(mapPlatformFailure(error));
    } on Object {
      return const FailureResult<MediaSourceLease>(
        AppFailure(
          code: 'STORAGE_OPERATION_FAILED',
          messageKey: 'storageOperationFailed',
          retryable: true,
          safeDetail: 'Android storage operation failed unexpectedly.',
        ),
      );
    }
  }

  @override
  Future<void> releasePlaybackSource(MediaSourceLease lease) =>
      _api.closePlaybackSource(lease.leaseId);

  @override
  Future<AppResult<void>> releaseRootPermission(LibraryRootLocator root) async {
    try {
      await _api.releasePermission(root.opaqueValue);
      return const Success<void>(null);
    } on PlatformException catch (error) {
      return FailureResult<void>(mapPlatformFailure(error));
    } on Object {
      return const FailureResult<void>(
        AppFailure(
          code: 'STORAGE_OPERATION_FAILED',
          messageKey: 'storageOperationFailed',
          retryable: true,
          safeDetail: 'Android storage operation failed unexpectedly.',
        ),
      );
    }
  }

  AuthorizedLibraryRoot _authorizedRoot(AuthorizedRootDto root) =>
      AuthorizedLibraryRoot(
        locator: LibraryRootLocator(
          storageKind: StorageKind.androidSaf,
          opaqueValue: root.treeUri,
        ),
        displayName: root.displayName,
      );

  RootAccessState _rootAccessState(String state) => switch (state) {
    'available' => RootAccessState.available,
    'permissionRevoked' => RootAccessState.permissionRevoked,
    'unavailable' => RootAccessState.unavailable,
    _ => throw FormatException('Unknown root access state.'),
  };

  PlaybackSourceStrategy _playbackStrategy(String strategy) =>
      PlaybackSourceStrategy.values.firstWhere(
        (value) => value.name == strategy,
        orElse: () => throw FormatException('Unknown playback strategy.'),
      );

  StorageScanEvent? _mapScanEvent(Map<Object?, Object?> raw, String scanId) =>
      switch (raw['eventType']) {
        'started' => StorageScanStarted(scanId),
        'batch' => StorageScanBatch(scanId, _mapEntries(raw['entries'])),
        'progress' => StorageScanProgress(
          scanId,
          (raw['visitedEntries'] as num?)?.toInt() ?? 0,
        ),
        'warning' => StorageScanWarning(scanId, _eventFailure(raw, true)),
        'completed' => StorageScanCompleted(scanId),
        'cancelled' => StorageScanCancelled(scanId),
        'failed' => StorageScanFailed(scanId, _eventFailure(raw, true)),
        _ => null,
      };

  List<StorageEntrySnapshot> _mapEntries(Object? rawEntries) {
    final entries = rawEntries as List<Object?>? ?? const <Object?>[];
    return entries
        .map((entry) => _mapEntry(entry! as Map<Object?, Object?>))
        .toList(growable: false);
  }

  StorageEntrySnapshot _mapEntry(Map<Object?, Object?> raw) {
    final rawFlags = (raw['flags'] as num?)?.toInt() ?? 0;
    final flags = <StorageEntryFlag>{
      if (rawFlags & 1 != 0) StorageEntryFlag.supportsRead,
      if (rawFlags & 2 != 0) StorageEntryFlag.virtualDocument,
    };
    final modifiedAtEpochMs = (raw['modifiedAtEpochMs'] as num?)?.toInt();
    return StorageEntrySnapshot(
      storageKey: raw['storageKey']! as String,
      parentStorageKey: raw['parentStorageKey'] as String?,
      relativePath: raw['relativePath']! as String,
      displayName: raw['displayName']! as String,
      isDirectory: raw['isDirectory']! as bool,
      mimeType: raw['mimeType'] as String?,
      sizeBytes: (raw['sizeBytes'] as num?)?.toInt(),
      modifiedAtUtc: modifiedAtEpochMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(modifiedAtEpochMs, isUtc: true),
      flags: flags,
    );
  }

  AppFailure _eventFailure(Map<Object?, Object?> raw, bool retryable) =>
      AppFailure(
        code: raw['code'] as String? ?? 'STORAGE_OPERATION_FAILED',
        messageKey: raw['messageKey'] as String? ?? 'storageOperationFailed',
        retryable: retryable,
        safeDetail: 'Android storage scan reported a controlled failure.',
      );
}

AppFailure mapPlatformFailure(PlatformException exception) {
  return switch (exception.code) {
    'PERMISSION_REVOKED' => const AppFailure(
      code: 'STORAGE_PERMISSION_REVOKED',
      messageKey: 'rootPermissionRevoked',
      retryable: true,
    ),
    'FILE_UNAVAILABLE' => const AppFailure(
      code: 'FILE_UNAVAILABLE',
      messageKey: 'fileUnavailable',
      retryable: true,
    ),
    'FILE_TOO_LARGE' => const AppFailure(
      code: 'SMALL_FILE_LIMIT_EXCEEDED',
      messageKey: 'subtitleTooLarge',
      retryable: false,
    ),
    _ => AppFailure(
      code: 'STORAGE_OPERATION_FAILED',
      messageKey: 'storageOperationFailed',
      retryable: true,
      safeDetail: 'Android storage operation failed with ${exception.code}.',
    ),
  };
}
