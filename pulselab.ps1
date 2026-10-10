#Requires -Version 5.1
# PulseLab - Launcher Portatil Offline (Oficina de Robotica)
[CmdletBinding()]
param(
    [switch]$DebugMode,
    [switch]$NoUpdate
)

$ErrorActionPreference = "Stop"

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
$localVersion = "2.2.7"
$verFile = Join-Path $scriptRoot "VERSION"
if (Test-Path -LiteralPath $verFile) {
    try { $localVersion = (Get-Content $verFile -Raw).Trim() } catch {}
}

# --- ROTINA DE ATUALIZACAO AUTOMATICA VERIFICADA (SHA-256) E RESILIENTE A FALHAS ---
function Update-PulseLabIfOnline {
    param(
        [string]$CurrentVersion,
        [string]$TargetDir
    )

    $versionUrl = "https://raw.githubusercontent.com/vfamim/pulselab/main/version.json"

    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    } catch {}

    # Probe rápido (timeout 2000ms). Se estiver offline na escola, sai instantaneamente.
    $remoteMeta = $null
    try {
        $req = [System.Net.WebRequest]::Create($versionUrl)
        $req.Timeout = 2000
        $req.Method = "GET"
        $resp = $req.GetResponse()
        $reader = New-Object System.IO.StreamReader($resp.GetResponseStream(), [System.Text.Encoding]::UTF8)
        $jsonText = $reader.ReadToEnd()
        $reader.Close()
        $resp.Close()
        if ($jsonText) {
            $remoteMeta = $jsonText | ConvertFrom-Json
        }
    } catch {
        # Sem internet ou timeout -> segue direto com o modelo vigente sem erro
        return
    }

    if (-not $remoteMeta -or -not $remoteMeta.version -or $remoteMeta.auto_update_enabled -eq $false) {
        return
    }

    # Comparar versões SemVer
    $cleanLocal = ($CurrentVersion -replace '[^0-9\.]', '').Trim('.')
    $cleanRemote = ($remoteMeta.version -replace '[^0-9\.]', '').Trim('.')
    try {
        $vLocal = [System.Version]::Parse($cleanLocal)
        $vRemote = [System.Version]::Parse($cleanRemote)
        if ($vRemote -le $vLocal) {
            return
        }
    } catch {
        if ($cleanRemote -eq $cleanLocal) {
            return
        }
    }

    Write-Host "[ATUALIZACAO] Nova versao detectada ($($remoteMeta.version)). Baixando pacote verificado..."
    $pkgUrl = $remoteMeta.package_url
    if (-not $pkgUrl) {
        $pkgUrl = "https://raw.githubusercontent.com/vfamim/pulselab/main/instalador/downloads/PulseLab-$($remoteMeta.version)-Windows.zip"
    }
    $shaUrl = "$pkgUrl.sha256"

    $tempDir = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "PulseLabUpdate_$([Guid]::NewGuid().ToString('N'))")
    try {
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        $tempZip = Join-Path $tempDir "package.zip"
        $tempSha = Join-Path $tempDir "package.zip.sha256"

        $webClient = New-Object System.Net.WebClient

        # 1. Baixar .sha256 oficial
        $webClient.DownloadFile($shaUrl, $tempSha)
        $expectedShaRaw = Get-Content -LiteralPath $tempSha -Raw
        $shaRegex = '\b([a-f0-9]{64})\b'
        if ($expectedShaRaw -notmatch $shaRegex) {
            Write-Host "[ATUALIZACAO] Checksum SHA-256 remoto invalido. Mantendo versao vigente."
            return
        }
        $expectedSha = $matches[1].ToLower()

        # 2. Baixar pacote ZIP
        $webClient.DownloadFile($pkgUrl, $tempZip)

        # 3. Validar SHA-256 localmente
        $hasher = [System.Security.Cryptography.SHA256]::Create()
        $fs = [System.IO.File]::OpenRead($tempZip)
        $hashBytes = $hasher.ComputeHash($fs)
        $fs.Close()
        $hasher.Dispose()
        $actualSha = ([BitConverter]::ToString($hashBytes) -replace '-', '').ToLower()

        if ($actualSha -ne $expectedSha) {
            Write-Host "[ATUALIZACAO] Checksum SHA-256 divergente. Abortando atualizacao para seguranca."
            return
        }

        # 4. Extrair arquivos verificados
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $extractDir = Join-Path $tempDir "extracted"
        [System.IO.Compression.ZipFile]::ExtractToDirectory($tempZip, $extractDir)

        $payloadRoot = $extractDir
        $subDirs = Get-ChildItem -LiteralPath $extractDir -Directory
        if ($subDirs.Count -eq 1 -and (Test-Path -LiteralPath (Join-Path $subDirs[0].FullName "pulselab.ps1"))) {
            $payloadRoot = $subDirs[0].FullName
        }

        # Copiar sobre o TargetDir preservando dados_locais intacto
        $items = Get-ChildItem -LiteralPath $payloadRoot
        foreach ($item in $items) {
            if ($item.Name -eq "dados_locais") {
                continue
            }
            $dest = Join-Path $TargetDir $item.Name
            if ($item.PSIsContainer) {
                Copy-Item -LiteralPath $item.FullName -Destination $dest -Recurse -Force
            } else {
                Copy-Item -LiteralPath $item.FullName -Destination $dest -Force
            }
        }

        Write-Host "[OK] Atualizado com sucesso para a versao $($remoteMeta.version)!"
    } catch {
        Write-Host "[ATUALIZACAO] Falha ao aplicar atualizacao ($($_.Exception.Message)). Mantendo versao vigente."
    } finally {
        if (Test-Path -LiteralPath $tempDir) {
            try { Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue } catch {}
        }
    }
}

