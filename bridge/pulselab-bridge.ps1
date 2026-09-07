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
        [System.Media.SystemSounds]::Exclamation.Play()
    } catch {
        try { [System.Console]::Beep(880, 300) } catch {}
    }
}

function Show-NativeCheckpointAlert([int]$mark) {
    Write-Host "[ALERTA] Hora do checkpoint de $mark minutos!" -ForegroundColor Yellow
    Play-CheckpointSound

    # Disparar alerta visual compacto via Windows Forms se disponível
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        $form = New-Object System.Windows.Forms.Form
        $form.Text = "PulseLab — Check-in de $mark min"
        $form.Size = New-Object System.Drawing.Size(340, 160)
        $form.StartPosition = "CenterScreen"
        $form.TopMost = $true
        $form.FormBorderStyle = "FixedDialog"
        $form.MaximizeBox = $false
        $form.MinimizeBox = $false

        $label = New-Object System.Windows.Forms.Label
        $label.Text = "Hora do check-in rápido de $mark minutos.`nPor favor, volte ao navegador para responder."
        $label.Size = New-Object System.Drawing.Size(300, 45)
        $label.Location = New-Object System.Drawing.Point(20, 15)
        $form.Controls.Add($label)

        $btn = New-Object System.Windows.Forms.Button
        $btn.Text = "Responder agora"
        $btn.Size = New-Object System.Drawing.Size(140, 32)
        $btn.Location = New-Object System.Drawing.Point(90, 75)
        $btn.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $btn.Add_Click({
            try {
                Start-Process "http://127.0.0.1:$Port/alunos/"
            } catch {}
            $form.Close()
        })
        $form.Controls.Add($btn)
        $form.AcceptButton = $btn

        $form.Show()
    } catch {
        # Fallback se WinForms não estiver disponível
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
    $listener.Start()
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host "PulseLab Bridge v1.7.0 ativo em $prefix" -ForegroundColor Green
    Write-Host "Pasta da WebApp: $AppRoot" -ForegroundColor Gray
    Write-Host "Armazenamento:   $DataDir" -ForegroundColor Gray
    Write-Host "Pressione Ctrl+C para encerrar." -ForegroundColor Gray
    Write-Host "==================================================" -ForegroundColor Cyan
} catch {
    Write-Error "Falha ao iniciar HttpListener na porta $Port`: $($_.Exception.Message)"
    exit 1
}

# 6. Loop de Atendimento
try {
    while ($listener.IsListening) {
        # Atender requisições de forma assíncrona para não travar o loop de verificação de tempo
        $asyncResult = $listener.BeginGetContext($null, $null)
        $waitHandles = @($asyncResult.AsyncWaitHandle)

        while (-not $asyncResult.IsCompleted) {
            [System.Threading.WaitHandle]::WaitAny($waitHandles, 1000) | Out-Null
            Check-SessionSchedule
        }

        $context = $listener.EndGetContext($asyncResult)
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

        # --- ROTAS DA API REST ---
        if ($path -eq "/health") {
            $uptime = ([DateTime]::UtcNow - $script:StartTime).TotalSeconds
            $spikeDetected = (Find-LatestSpikeProject) -ne $null
            $healthObj = @{
                status = "ok"
                version = "1.7.0"
                uptime_seconds = [Math]::Round($uptime, 1)
                port = $Port
                spike_detected = $spikeDetected
                has_active_session = ($script:ActiveSession -ne $null)
            }
            $json = $healthObj | ConvertTo-Json
            $buf = [System.Text.Encoding]::UTF8.GetBytes($json)
            $response.ContentType = "application/json; charset=utf-8"
            $response.OutputStream.Write($buf, 0, $buf.Length)
            $response.Close()
            continue
        }

        if ($path -eq "/v1/sessions" -and $request.HttpMethod -eq "POST") {
            $reader = New-Object System.IO.StreamReader($request.InputStream, $request.ContentEncoding)
            $body = $reader.ReadToEnd() | ConvertFrom-Json
            $reader.Close()

            $script:ActiveSession = [PSCustomObject]@{
                session_id = [string]$body.session_id
                started_at = [int64]$body.started_at
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
    }
}
finally {
    if ($listener) {
        $listener.Stop()
        $listener.Close()
    }
}
