#Requires -Version 5.1
# PulseLab 1.7.0 - compatibility setup for a checked-out repository

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SupabaseUrl,
    [Parameter(Mandatory = $true)][string]$SupabaseAnonKey,
    [Parameter(Mandatory = $true)][string]$SiteId,
    [Parameter(Mandatory = $true)][string]$RegionalHub,
    [Parameter(Mandatory = $true)][string]$SchoolCode,
    [string]$ComputerId = $env:COMPUTERNAME,
    [string]$LauncherPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ([string]::IsNullOrWhiteSpace($LauncherPath)) {
    $LauncherPath = Join-Path $repoRoot "pulselab.ps1"
}
$enrollPath = Join-Path $repoRoot "supabase\scripts\enroll-device.ps1"
foreach ($path in @($LauncherPath, $enrollPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required file not found: $path" }
}

$targetDir = "$env:LOCALAPPDATA\PulseLab"
$agentScript = (Resolve-Path "$PSScriptRoot\..\agent\pulselab-agent.ps1").Path
$launcherScript = (Resolve-Path "$PSScriptRoot\..\pulselab.ps1").Path

Write-Host "Configuring PulseLab development launcher..." -ForegroundColor Cyan

# Create local data and config directories
New-Item -ItemType Directory -Path "$targetDir\logs" -Force | Out-Null
New-Item -ItemType Directory -Path "$targetDir\data" -Force | Out-Null
New-Item -ItemType Directory -Path "$targetDir\config" -Force | Out-Null

if (Test-Path $ConfigPath) {
    Copy-Item -Path $ConfigPath -Destination "$targetDir\config\config.json" -Force
    Write-Host "Copied config from $ConfigPath" -ForegroundColor Green
}

# Create Startup Shortcut using Windows Script Host
$wsh = New-Object -ComObject WScript.Shell
$startupFolder = [Environment]::GetFolderPath("Startup")
$shortcutPath = Join-Path $startupFolder "PulseLab.lnk"
$shortcut = $wsh.CreateShortcut($shortcutPath)
$shortcut.TargetPath = "powershell.exe"
$shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$launcherScript`""
$shortcut.WorkingDirectory = Split-Path -Parent $launcherScript
$shortcut.Description = "PulseLab 1.7.0 - Oficina de Robotica"
$shortcut.Save()

Write-Host "PulseLab 1.7.0 enrolled and configured for the current user." -ForegroundColor Green
Write-Host "Startup shortcut created at: $shortcutPath" -ForegroundColor Green
