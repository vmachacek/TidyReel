<#
.SYNOPSIS
Checks the Play bundle script with isolated fake Flutter and JDK commands.
.DESCRIPTION
Does not run Flutter, access a private keystore, or generate signing keys.
Uses a public certificate already in the Windows certificate store as a fixture.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$source = Join-Path $PSScriptRoot 'build-play-bundle.ps1'
$temporaryDirectory = [System.IO.Path]::GetTempPath()
$testRoot = Join-Path $temporaryDirectory ('tidyreel-play-bundle-tests-' + [Guid]::NewGuid().ToString('N'))
$powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path -LiteralPath $powershell -PathType Leaf)) {
  throw 'These checks require Windows PowerShell 5.1.'
}
$previousJavaHome = $env:JAVA_HOME
$propertyName = 'ORG_GRADLE_PROJECT_POCKET_CINEMA_PERSONAL_INSTALL'
$previousProperty = [Environment]::GetEnvironmentVariable($propertyName, 'Process')
$testEnvironmentNames = @('PLAY_TEST_ROOT', 'PLAY_TEST_SCENARIO')
$previousTestEnvironment = @{}
foreach ($name in $testEnvironmentNames) {
  $previousTestEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}

function Assert-That([bool]$Condition, [string]$Message) {
  if (-not $Condition) { throw "Assertion failed: $Message" }
}

function New-Launcher([string]$Path, [string]$ScriptName) {
  $contents = "@echo off`r`n`"$powershell`" -NoProfile -ExecutionPolicy Bypass -File `"%~dp0$ScriptName`" %*`r`nexit /b %ERRORLEVEL%`r`n"
  [System.IO.File]::WriteAllText($Path, $contents, [System.Text.Encoding]::ASCII)
}

try {
  [System.IO.Directory]::CreateDirectory((Join-Path $testRoot 'tool')) | Out-Null
  $app = Join-Path $testRoot 'apps\pocket_cinema'
  [System.IO.Directory]::CreateDirectory((Join-Path $app 'android')) | Out-Null
  $jdkBin = Join-Path $testRoot 'fake-jdk\bin'
  [System.IO.Directory]::CreateDirectory($jdkBin) | Out-Null
  $script = Join-Path $testRoot 'tool\build-play-bundle.ps1'
  Copy-Item -LiteralPath $source -Destination $script
  [System.IO.File]::WriteAllText((Join-Path $app 'pubspec.yaml'), 'name: fixture')
  $keyProperties = Join-Path $app 'android\key.properties'
  [System.IO.File]::WriteAllText($keyProperties, '# Signing configuration fixture; no secrets.')
  $publicCertificate = Get-ChildItem Cert:\LocalMachine\Root |
    Where-Object { $_.NotBefore -lt (Get-Date) -and $_.NotAfter -gt (Get-Date) -and $_.Subject -notmatch 'Android Debug' } |
    Select-Object -First 1
  Assert-That ($null -ne $publicCertificate) 'A currently valid public root certificate must be available.'
  $publicBytes = $publicCertificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)
  $base64 = [Convert]::ToBase64String($publicBytes, [Base64FormattingOptions]::InsertLineBreaks)
  [System.IO.File]::WriteAllText((Join-Path $testRoot 'public-certificate.pem'), "-----BEGIN CERTIFICATE-----`r`n$base64`r`n-----END CERTIFICATE-----`r`n")

  $fakeFlutter = @'