if (-not $NoUpdate) {
    Update-PulseLabIfOnline -CurrentVersion $localVersion -TargetDir $scriptRoot
    if (Test-Path -LiteralPath $verFile) {
        try { $localVersion = (Get-Content $verFile -Raw).Trim() } catch {}
    }
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

    $bridgeArgs = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$bridge`" -Port $port -AppRoot `"$app`""
    $bridgeProc = Start-Process powershell.exe -ArgumentList $bridgeArgs -PassThru -WindowStyle Hidden -RedirectStandardError $startupErrLog

    $ready = $false
    $maxAttempts = 60
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

        # A janela do bridge fecha ao falhar; o log em dados_locais e a unica pista que sobra.
        $logCandidates = @((Join-Path $scriptRoot "dados_locais\bridge.log"))
        if ($env:LOCALAPPDATA) { $logCandidates += Join-Path $env:LOCALAPPDATA "PulseLab\dados_locais\bridge.log" }
        foreach ($log in $logCandidates) {
            if (Test-Path -LiteralPath $log) {
                Write-Host "Ultimas linhas de ${log}:"
                Get-Content -LiteralPath $log -Tail 15 | ForEach-Object { Write-Host "  $_" }
                break
            }
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

# Disparo preferencial do Microsoft Edge em Modo Aplicativo Dedicado (--app)
# Evita abas, barra de enderecos e distracoes na bancada, operando com consumo ultraleve (~90MB).
$edgeCandidates = @(
    (Join-Path ${env:ProgramFiles(x86)} "Microsoft\Edge\Application\msedge.exe"),
    (Join-Path $env:ProgramFiles "Microsoft\Edge\Application\msedge.exe"),
    (Join-Path $env:LOCALAPPDATA "Microsoft\Edge\Application\msedge.exe")
)
$edgePath = $edgeCandidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1

if ($edgePath) {
    Start-Process -FilePath $edgePath -ArgumentList "--app=`"http://127.0.0.1:$port/alunos/`" --disable-features=Translate,InterestFeedContentSuggestions"
} else {
    Start-Process "http://127.0.0.1:$port/alunos/"
}
