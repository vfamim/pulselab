# ==============================================================================
# PulseLab — Bridge HTTP Local e Companion de Alertas (Windows Offline)
# ==============================================================================
# - Servidor web local em http://127.0.0.1:43127/alunos/
# - Agenda de checkpoints e relógio de sessão independente
# - Alertas sonoros e visuais nativos quando o navegador estiver em segundo plano
# - Extração de métricas de telemetria do SPIKE via spike-parser.ps1
# ==============================================================================

[CmdletBinding()]
param(
    [int]$Port = 43127,
    [string]$AppRoot = "",
    [string]$DataDir = "",
    [switch]$NoAlert
)

$ErrorActionPreference = "Continue"

# 1. Carregar o parser do SPIKE
$parserScript = Join-Path $PSScriptRoot "spike-parser.ps1"
if (Test-Path $parserScript) {
    . $parserScript
}

# 2. Configurar caminhos
if (-not $AppRoot) {
    $candidateApp = Join-Path $PSScriptRoot "..\app\alunos"
    if (Test-Path $candidateApp) {
        $AppRoot = (Resolve-Path $candidateApp).Path
    } else {
        $candidateAlunos = Join-Path $PSScriptRoot "..\alunos"
        if (Test-Path $candidateAlunos) {
            $AppRoot = (Resolve-Path $candidateAlunos).Path
        } else {
            $AppRoot = $PSScriptRoot
        }
    }
}

if (-not $DataDir) {
    $localAppData = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { $env:USERPROFILE }
    $DataDir = Join-Path $localAppData "PulseLab\data"
}

if (-not (Test-Path $DataDir)) {
    New-Item -ItemType Directory -Path $DataDir -Force | Out-Null
}

$scheduleFile = Join-Path $DataDir "active_schedule.json"

# 3. Estado em memória
$script:StartTime = [DateTime]::UtcNow
$script:ActiveSession = $null
$script:LastAlertMark = 0
$script:LastAlertTime = [DateTime]::MinValue
$script:AlertCount = 0

if (Test-Path $scheduleFile) {
    try {
        $loaded = Get-Content -Path $scheduleFile -Raw | ConvertFrom-Json
        $script:ActiveSession = $loaded
    } catch {
        # ignore corrupt schedule
    }
}

# 3.1 Supabase Sync Configuration & Tracker (Store-and-forward)
$script:SupabaseUrl = "https://cylsqbmtglvdfubbarqe.supabase.co"
$script:SupabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImN5bHNxYm10Z2x2ZGZ1YmJhcnFlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzc5NjE1MzIsImV4cCI6MjA5MzUzNzUzMn0.tscU354WLjnYz6E6NOrDQK16ViWBc-Af5FYhvZikFbU"

$candidateConfig = Join-Path $PSScriptRoot "..\config\config.json"
if (-not (Test-Path $candidateConfig)) {
    $candidateConfig = Join-Path $PSScriptRoot "..\..\config\config.json"
}
if (Test-Path $candidateConfig) {
    try {
        $cfgJson = Get-Content -Path $candidateConfig -Raw | ConvertFrom-Json
        if ($cfgJson.supabase_url) { $script:SupabaseUrl = $cfgJson.supabase_url }
        if ($cfgJson.supabase_anon_key) { $script:SupabaseAnonKey = $cfgJson.supabase_anon_key }
    } catch {}
}

$script:BridgeVersion = "1.8.0"
$script:LastSyncAttempt = [DateTime]::MinValue
$script:LastUpdateAttempt = [DateTime]::MinValue
$script:SyncedEventIds = [System.Collections.Generic.HashSet[string]]::new()
$script:SyncedTrackerFile = Join-Path $DataDir "events_synced.txt"

if (Test-Path $script:SyncedTrackerFile) {
    try {
        Get-Content $script:SyncedTrackerFile | ForEach-Object {
            $tracked = $_.Trim()
            if ($tracked) { [void]$script:SyncedEventIds.Add($tracked) }
        }
    } catch {}
}

