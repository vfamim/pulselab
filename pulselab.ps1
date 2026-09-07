#Requires -Version 5.1
# PulseLab 1.7.0 - Web-First Bridge & Student PWA Launcher

[CmdletBinding()]
param(
    [int]$Port = 43127,
    [string]$AppRoot = "",
    [string]$DataDir = "",
    [switch]$NoBrowser,
    [switch]$Hidden
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = $PSScriptRoot
$bridgeScript = Join-Path $scriptRoot "bridge\pulselab-bridge.ps1"
if (-not (Test-Path -LiteralPath $bridgeScript -PathType Leaf)) {
    $altBridge = Join-Path $env:LOCALAPPDATA "PulseLab\bridge\pulselab-bridge.ps1"
    if (Test-Path -LiteralPath $altBridge -PathType Leaf) {
        $bridgeScript = $altBridge
        $scriptRoot = Join-Path $env:LOCALAPPDATA "PulseLab"
    } else {
        throw "PulseLab bridge script not found: $bridgeScript"
    }
}

if ([string]::IsNullOrWhiteSpace($AppRoot)) {
    $candidates = @(
        (Join-Path $scriptRoot "app\alunos"),
        (Join-Path $scriptRoot "alunos"),
        (Join-Path $env:LOCALAPPDATA "PulseLab\app\alunos")
    )
    foreach ($cand in $candidates) {
        if (Test-Path -LiteralPath (Join-Path $cand "index.html") -PathType Leaf) {
            $AppRoot = $cand
            break
        }
    }
}

if ([string]::IsNullOrWhiteSpace($DataDir)) {
    $DataDir = Join-Path $env:LOCALAPPDATA "PulseLab\data"
}

Write-Host "===================================================================="
Write-Host "               PULSELAB 1.7.0 - OFICINA DE ROBÓTICA"
Write-Host "===================================================================="
Write-Host "Iniciando servidor local do PulseLab na porta $Port..."

$windowStyle = if ($Hidden) { "Hidden" } else { "Normal" }

Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$bridgeScript`" -Port $Port -AppRoot `"$AppRoot`" -DataDir `"$DataDir`""

Start-Sleep -Milliseconds 800

if (-not $NoBrowser) {
    Write-Host "Abrindo interface dos alunos no navegador padrão..."
    Start-Process "http://127.0.0.1:$Port/alunos/"
}

Write-Host "[OK] PulseLab ativo em http://127.0.0.1:$Port/alunos/"
Write-Host "Alertas nativos aos 20 e 40 minutos de oficina."
