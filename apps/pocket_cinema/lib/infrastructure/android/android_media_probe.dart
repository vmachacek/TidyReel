import 'package:flutter/services.dart';
import 'package:media_domain/media_domain.dart';
import 'package:media_platform_storage/media_platform_storage.dart';

import 'storage_platform_api.dart';

final class AndroidMediaProbe implements MediaProbe {
  const AndroidMediaProbe(this._api);

  final StoragePlatformApi _api;

  @override
  Future<AppResult<MediaProbeResult>> probe({
    required LibraryRootLocator root,
    required String storageKey,
    required CancellationToken cancellationToken,
  }) async {
    if (cancellationToken.isCancelled) {
      return const FailureResult<MediaProbeResult>(_cancelledFailure);
    }
    try {
      final result = await _api.probeFile(root.opaqueValue, storageKey);
      if (cancellationToken.isCancelled) {
        return const FailureResult<MediaProbeResult>(_cancelledFailure);
      }
      return Success<MediaProbeResult>(
        MediaProbeResult(
          duration: result.durationMs == null
              ? null
              : Duration(milliseconds: result.durationMs!),
          containerFormat: result.containerFormat,
          width: result.width,
          height: result.height,
          rotationDegrees: result.rotationDegrees,
          videoCodec: result.videoCodec,
          audioCodecSummary: result.audioCodecSummary,
          streamCount: result.streamCount,
        ),
      );
    } on PlatformException catch (error) {
      return FailureResult<MediaProbeResult>(_mapProbeFailure(error));
    } on Object {
      return const FailureResult<MediaProbeResult>(
        AppFailure(
          code: 'PROBE_FAILED',
          messageKey: 'probeFailed',
          retryable: true,
          safeDetail: 'Android media probing failed unexpectedly.',
        ),
      );
    }
  }
}

const _cancelledFailure = AppFailure(
  code: 'PROBE_CANCELLED',
  messageKey: 'probeCancelled',
  retryable: true,
);

AppFailure _mapProbeFailure(PlatformException error) => switch (error.code) {
  'UNSUPPORTED_PROBE_FORMAT' => const AppFailure(
    code: 'PROBE_UNSUPPORTED',
    messageKey: 'probeUnsupported',
    retryable: false,
  ),
  'FILE_UNAVAILABLE' => const AppFailure(
    code: 'FILE_UNAVAILABLE',
    messageKey: 'fileUnavailable',
    retryable: true,
  ),
  'PERMISSION_REVOKED' => const AppFailure(
    code: 'STORAGE_PERMISSION_REVOKED',
    messageKey: 'rootPermissionRevoked',
    retryable: true,
  ),
  'PROBE_IO_FAILED' || 'PROBE_FAILED' => AppFailure(
    code: 'PROBE_FAILED',
    messageKey: 'probeFailed',
    retryable: true,
    safeDetail: 'Android media probing failed with ${error.code}.',
  ),
  _ => AppFailure(
    code: 'PROBE_FAILED',
    messageKey: 'probeFailed',
    retryable: true,
    safeDetail: 'Android media probing failed with ${error.code}.',
  ),
};
