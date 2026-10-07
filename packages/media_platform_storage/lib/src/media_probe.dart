import 'package:media_domain/media_domain.dart';

import 'storage_models.dart';

abstract interface class MediaProbe {
  Future<AppResult<MediaProbeResult>> probe({
    required LibraryRootLocator root,
    required String storageKey,
    required CancellationToken cancellationToken,
  });
}
