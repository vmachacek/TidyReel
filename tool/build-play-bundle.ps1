<#
.SYNOPSIS
Builds and verifies a signed Google Play Android App Bundle.

.DESCRIPTION
Requires apps\pocket_cinema\android\key.properties and its upload keystore.
Builds with the personal-install mode disabled. Copies a verified release AAB,
SHA256 checksum, and public upload certificate into apps\pocket_cinema\build\google-play
by default. The private keystore and its passwords are never exported.

.PARAMETER DestinationDirectory
The folder for timestamped AAB and PEM files. Created if necessary.

.PARAMETER FlutterPath
The Flutter executable. Defaults to this project's pinned SDK.

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\tool\build-play-bundle.ps1
#>
[CmdletBinding()]
param(
  [string]$DestinationDirectory,
  [string]$FlutterPath = 'C:\dev\sdks\flutter-3.47.3\flutter\bin\flutter.bat'
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$workspace = Split-Path -Parent $PSScriptRoot
$app = Join-Path $workspace 'apps\pocket_cinema'

function Find-JdkTool([string]$Name) {
  if (-not [string]::IsNullOrWhiteSpace($env:JAVA_HOME)) {
    foreach ($extension in @('.exe', '.cmd', '.bat')) {
      $candidate = Join-Path $env:JAVA_HOME "bin\$Name$extension"
      if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        return (Resolve-Path -LiteralPath $candidate).ProviderPath
      }
    }
  }
  $command = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue |
    Select-Object -First 1
  if ($null -eq $command) {
    throw "JDK tool '$Name' was not found. Set JAVA_HOME to your JDK or add its bin folder to PATH."
  }
  return $command.Source
}

function Invoke-JdkTool([string]$Executable, [string[]]$Arguments) {
  $previousErrorAction = $ErrorActionPreference
  try {
    # Windows PowerShell reports redirected native stderr as error records.
    $ErrorActionPreference = 'Continue'
    $output = @(& $Executable @Arguments 2>&1 | ForEach-Object { $_.ToString() })
    $exitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousErrorAction
  }
  return @{ ExitCode = $exitCode; Output = ($output -join "`n") }
}

if (-not (Test-Path -LiteralPath $FlutterPath -PathType Leaf)) {
  throw "Flutter executable not found at '$FlutterPath'. Supply -FlutterPath with the correct path."
}
$FlutterPath = (Resolve-Path -LiteralPath $FlutterPath).ProviderPath
if (-not (Test-Path -LiteralPath (Join-Path $app 'pubspec.yaml') -PathType Leaf)) {
  throw "Pocket Cinema app not found at '$app'. Keep this script in the repository's tool folder."
}
if (-not (Test-Path -LiteralPath (Join-Path $app 'android\key.properties') -PathType Leaf)) {
  throw 'Release signing is not configured. Create apps\pocket_cinema\android\key.properties with your upload-keystore settings first.'
}
$jarsigner = Find-JdkTool 'jarsigner'
$keytool = Find-JdkTool 'keytool'

if ([string]::IsNullOrWhiteSpace($DestinationDirectory)) {
  $DestinationDirectory = Join-Path $app 'build\google-play'
}
# Resolve a relative destination before changing into the app directory.
$destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DestinationDirectory)
if ((Test-Path -LiteralPath $destination) -and
    -not (Test-Path -LiteralPath $destination -PathType Container)) {
  throw "The destination '$destination' is a file; choose a folder."
}
[System.IO.Directory]::CreateDirectory($destination) | Out-Null
$bundle = Join-Path $app 'build\app\outputs\bundle\release\app-release.aab'
$logDirectory = Join-Path $app 'build\play-bundle-script'
[System.IO.Directory]::CreateDirectory($logDirectory) | Out-Null
if (Test-Path -LiteralPath $bundle -PathType Leaf) {
  Remove-Item -LiteralPath $bundle
}

