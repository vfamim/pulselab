#Requires -Version 5.1
# PulseLab 1.7.0 - Local Windows Installer (PWA + Bridge)

[CmdletBinding()]
param(
    [string]$DestinationDir = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$Version = "1.7.0"

function Write-InstallLog {
    param([ValidateSet("INFO", "OK", "WARN", "ERROR")][string]$Level, [string]$Message)
    Write-Host "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] [$Level] $Message"
}

if ([string]::IsNullOrWhiteSpace($DestinationDir)) {
    $localAppData = [Environment]::GetFolderPath("LocalApplicationData")
    if ([string]::IsNullOrWhiteSpace($localAppData)) { throw "LOCALAPPDATA is unavailable." }
    $DestinationDir = Join-Path $localAppData "PulseLab"
}

$sourceRoot = $PSScriptRoot
Write-InstallLog "INFO" "Instalando PulseLab $Version para o usuário atual do Windows..."

New-Item -ItemType Directory -Path $DestinationDir -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $DestinationDir "data") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $DestinationDir "app\alunos") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $DestinationDir "bridge") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $DestinationDir "config") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $DestinationDir "tools") -Force | Out-Null

# Copiar arquivos da aplicacao (PWA)
$appSrc = Join-Path $sourceRoot "app\alunos"
if (-not (Test-Path -LiteralPath $appSrc)) {
    $appSrc = Join-Path $sourceRoot "alunos"
}
if (Test-Path -LiteralPath $appSrc) {
    Copy-Item -Path (Join-Path $appSrc "*") -Destination (Join-Path $DestinationDir "app\alunos") -Recurse -Force
}

# Copiar Bridge
$bridgeSrc = Join-Path $sourceRoot "bridge"
if (Test-Path -LiteralPath $bridgeSrc) {
    Copy-Item -Path (Join-Path $bridgeSrc "*") -Destination (Join-Path $DestinationDir "bridge") -Recurse -Force
}

# Copiar Config
$configSrc = Join-Path $sourceRoot "config"
if (Test-Path -LiteralPath $configSrc) {
    Copy-Item -Path (Join-Path $configSrc "*") -Destination (Join-Path $DestinationDir "config") -Recurse -Force
}

# Copiar Ferramentas
$toolsSrc = Join-Path $sourceRoot "tools"
if (Test-Path -LiteralPath $toolsSrc) {
    Copy-Item -Path (Join-Path $toolsSrc "*") -Destination (Join-Path $DestinationDir "tools") -Recurse -Force
}

# Copiar arquivos de inicializacao e scripts
foreach ($file in @("Iniciar-PulseLab.bat", "Desinstalar-PulseLab.bat", "Instalar-PulseLab.bat", "pulselab.ps1", "VERSION")) {
    $src = Join-Path $sourceRoot $file
    if (Test-Path -LiteralPath $src) {
        Copy-Item -LiteralPath $src -Destination (Join-Path $DestinationDir $file) -Force
    }
}

# Criar atalho na Area de Trabalho
$desktopPath = [Environment]::GetFolderPath("Desktop")
if (-not [string]::IsNullOrWhiteSpace($desktopPath) -and (Test-Path -LiteralPath $desktopPath)) {
    $shortcutPath = Join-Path $desktopPath "PulseLab - Iniciar Oficina.lnk"
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = Join-Path $DestinationDir "Iniciar-PulseLab.bat"
    $shortcut.WorkingDirectory = $DestinationDir
    $shortcut.Description = "PulseLab $Version - Iniciar Oficina de Robótica"
    $shortcut.Save()
}

Write-InstallLog "OK" "PulseLab $Version instalado com sucesso!"
Write-InstallLog "INFO" "Diretório de instalação: $DestinationDir"
Write-InstallLog "INFO" "Atalho criado na Área de Trabalho: PulseLab - Iniciar Oficina"
Write-Host ""
Write-Host "====================================================================" -ForegroundColor Green
Write-Host "  Instalação concluída! O atalho já está na sua Área de Trabalho.   " -ForegroundColor Green
Write-Host "====================================================================" -ForegroundColor Green
Write-Host ""
