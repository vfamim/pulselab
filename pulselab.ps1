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
$localVersion = "2.2.3"
$verFile = Join-Path $scriptRoot "VERSION"
if (Test-Path -LiteralPath $verFile) {
    try { $localVersion = (Get-Content $verFile -Raw).Trim() } catch {}
}

Write-Host "===================================================================="
Write-Host "           PULSELAB $localVersion - OFICINA DE ROBOTICA"
Write-Host "===================================================================="

# --- 1. VALIDACAO DE SINTAXE DO BRIDGE (AST FAIL-FAST) ---
$parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($bridge, [ref]$null, [ref]$parseErrors)
if ($parseErrors -and $parseErrors.Count -gt 0) {
    $firstErr = $parseErrors[0]
    $errDetail = "Erro de sintaxe no script do servidor bridge ($($firstErr.Extent.File): linha $($firstErr.Extent.StartLineNumber)): $($firstErr.Message)"
    Write-Host "[ERRO CRITICO] $errDetail" -ForegroundColor Red
    throw $errDetail
}

# --- 2. GESTAO DE PORTA E PROCESSO RESIDUAL ---
$port = 43128
$running = $null
try {
    $health = Invoke-RestMethod -Uri "http://127.0.0.1:$port/health" -TimeoutSec 1
    if ($health -and $health.status -eq "ok") {
        $running = $health
    }
} catch {}

if (-not $running) {
    # Verificar se ha conexao escutando na porta
    $isPortBound = $false
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $iar = $tcp.BeginConnect("127.0.0.1", $port, $null, $null)
        if ($iar.AsyncWaitHandle.WaitOne(400)) {
            if ($tcp.Connected) {
                $tcp.EndConnect($iar)
                $isPortBound = $true
            }
        }
        $tcp.Close()
    } catch {}

    if ($isPortBound) {
        $owningPid = $null
        $owningProcName = ""
        try {
            $conn = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($conn) {
                $owningPid = $conn.OwningProcess
                $procObj = Get-Process -Id $owningPid -ErrorAction SilentlyContinue
                if ($procObj) { $owningProcName = $procObj.ProcessName }
            }
        } catch {}

        # Identificar se e um bridge residual do PulseLab travado
        $isResidualBridge = $false
        if ($owningPid -and $owningProcName -match "^powershell") {
            try {
                $wmi = Get-CimInstance Win32_Process -Filter "ProcessId = $owningPid" -ErrorAction SilentlyContinue
                if ($wmi -and $wmi.CommandLine -match "pulselab-bridge") {
                    $isResidualBridge = $true
                }
            } catch {}
        }

        if ($isResidualBridge) {
            Write-Host "[AVISO] Processo residual do Bridge (PID $owningPid) detectado sem responder a /health. Encerrando para reiniciar com seguranca..." -ForegroundColor Yellow
            try {
                Stop-Process -Id $owningPid -Force -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 800
            } catch {}
        } else {
            $procInfo = if ($owningPid) { " (PID $owningPid - $owningProcName)" } else { "" }
            $errMsg = "A porta $port ja esta ocupada por outro processo$procInfo que nao responde a /health. Encerre o aplicativo conflitante para iniciar o PulseLab."
            Write-Host "[ERRO CRITICO] $errMsg" -ForegroundColor Red
            throw $errMsg
        }
    }

    # --- 3. INICIALIZACAO DO BRIDGE COM MONITORAMENTO E LOG DE ERRO ---
    $dataDir = Join-Path $scriptRoot "dados_locais"
    if (-not (Test-Path -LiteralPath $dataDir)) {
        try { New-Item -ItemType Directory -Path $dataDir -Force | Out-Null } catch {}
    }
    $startupErrLog = if (Test-Path -LiteralPath $dataDir) {
        Join-Path $dataDir "bridge-startup-error.log"
    } else {
        Join-Path $scriptRoot "bridge-startup-error.log"
    }
    if (Test-Path -LiteralPath $startupErrLog) {
        try { Remove-Item -LiteralPath $startupErrLog -Force -ErrorAction SilentlyContinue } catch {}
    }

    $bridgeArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$bridge`" -Port $port -AppRoot `"$app`""
    $bridgeProc = Start-Process powershell.exe -ArgumentList $bridgeArgs -PassThru -RedirectStandardError $startupErrLog

    $ready = $false
    $maxAttempts = 40
    for ($i = 0; $i -lt $maxAttempts; $i++) {
        # Deteccao antecipada de encerramento do processo filho
        if ($bridgeProc -and $bridgeProc.HasExited) {
            break
        }

        try {
            $health = Invoke-RestMethod -Uri "http://127.0.0.1:$port/health" -TimeoutSec 1
            if ($health -and $health.status -eq "ok") {
                $ready = $true
                break
            }
        } catch {}

        Start-Sleep -Milliseconds 250
    }

    if (-not $ready) {
        $errDetail = ""
        if ($bridgeProc -and $bridgeProc.HasExited) {
            $exitCode = try { $bridgeProc.ExitCode } catch { "desconhecido" }
            $rawErr = if (Test-Path -LiteralPath $startupErrLog) {
                try { (Get-Content -LiteralPath $startupErrLog -Raw -ErrorAction SilentlyContinue).Trim() } catch { "" }
            } else { "" }

            if ($rawErr) {
                $errDetail = "Servidor local (PID $($bridgeProc.Id)) encerrou prematuramente com codigo $exitCode.`r`nDetalhes do erro:`r`n$rawErr"
            } else {
                $errDetail = "Servidor local (PID $($bridgeProc.Id)) encerrou prematuramente com codigo $exitCode sem saida de erro."
            }
        } else {
            $pidInfo = if ($bridgeProc) { " (PID $($bridgeProc.Id))" } else { "" }
            $errDetail = "Servidor local$pidInfo em execucao, mas nao respondeu na porta $port dentro do tempo limite. Confira a janela do PowerShell."
        }

        Write-Host "[ERRO CRITICO] $errDetail" -ForegroundColor Red
        throw $errDetail
    }

    # Limpeza do log temporario se inicializacao ocorreu sem erros
    if (Test-Path -LiteralPath $startupErrLog) {
        try {
            $rawErr = (Get-Content -LiteralPath $startupErrLog -Raw -ErrorAction SilentlyContinue).Trim()
            if (-not $rawErr) {
                Remove-Item -LiteralPath $startupErrLog -Force -ErrorAction SilentlyContinue
            }
        } catch {}
    }
}

Write-Host "[OK] Servidor ativo em http://127.0.0.1:$port/alunos/"
Start-Process "http://127.0.0.1:$port/alunos/"
