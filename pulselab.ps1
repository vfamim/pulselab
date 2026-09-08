#Requires -Version 5.1
# PulseLab 1.7.1 - Web-First Bridge & Student PWA Launcher

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

function Get-DefaultBrowserExe {
    try {
        $progId = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\http\UserChoice" -ErrorAction SilentlyContinue).ProgId
        if (-not $progId) {
            $progId = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice" -ErrorAction SilentlyContinue).ProgId
        }
        if ($progId) {
            $cmd = (Get-ItemProperty "Registry::HKEY_CLASSES_ROOT\$progId\shell\open\command" -ErrorAction SilentlyContinue).'(default)'
            if ($cmd -match '"([^"]+\.exe)"') {
                return $Matches[1]
            } elseif ($cmd -match '([^\s]+\.exe)') {
                return $Matches[1]
            }
        }
    } catch {}
    return $null
}

Write-Host "===================================================================="
Write-Host "               PULSELAB 1.7.1 - OFICINA DE ROBÓTICA"
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
        $ws.Run($cmd, 0, $false) | Out-Null
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
    $browserExe = Get-DefaultBrowserExe
    $opened = $false

    if ($browserExe -and (Test-Path -LiteralPath $browserExe -PathType Leaf)) {
        $browserName = [System.IO.Path]::GetFileNameWithoutExtension($browserExe)
        $browserLower = $browserName.ToLowerInvariant()

        # Se o navegador padrão for baseado em Chromium (Brave, Chrome, Edge, Vivaldi, Opera)
        # abrir em modo janela dedicada (--app) para foco imediato no primeiro plano da tela
        if ($browserLower -match 'brave|chrome|msedge|edge|opera|vivaldi') {
            try {
                Write-Host "Abrindo interface no navegador padrão ($browserName) em janela dedicada..." -ForegroundColor Green
                Start-Process -FilePath $browserExe -ArgumentList @("--app=$targetUrl")
                $opened = $true
            } catch {}
        } elseif ($browserLower -match 'firefox') {
            try {
                Write-Host "Abrindo interface no navegador padrão ($browserName)..." -ForegroundColor Green
                Start-Process -FilePath $browserExe -ArgumentList @("-new-window", $targetUrl)
                $opened = $true
            } catch {}
        } else {
            try {
                Write-Host "Abrindo interface no navegador padrão ($browserName)..." -ForegroundColor Green
                Start-Process -FilePath $browserExe -ArgumentList @($targetUrl)
                $opened = $true
            } catch {}
        }
    }

    if (-not $opened) {
        Write-Host "Abrindo interface no navegador padrão do sistema..." -ForegroundColor Cyan
        Start-Process $targetUrl
    }
}

Write-Host "[OK] PulseLab ativo em http://127.0.0.1:$Port/alunos/"
Write-Host "Alertas nativos aos 20 e 40 minutos de oficina."
