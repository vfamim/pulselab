#Requires -Version 5.1
# PulseLab 1.6.0 - compatibility setup for a checked-out repository

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

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase -ErrorAction Stop
[Environment]::SetEnvironmentVariable("PULSELAB_URL", $SupabaseUrl, "User")
[Environment]::SetEnvironmentVariable("PULSELAB_ANON_KEY", $SupabaseAnonKey, "User")
[Environment]::SetEnvironmentVariable("PULSELAB_KEY", $null, "User")

& $enrollPath `
    -SupabaseUrl $SupabaseUrl `
    -SupabaseAnonKey $SupabaseAnonKey `
    -SiteId $SiteId `
    -RegionalHub $RegionalHub `
    -SchoolCode $SchoolCode `
    -ComputerId $ComputerId

$locations = @([Environment]::GetFolderPath("Desktop"), [Environment]::GetFolderPath("Programs")) |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path -LiteralPath $_) }
foreach ($location in $locations) {
    $shortcutPath = Join-Path $location "Iniciar PulseLab - Oficina de Robotica.lnk"
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$LauncherPath`""
    $shortcut.WorkingDirectory = $repoRoot
    $shortcut.Description = "PulseLab 1.6.0 - Oficina de Robotica"
    $shortcut.Save()
}
Write-Host "PulseLab 1.6.0 enrolled and configured for the current user." -ForegroundColor Green
