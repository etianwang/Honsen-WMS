#requires -version 5.1
[CmdletBinding()]
param(
    [ValidateSet("Install", "Uninstall")]
    [string]$Action = "Install",
    [ValidateSet("user", "machine")]
    [string]$Scope = "user",
    [string]$InstallLocation
)

$ErrorActionPreference = "Stop"
$SourceRoot = Split-Path -Parent $PSCommandPath
$ManifestName = "honsen.app.json"
$SourceManifestPath = Join-Path $SourceRoot $ManifestName

if (-not (Test-Path -LiteralPath $SourceManifestPath)) {
    throw "Missing $ManifestName beside this installer. Build the desktop package first."
}

$Manifest = Get-Content -LiteralPath $SourceManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$AppId = [string]$Manifest.appId
$RegistryRoot = if ($Scope -eq "machine") { "HKLM:\Software\Honsen Program\Apps" } else { "HKCU:\Software\Honsen Program\Apps" }
$RegistryPath = Join-Path $RegistryRoot $AppId

if ($Action -eq "Uninstall") {
    if (Test-Path -LiteralPath $RegistryPath) {
        Remove-Item -LiteralPath $RegistryPath -Recurse -Force
    }
    Write-Host "Removed Honsen Program registration for $AppId ($Scope)."
    exit 0
}

$SourceExe = Join-Path $SourceRoot ([string]$Manifest.executable)
if (-not (Test-Path -LiteralPath $SourceExe -PathType Leaf)) {
    throw "Missing application executable: $SourceExe"
}

if ([string]::IsNullOrWhiteSpace($InstallLocation)) {
    $InstallLocation = if ($Scope -eq "machine") {
        Join-Path $env:ProgramFiles "Honsen WMS"
    } else {
        Join-Path $env:LOCALAPPDATA "Programs\Honsen WMS"
    }
}

$InstallLocation = [IO.Path]::GetFullPath($InstallLocation)
New-Item -ItemType Directory -Path $InstallLocation -Force | Out-Null
$ExecutablePath = Join-Path $InstallLocation ([string]$Manifest.executable)
Copy-Item -LiteralPath $SourceExe -Destination $ExecutablePath -Force
$InstalledScriptPath = Join-Path $InstallLocation "Install-HonsenWms.ps1"
if ([IO.Path]::GetFullPath($PSCommandPath) -ne [IO.Path]::GetFullPath($InstalledScriptPath)) {
    Copy-Item -LiteralPath $PSCommandPath -Destination $InstalledScriptPath -Force
}

$Utf8NoBom = [Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText((Join-Path $InstallLocation $ManifestName), ($Manifest | ConvertTo-Json -Depth 3), $Utf8NoBom)

New-Item -Path $RegistryPath -Force | Out-Null
$Values = [ordered]@{
    AppId = $AppId
    DisplayName = [string]$Manifest.displayName
    Version = [string]$Manifest.version
    InstallLocation = $InstallLocation
    ExecutablePath = $ExecutablePath
    InstallScope = $Scope
    Publisher = [string]$Manifest.publisher
    UpdateManifestUrl = [string]$Manifest.updateManifestUrl
}
foreach ($Name in $Values.Keys) {
    New-ItemProperty -Path $RegistryPath -Name $Name -Value $Values[$Name] -PropertyType String -Force | Out-Null
}

Write-Host "Installed $($Manifest.displayName) $($Manifest.version) to $InstallLocation ($Scope)."
