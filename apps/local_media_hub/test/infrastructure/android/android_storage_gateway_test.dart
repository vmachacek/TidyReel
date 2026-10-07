import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_media_hub/infrastructure/android/android_storage_gateway.dart';
import 'package:media_domain/media_domain.dart';
import 'package:media_platform_storage/media_platform_storage.dart';

import '../../support/fake_storage_platform_api.dart';

void main() {
  test('platform exception becomes a redacted typed failure', () async {
    final api = FakeStoragePlatformApi(
      chooseError: PlatformException(
        code: 'PERMISSION_REVOKED',
        message: 'content://private/tree/id',
      ),
    );
    final gateway = AndroidStorageGateway(
      api: api,
      scanEvents: const Stream.empty(),
    );

    final result = await gateway.chooseRoot();

    final failure = (result as FailureResult<AuthorizedLibraryRoot>).failure;
    expect(failure.code, 'STORAGE_PERMISSION_REVOKED');
    expect(failure.safeDetail, isNot(contains('content://')));
  });

  test('unknown scan ids and events after completion are ignored', () async {
    final events = StreamController<Map<Object?, Object?>>();
    final gateway = AndroidStorageGateway(
      api: FakeStoragePlatformApi(),
      scanEvents: events.stream,
    );
    final token = CancellationController();
    final received = <StorageScanEvent>[];
    final subscription = gateway
        .enumerateRecursively(
          root: root,
          scanId: 'known',
          cancellationToken: token.token,
        )
        .listen(received.add);

    events.add({'scanId': 'other', 'eventType': 'completed'});
    events.add({'scanId': 'known', 'eventType': 'completed'});
    events.add({
      'scanId': 'known',
      'eventType': 'batch',
      'entries': <Object?>[],
    });
    await events.close();
    await subscription.asFuture<void>();

    expect(received, hasLength(1));
    expect(received.single, isA<StorageScanCompleted>());
  });

  test('malformed native events fail the active scan safely', () async {
    final events = StreamController<Map<Object?, Object?>>();
    final gateway = AndroidStorageGateway(
      api: FakeStoragePlatformApi(),
      scanEvents: events.stream,
    );

    final values = gateway
        .enumerateRecursively(
          root: root,
          scanId: 'known',
          cancellationToken: CancellationController().token,
        )
        .toList();

    events.add({
      'scanId': 'known',
      'eventType': 'batch',
      'entries': <Object?>[null],
    });
    await events.close();

    final failure = (await values).single as StorageScanFailed;
    expect(failure.scanId, 'known');
    expect(failure.failure.safeDetail, isNot(contains('content://')));
  });
}

const root = LibraryRootLocator(
  storageKind: StorageKind.androidSaf,
  opaqueValue: 'content://redacted-tree',
);
