<#
.SYNOPSIS
Tests physical media organization in a separate Android app and disposable tree.
.DESCRIPTION
Creates five tiny text fixtures, installs com.pocketcinema.app.organizercheck,
and opens the Android folder picker. Select the displayed fixture folder under
Download. The real Pocket Cinema app and its private data are never replaced.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)]
  [ValidatePattern('^[A-Za-z0-9.:_-]+$')]
  [string]$DeviceId,
  [ValidatePattern('^TidyReelOrganizerCheck-[0-9]+$')]
  [string]$FixtureName = ('TidyReelOrganizerCheck-' + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()),
  [string]$FlutterPath = 'C:\dev\sdks\flutter-3.47.3\flutter\bin\flutter.bat',
  [string]$AdbPath = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
)

$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$appDirectory = Join-Path $workspace 'apps\pocket_cinema'
$fixtureDirectory = Join-Path $appDirectory "build\organizer-fixtures\$FixtureName"
$remoteFixturePath = "/sdcard/Download/$FixtureName"
$testPackage = 'com.pocketcinema.app.organizercheck'
$propertyName = 'ORG_GRADLE_PROJECT_POCKET_CINEMA_ORGANIZER_SMOKE'
$previousProperty = [Environment]::GetEnvironmentVariable($propertyName, 'Process')
$personalProperty = 'ORG_GRADLE_PROJECT_POCKET_CINEMA_PERSONAL_INSTALL'
$previousPersonalProperty = [Environment]::GetEnvironmentVariable($personalProperty, 'Process')
$PSNativeCommandUseErrorActionPreference = $false

function Invoke-OrganizerAdb {
  param([string[]]$CommandArgs)
  & $AdbPath -s $DeviceId @CommandArgs
  if ($LASTEXITCODE -ne 0) { throw "ADB failed ($LASTEXITCODE)." }
}

foreach ($executable in @($FlutterPath, $AdbPath)) {
  if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
    throw "Executable not found: $executable"
  }
}
if ($remoteFixturePath -notmatch '^/sdcard/Download/TidyReelOrganizerCheck-[0-9]+$') {
  throw 'Invalid disposable fixture path.'
}
Invoke-OrganizerAdb -CommandArgs @('get-state')
Invoke-OrganizerAdb -CommandArgs @('shell', 'test', '!', '-e', $remoteFixturePath)

$newline = [string][char]10
$fixtures = @{
  'Movie.2024.1080p-GROUP.mkv' = "tidyreel-movie-content$newline"
  'Movie.2024.1080p-GROUP.forced.en.srt' = (@('1', '00:00:00,000 --> 00:00:01,000', 'Fixture subtitle', '') -join $newline)
  'Show.S01E01E02.1080p-WEB.mkv' = "tidyreel-show-content$newline"
  'Collision.2024.1080p-GROUP.mkv' = "tidyreel-collision-source$newline"
  'Movies/Collision (2024)/COLLISION (2024).MKV' = "tidyreel-existing-destination-preserved$newline"
}
[System.IO.Directory]::CreateDirectory($fixtureDirectory) | Out-Null
Invoke-OrganizerAdb -CommandArgs @('shell', 'mkdir', '-p', "'$remoteFixturePath/Movies/Collision (2024)'")
foreach ($fixture in $fixtures.GetEnumerator()) {
  $localPath = Join-Path $fixtureDirectory $fixture.Key
  [System.IO.Directory]::CreateDirectory((Split-Path -Parent $localPath)) | Out-Null
  [System.IO.File]::WriteAllText($localPath, $fixture.Value, [System.Text.UTF8Encoding]::new($false))
  Invoke-OrganizerAdb -CommandArgs @('push', $localPath, "$remoteFixturePath/$($fixture.Key)")
}

Write-Host "In the folder picker, select only Download/$FixtureName, then Use this folder and Allow."
Write-Host 'Running in the isolated organizercheck app; Pocket Cinema will retain its data.'
[Environment]::SetEnvironmentVariable($propertyName, 'true', 'Process')
[Environment]::SetEnvironmentVariable($personalProperty, $null, 'Process')
Push-Location $appDirectory
try {
  & $FlutterPath test integration_test/library_organizer_android_test.dart -d $DeviceId --no-uninstall "--dart-define=ORGANIZER_FIXTURE_NAME=$FixtureName"
  if ($LASTEXITCODE -ne 0) { throw "Organizer device test failed ($LASTEXITCODE). Fixtures remain at $remoteFixturePath." }
  $installedPackage = Invoke-OrganizerAdb -CommandArgs @('shell', 'pm', 'list', 'packages', $testPackage)
  if (@($installedPackage).Count -ne 1 -or $installedPackage.Trim() -ne "package:$testPackage") {
    throw 'Could not verify the isolated test package for cleanup.'
  }
  $resolvedDownload = (Invoke-OrganizerAdb -CommandArgs @('shell', 'readlink', '-f', '/sdcard/Download')).Trim()
  $resolvedFixture = (Invoke-OrganizerAdb -CommandArgs @('shell', 'readlink', '-f', $remoteFixturePath)).Trim()
  if ($resolvedDownload -notmatch '^/storage/emulated/[0-9]+/Download$' -or
      $resolvedFixture -ne "$resolvedDownload/$FixtureName") {
    throw 'The fixture path no longer resolves to its expected Download folder. Cleanup stopped.'
  }
  $expectedFiles = @(
    'Movies/Movie (2024)/Movie (2024).mkv'
    'Movies/Movie (2024)/Movie (2024).forced.en.srt'
    'TV/Show (2022)/Season 01/S01E01-E02.mkv'
    'Collision.2024.1080p-GROUP.mkv'
    'Movies/Collision (2024)/COLLISION (2024).MKV'
  ) | ForEach-Object { "$resolvedFixture/$_" }
  $actualFiles = Invoke-OrganizerAdb -CommandArgs @('shell', 'find', $resolvedFixture, '-type', 'f')
  if (@(Compare-Object -ReferenceObject $expectedFiles -DifferenceObject @($actualFiles)).Count -ne 0) {
    throw 'Unexpected files appeared in the fixture folder. Cleanup stopped.'
  }
  # Remove only the package and tree created by this test.
  Invoke-OrganizerAdb -CommandArgs @('uninstall', $testPackage)
  Invoke-OrganizerAdb -CommandArgs @('shell', 'rm', '-r', '--', $remoteFixturePath)
} finally {
  Pop-Location
  [Environment]::SetEnvironmentVariable($propertyName, $previousProperty, 'Process')
  [Environment]::SetEnvironmentVariable($personalProperty, $previousPersonalProperty, 'Process')
}
