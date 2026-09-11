#Requires -Version 5.1
# PulseLab 1.7.1 - Web-First Bridge & Student WebApp Launcher

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
Write-Host "               PULSELAB 1.7.1 - OFICINA DE ROBOTICA"
Write-Host "===================================================================="
Write-Host "Iniciando servidor local do PulseLab na porta $Port..."

# Verificar se o Bridge ja esta rodando
$alreadyRunning = $false
try {
    $resp = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/health" -UseBasicParsing -TimeoutSec 1 -ErrorAction SilentlyContinue
    if ($resp -and $resp.StatusCode -eq 200) { $alreadyRunning = $true }
} catch {}

if (-not $alreadyRunning) {
    $argList = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-WindowStyle", "Hidden",
        "-File", $bridgeScript,
        "-Port", [string]$Port,
        "-AppRoot", $AppRoot,
        "-DataDir", $DataDir
    )
    Start-Process -FilePath "powershell.exe" -ArgumentList $argList
    
    # Aguardar brevemente ate o servidor responder
    for ($i = 0; $i -lt 10; $i++) {
        Start-Sleep -Milliseconds 300
        try {
            $resp = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/health" -UseBasicParsing -TimeoutSec 1 -ErrorAction SilentlyContinue
            if ($resp -and $resp.StatusCode -eq 200) { break }
        } catch {}
    }
}

if (-not $NoBrowser) {
    Write-Host "Abrindo interface dos alunos no navegador padrao..."
    Start-Process "http://127.0.0.1:$Port/alunos/"
}

Write-Host "[OK] PulseLab ativo em http://127.0.0.1:$Port/alunos/"
Write-Host "Alertas nativos aos 20 e 40 minutos de oficina."