$propertyName = 'ORG_GRADLE_PROJECT_POCKET_CINEMA_PERSONAL_INSTALL'
$originalProperty = [Environment]::GetEnvironmentVariable($propertyName, 'Process')
Write-Host 'Building Pocket Cinema for Google Play...'
Push-Location $app
try {
  [Environment]::SetEnvironmentVariable($propertyName, 'false', 'Process')
  for ($attempt = 1; $attempt -le 2; $attempt++) {
    $buildLog = Join-Path $logDirectory "release-attempt-$attempt.log"
    [System.IO.File]::WriteAllText($buildLog, '')
    $previousErrorAction = $ErrorActionPreference
    try {
      $ErrorActionPreference = 'Continue'
      # Keep pub enabled to regenerate the registrant for release mode.
      & $FlutterPath build appbundle '--release' 2>&1 |
        ForEach-Object { $_.ToString() } |
        Tee-Object -FilePath $buildLog -ErrorAction Stop |
        ForEach-Object { Write-Host $_ }
      $buildExitCode = $LASTEXITCODE
    } finally {
      $ErrorActionPreference = $previousErrorAction
    }
    if ($buildExitCode -eq 0) { break }
    $buildOutput = Get-Content -LiteralPath $buildLog -Raw
    $staleTestPlugin = $buildOutput -match 'GeneratedPluginRegistrant\.java' -and
      $buildOutput -match 'package\s+dev\.flutter\.plugins\.integration_test\s+does\s+not\s+exist'
    if ($attempt -eq 1 -and $staleTestPlugin) {
      Write-Host 'Release plugin registration changed during the build. Regenerating and retrying once...'
      continue
    }
    throw "Flutter app-bundle build failed with exit code $buildExitCode. No bundle was copied. Build log: $buildLog"
  }
} finally {
  [Environment]::SetEnvironmentVariable($propertyName, $originalProperty, 'Process')
  Pop-Location
}

if (-not (Test-Path -LiteralPath $bundle -PathType Leaf)) {
  throw "Flutter reported success, but the expected AAB was not found at '$bundle'."
}
if ((Get-Item -LiteralPath $bundle).Length -eq 0) {
  throw 'Flutter produced an empty AAB. No bundle was copied.'
}

$locale = @('-J-Duser.language=en', '-J-Duser.country=US')
$verification = Invoke-JdkTool $jarsigner (@('-verify', '-strict', '-verbose:summary', '-certs') + $locale + @($bundle))
$verificationLog = Join-Path $logDirectory 'signature-verification.log'
[System.IO.File]::WriteAllText($verificationLog, $verification.Output)
# Exit code 4 covers the normal self-signed/untrusted upload certificate.
# Other strict bits reject unsigned entries, invalid usage, or signer errors.
# Unsigned JARs can return zero, so also require jarsigner's verified result.
if (($verification.ExitCode -notin @(0, 4)) -or
    $verification.Output -notmatch '(?im)^\s*jar verified(?:, with signer errors)?\.\s*$') {
  throw "The AAB is unsigned or failed signature verification (exit code $($verification.ExitCode)). No bundle was copied. Details: $verificationLog"
}
if ($verification.Output -match '(?im)(?:^|[,\s])CN\s*=\s*Android Debug(?:\s*,|\s*$)') {
  throw 'The AAB uses an Android Debug certificate. Configure your release upload key; no bundle was copied.'
}
$certificateResult = Invoke-JdkTool $keytool (@('-printcert', '-rfc', '-jarfile') + @($bundle) + $locale)
$pemMatches = [regex]::Matches($certificateResult.Output, '(?s)-----BEGIN CERTIFICATE-----\s*([A-Za-z0-9+/=\s]+?)\s*-----END CERTIFICATE-----')
if ($certificateResult.ExitCode -ne 0 -or $pemMatches.Count -eq 0) {
  throw 'Could not read the signed AAB upload certificate. No bundle was copied.'
}
$certificateBytes = [Convert]::FromBase64String(($pemMatches[0].Groups[1].Value -replace '\s', ''))
$certificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList (,$certificateBytes)
try {
  $signerName = $certificate.GetNameInfo([System.Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false)
  if ($signerName -eq 'Android Debug') {
    throw 'The AAB uses an Android Debug certificate. No bundle was copied.'
  }
  if ($certificate.NotBefore -gt (Get-Date) -or $certificate.NotAfter -lt (Get-Date)) {
    throw 'The AAB upload certificate is outside its validity dates. No bundle was copied.'
  }
} finally {
  $certificate.Dispose()
}

$identifier = (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
$target = Join-Path $destination "pocket-cinema-play-$identifier.aab"
$certificatePath = Join-Path $destination "pocket-cinema-upload-certificate-$identifier.pem"
$checksumPath = $target + '.sha256'
$pem = $pemMatches[0].Value -replace "`r?`n", "`r`n"
[System.IO.File]::WriteAllText($certificatePath, $pem + "`r`n", [System.Text.Encoding]::ASCII)
Copy-Item -LiteralPath $bundle -Destination $target
$sha256 = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
[System.IO.File]::WriteAllText($checksumPath, "$sha256  $(Split-Path -Leaf $target)`r`n", [System.Text.Encoding]::ASCII)
Write-Host "Verified Google Play bundle: $target"
Write-Host "SHA256: $sha256"
Write-Host "Checksum file: $checksumPath"
Write-Host "Public upload certificate: $certificatePath"
[pscustomobject]@{ BundlePath = $target; Sha256 = $sha256; ChecksumPath = $checksumPath; UploadCertificatePath = $certificatePath }