function Sync-EventsToSupabase {
    $eventsFile = Join-Path $DataDir "events.jsonl"
    if (-not (Test-Path $eventsFile)) { return }

    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls11 -bor [System.Net.SecurityProtocolType]::Tls
    } catch {}

    try {
        $lines = [System.IO.File]::ReadAllLines($eventsFile)
        $syncedCount = 0
        foreach ($line in $lines) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $ev = $line | ConvertFrom-Json
                $eventId = [string]$ev.event_id
                if (-not $eventId -or $script:SyncedEventIds.Contains($eventId)) {
                    continue
                }

                $targetTable = if ($ev._target_table) { 
                    $ev._target_table 
                } elseif ($ev.event_type -in @("pre", "checkpoint", "post")) {
                    "research_events"
                } else {
                    "research_session_events"
                }

                $cleanDict = [System.Collections.Specialized.OrderedDictionary]::new()
                foreach ($prop in $ev.PSObject.Properties) {
                    if (-not $prop.Name.StartsWith("_") -and $null -ne $prop.Value) {
                        $cleanDict[$prop.Name] = $prop.Value
                    }
                }

                $bodyJson = $cleanDict | ConvertTo-Json -Depth 10 -Compress
                $headers = @{
                    apikey = $script:SupabaseAnonKey
                    Authorization = "Bearer $($script:SupabaseAnonKey)"
                    "Content-Type" = "application/json"
                    Prefer = "resolution=ignore-duplicates,return=minimal"
                }

                $uri = "$($script:SupabaseUrl)/rest/v1/$targetTable"
                Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $bodyJson -TimeoutSec 6 -ErrorAction Stop | Out-Null

                [void]$script:SyncedEventIds.Add($eventId)
                [System.IO.File]::AppendAllText($script:SyncedTrackerFile, "$eventId`r`n", [System.Text.Encoding]::UTF8)
                $syncedCount++
            } catch {
                # Offline ou timeout: aguarda próxima janela
                break
            }
        }
        if ($syncedCount -gt 0) {
            Write-BridgeLog "Sincronizados $syncedCount evento(s) da oficina com o Supabase com sucesso." "INFO"
        }
    } catch {}
}

function Check-PulseLabAutoUpdate {
    try {
        $versionUrl = "https://pulselab-robotica-edu.web.app/VERSION"
        $req = [System.Net.WebRequest]::Create($versionUrl)
        $req.Timeout = 2500
        $req.Method = "GET"
        $resp = $req.GetResponse()
        $stream = $resp.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($stream)
        $remoteVer = ($reader.ReadToEnd()).Trim()
        $reader.Close()
        $resp.Close()

        if (-not $remoteVer) { return }

        $isNewer = $false
        try {
            $vRemote = [System.Version]::Parse($remoteVer)
            $vLocal = [System.Version]::Parse($script:BridgeVersion)
            if ($vRemote -gt $vLocal) { $isNewer = $true }
        } catch {
            if ($remoteVer -ne $script:BridgeVersion) { $isNewer = $true }
        }

        if ($isNewer) {
            Write-BridgeLog "[AUTO-UPDATE] Nova versao v$remoteVer detectada na nuvem! Atualizando PWA e Bridge silenciosamente..." "INFO"
            $zipUrl = "https://pulselab-robotica-edu.web.app/instalador/downloads/PulseLab-Alunos-Offline-v$remoteVer.zip"
            $tempZip = Join-Path $env:TEMP "PulseLab-Update-$remoteVer.zip"
            $tempExtract = Join-Path $env:TEMP "PulseLab-Extract-$remoteVer"

            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
            $wc = New-Object System.Net.WebClient
            $wc.DownloadFile($zipUrl, $tempZip)

            if (Test-Path $tempZip) {
                if (Test-Path $tempExtract) { Remove-Item -Recurse -Force $tempExtract -ErrorAction SilentlyContinue }
                Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
                [System.IO.Compression.ZipFile]::ExtractToDirectory($tempZip, $tempExtract)

                $sourceRoot = $tempExtract
                $inner = Join-Path $tempExtract "PulseLab-$remoteVer-Windows"
                if (Test-Path $inner) { $sourceRoot = $inner }

                # Atualizar a pasta da WebApp (PWA estática)
                $srcApp = Join-Path $sourceRoot "app\alunos"
                if (Test-Path $srcApp -and Test-Path $AppRoot) {
                    Copy-Item -Path "$srcApp\*" -Destination $AppRoot -Recurse -Force -ErrorAction SilentlyContinue
                    Write-BridgeLog "[AUTO-UPDATE] WebApp dos alunos atualizada em tempo real para v$remoteVer!" "OK"
                }

                # Atualizar arquivos de versão
                $script:BridgeVersion = $remoteVer
                try {
                    $localVerPath = Join-Path $AppRoot "..\..\VERSION"
                    if (Test-Path (Split-Path -Parent $localVerPath)) {
                        [System.IO.File]::WriteAllText($localVerPath, $remoteVer, [System.Text.Encoding]::UTF8)
                    }
                } catch {}

                # Limpar temporários
                Remove-Item -Force $tempZip -ErrorAction SilentlyContinue
                Remove-Item -Recurse -Force $tempExtract -ErrorAction SilentlyContinue

                Write-BridgeLog "[AUTO-UPDATE] Atualizacao concluida com sucesso para v$remoteVer." "OK"
            }
        }
    } catch {
        # Offline ou timeout: operacao silenciosa
    }
}

