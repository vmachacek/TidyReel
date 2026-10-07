import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_cinema/infrastructure/android/android_media_probe.dart';
import 'package:media_domain/media_domain.dart';
import 'package:media_platform_storage/media_platform_storage.dart';

import '../../support/fake_storage_platform_api.dart';

void main() {
  test(
    'unsupported probe format is distinct from retryable IO failure',
    () async {
      final unsupportedApi = FakeStoragePlatformApi(
        probeError: PlatformException(code: 'UNSUPPORTED_PROBE_FORMAT'),
      );
      final failedApi = FakeStoragePlatformApi(
        probeError: PlatformException(
          code: 'PROBE_IO_FAILED',
          message: 'content://private/document',
        ),
      );

      final unsupported = await AndroidMediaProbe(unsupportedApi).probe(
        root: root,
        storageKey: 'provider|opaque',
        cancellationToken: CancellationController().token,
      );
      final failed = await AndroidMediaProbe(failedApi).probe(
        root: root,
        storageKey: 'provider|opaque',
        cancellationToken: CancellationController().token,
      );

      final unsupportedFailure =
          (unsupported as FailureResult<MediaProbeResult>).failure;
      final failedFailure = (failed as FailureResult<MediaProbeResult>).failure;
      expect(unsupportedFailure.code, 'PROBE_UNSUPPORTED');
      expect(unsupportedFailure.retryable, isFalse);
      expect(failedFailure.code, 'PROBE_FAILED');
      expect(failedFailure.safeDetail, isNot(contains('content://')));
    },
  );
}
