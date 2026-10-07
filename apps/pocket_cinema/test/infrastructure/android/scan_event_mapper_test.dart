import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_cinema/infrastructure/android/android_storage_gateway.dart';
import 'package:media_domain/media_domain.dart';
import 'package:media_platform_storage/media_platform_storage.dart';

import '../../support/fake_storage_platform_api.dart';

void main() {
  test(
    'maps nullable entry metadata and ignores events after completion',
    () async {
      final controller = StreamController<Map<Object?, Object?>>();
      final gateway = AndroidStorageGateway(
        api: FakeStoragePlatformApi(),
        scanEvents: controller.stream,
      );
      final cancellation = CancellationController();
      final values = gateway
          .enumerateRecursively(
            root: root,
            scanId: 'scan-1',
            cancellationToken: cancellation.token,
          )
          .toList();

      controller.add({
        'scanId': 'scan-1',
        'eventType': 'batch',
        'entries': [
          {
            'storageKey': 'provider|opaque',
            'parentStorageKey': null,
            'relativePath': 'Movie.mkv',
            'displayName': 'Movie.mkv',
            'isDirectory': false,
            'mimeType': null,
            'sizeBytes': null,
            'modifiedAtEpochMs': null,
            'flags': 0,
          },
        ],
      });
      controller.add({'scanId': 'scan-1', 'eventType': 'completed'});
      controller.add({'scanId': 'scan-1', 'eventType': 'completed'});
      await controller.close();

      final events = await values;
      final batch = events.whereType<StorageScanBatch>().single;
      expect(batch.entries.single.sizeBytes, isNull);
      expect(batch.entries.single.modifiedAtUtc, isNull);
      expect(events.whereType<StorageScanCompleted>(), hasLength(1));
    },
  );
}
