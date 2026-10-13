import 'package:flutter/services.dart';
import 'package:media_platform_storage/media_platform_storage.dart';

import 'library_organization_plan.dart';

class LibraryOrganizationResult {
  const LibraryOrganizationResult({
    required this.storageKey,
    required this.destinationRelativePath,
    required this.status,
    this.message,
    this.newStorageKey,
    this.newParentStorageKey,
    this.actualRelativePath,
  });

  final String storageKey, destinationRelativePath, status;
  final String? message, newStorageKey, newParentStorageKey, actualRelativePath;
  bool get moved => status == 'moved';
  bool get failed => status == 'failed';
}

class LibraryOrganizer {
  static const channel = MethodChannel('com.pocketcinema.app/organizer');

  Future<bool> hasWriteAccess(LibraryRootLocator root) async =>
      await channel.invokeMethod<bool>('checkWriteAccess', {
        'treeUri': root.opaqueValue,
      }) ==
      true;

  Future<List<LibraryOrganizationResult>> apply({
    required LibraryRootLocator root,
    required LibraryOrganizationPlan plan,
  }) async {
    final moves = plan.items.where((item) => item.isMove).toList();
    final raw = await channel.invokeMapMethod<String, Object?>(
      'organizeFiles',
      {
        'treeUri': root.opaqueValue,
        'items': [
          for (final item in moves)
            {
              'storageKey': item.source.storageKey,
              'parentStorageKey': item.source.parentStorageKey,
              'sourceRelativePath': item.source.relativePath,
              'destinationRelativePath': item.destinationRelativePath,
              if (item.videoStorageKey != null &&
                  moves.any(
                    (video) => video.source.storageKey == item.videoStorageKey,
                  ))
                'videoStorageKey': item.videoStorageKey,
            },
        ],
      },
    );
    final results = raw?['items'];
    if (results is! List || results.length != moves.length) {
      throw PlatformException(
        code: 'ORGANIZER_RESULT_INVALID',
        message: 'Could not verify all moves. Rescan the library before trying again.',
      );
    }
    final remaining = {for (final item in moves) item.source.storageKey: item};
    return results.map((value) {
      if (value is! Map) throw const FormatException('Invalid move result.');
      final key = value['storageKey'];
      final item = remaining.remove(key);
      final status = value['status'];
      if (key is! String ||
          item == null ||
          value['destinationRelativePath'] != item.destinationRelativePath ||
          !['moved', 'unchanged', 'failed'].contains(status) ||
          (status == 'moved' && value['newStorageKey'] is! String)) {
        throw const FormatException('Could not verify a move result.');
      }
      return LibraryOrganizationResult(
        storageKey: key,
        destinationRelativePath: item.destinationRelativePath!,
        status: status as String,
        message: value['message'] as String?,
        newStorageKey: value['newStorageKey'] as String?,
        newParentStorageKey: value['newParentStorageKey'] as String?,
        actualRelativePath: value['actualRelativePath'] as String?,
      );
    }).toList();
  }
}
