#Requires -Version 5.1
# PulseLab - Launcher Portatil Offline (Oficina de Robotica)
[CmdletBinding()]
param(
    [switch]$DebugMode,
    [switch]$AllowUpdate
)

$ErrorActionPreference = "Stop"

# Auto-update remoto desabilitado por politica de seguranca institucional
if ($AllowUpdate) {
    throw "Atualizacao remota desabilitada: nao ha infraestrutura institucional de assinatura digital configurada. Realize a atualizacao manual utilizando pacote institucional previamente verificado e autenticado pela instituicao."
}

try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch {}

$scriptRoot = $PSScriptRoot
$bridge = Join-Path $scriptRoot "bridge\pulselab-bridge.ps1"
$app = Join-Path $scriptRoot "app\alunos"
if (-not (Test-Path -LiteralPath $app)) { $app = Join-Path $scriptRoot "alunos" }

if (-not (Test-Path -LiteralPath $bridge) -or -not (Test-Path -LiteralPath (Join-Path $app "index.html"))) {
    throw "Pacote incompleto. Extraia todo o ZIP antes de iniciar."
}

# --- VERIFICA VERSAO LOCAL ---
$localVersion = "2.2.0"
$verFile = Join-Path $scriptRoot "VERSION"
if (Test-Path -LiteralPath $verFile) {
    try { $localVersion = (Get-Content $verFile -Raw).Trim() } catch {}
}

Write-Host "===================================================================="
Write-Host "           PULSELAB $localVersion - OFICINA DE ROBOTICA"
Write-Host "===================================================================="

# --- INICIALIZACAO DO SERVIDOR LOCAL (BRIDGE) ---
$port = 43128
$running = $null
try { $running = Invoke-RestMethod -Uri "http://127.0.0.1:$port/health" -TimeoutSec 1 } catch {}

if (-not $running) {
    Start-Process powershell.exe -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", ('"' + $bridge + '"'), "-Port", "$port", "-AppRoot", ('"' + $app + '"'))
    $ready = $false
    for ($i = 0; $i -lt 20; $i++) {
        try {
            $health = Invoke-RestMethod -Uri "http://127.0.0.1:$port/health" -TimeoutSec 1
            if ($health) { $ready = $true; break }
        } catch {}
        Start-Sleep -Milliseconds 250
    }
    if (-not $ready) { throw "Servidor local nao iniciou na porta $port. Confira a janela do PowerShell." }
}

Write-Host "[OK] Servidor ativo em http://127.0.0.1:$port/alunos/"
Start-Process "http://127.0.0.1:$port/alunos/"