$script:LogFilePath = Join-Path $DataDir "bridge.log"

function Write-BridgeLog([string]$msg, [string]$level = "INFO") {
    $timestamp = [DateTime]::UtcNow.ToString("yyyy-MM-dd HH:mm:ss")
    $line = "[$timestamp] [$level] $msg"
    try {
        if ($script:LogFilePath) {
            [System.IO.File]::AppendAllText($script:LogFilePath, "$line`r`n", [System.Text.Encoding]::UTF8)
        }
    } catch {}
    try {
        if ([System.Environment]::UserInteractive -and [System.Console]::WindowHeight -gt 0) {
            Write-Host $line
        }
    } catch {}
}

# 4. Funções de Suporte
function Get-MimeType([string]$ext) {
    switch ($ext.ToLowerInvariant()) {
        ".html" { return "text/html; charset=utf-8" }
        ".js"   { return "application/javascript; charset=utf-8" }
        ".mjs"  { return "application/javascript; charset=utf-8" }
        ".css"  { return "text/css; charset=utf-8" }
        ".json" { return "application/json; charset=utf-8" }
        ".svg"  { return "image/svg+xml" }
        ".webmanifest" { return "application/manifest+json" }
        ".png"  { return "image/png" }
        ".ico"  { return "image/x-icon" }
        default { return "application/octet-stream" }
    }
}

function Play-CheckpointSound {
    try {
        [System.Media.SystemSounds]::Asterisk.Play()
    } catch {
        try { [System.Console]::Beep(880, 200) } catch {}
    }
}

function Show-NativeCheckpointAlert([int]$mark) {
    Write-BridgeLog "[ALERTA] Hora do checkpoint de $mark minutos!" "WARN"

    try {
        $toastScript = $null
        if ($PSScriptRoot) {
            $cToast = Join-Path $PSScriptRoot "pulselab-toast.ps1"
            if (Test-Path $cToast) { $toastScript = (Resolve-Path $cToast).Path }
        }
        if (-not $toastScript -and $env:LOCALAPPDATA) {
            $cToast = Join-Path $env:LOCALAPPDATA "PulseLab\bridge\pulselab-toast.ps1"
            if (Test-Path $cToast) { $toastScript = $cToast }
        }

        if ($toastScript) {
            Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @(
                "-STA",
                "-ExecutionPolicy", "Bypass",
                "-NoProfile",
                "-WindowStyle", "Hidden",
                "-File", "`"$toastScript`"",
                "-Mark", "$mark",
                "-Port", "$Port",
                "-AppRoot", "`"$AppRoot`""
            ) | Out-Null
        } else {
            # Fallback sonoro se o script não for localizado
            try { [System.Media.SystemSounds]::Asterisk.Play() } catch {}
        }
    } catch {
        Write-BridgeLog "Falha ao disparar alerta visual: $($_.Exception.Message)" "WARN"
    }
}

function Check-SessionSchedule {
    if ($NoAlert -or $null -eq $script:ActiveSession) { return }

    $startedAt = $script:ActiveSession.started_at
    if (-not $startedAt) { return }

    $nowMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $elapsedMinutes = ($nowMs - $startedAt) / 60000.0

    $marks = @(20, 40)
    if ($script:ActiveSession.marks) {
        $marks = $script:ActiveSession.marks
    }

    $acks = if ($script:ActiveSession.acks) { $script:ActiveSession.acks } else { @() }

    foreach ($m in $marks) {
        if ($elapsedMinutes -ge $m -and -not ($acks -contains $m)) {
            $timeSinceLastAlert = ([DateTime]::UtcNow - $script:LastAlertTime).TotalSeconds

            # Se for novo mark ou intervalo de repetição (60 segundos)
            if ($script:LastAlertMark -ne $m -or ($timeSinceLastAlert -ge 60 -and $script:AlertCount -lt 3)) {
                $script:LastAlertMark = $m
                $script:LastAlertTime = [DateTime]::UtcNow
                $script:AlertCount++
                Show-NativeCheckpointAlert -mark $m
            }
            break
        }
    }
}

