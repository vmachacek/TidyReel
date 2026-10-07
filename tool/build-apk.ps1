<#
.SYNOPSIS
Builds Pocket Cinema and moves its APK into a local Google Drive folder.

.DESCRIPTION
Builds a release APK by default. The default destination is
My Drive\Pocket Cinema\APKs under your Windows user profile. Each APK gets a
timestamped filename so previous builds are kept. Google Drive for desktop
handles uploading the file after it is moved into the synced folder.
If a release build hits a stale integration-test plugin registration, the
script regenerates the release files by retrying the build once.

.PARAMETER DestinationDirectory
The local folder that should receive the APK. Created if it does not exist.

.PARAMETER BuildMode
Release (default) or Debug.

.PARAMETER FlutterPath
The Flutter executable. Defaults to this project's pinned SDK.

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\tool\build-apk.ps1

.EXAMPLE
.\tool\build-apk.ps1 -DestinationDirectory "$env:USERPROFILE\My Drive\APKs" -BuildMode Debug
#>
[CmdletBinding()]
param(
  [string]$DestinationDirectory,

  [ValidateSet('Release', 'Debug')]
  [string]$BuildMode = 'Release',

  [string]$FlutterPath = 'C:\dev\sdks\flutter-3.47.3\flutter\bin\flutter.bat'
)

$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$app = Join-Path $workspace 'apps\pocket_cinema'

if (-not (Test-Path -LiteralPath $FlutterPath -PathType Leaf)) {
  throw "Flutter executable not found at '$FlutterPath'. Supply -FlutterPath with the correct path."
}
$FlutterPath = (Resolve-Path -LiteralPath $FlutterPath).ProviderPath
if (-not (Test-Path -LiteralPath (Join-Path $app 'pubspec.yaml') -PathType Leaf)) {
  throw "Pocket Cinema app not found at '$app'. Keep this script in the repository's tool folder."
}

if ([string]::IsNullOrWhiteSpace($DestinationDirectory)) {
  $driveRoot = Join-Path $env:USERPROFILE 'My Drive'
  if (-not (Test-Path -LiteralPath $driveRoot -PathType Container)) {
    throw "Local Google Drive folder not found at '$driveRoot'. Supply -DestinationDirectory with your synced folder path."
  }
  $DestinationDirectory = Join-Path $driveRoot 'Pocket Cinema\APKs'
}

# Resolve relative destinations before changing into the app directory.
$destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DestinationDirectory)
if (Test-Path -LiteralPath $destination) {
  if (-not (Test-Path -LiteralPath $destination -PathType Container)) {
    throw "The destination '$destination' is a file; choose a folder."
  }
} else {
  [System.IO.Directory]::CreateDirectory($destination) | Out-Null
}

$mode = $BuildMode.ToLowerInvariant()
$apk = Join-Path $app "build\app\outputs\flutter-apk\app-$mode.apk"
$logDirectory = Join-Path $app 'build\apk-script'
[System.IO.Directory]::CreateDirectory($logDirectory) | Out-Null

# Check native exit codes ourselves, including when called from PowerShell 7.
$PSNativeCommandUseErrorActionPreference = $false

Write-Host "Building Pocket Cinema ($mode)..."
Push-Location $app
try {
  for ($attempt = 1; $attempt -le 2; $attempt++) {
    $buildLog = Join-Path $logDirectory "$mode-attempt-$attempt.log"
    [System.IO.File]::WriteAllText($buildLog, '')
    $previousErrorAction = $ErrorActionPreference
    try {
      # Windows PowerShell treats redirected native stderr as error records.
      # Keep streaming it, then use Flutter's exit code to detect build failure.
      $ErrorActionPreference = 'Continue'
      # Keep pub enabled so Flutter regenerates the registrant for this mode.
      & $FlutterPath build apk "--$mode" 2>&1 |
        ForEach-Object { $_.ToString() } |
        Tee-Object -FilePath $buildLog -ErrorAction Stop |
        ForEach-Object { Write-Host $_ }
      $buildExitCode = $LASTEXITCODE
    } finally {
      $ErrorActionPreference = $previousErrorAction
    }

    if ($buildExitCode -eq 0) {
      break
    }

    $buildOutput = Get-Content -LiteralPath $buildLog -Raw
    # A debug/test/pub command can rewrite the shared Java registrant while
    # Gradle is building release. A normal rebuild regenerates release tooling.
    $staleTestPlugin = $mode -eq 'release' -and
      $buildOutput -match 'GeneratedPluginRegistrant\.java' -and
      $buildOutput -match 'package\s+dev\.flutter\.plugins\.integration_test\s+does\s+not\s+exist'
    if ($attempt -eq 1 -and $staleTestPlugin) {
      Write-Host 'Release plugin registration changed during the build. Regenerating and retrying once...'
      continue
    }

    throw "Flutter APK build failed with exit code $buildExitCode. No APK was moved. Build log: $buildLog"
  }
} finally {
  Pop-Location
}

if (-not (Test-Path -LiteralPath $apk -PathType Leaf)) {
  throw "Flutter reported success, but the expected APK was not found at '$apk'."
}
if ((Get-Item -LiteralPath $apk).Length -eq 0) {
  throw "The APK at '$apk' is empty. No APK was moved."
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$target = Join-Path $destination "pocket-cinema-$mode-$timestamp.apk"
if (Test-Path -LiteralPath $target) {
  throw "An APK already exists at '$target'. No file was overwritten; run the script again."
}

Move-Item -LiteralPath $apk -Destination $target
Write-Host "APK moved to: $target"
Write-Host 'Google Drive for desktop will sync it when running and connected.'
