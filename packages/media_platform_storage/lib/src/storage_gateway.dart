import 'package:media_domain/media_domain.dart';

import 'storage_models.dart';

abstract interface class LibraryStorageGateway {
  Future<AppResult<AuthorizedLibraryRoot>> chooseRoot();

  Future<AppResult<List<AuthorizedLibraryRoot>>> listPersistedRoots();

  Future<AppResult<RootAccessState>> checkAccess(LibraryRootLocator root);

  Stream<StorageScanEvent> enumerateRecursively({
    required LibraryRootLocator root,
    required String scanId,
    required CancellationToken cancellationToken,
  });

  Future<AppResult<SmallFileContent>> readSmallFile({
    required LibraryRootLocator root,
    required String storageKey,
    required int maximumBytes,
  });

  Future<AppResult<MediaSourceLease>> openPlaybackSource({
    required LibraryRootLocator root,
    required String storageKey,
    required PlaybackSourceStrategy strategy,
  });

  Future<void> releasePlaybackSource(MediaSourceLease lease);

  Future<AppResult<void>> releaseRootPermission(LibraryRootLocator root);
}
