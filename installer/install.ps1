#Requires -Version 5.1
# PulseLab 1.6.0 - local Windows installer (pre-configured)

[CmdletBinding()]
param(
    [string]$SupabaseUrl = "",
    [string]$SupabaseAnonKey = "",
    [string]$SiteId = "",
    [string]$RegionalHub = "",
    [string]$SchoolCode = "",
    [string]$ComputerId = $env:COMPUTERNAME,
    [string]$DestinationDir = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$Version = "1.6.0"

function Write-InstallLog {
    param([ValidateSet("INFO", "OK", "WARN", "ERROR")][string]$Level, [string]$Message)
    Write-Host "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] [$Level] $Message"
}

if ([string]::IsNullOrWhiteSpace($DestinationDir)) {
    $localAppData = [Environment]::GetFolderPath("LocalApplicationData")
    if ([string]::IsNullOrWhiteSpace($localAppData)) { throw "LOCALAPPDATA is unavailable." }
    $DestinationDir = Join-Path $localAppData "PulseLab\App"
}

$sourceRoot = $PSScriptRoot
$sourceLauncher = Join-Path $sourceRoot "pulselab.ps1"
$sourceAgent = Join-Path $sourceRoot "agent\pulselab-agent.ps1"
$sourceConfig = Join-Path $sourceRoot "config\config.json"
$sourceEnrollment = Join-Path $sourceRoot "supabase\scripts\enroll-device.ps1"
foreach ($required in @($sourceLauncher, $sourceAgent, $sourceConfig)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Installer package is incomplete: $required"
    }
}

try {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase -ErrorAction Stop
} catch {
    throw "PulseLab requires Windows 10/11 Desktop with Windows PowerShell 5.1 and WPF."
}

# Ler configuracao base do pacote para usar valores pre-configurados
$baseConfig = Get-Content -LiteralPath $sourceConfig -Raw -Encoding UTF8 | ConvertFrom-Json

if ([string]::IsNullOrWhiteSpace($SupabaseUrl)) {
    if (-not [string]::IsNullOrWhiteSpace($env:PULSELAB_URL)) {
        $SupabaseUrl = $env:PULSELAB_URL
    } elseif ($baseConfig.PSObject.Properties.Name -contains "supabase_url" -and -not [string]::IsNullOrWhiteSpace([string]$baseConfig.supabase_url)) {
        $SupabaseUrl = [string]$baseConfig.supabase_url
    }
}

if ([string]::IsNullOrWhiteSpace($SupabaseAnonKey)) {
    if (-not [string]::IsNullOrWhiteSpace($env:PULSELAB_ANON_KEY)) {
        $SupabaseAnonKey = $env:PULSELAB_ANON_KEY
    } elseif ($baseConfig.PSObject.Properties.Name -contains "supabase_anon_key" -and -not [string]::IsNullOrWhiteSpace([string]$baseConfig.supabase_anon_key)) {
        $SupabaseAnonKey = [string]$baseConfig.supabase_anon_key
    } elseif ($baseConfig.PSObject.Properties.Name -contains "supabase_key" -and -not [string]::IsNullOrWhiteSpace([string]$baseConfig.supabase_key)) {
        $SupabaseAnonKey = [string]$baseConfig.supabase_key
    }
}

if ([string]::IsNullOrWhiteSpace($SiteId) -and $baseConfig.PSObject.Properties.Name -contains "site_id") {
    $SiteId = [string]$baseConfig.site_id
}
if ([string]::IsNullOrWhiteSpace($RegionalHub) -and $baseConfig.PSObject.Properties.Name -contains "regional_hub") {
    $RegionalHub = [string]$baseConfig.regional_hub
}
if ([string]::IsNullOrWhiteSpace($SchoolCode) -and $baseConfig.PSObject.Properties.Name -contains "school_code") {
    $SchoolCode = [string]$baseConfig.school_code
}

Write-InstallLog "INFO" "Instalando PulseLab $Version para o usuario atual do Windows..."
$parentDir = Split-Path -Parent $DestinationDir
New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
$stageDir = "$DestinationDir.stage-$([Guid]::NewGuid().ToString('N'))"
$backupDir = "$DestinationDir.backup"
try {
    New-Item -ItemType Directory -Path (Join-Path $stageDir "agent") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $stageDir "config") -Force | Out-Null
    Copy-Item -LiteralPath $sourceLauncher -Destination (Join-Path $stageDir "pulselab.ps1") -Force
    Copy-Item -LiteralPath $sourceAgent -Destination (Join-Path $stageDir "agent\pulselab-agent.ps1") -Force
    if (Test-Path -LiteralPath $sourceEnrollment -PathType Leaf) {
        New-Item -ItemType Directory -Path (Join-Path $stageDir "supabase\scripts") -Force | Out-Null
        Copy-Item -LiteralPath $sourceEnrollment -Destination (Join-Path $stageDir "supabase\scripts\enroll-device.ps1") -Force
    }

    # Copiar batch files auxiliares se existirem
    foreach ($batFile in @("Iniciar-Oficina-Oficial.bat", "Iniciar-PulseLab-Dev.bat", "Testar-Pulselab-Rapido.bat")) {
        $srcBat = Join-Path $sourceRoot $batFile
        if (Test-Path -LiteralPath $srcBat -PathType Leaf) {
            Copy-Item -LiteralPath $srcBat -Destination (Join-Path $stageDir $batFile) -Force
        }
    }

    $config = Get-Content -LiteralPath $sourceConfig -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not [string]::IsNullOrWhiteSpace($SiteId)) { $config.site_id = $SiteId }
    if (-not [string]::IsNullOrWhiteSpace($RegionalHub)) { $config.regional_hub = $RegionalHub }
    if (-not [string]::IsNullOrWhiteSpace($SchoolCode)) { $config.school_code = $SchoolCode }
    if (-not [string]::IsNullOrWhiteSpace($SupabaseUrl)) { $config.supabase_url = $SupabaseUrl }
    if (-not [string]::IsNullOrWhiteSpace($SupabaseAnonKey)) {
        $config.supabase_anon_key = $SupabaseAnonKey
        $config.supabase_key = $SupabaseAnonKey
    }
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

if (-not [string]::IsNullOrWhiteSpace($SupabaseUrl)) {
    [Environment]::SetEnvironmentVariable("PULSELAB_URL", $SupabaseUrl, "User")
}
if (-not [string]::IsNullOrWhiteSpace($SupabaseAnonKey)) {
    [Environment]::SetEnvironmentVariable("PULSELAB_ANON_KEY", $SupabaseAnonKey, "User")
}

$launcherPath = Join-Path $DestinationDir "pulselab.ps1"
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
    $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$launcherPath`""
    $shortcut.WorkingDirectory = $DestinationDir
    $shortcut.Description = "PulseLab $Version - Oficina de Robotica"
    $shortcut.Save()
}

if (Test-Path -LiteralPath $backupDir) { Remove-Item -LiteralPath $backupDir -Recurse -Force -ErrorAction SilentlyContinue }
Write-InstallLog "OK" "PulseLab $Version instalado com sucesso!"
Write-InstallLog "INFO" "Aplicativo instalado em: $DestinationDir"
Write-InstallLog "INFO" "Atalho criado na Area de Trabalho: Iniciar PulseLab - Oficina de Robotica"
Write-Host ""
Write-Host "====================================================================" -ForegroundColor Green
Write-Host "  Instalacao concluida! O atalho ja esta na sua Area de Trabalho.   " -ForegroundColor Green
Write-Host "====================================================================" -ForegroundColor Green
Write-Host ""
Start-Sleep -Seconds 2
