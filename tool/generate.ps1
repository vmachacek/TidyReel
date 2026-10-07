$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$app = Join-Path $workspace 'apps\local_media_hub'
$dart = 'C:\dev\sdks\flutter-3.47.3\flutter\bin\dart.bat'
if (-not (Test-Path -LiteralPath $dart)) {
  throw "Pinned Dart executable not found at $dart"
}

Push-Location $app
try {
  & $dart run pigeon `
    --input pigeons/storage_api.dart `
    --dart_out lib/infrastructure/android/generated/storage_api.g.dart `
    --kotlin_out android/app/src/main/kotlin/com/tidyreel/local_media_hub/platform/StorageApi.g.kt `
    --kotlin_package com.tidyreel.local_media_hub.platform
  if ($LASTEXITCODE -ne 0) {
    throw "Pigeon failed with exit code $LASTEXITCODE"
  }
  & $dart format lib/infrastructure/android/generated/storage_api.g.dart
  if ($LASTEXITCODE -ne 0) {
    throw "Formatting generated Dart failed with exit code $LASTEXITCODE"
  }
} finally {
  Pop-Location
}
