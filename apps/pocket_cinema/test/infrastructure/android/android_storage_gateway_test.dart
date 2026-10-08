import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_cinema/infrastructure/android/android_storage_gateway.dart';
import 'package:media_domain/media_domain.dart';
import 'package:media_platform_storage/media_platform_storage.dart';

import '../../support/fake_storage_platform_api.dart';

void main() {
  test('events published before startScan returns are buffered', () async {
    final events = StreamController<Map<Object?, Object?>>.broadcast(
      sync: true,
    );
    final cancelledIds = <String>[];
    final gateway = AndroidStorageGateway(
      api: FakeStoragePlatformApi(
        onStartScan: (scanId) async {
          expect(events.hasListener, isTrue);
          events.add({
            'scanId': scanId,
            'eventType': 'batch',
            'entries': <Object?>[],
          });
          events.add({'scanId': scanId, 'eventType': 'completed'});
        },
        onCancelScan: (scanId) async => cancelledIds.add(scanId),
      ),
      scanEvents: events.stream,
    );

    final received = await gateway
        .enumerateRecursively(
          root: root,
          scanId: 'fast',
          cancellationToken: CancellationController().token,
        )
        .toList()
        .timeout(const Duration(seconds: 2));

    expect(received, [isA<StorageScanBatch>(), isA<StorageScanCompleted>()]);
    expect(cancelledIds, isEmpty);
    expect(events.hasListener, isFalse);
    await events.close();
  });

  test('failed scan startup releases the event subscription', () async {
    final events = StreamController<Map<Object?, Object?>>.broadcast();
    final gateway = AndroidStorageGateway(
      api: FakeStoragePlatformApi(
        onStartScan: (_) async {
          throw PlatformException(code: 'PERMISSION_REVOKED');
        },
      ),
      scanEvents: events.stream,
    );

    final received = await gateway
        .enumerateRecursively(
          root: root,
          scanId: 'failed',
          cancellationToken: CancellationController().token,
        )
        .toList();

    expect(received.single, isA<StorageScanFailed>());
    expect(events.hasListener, isFalse);
    await events.close();
  });

  test(
    'consumer cancellation stops the native scan and releases events',
    () async {
      final events = StreamController<Map<Object?, Object?>>.broadcast();
      final started = Completer<void>();
      final cancelledIds = <String>[];
      final gateway = AndroidStorageGateway(
        api: FakeStoragePlatformApi(
          onStartScan: (_) async => started.complete(),
          onCancelScan: (scanId) async => cancelledIds.add(scanId),
        ),
        scanEvents: events.stream,
      );
      final subscription = gateway
          .enumerateRecursively(
            root: root,
            scanId: 'abandoned',
            cancellationToken: CancellationController().token,
          )
          .listen((_) {});
      await started.future;
      await Future<void>.delayed(Duration.zero);

      await subscription.cancel().timeout(const Duration(seconds: 2));

      expect(cancelledIds, ['abandoned']);
      expect(events.hasListener, isFalse);
      await events.close();
    },
  );

  test(
    'cancellation during startup reaches the registered native scan',
    () async {
      final events = StreamController<Map<Object?, Object?>>.broadcast();
      final starting = Completer<void>();
      final finishStartup = Completer<void>();
      final cancelledIds = <String>[];
      final cancellation = CancellationController();
      final gateway = AndroidStorageGateway(
        api: FakeStoragePlatformApi(
          onStartScan: (_) async {
            starting.complete();
            await finishStartup.future;
          },
          onCancelScan: (scanId) async {
            cancelledIds.add(scanId);
            events.add({'scanId': scanId, 'eventType': 'cancelled'});
          },
        ),
        scanEvents: events.stream,
      );
      final received = gateway
          .enumerateRecursively(
            root: root,
            scanId: 'cancelled',
            cancellationToken: cancellation.token,
          )
          .toList();
      await starting.future;
      cancellation.cancel();
      await Future<void>.delayed(Duration.zero);
      expect(cancelledIds, isEmpty);
      finishStartup.complete();

      expect(
        (await received.timeout(const Duration(seconds: 2))).single,
        isA<StorageScanCancelled>(),
      );
      expect(cancelledIds, ['cancelled']);
      expect(events.hasListener, isFalse);
      await events.close();
    },
  );

  test(
    'consumer cancellation during startup still stops native work',
    () async {
      final events = StreamController<Map<Object?, Object?>>.broadcast();
      final starting = Completer<void>();
      final finishStartup = Completer<void>();
      final cancelled = Completer<String>();
      final gateway = AndroidStorageGateway(
        api: FakeStoragePlatformApi(
          onStartScan: (_) async {
            starting.complete();
            await finishStartup.future;
          },
          onCancelScan: (scanId) async => cancelled.complete(scanId),
        ),
        scanEvents: events.stream,
      );
      final subscription = gateway
          .enumerateRecursively(
            root: root,
            scanId: 'abandoned-startup',
            cancellationToken: CancellationController().token,
          )
          .listen((_) {});
      await starting.future;

      await subscription.cancel().timeout(const Duration(seconds: 2));
      expect(events.hasListener, isFalse);
      finishStartup.complete();

      expect(
        await cancelled.future.timeout(const Duration(seconds: 2)),
        'abandoned-startup',
      );
      await events.close();
    },
  );

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