$ErrorActionPreference = 'Stop'
$root = $env:PLAY_TEST_ROOT
$countPath = Join-Path $root 'build-count.txt'
$count = 0
if (Test-Path -LiteralPath $countPath) { $count = [int](Get-Content -LiteralPath $countPath -Raw) }
$count++
[System.IO.File]::WriteAllText($countPath, [string]$count)
[System.IO.File]::AppendAllText((Join-Path $root 'build-arguments.txt'), ($args -join ' ') + "`n")
[System.IO.File]::WriteAllText((Join-Path $root 'build-property.txt'), $env:ORG_GRADLE_PROJECT_POCKET_CINEMA_PERSONAL_INSTALL)
if ($env:PLAY_TEST_SCENARIO -eq 'failure') { Write-Output 'Unrelated compiler failure'; exit 7 }
if ($env:PLAY_TEST_SCENARIO -eq 'always-stale' -or ($env:PLAY_TEST_SCENARIO -eq 'stale' -and $count -eq 1)) {
  [Console]::Error.WriteLine('GeneratedPluginRegistrant.java: package dev.flutter.plugins.integration_test does not exist')
  exit 1
}
if ($env:PLAY_TEST_SCENARIO -eq 'missing') { exit 0 }
$bundle = Join-Path (Get-Location).Path 'build\app\outputs\bundle\release\app-release.aab'
[System.IO.Directory]::CreateDirectory((Split-Path -Parent $bundle)) | Out-Null
$contents = 'AAB fixture'
if ($env:PLAY_TEST_SCENARIO -eq 'empty') { $contents = '' }
[System.IO.File]::WriteAllText($bundle, $contents)
Write-Output 'Fake Flutter build complete.'
exit 0
'@
  $fakeJarsigner = @'
[System.IO.File]::WriteAllText((Join-Path $env:PLAY_TEST_ROOT 'verification-arguments.txt'), ($args -join ' '))
switch ($env:PLAY_TEST_SCENARIO) {
  'unsigned' { Write-Output 'jar is unsigned.'; exit 0 }
  'tampered' { Write-Output 'jarsigner: java.lang.SecurityException: invalid entry digest'; exit 1 }
  'unsigned-entry' { Write-Output 'jar verified, with signer errors.'; exit 20 }
  'debug' { Write-Output 'X.509, CN=Android Debug, O=Android, C=US'; Write-Output 'jar verified, with signer errors.'; exit 4 }
  'selfsigned' { Write-Output 'jar verified, with signer errors.'; exit 4 }
  default { Write-Output 'jar verified.'; exit 0 }
}
'@
  $fakeKeytool = @'
