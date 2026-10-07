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
