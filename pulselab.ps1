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

# Verificar se o Bridge já está rodando
$alreadyRunning = $false
try {
    $resp = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/health" -UseBasicParsing -TimeoutSec 1 -ErrorAction SilentlyContinue
    if ($resp -and $resp.StatusCode -eq 200) { $alreadyRunning = $true }
} catch {}

if (-not $alreadyRunning) {
    try {
        $ws = New-Object -ComObject WScript.Shell
        $cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$bridgeScript`" -Port $Port -AppRoot `"$AppRoot`" -DataDir `"$DataDir`""
        $ws.Run($cmd, 0, $false)
    } catch {
        $argList = @(
            '-NoProfile',
            '-ExecutionPolicy', 'Bypass',
            '-WindowStyle', 'Hidden',
            '-File', $bridgeScript,
            '-Port', [string]$Port,
            '-AppRoot', $AppRoot,
            '-DataDir', $DataDir
        )
        Start-Process -FilePath "powershell.exe" -ArgumentList $argList
    }
    
    # Aguardar até o servidor responder (até 6 segundos)
    $started = $false
    for ($i = 0; $i -lt 15; $i++) {
        Start-Sleep -Milliseconds 400
        try {
            $resp = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/health" -UseBasicParsing -TimeoutSec 1 -ErrorAction SilentlyContinue
            if ($resp -and $resp.StatusCode -eq 200) {
                $started = $true
                break
            }
        } catch {}
    }

    if (-not $started) {
        $logPath = Join-Path $DataDir "bridge.log"
        Write-Host "[AVISO] O servidor local demorou para responder." -ForegroundColor Yellow
        if (Test-Path $logPath) {
            Write-Host "Últimas linhas do log ($logPath):" -ForegroundColor Yellow
            Get-Content $logPath -Tail 5 | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
        }
    }
}

if (-not $NoBrowser) {
    $targetUrl = "http://127.0.0.1:$Port/alunos/"
    
    # Priorizar navegadores Chromium com modo --app para abrir janela limpa e com foco na frente
    $chromiumCandidates = @(
        "$env:ProgramFiles\BraveSoftware\Brave-Browser\Application\brave.exe",
        "${env:ProgramFiles(x86)}\BraveSoftware\Brave-Browser\Application\brave.exe",
        "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\Application\brave.exe",
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe"
    )

    $opened = $false
    foreach ($exe in $chromiumCandidates) {
        if (-not [string]::IsNullOrWhiteSpace($exe) -and (Test-Path -LiteralPath $exe -PathType Leaf)) {
            try {
                $browserName = [System.IO.Path]::GetFileNameWithoutExtension($exe)
                Write-Host "Abrindo interface em janela dedicada via $browserName..." -ForegroundColor Green
                Start-Process -FilePath $exe -ArgumentList @("--app=$targetUrl")
                $opened = $true
                break
            } catch {}
        }
    }

    if (-not $opened) {
        Write-Host "Abrindo interface dos alunos no navegador padrão..." -ForegroundColor Cyan
        Start-Process $targetUrl
    }
}

Write-Host "[OK] PulseLab ativo em http://127.0.0.1:$Port/alunos/"
Write-Host "Alertas nativos aos 20 e 40 minutos de oficina."