# 5. Iniciar Servidor HTTP Listener
$listener = New-Object System.Net.HttpListener
$prefix = "http://127.0.0.1:$Port/"
$listener.Prefixes.Add($prefix)
try {
    $listener.Prefixes.Add("http://localhost:$Port/")
} catch {}

try {
    $listener.Start()
    Write-BridgeLog "PulseLab Bridge v$($script:BridgeVersion) ativo em $prefix" "INFO"
    Write-BridgeLog "Pasta da WebApp: $AppRoot" "INFO"
    Write-BridgeLog "Armazenamento:   $DataDir" "INFO"
} catch {
    Write-BridgeLog "Falha ao iniciar HttpListener na porta $Port`: $($_.Exception.ToString())" "ERROR"
    exit 1
}

# 6. Loop de Atendimento Resiliente
try {
    while ($listener.IsListening) {
        $asyncResult = $null
        try {
            $asyncResult = $listener.BeginGetContext($null, $null)
        } catch {
            if (-not $listener.IsListening) { break }
            Start-Sleep -Milliseconds 100
            continue
        }

        while (-not $asyncResult.IsCompleted) {
            $asyncResult.AsyncWaitHandle.WaitOne(1000) | Out-Null
            Check-SessionSchedule
            if (([DateTime]::UtcNow - $script:LastSyncAttempt).TotalSeconds -ge 30) {
                $script:LastSyncAttempt = [DateTime]::UtcNow
                Sync-EventsToSupabase
            }
            if (([DateTime]::UtcNow - $script:LastUpdateAttempt).TotalSeconds -ge 120) {
                $script:LastUpdateAttempt = [DateTime]::UtcNow
                Check-PulseLabAutoUpdate
            }
        }

        $context = $null
        try {
            $context = $listener.EndGetContext($asyncResult)
        } catch {
            if (-not $listener.IsListening) { break }
            continue
        }

        if ($null -eq $context) { continue }

        # Processar cada requisição com tratamento de erro individual para garantir 100% de estabilidade
        try {
            $request = $context.Request
            $response = $context.Response

            # CORS Local
            $response.AddHeader("Access-Control-Allow-Origin", "*")
            $response.AddHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
            $response.AddHeader("Access-Control-Allow-Headers", "Content-Type")

            if ($request.HttpMethod -eq "OPTIONS") {
                $response.StatusCode = 200
                $response.Close()
                continue
            }

            $rawUrl = $request.RawUrl
            $path = $request.Url.LocalPath

            # Redirecionar raiz "/" ou "/alunos" (sem barra final) para "/alunos/"
            if ($path -eq "/" -or $path -eq "/alunos") {
                $response.StatusCode = 302
                $response.RedirectLocation = "/alunos/"
                $response.Close()
                continue
            }

            # --- ROTAS DA API REST ---
            if ($path -eq "/health" -or $path -eq "/v1/health") {
                $uptime = ([DateTime]::UtcNow - $script:StartTime).TotalSeconds
                $spikeDetected = $false
                if (Get-Command Find-LatestSpikeProject -ErrorAction SilentlyContinue) {
                    $spikeDetected = (Find-LatestSpikeProject) -ne $null
                }
                $healthObj = @{
                    status = "ok"
                    version = $script:BridgeVersion
                    uptime_seconds = [Math]::Round($uptime, 1)
                    port = $Port
                    spike_detected = $spikeDetected
                    has_active_session = ($script:ActiveSession -ne $null)
                }
                $json = $healthObj | ConvertTo-Json
                $buf = [System.Text.Encoding]::UTF8.GetBytes($json)
                $response.ContentType = "application/json; charset=utf-8"
                $response.ContentLength64 = $buf.Length
                $response.OutputStream.Write($buf, 0, $buf.Length)
                $response.Close()
                continue
            }

            if ($path -eq "/update" -or $path -eq "/v1/update") {
                Check-PulseLabAutoUpdate
                $updateObj = @{
                    status = "checked"
                    version = $script:BridgeVersion
                }
                $buf = [System.Text.Encoding]::UTF8.GetBytes(($updateObj | ConvertTo-Json))
                $response.ContentType = "application/json; charset=utf-8"
                $response.ContentLength64 = $buf.Length
                $response.OutputStream.Write($buf, 0, $buf.Length)
                $response.Close()
                continue
            }

            if ($path -eq "/v1/sessions" -and $request.HttpMethod -eq "POST") {
                $reader = New-Object System.IO.StreamReader($request.InputStream, $request.ContentEncoding)
                $body = $reader.ReadToEnd() | ConvertFrom-Json
                $reader.Close()

                $parsedStartedAt = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
                if ($body.started_at) {
                    $strVal = [string]$body.started_at
                    if ($strVal -match '^\d+$') {
                        $parsedStartedAt = [int64]$strVal
                    } else {
                        try {
                            $parsedStartedAt = [DateTimeOffset]::Parse($strVal).ToUnixTimeMilliseconds()
                        } catch {
                            $parsedStartedAt = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
                        }
                    }
                }

                $script:ActiveSession = [PSCustomObject]@{
                    session_id = [string]$body.session_id
                    started_at = $parsedStartedAt
                    marks = if ($body.marks) { @($body.marks) } else { @(20, 40) }
                    acks = @()
                    created_at = [DateTime]::UtcNow.ToString("o")
                }
                $script:ActiveSession | ConvertTo-Json | Set-Content -Path $scheduleFile -Force
                $script:LastAlertMark = 0
                $script:AlertCount = 0

                $respObj = @{ status = "scheduled"; session_id = $script:ActiveSession.session_id }
                $buf = [System.Text.Encoding]::UTF8.GetBytes(($respObj | ConvertTo-Json))
                $response.ContentType = "application/json; charset=utf-8"
                $response.ContentLength64 = $buf.Length
                $response.OutputStream.Write($buf, 0, $buf.Length)
                $response.Close()
                continue
            }

            if ($path -match "^/v1/sessions/([^/]+)/checkpoints/(\d+)/ack$" -and $request.HttpMethod -eq "POST") {
                $sessId = $Matches[1]
                $mark = [int]$Matches[2]

                if ($script:ActiveSession) {
                    $currentAcks = @($script:ActiveSession.acks)
                    if (-not ($currentAcks -contains $mark)) {
                        $currentAcks += $mark
                        $script:ActiveSession.acks = $currentAcks
                        $script:ActiveSession | ConvertTo-Json | Set-Content -Path $scheduleFile -Force
                    }
                }

                $respObj = @{ status = "acknowledged"; mark = $mark }
                $buf = [System.Text.Encoding]::UTF8.GetBytes(($respObj | ConvertTo-Json))
                $response.ContentType = "application/json; charset=utf-8"
                $response.ContentLength64 = $buf.Length
                $response.OutputStream.Write($buf, 0, $buf.Length)
                $response.Close()
                continue
            }

            if ($path -eq "/v1/alert" -and $request.HttpMethod -eq "POST") {
                $mark = 20
                try {
                    $reader = New-Object System.IO.StreamReader($request.InputStream, $request.ContentEncoding)
                    $bodyRaw = $reader.ReadToEnd()
                    $reader.Close()
                    if ($bodyRaw) {
                        $body = $bodyRaw | ConvertFrom-Json
                        if ($body.mark) { $mark = [int]$body.mark }
                    }
                } catch {}

                Show-NativeCheckpointAlert -mark $mark
                $respObj = @{ status = "triggered"; mark = $mark }
                $buf = [System.Text.Encoding]::UTF8.GetBytes(($respObj | ConvertTo-Json))
                $response.ContentType = "application/json; charset=utf-8"
                $response.ContentLength64 = $buf.Length
                $response.OutputStream.Write($buf, 0, $buf.Length)
                $response.Close()
                continue
            }

            if ($path -eq "/v1/events" -and $request.HttpMethod -eq "POST") {
                try {
                    $reader = New-Object System.IO.StreamReader($request.InputStream, $request.ContentEncoding)
                    $eventJson = $reader.ReadToEnd()
                    $reader.Close()

                    if ($eventJson) {
                        $eventsFile = Join-Path $DataDir "events.jsonl"
                        [System.IO.File]::AppendAllText($eventsFile, "$eventJson`r`n", [System.Text.Encoding]::UTF8)
                        Sync-EventsToSupabase
                    }
                } catch {
                    Write-BridgeLog "Falha ao gravar evento no disco: $($_.Exception.Message)" "WARN"
                }

                $respObj = @{ status = "persisted" }
                $buf = [System.Text.Encoding]::UTF8.GetBytes(($respObj | ConvertTo-Json))
                $response.ContentType = "application/json; charset=utf-8"
                $response.ContentLength64 = $buf.Length
                $response.OutputStream.Write($buf, 0, $buf.Length)
                $response.Close()
                continue
            }

            if ($path -eq "/v1/sessions/reset" -and $request.HttpMethod -eq "POST") {
                $script:ActiveSession = $null
                $script:LastAlertMark = 0
                $script:AlertCount = 0
                if (Test-Path $scheduleFile) {
                    try { Remove-Item -LiteralPath $scheduleFile -Force -ErrorAction SilentlyContinue } catch {}
                }
                $respObj = @{ status = "reset" }
                $buf = [System.Text.Encoding]::UTF8.GetBytes(($respObj | ConvertTo-Json))
                $response.ContentType = "application/json; charset=utf-8"
                $response.ContentLength64 = $buf.Length
                $response.OutputStream.Write($buf, 0, $buf.Length)
                $response.Close()
                continue
            }

            if ($path -eq "/v1/spike/metrics" -and $request.HttpMethod -eq "GET") {
                $metrics = if (Get-Command Get-SpikeProjectMetrics -ErrorAction SilentlyContinue) {
                    Get-SpikeProjectMetrics
                } else {
                    @{ source = "spike_project"; project_saved = $false; error = "parser_not_loaded" }
                }
                $buf = [System.Text.Encoding]::UTF8.GetBytes(($metrics | ConvertTo-Json -Depth 5))
                $response.ContentType = "application/json; charset=utf-8"
                $response.ContentLength64 = $buf.Length
                $response.OutputStream.Write($buf, 0, $buf.Length)
                $response.Close()
                continue
            }

            # --- ARQUIVOS ESTÁTICOS DA WEBAPP ---
            $subPath = $path.TrimStart('/')
            if ($subPath.StartsWith("alunos/")) {
                $subPath = $subPath.Substring(7)
            }
            if (-not $subPath -or $subPath -eq "index.html") {
                $subPath = "index.html"
            }

            $localFilePath = Join-Path $AppRoot $subPath
            $fullPath = [System.IO.Path]::GetFullPath($localFilePath)

            # Sanitização e proteção contra Path Traversal
            if (-not $fullPath.StartsWith([System.IO.Path]::GetFullPath($AppRoot))) {
                $response.StatusCode = 403
                $response.Close()
                continue
            }

            if (Test-Path $fullPath -PathType Leaf) {
                $ext = [System.IO.Path]::GetExtension($fullPath)
                $response.ContentType = Get-MimeType $ext
                $fileBytes = [System.IO.File]::ReadAllBytes($fullPath)
                $response.ContentLength64 = $fileBytes.Length
                $response.OutputStream.Write($fileBytes, 0, $fileBytes.Length)
                $response.Close()
            } elseif (Test-Path (Join-Path $AppRoot "index.html")) {
                # Fallback SPA routing
                $indexPath = Join-Path $AppRoot "index.html"
                $response.ContentType = "text/html; charset=utf-8"
                $fileBytes = [System.IO.File]::ReadAllBytes($indexPath)
                $response.ContentLength64 = $fileBytes.Length
                $response.OutputStream.Write($fileBytes, 0, $fileBytes.Length)
                $response.Close()
            } else {
                $response.StatusCode = 404
                $response.Close()
            }
        } catch {
            Write-BridgeLog "Aviso ao atender requisicao $($request.HttpMethod) $path`: $($_.Exception.Message)" "WARN"
            try {
                if ($context -and $context.Response) {
                    $context.Response.StatusCode = 500
                    $context.Response.Close()
                }
            } catch {}
        }
    }
} catch {
    Write-BridgeLog "Excecao no loop do Bridge: $($_.Exception.ToString())" "ERROR"
} finally {
    Write-BridgeLog "Finalizando listener HTTP do PulseLab..." "INFO"
    if ($listener) {
        try { $listener.Stop() } catch {}
        try { $listener.Close() } catch {}
    }
}
