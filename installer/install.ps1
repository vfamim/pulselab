#Requires -Version 5.1
# PulseLab 1.5.0 - local, secret-free Windows installer

[CmdletBinding()]
param(
    [string]$SupabaseUrl = $env:PULSELAB_URL,
    [string]$SupabaseAnonKey = $env:PULSELAB_ANON_KEY,
    [string]$SiteId = "",
    [string]$RegionalHub = "",
    [string]$SchoolCode = "",
    [string]$ComputerId = $env:COMPUTERNAME,
    [string]$DestinationDir = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$Version = "1.5.0"

function Write-InstallLog {
    param([ValidateSet("INFO", "OK", "WARN", "ERROR")][string]$Level, [string]$Message)
    Write-Host "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] [$Level] $Message"
}

function Read-RequiredValue {
    param([string]$CurrentValue, [string]$Prompt)
    $value = $CurrentValue
    while ([string]::IsNullOrWhiteSpace($value)) {
        $value = Read-Host $Prompt
    }
    return $value.Trim().Trim('"').Trim("'")
}

if ([string]::IsNullOrWhiteSpace($DestinationDir)) {
    $localAppData = [Environment]::GetFolderPath("LocalApplicationData")
    if ([string]::IsNullOrWhiteSpace($localAppData)) { throw "LOCALAPPDATA is unavailable." }
    $DestinationDir = Join-Path $localAppData "PulseLab\App"
}

$sourceRoot = $PSScriptRoot
$sourceAgent = Join-Path $sourceRoot "agent\pulselab-agent.ps1"
$sourceConfig = Join-Path $sourceRoot "config\config.json"
$sourceEnrollment = Join-Path $sourceRoot "supabase\scripts\enroll-device.ps1"
foreach ($required in @($sourceAgent, $sourceConfig, $sourceEnrollment)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Installer package is incomplete: $required"
    }
}

try {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase -ErrorAction Stop
} catch {
    throw "PulseLab requires Windows 10/11 Desktop with Windows PowerShell 5.1 and WPF."
}

$SupabaseUrl = Read-RequiredValue $SupabaseUrl "URL do projeto Supabase"
$SupabaseAnonKey = Read-RequiredValue $SupabaseAnonKey "Chave publica anon do Supabase"
$SiteId = Read-RequiredValue $SiteId "Codigo da sede/site"
$RegionalHub = Read-RequiredValue $RegionalHub "Codigo da regional/polo"
$SchoolCode = Read-RequiredValue $SchoolCode "Codigo da escola"
if ($SupabaseUrl -notmatch '^https://[a-z0-9-]+\.supabase\.co/?$') {
    throw "SupabaseUrl must be an HTTPS project URL ending in .supabase.co."
}
foreach ($pair in @{ SiteId=$SiteId; RegionalHub=$RegionalHub; SchoolCode=$SchoolCode }.GetEnumerator()) {
    if ([string]::IsNullOrWhiteSpace([string]$pair.Value) -or [string]$pair.Value -match '^CONFIGURE_') {
        throw "$($pair.Key) must be configured with a real operational code."
    }
}

Write-InstallLog "INFO" "Installing PulseLab $Version for the current Windows user."
$parentDir = Split-Path -Parent $DestinationDir
New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
$stageDir = "$DestinationDir.stage-$([Guid]::NewGuid().ToString('N'))"
$backupDir = "$DestinationDir.backup"
try {
    New-Item -ItemType Directory -Path (Join-Path $stageDir "agent") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $stageDir "config") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $stageDir "supabase\scripts") -Force | Out-Null
    Copy-Item -LiteralPath $sourceAgent -Destination (Join-Path $stageDir "agent\pulselab-agent.ps1") -Force
    Copy-Item -LiteralPath $sourceEnrollment -Destination (Join-Path $stageDir "supabase\scripts\enroll-device.ps1") -Force

    $config = Get-Content -LiteralPath $sourceConfig -Raw -Encoding UTF8 | ConvertFrom-Json
    $config.site_id = $SiteId
    $config.regional_hub = $RegionalHub
    $config.school_code = $SchoolCode
    $config.supabase_url = $SupabaseUrl
    $config.supabase_anon_key = $SupabaseAnonKey
    $config.supabase_key = ""
    $config | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $stageDir "config\config.json") -Encoding UTF8 -Force

    if (Test-Path -LiteralPath $backupDir) { Remove-Item -LiteralPath $backupDir -Recurse -Force }
    if (Test-Path -LiteralPath $DestinationDir) { Move-Item -LiteralPath $DestinationDir -Destination $backupDir -Force }
    Move-Item -LiteralPath $stageDir -Destination $DestinationDir -Force
} catch {
    if (Test-Path -LiteralPath $stageDir) { Remove-Item -LiteralPath $stageDir -Recurse -Force -ErrorAction SilentlyContinue }
    if (-not (Test-Path -LiteralPath $DestinationDir) -and (Test-Path -LiteralPath $backupDir)) {
        Move-Item -LiteralPath $backupDir -Destination $DestinationDir -Force
    }
    throw
}

[Environment]::SetEnvironmentVariable("PULSELAB_URL", $SupabaseUrl, "User")
[Environment]::SetEnvironmentVariable("PULSELAB_ANON_KEY", $SupabaseAnonKey, "User")
[Environment]::SetEnvironmentVariable("PULSELAB_KEY", $null, "User")

$enrollScript = Join-Path $DestinationDir "supabase\scripts\enroll-device.ps1"
Write-InstallLog "INFO" "The one-time enrollment token will be requested in a masked prompt."
& $enrollScript `
    -SupabaseUrl $SupabaseUrl `
    -SupabaseAnonKey $SupabaseAnonKey `
    -SiteId $SiteId `
    -RegionalHub $RegionalHub `
    -SchoolCode $SchoolCode `
    -ComputerId $ComputerId

$agentPath = Join-Path $DestinationDir "agent\pulselab-agent.ps1"
$shortcutName = "Iniciar PulseLab - Oficina de Robotica.lnk"
$locations = @(
    [Environment]::GetFolderPath("Desktop"),
    [Environment]::GetFolderPath("Programs")
) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path -LiteralPath $_) }
foreach ($location in $locations) {
    $shortcutPath = Join-Path $location $shortcutName
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$agentPath`""
    $shortcut.WorkingDirectory = Split-Path -Parent $agentPath
    $shortcut.Description = "PulseLab $Version - Oficina de Robotica"
    $shortcut.Save()
}

if (Test-Path -LiteralPath $backupDir) { Remove-Item -LiteralPath $backupDir -Recurse -Force -ErrorAction SilentlyContinue }
Write-InstallLog "OK" "PulseLab $Version installed and enrolled successfully."
Write-InstallLog "INFO" "Application: $DestinationDir"
Write-InstallLog "INFO" "Device session: $([Environment]::GetFolderPath('LocalApplicationData'))\PulseLab\device_session.dat (DPAPI)"
Read-Host "Pressione Enter para finalizar"
