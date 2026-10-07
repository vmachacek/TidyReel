# Dependency review

## Pigeon

- Purpose: generate typed Flutter-to-Kotlin platform messages for Android storage and probe operations.
- Maintainer: Flutter team in the `flutter/packages` repository.
- License: BSD-3-Clause.
- Runtime impact: generated channel code only; no network behavior.
- Removal path: replace the generated interfaces while preserving the app-owned `StoragePlatformApi` boundary.

## Meta

- Purpose: supply annotations imported by Pigeon-generated Dart bridge code.
- Maintainer: Dart team.
- License: BSD-3-Clause.
- Runtime impact: annotations only; no network behavior.
- Removal path: remove it when the selected Pigeon generator no longer emits a direct `package:meta` import.

## media_kit

- Purpose: provide the player API used by the direct Android `content://` playback spike.
- Maintainer and activity: community-maintained in the `media-kit/media-kit` repository, with current packages selected from pub.dev during this milestone.
- License: MIT.
- Platform coverage: Android and desktop platforms needed by the product direction; this milestone verifies Android only.
- Runtime impact: opens local media sources through libmpv; no provider credentials or network service are required.
- Native and size implications: paired with `media_kit_libs_video`, which bundles native libmpv binaries and therefore increases the application binary size.
- Local access: receives a short-lived app-owned source URI; raw paths and URIs must not enter diagnostics.
- Removal path: replace the implementation behind the app-owned `PlaybackEngine` boundary.

## media_kit_video

- Purpose: provide Flutter video output for the `media_kit` player.
- Maintainer and activity: maintained with `media_kit`, with the current compatible release selected from pub.dev during this milestone.
- License: MIT.
- Platform coverage: Android and desktop Flutter targets; this milestone verifies Android only.
- Runtime impact: renders local playback state from the player and requires no provider credentials.
- Native and size implications: integrates the Flutter video surface; native decoder binaries come from `media_kit_libs_video`.
- Local access: does not enumerate storage and only renders the source already opened by the player.
- Removal path: replace it together with the adapter behind `PlaybackEngine`.

## media_kit_libs_video

- Purpose: supply the native libmpv binaries required by `media_kit` video playback.
- Maintainer and activity: maintained with `media_kit`, with the current compatible release selected from pub.dev during this milestone.
- License: MIT package; bundled native components retain their respective notices.
- Platform coverage: Android and desktop native runtimes; this milestone verifies Android only.
- Runtime impact: local native playback and codec support, with no provider credentials or network service.
- Native and size implications: materially increases packaged binary size and adds native ABI artifacts.
- Local access: decodes the local URI supplied through the player boundary.
- Removal path: remove with the `media_kit` adapter or replace the native backend while preserving `PlaybackEngine`.