[System.IO.File]::WriteAllText((Join-Path $env:PLAY_TEST_ROOT 'certificate-arguments.txt'), ($args -join ' '))
if ($env:PLAY_TEST_SCENARIO -eq 'keytool-failure') { exit 9 }
if ($env:PLAY_TEST_SCENARIO -eq 'missing-certificate') { Write-Output 'Not a signed jar file'; exit 0 }
if ($env:PLAY_TEST_SCENARIO -eq 'bad-certificate') { Write-Output "-----BEGIN CERTIFICATE-----`nYWJj`n-----END CERTIFICATE-----"; exit 0 }
Get-Content -LiteralPath (Join-Path $env:PLAY_TEST_ROOT 'public-certificate.pem')
exit 0
'@
  [System.IO.File]::WriteAllText((Join-Path $testRoot 'fake-flutter.ps1'), $fakeFlutter)
  [System.IO.File]::WriteAllText((Join-Path $jdkBin 'fake-jarsigner.ps1'), $fakeJarsigner)
  [System.IO.File]::WriteAllText((Join-Path $jdkBin 'fake-keytool.ps1'), $fakeKeytool)
  $flutter = Join-Path $testRoot 'flutter.cmd'
  New-Launcher $flutter 'fake-flutter.ps1'
  New-Launcher (Join-Path $jdkBin 'jarsigner.cmd') 'fake-jarsigner.ps1'
  New-Launcher (Join-Path $jdkBin 'keytool.cmd') 'fake-keytool.ps1'
  $env:JAVA_HOME = Split-Path -Parent $jdkBin
  $env:PLAY_TEST_ROOT = $testRoot

  $scenarios = @(
    @{ Name = 'success'; Pass = $true; Builds = 1 },
    @{ Name = 'selfsigned'; Pass = $true; Builds = 1 },
    @{ Name = 'stale'; Pass = $true; Builds = 2 },
    @{ Name = 'always-stale'; Pass = $false; Builds = 2; Message = 'build failed with exit code 1' },
    @{ Name = 'failure'; Pass = $false; Builds = 1; Message = 'build failed with exit code 7' },
    @{ Name = 'missing'; Pass = $false; Builds = 1; Message = 'expected AAB was not found' },
    @{ Name = 'empty'; Pass = $false; Builds = 1; Message = 'empty AAB' },
    @{ Name = 'unsigned'; Pass = $false; Builds = 1; Message = 'unsigned or failed signature verification' },
    @{ Name = 'tampered'; Pass = $false; Builds = 1; Message = 'unsigned or failed signature verification' },
    @{ Name = 'unsigned-entry'; Pass = $false; Builds = 1; Message = 'unsigned or failed signature verification' },
    @{ Name = 'debug'; Pass = $false; Builds = 1; Message = 'Android Debug certificate' },
    @{ Name = 'keytool-failure'; Pass = $false; Builds = 1; Message = 'Could not read' },
    @{ Name = 'missing-certificate'; Pass = $false; Builds = 1; Message = 'Could not read' },
    @{ Name = 'bad-certificate'; Pass = $false; Builds = 1 }
  )
  $initialLocation = (Get-Location).Path
  foreach ($scenario in $scenarios) {
    $env:PLAY_TEST_SCENARIO = $scenario.Name
    $env:ORG_GRADLE_PROJECT_POCKET_CINEMA_PERSONAL_INSTALL = 'original-test-value'
    $countPath = Join-Path $testRoot 'build-count.txt'
    [System.IO.File]::WriteAllText($countPath, '0')
    $destination = Join-Path $testRoot ('outputs with spaces\' + $scenario.Name)
    $failure = $null
    $result = $null
    try { $result = & $script -FlutterPath $flutter -DestinationDirectory $destination }
    catch { $failure = $_ }
    Assert-That ($env:ORG_GRADLE_PROJECT_POCKET_CINEMA_PERSONAL_INSTALL -eq 'original-test-value') "$($scenario.Name): Restore the original Gradle environment."
    Assert-That ((Get-Location).Path -eq $initialLocation) "$($scenario.Name): Restore the working directory."
    Assert-That ([int](Get-Content -LiteralPath $countPath -Raw) -eq $scenario.Builds) "$($scenario.Name): Build/retry count."
    Assert-That ((Get-Content -LiteralPath (Join-Path $testRoot 'build-property.txt') -Raw) -eq 'false') "$($scenario.Name): Disable personal-install mode during build."
    if ($scenario.Pass) {
      Assert-That ($null -eq $failure) "$($scenario.Name): Expected success; received $failure"
      Assert-That ((Get-Item -LiteralPath $result.BundlePath).Length -gt 0) "$($scenario.Name): Copy nonempty AAB."
      Assert-That ($result.Sha256 -eq (Get-FileHash -LiteralPath $result.BundlePath -Algorithm SHA256).Hash) "$($scenario.Name): Report correct SHA256."
      Assert-That ((Get-Content -LiteralPath $result.ChecksumPath -Raw).Trim() -eq ($result.Sha256 + '  ' + (Split-Path -Leaf $result.BundlePath))) "$($scenario.Name): Save a checksum sidecar for this AAB."
      Assert-That ((Get-Content -LiteralPath $result.UploadCertificatePath -Raw).Contains('BEGIN CERTIFICATE')) "$($scenario.Name): Export public PEM."
    } else {
      Assert-That ($null -ne $failure) "$($scenario.Name): Expected failure."
      if ($scenario.Message) { Assert-That ($failure.ToString().Contains($scenario.Message)) "$($scenario.Name): Explain the expected failure; received $failure" }
      Assert-That (@(Get-ChildItem -LiteralPath $destination -File).Count -eq 0) "$($scenario.Name): Copy nothing after failure."
    }
    Write-Host "PASS: $($scenario.Name)"
  }
  $arguments = Get-Content -LiteralPath (Join-Path $testRoot 'build-arguments.txt') -Raw
  Assert-That ($arguments -notmatch '--no-pub' -and $arguments -match 'build appbundle --release') 'Build a release app bundle with pub enabled.'
  $verificationArguments = Get-Content -LiteralPath (Join-Path $testRoot 'verification-arguments.txt') -Raw
  Assert-That ($verificationArguments -match '-strict' -and $verificationArguments -match '-J-Duser.language=en') 'Use strict verification and a predictable JVM output locale.'
  $certificateArguments = Get-Content -LiteralPath (Join-Path $testRoot 'certificate-arguments.txt') -Raw
  Assert-That ($certificateArguments -match '-jarfile' -and $certificateArguments -notmatch '-(?:store|key)pass') 'Export a certificate without reading keystore passwords.'

  # Default output location and restoration of a previously absent variable.
  [Environment]::SetEnvironmentVariable($propertyName, $null, 'Process')
  $env:PLAY_TEST_SCENARIO = 'success'
  $firstDefault = & $script -FlutterPath $flutter
  $secondDefault = & $script -FlutterPath $flutter
  Assert-That ($null -eq [Environment]::GetEnvironmentVariable($propertyName, 'Process')) 'Restore an absent Gradle environment variable.'
  Assert-That ((Split-Path -Parent $firstDefault.BundlePath) -eq (Join-Path $app 'build\google-play')) 'Default destination is inside ignored app build output.'
  Assert-That ($firstDefault.BundlePath -ne $secondDefault.BundlePath) 'Keep each bundle under a unique filename.'
  Assert-That (Test-Path -LiteralPath $firstDefault.BundlePath) 'Preserve the previous exported bundle.'

  # Preconditions must fail before invoking Flutter.
  [System.IO.File]::WriteAllText($countPath, '0')
  Remove-Item -LiteralPath $keyProperties
  $failure = $null
  try { & $script -FlutterPath $flutter | Out-Null } catch { $failure = $_ }
  Assert-That ($failure.ToString().Contains('Release signing is not configured')) 'Require release signing configuration.'
  Assert-That ([int](Get-Content -LiteralPath $countPath -Raw) -eq 0) 'Do not build without signing configuration.'
  Write-Host 'PASS: default destination, unique names, absent environment, signing precondition'
  Write-Host 'All Play bundle script checks passed (Windows PowerShell 5.1 compatible).'
} finally {
  $env:JAVA_HOME = $previousJavaHome
  [Environment]::SetEnvironmentVariable($propertyName, $previousProperty, 'Process')
  foreach ($name in $testEnvironmentNames) {
    [Environment]::SetEnvironmentVariable($name, $previousTestEnvironment[$name], 'Process')
  }
  # Check the resolved absolute target before recursively removing test fixtures.
  if (Test-Path -LiteralPath $testRoot -PathType Container) {
    $resolvedRoot = (Resolve-Path -LiteralPath $testRoot).ProviderPath
    $expectedRoot = [System.IO.Path]::GetFullPath($testRoot)
    $temporaryPrefix = [System.IO.Path]::GetFullPath($temporaryDirectory).TrimEnd('\') + '\'
    if ($resolvedRoot -ne $expectedRoot -or -not $resolvedRoot.StartsWith($temporaryPrefix, [StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path -Leaf $resolvedRoot) -notlike 'tidyreel-play-bundle-tests-*') {
      throw "Refusing to remove an unexpected test directory: $resolvedRoot"
    }
    Remove-Item -LiteralPath $resolvedRoot -Recurse -Force
  }
}
