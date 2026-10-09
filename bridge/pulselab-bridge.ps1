# ==============================================================================
# PulseLab — Bridge HTTP Local e Companion de Alertas (Windows Offline)
# ==============================================================================
# - Servidor web local em http://127.0.0.1:43128/alunos/
# - Agenda de checkpoints e relógio de sessão independente
# - Alertas sonoros e visuais nativos quando o navegador estiver em segundo plano
# - Extração de métricas de telemetria do SPIKE via spike-parser.ps1
# ==============================================================================

[CmdletBinding()]
param(
    [int]$Port = 43128,
    [string]$AppRoot = "",
    [string]$DataDir = "",
    [switch]$NoAlert,
    [switch]$EnableAutoUpdate
)

$script:AutoUpdateEnabled = $false

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
    # Prioriza pasta portátil dados_locais junto ao aplicativo (offline-first)
    $candidateDirs = @(
        (Join-Path $PSScriptRoot "..\dados_locais"),
        (Join-Path $PSScriptRoot "dados_locais")
    )
    $foundDataDir = $null
    foreach ($cand in $candidateDirs) {
        if (Test-Path $cand) {
            $foundDataDir = (Resolve-Path $cand).Path
            break
        }
    }
    if ($foundDataDir) {
        $DataDir = $foundDataDir
    } else {
        try {
            $portableDir = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\dados_locais"))
            New-Item -ItemType Directory -Path $portableDir -Force | Out-Null
            $DataDir = $portableDir
        } catch {
            $localAppData = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { $env:USERPROFILE }
            $DataDir = Join-Path $localAppData "PulseLab\dados_locais"
        }
    }
}

if (-not (Test-Path $DataDir)) {
    New-Item -ItemType Directory -Path $DataDir -Force | Out-Null
}

$sessoesDir = Join-Path $DataDir "sessoes"
if (-not (Test-Path $sessoesDir)) {
    New-Item -ItemType Directory -Path $sessoesDir -Force | Out-Null
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
$script:SupabaseOperationalJwt = ""
$script:InstallationId = ""
$script:SiteId = "Polo-Nordeste"

if ($env:PULSELAB_OPERATIONAL_JWT) {
    $script:SupabaseOperationalJwt = $env:PULSELAB_OPERATIONAL_JWT
}

$candidateConfig = Join-Path $PSScriptRoot "..\config\config.json"
if (-not (Test-Path $candidateConfig)) {
    $candidateConfig = Join-Path $PSScriptRoot "..\..\config\config.json"
}
if (Test-Path $candidateConfig) {
    try {
        $cfgJson = Get-Content -Path $candidateConfig -Raw | ConvertFrom-Json
        if ($cfgJson.supabase_url) { $script:SupabaseUrl = $cfgJson.supabase_url }
        if ($cfgJson.supabase_anon_key) { $script:SupabaseAnonKey = $cfgJson.supabase_anon_key }
        if ($cfgJson.site_id -and $cfgJson.site_id -ne "CONFIGURE_SEDE") { $script:SiteId = $cfgJson.site_id }
    } catch {}
}

# Tenta carregar credencial operacional de dispositivo e perfil de instalacao
$localDataRoot = [Environment]::GetFolderPath("LocalApplicationData")
if ([string]::IsNullOrWhiteSpace($localDataRoot)) { $localDataRoot = $env:TEMP }

$instCandidates = @(
    (Join-Path $DataDir "installation.json"),
    (Join-Path $PSScriptRoot "..\config\installation.json"),
    (Join-Path $localDataRoot "PulseLab\installation.json")
)
foreach ($c in $instCandidates) {
    if (Test-Path $c) {
        try {
            $ij = Get-Content $c -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($ij.installation_id) { $script:InstallationId = [string]$ij.installation_id }
            if ($ij.site_id) { $script:SiteId = [string]$ij.site_id }
            if ($script:InstallationId) { break }
        } catch {}
    }
}

if (-not $script:SupabaseOperationalJwt) {
    $sessionCandidates = @(
        (Join-Path $DataDir "device_session.json"),
        (Join-Path $DataDir "device_session.dat"),
        (Join-Path $localDataRoot "PulseLab\device_session.dat")
    )
    foreach ($cand in $sessionCandidates) {
        if (Test-Path $cand) {
            try {
                if ($cand.EndsWith(".json")) {
                    $devSess = Get-Content $cand -Raw -Encoding UTF8 | ConvertFrom-Json
                    if ($devSess.access_token) {
                        $script:SupabaseOperationalJwt = [string]$devSess.access_token
                        if ($devSess.installation_id) { $script:InstallationId = [string]$devSess.installation_id }
                        if ($devSess.site_id) { $script:SiteId = [string]$devSess.site_id }
                        break
                    }
                } else {
                    Add-Type -AssemblyName System.Security -ErrorAction SilentlyContinue
                    $encBytes = [System.IO.File]::ReadAllBytes($cand)
                    if ($encBytes -and $encBytes.Length -gt 0) {
                        $decBytes = [System.Security.Cryptography.ProtectedData]::Unprotect($encBytes, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
                        if ($decBytes) {
                            $decStr = [System.Text.Encoding]::UTF8.GetString($decBytes)
                            $devSess = $decStr | ConvertFrom-Json
                            if ($devSess.access_token) {
                                $script:SupabaseOperationalJwt = [string]$devSess.access_token
                                if ($devSess.installation_id) { $script:InstallationId = [string]$devSess.installation_id }
                                if ($devSess.site_id) { $script:SiteId = [string]$devSess.site_id }
                                break
                            }
                        }
                    }
                }
            } catch {}
        }
    }
}

$script:BridgeVersion = "2.2.2"
$verCandidate = Join-Path $PSScriptRoot "..\VERSION"
if (Test-Path $verCandidate) {
    try { $script:BridgeVersion = (Get-Content $verCandidate -Raw).Trim() } catch {}
}
$script:LastSyncAttempt = [DateTime]::MinValue
$script:LastRetentionCleanup = [DateTime]::MinValue
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

# Falha 10: Rastreamento persistente de quarentena para evitar loops infinitos ao reiniciar o Bridge
$script:QuarantinedEventIds = [System.Collections.Generic.HashSet[string]]::new()
$script:QuarantinedTrackerFile = Join-Path $DataDir "events_quarantine.txt"

if (Test-Path $script:QuarantinedTrackerFile) {
    try {
        Get-Content $script:QuarantinedTrackerFile | ForEach-Object {
            $tracked = $_.Trim()
            if ($tracked) { [void]$script:QuarantinedEventIds.Add($tracked) }
        }
    } catch {}
}

$script:SyncedSessionIds = [System.Collections.Generic.HashSet[string]]::new()
$script:SyncedSessionsTrackerFile = Join-Path $DataDir "sessions_synced.txt"

if (Test-Path $script:SyncedSessionsTrackerFile) {
    try {
        Get-Content $script:SyncedSessionsTrackerFile | ForEach-Object {
            $tracked = $_.Trim()
            if ($tracked) { [void]$script:SyncedSessionIds.Add($tracked) }
        }
    } catch {}
}

$script:QuarantinedSessionIds = [System.Collections.Generic.HashSet[string]]::new()
$script:QuarantinedSessionsTrackerFile = Join-Path $DataDir "sessions_quarantine.txt"

if (Test-Path $script:QuarantinedSessionsTrackerFile) {
    try {
        Get-Content $script:QuarantinedSessionsTrackerFile | ForEach-Object {
            $tracked = $_.Trim()
            if ($tracked) { [void]$script:QuarantinedSessionIds.Add($tracked) }
        }
    } catch {}
}

$script:HasLoggedJwtWarning = $false

function Sync-EventsToSupabase {
    # Falha 1: Bridge não deve sincronizar remotamente sem JWT autenticado operacional explícito.
    # Não trate anon key como autenticação suficiente (RLS revogou anon).
    if (-not $script:SupabaseOperationalJwt) {
        if (-not $script:HasLoggedJwtWarning) {
            Write-BridgeLog "Bridge em modo offline-first seguro: sincronizacao remota desativada (nenhum JWT operacional configurado). Dados salvos localmente em dados_locais." "INFO"
            $script:HasLoggedJwtWarning = $true
        }
        return
    }

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
                if (-not $eventId -or $script:SyncedEventIds.Contains($eventId) -or $script:QuarantinedEventIds.Contains($eventId)) {
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
                    Authorization = "Bearer $($script:SupabaseOperationalJwt)"
                    "Content-Type" = "application/json"
                    Prefer = "resolution=ignore-duplicates,return=minimal"
                }

                $uri = "$($script:SupabaseUrl)/rest/v1/$targetTable?on_conflict=event_id"
                Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $bodyJson -TimeoutSec 6 -ErrorAction Stop | Out-Null

                [void]$script:SyncedEventIds.Add($eventId)
                [System.IO.File]::AppendAllText($script:SyncedTrackerFile, "$eventId`r`n", [System.Text.Encoding]::UTF8)
                $syncedCount++
            } catch {
                $statusCode = 0
                $errBody = ""
                try {
                    $statusCode = [int]$_.Exception.Response.StatusCode
                    $respStream = $_.Exception.Response.GetResponseStream()
                    if ($respStream) {
                        $sReader = New-Object System.IO.StreamReader($respStream)
                        $errBody = $sReader.ReadToEnd()
                        $sReader.Close()
                    }
                } catch {}

                if ($statusCode -eq 409) {
                    # Falha 3: Conflito: aceita como idempotente SOMENTE se for comprovadamente unique_violation (23505) na chave primária esperada (event_id)
                    $isPkDuplicate = $false
                    $errLower = "$errBody".ToLower()
                    $hasUniqueMarker = ($errLower -match "23505" -or $errLower -match "duplicate key" -or $errLower -match "unique constraint" -or $errLower -match "already exists")
                    if ($hasUniqueMarker -and ($errLower -match "\(event_id\)=" -or $errLower -match "key \(event_id\)" -or $errLower -match "research_events_pkey" -or $errLower -match "research_session_events_pkey" -or $errLower -match "event_id_pkey")) {
                        $isPkDuplicate = $true
                    }

                    if ($isPkDuplicate) {
                        [void]$script:SyncedEventIds.Add($eventId)
                        [System.IO.File]::AppendAllText($script:SyncedTrackerFile, "$eventId`r`n", [System.Text.Encoding]::UTF8)
                        $syncedCount++
                        continue
                    }
                }

                # Falha 10: Erros 4xx não idempotentes (incluindo 409 por check constraint/FK, 400, 422, etc):
                # Quarentena observável persistida em arquivo para não travar a fila com retentativas infinitas ao reiniciar o Bridge
                if ($statusCode -ge 400 -and $statusCode -lt 500) {
                    try {
                        $quarantineFile = Join-Path $DataDir "events_quarantine.jsonl"
                        $qObj = [PSCustomObject]@{
                            event_id = $eventId
                            status_code = $statusCode
                            error = $errBody
                            quarantined_at = [DateTime]::UtcNow.ToString("o")
                            event = $ev
                        }
                        $qJson = $qObj | ConvertTo-Json -Compress -Depth 10
                        [System.IO.File]::AppendAllText($quarantineFile, "$qJson`r`n", [System.Text.Encoding]::UTF8)
                        [void]$script:QuarantinedEventIds.Add($eventId)
                        [System.IO.File]::AppendAllText($script:QuarantinedTrackerFile, "$eventId`r`n", [System.Text.Encoding]::UTF8)
                        Write-BridgeLog "[QUARENTENA] Evento $eventId rejeitado com HTTP $statusCode (salvo em events_quarantine.jsonl): $errBody" "WARN"
                    } catch {}
                    continue
                }

                # Offline (sem resposta) ou erro 5xx de servidor: interrompe para retentar na próxima janela
                break
            }
        }
        if ($syncedCount -gt 0) {
            Write-BridgeLog "Sincronizados $syncedCount evento(s) da oficina com o Supabase com sucesso." "INFO"
        }

        # Compactação periódica: se o arquivo de eventos cresceu além de 150 linhas, arquiva eventos já sincronizados
        if ($lines.Length -gt 150 -and $script:SyncedEventIds.Count -gt 0) {
            try {
                $unsynced = [System.Collections.Generic.List[string]]::new()
                $archived = [System.Collections.Generic.List[string]]::new()
                foreach ($l in $lines) {
                    if ([string]::IsNullOrWhiteSpace($l)) { continue }
                    try {
                        $parsed = $l | ConvertFrom-Json
                        if ($script:SyncedEventIds.Contains([string]$parsed.event_id)) {
                            $archived.Add($l)
                        } else {
                            $unsynced.Add($l)
                        }
                    } catch {
                        $unsynced.Add($l)
                    }
                }
                if ($archived.Count -gt 0) {
                    $archiveFile = Join-Path $DataDir "events_archive.jsonl"
                    [System.IO.File]::AppendAllLines($archiveFile, $archived, [System.Text.Encoding]::UTF8)
                    [System.IO.File]::WriteAllLines($eventsFile, $unsynced, [System.Text.Encoding]::UTF8)
                    Write-BridgeLog "Compactada fila local: $($archived.Count) evento(s) arquivados com sucesso." "INFO"
                }
            } catch {}
        }
    } catch {}
}

function Sync-SessionSnapshotsToSupabase {
    if (-not $script:SupabaseOperationalJwt) { return }

    $sessoesDir = Join-Path $DataDir "sessoes"
    if (-not (Test-Path $sessoesDir)) { return }

    $sessionFiles = Get-ChildItem -Path $sessoesDir -Filter "sessao_*.json" -ErrorAction SilentlyContinue
    if (-not $sessionFiles) { return }

    $nowIso = [DateTime]::UtcNow.ToString("o")
    $syncedSessCount = 0

    foreach ($sfile in $sessionFiles) {
        try {
            $rawContent = [System.IO.File]::ReadAllText($sfile.FullName, [System.Text.Encoding]::UTF8)
            if ([string]::IsNullOrWhiteSpace($rawContent)) { continue }
            $sdata = $rawContent | ConvertFrom-Json
            if (-not $sdata -or -not $sdata.session_id) { continue }

            $sid = [string]$sdata.session_id
            if ($script:SyncedSessionIds.Contains($sid) -or $script:QuarantinedSessionIds.Contains($sid)) {
                continue
            }

            $instId = if ($sdata.installation_id) { [string]$sdata.installation_id } elseif ($script:InstallationId) { $script:InstallationId } else { "10000000-0000-4000-8000-000000000001" }
            $siteVal = if ($sdata.site_id) { [string]$sdata.site_id } elseif ($script:SiteId) { $script:SiteId } else { "Polo-Nordeste" }

            $sessRecord = [System.Collections.Specialized.OrderedDictionary]::new()
            $sessRecord["session_id"] = $sid
            $sessRecord["group_id"] = if ($sdata.group_id) { [string]$sdata.group_id } else { [Guid]::Empty.ToString() }
            $sessRecord["installation_id"] = $instId
            $sessRecord["site_id"] = $siteVal
            $sessRecord["school_code"] = if ($sdata.school_code) { [string]$sdata.school_code } else { "geral" }
            $sessRecord["workshop_code"] = if ($sdata.workshop_code) { [string]$sdata.workshop_code } else { "oficina-spike" }
            $sessRecord["class_code"] = if ($sdata.class_code) { [string]$sdata.class_code } else { "turma-geral" }
            $sessRecord["environment"] = if ($sdata.is_synthetic) { "test" } else { "production" }
            $sessRecord["protocol_version"] = if ($sdata.protocol_version) { [string]$sdata.protocol_version } else { $script:BridgeVersion }
            $sessRecord["instrument_version"] = if ($sdata.instrument_version) { [string]$sdata.instrument_version } else { "bancada-$($script:BridgeVersion)" }
            $sessRecord["group_size"] = if ($sdata.group_size) { [int]$sdata.group_size } else { 2 }
            $sessRecord["phase"] = if ($sdata.phase) { [string]$sdata.phase } else { "completed" }
            $sessRecord["session_payload"] = $sdata
            $sessRecord["created_at"] = if ($sdata.started_at) { [string]$sdata.started_at } else { $nowIso }
            $sessRecord["updated_at"] = if ($sdata.completed_at) { [string]$sdata.completed_at } else { $nowIso }

            $bodyJson = $sessRecord | ConvertTo-Json -Depth 10 -Compress
            $headers = @{
                apikey = $script:SupabaseAnonKey
                Authorization = "Bearer $($script:SupabaseOperationalJwt)"
                "Content-Type" = "application/json"
                Prefer = "resolution=ignore-duplicates,return=minimal"
            }

            $uri = "$($script:SupabaseUrl)/rest/v1/research_bancada_sessions?on_conflict=session_id"
            Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $bodyJson -TimeoutSec 8 -ErrorAction Stop | Out-Null

            [void]$script:SyncedSessionIds.Add($sid)
            [System.IO.File]::AppendAllText($script:SyncedSessionsTrackerFile, "$sid`r`n", [System.Text.Encoding]::UTF8)
            $syncedSessCount++
        } catch {
            $statusCode = 0
            $errBody = ""
            try {
                $statusCode = [int]$_.Exception.Response.StatusCode
                $respStream = $_.Exception.Response.GetResponseStream()
                if ($respStream) {
                    $sReader = New-Object System.IO.StreamReader($respStream)
                    $errBody = $sReader.ReadToEnd()
                    $sReader.Close()
                }
            } catch {}

            if ($statusCode -eq 409) {
                $errLower = "$errBody".ToLower()
                if ($errLower -match "23505" -or $errLower -match "duplicate key" -or $errLower -match "research_bancada_sessions_pkey" -or $errLower -match "already exists") {
                    [void]$script:SyncedSessionIds.Add($sid)
                    [System.IO.File]::AppendAllText($script:SyncedSessionsTrackerFile, "$sid`r`n", [System.Text.Encoding]::UTF8)
                    $syncedSessCount++
                    continue
                }
            }

            if ($statusCode -ge 400 -and $statusCode -lt 500) {
                try {
                    $quarantineFile = Join-Path $DataDir "sessions_quarantine.jsonl"
                    $qObj = [PSCustomObject]@{
                        session_id = $sid
                        status_code = $statusCode
                        error = $errBody
                        quarantined_at = [DateTime]::UtcNow.ToString("o")
                    }
                    $qJson = $qObj | ConvertTo-Json -Compress -Depth 5
                    [System.IO.File]::AppendAllText($quarantineFile, "$qJson`r`n", [System.Text.Encoding]::UTF8)
                    [void]$script:QuarantinedSessionIds.Add($sid)
                    [System.IO.File]::AppendAllText($script:QuarantinedSessionsTrackerFile, "$sid`r`n", [System.Text.Encoding]::UTF8)
                    Write-BridgeLog "[QUARENTENA] Sessao $sid rejeitada com HTTP ${statusCode}: $errBody" "WARN"
                } catch {}
                continue
            }

            break
        }
    }

    if ($syncedSessCount -gt 0) {
        Write-BridgeLog "Sincronizados $syncedSessCount snapshot(s) de sessao de bancada com o Supabase com sucesso." "INFO"
    }
}

function Test-PulseLabAllowedOrigin {
    param(
        [string]$Origin,
        [int]$ExpectedPort
    )
    if ([string]::IsNullOrWhiteSpace($Origin) -or $Origin -eq "null") {
        return $false
    }
    if ($Origin -eq "http://127.0.0.1:$ExpectedPort" -or $Origin -eq "http://localhost:$ExpectedPort") {
        return $true
    }
    return $false
}

function Check-PulseLabAutoUpdate {
    Write-BridgeLog "[AUTO-UPDATE] Atualizacao remota desabilitada permanentemente: sem infraestrutura institucional de assinatura digital." "WARN"
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

function Move-BridgeAtomicFile {
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$DestinationPath
    )
    if (-not (Test-Path -LiteralPath $SourcePath)) { return }
    try {
        if (Test-Path -LiteralPath $DestinationPath) {
            Move-Item -LiteralPath $SourcePath -Destination $DestinationPath -Force
        } else {
            [System.IO.File]::Move($SourcePath, $DestinationPath)
        }
    } catch {
        try {
            [System.IO.File]::Copy($SourcePath, $DestinationPath, $true)
            [System.IO.File]::Delete($SourcePath)
        } catch {
            Write-BridgeLog "Falha ao mover arquivo atomico de '$SourcePath' para '$DestinationPath': $($_.Exception.Message)" "WARN"
            throw
        }
    }
}

function Invoke-BridgeRetentionCleanup {
    [CmdletBinding()]
    param([int]$MaxAgeDays = 7)

    $cutoffUtc = [DateTime]::UtcNow.AddDays(-$MaxAgeDays)
    $expiredSessionIds = [System.Collections.Generic.HashSet[string]]::new()

    # 1. Identificar sessoes expiradas pelo diretorio sessoes/
    $sessoesDir = Join-Path $DataDir "sessoes"
    if (Test-Path -LiteralPath $sessoesDir) {
        $sessFiles = Get-ChildItem -LiteralPath $sessoesDir -Filter "*.json" -File -ErrorAction SilentlyContinue
        foreach ($sf in $sessFiles) {
            try {
                $sessJson = Get-Content -LiteralPath $sf.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                $createdStr = if ($sessJson.created_at) { $sessJson.created_at } elseif ($sessJson.startedAt) { $sessJson.startedAt } elseif ($sessJson.started_at) { $sessJson.started_at } else { $null }
                $createdUtc = $null
                if ($createdStr) {
                    try {
                        if ($createdStr -match '^\d+$') {
                            $createdUtc = [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$createdStr).UtcDateTime
                        } else {
                            $createdUtc = [DateTime]::Parse($createdStr, $null, [System.Globalization.DateTimeStyles]::AdjustToUniversal)
                        }
                    } catch {}
                }
                if (-not $createdUtc) {
                    $createdUtc = $sf.CreationTimeUtc
                }

                # Prazo absoluto: sete dias desde a criacao, sem extensao por retomada
                if ($createdUtc -lt $cutoffUtc) {
                    $sid = if ($sessJson.session_id) { $sessJson.session_id } else { $sf.BaseName -replace '^sessao_', '' }
                    if ($sid) { [void]$expiredSessionIds.Add([string]$sid) }
                }
            } catch {}
        }
    }

    # 2. Identificar sessoes expiradas no catalogo
    $catFile = Join-Path $DataDir "catalogo_sessoes.json"
    if (Test-Path -LiteralPath $catFile) {
        try {
            $catExisting = Get-Content -LiteralPath $catFile -Raw -Encoding UTF8 | ConvertFrom-Json
            $items = if ($catExisting -is [System.Collections.IEnumerable]) { $catExisting } elseif ($catExisting) { @($catExisting) } else { @() }
            foreach ($it in $items) {
                if ($it.session_id) {
                    $cStr = if ($it.created_at) { $it.created_at } elseif ($it.started_at) { $it.started_at } elseif ($it.startedAt) { $it.startedAt } else { $null }
                    if ($cStr) {
                        try {
                            $cUtc = if ($cStr -match '^\d+$') { [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$cStr).UtcDateTime } else { [DateTime]::Parse($cStr, $null, [System.Globalization.DateTimeStyles]::AdjustToUniversal) }
                            if ($cUtc -lt $cutoffUtc) {
                                [void]$expiredSessionIds.Add([string]$it.session_id)
                            }
                        } catch {}
                    }
                }
            }
        } catch {}
    }

    # 2.1 Sessoes interrompidas podem existir apenas em active_schedule.json.
    # A retomada nunca estende o prazo absoluto contado desde started_at/created_at.
    if (Test-Path -LiteralPath $scheduleFile) {
        try {
            $activeSchedule = Get-Content -LiteralPath $scheduleFile -Raw -Encoding UTF8 | ConvertFrom-Json
            $activeSid = [string]$activeSchedule.session_id
            $activeCreatedStr = if ($activeSchedule.created_at) { $activeSchedule.created_at } elseif ($activeSchedule.started_at) { $activeSchedule.started_at } elseif ($activeSchedule.startedAt) { $activeSchedule.startedAt } else { $null }
            if ($activeSid -and $activeCreatedStr) {
                $activeCreatedUtc = if ($activeCreatedStr -match '^\d+$') { [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$activeCreatedStr).UtcDateTime } else { [DateTime]::Parse($activeCreatedStr, $null, [System.Globalization.DateTimeStyles]::AdjustToUniversal) }
                if ($activeCreatedUtc -lt $cutoffUtc) {
                    [void]$expiredSessionIds.Add($activeSid)
                    Remove-Item -LiteralPath $scheduleFile -Force -ErrorAction SilentlyContinue
                    if ($script:ActiveSession -and [string]$script:ActiveSession.session_id -eq $activeSid) {
                        $script:ActiveSession = $null
                    }
                }
            }
        } catch {
            Write-BridgeLog "Aviso ao avaliar agenda ativa na retencao: $($_.Exception.Message)" "WARN"
        }
    }

    if ($expiredSessionIds.Count -eq 0) {
        return
    }

    # 3. Expurgo atomico de sessoes expiradas e TODOS os seus eventos associados
    $purgedEventsCount = 0
    $purgedEventIds = [System.Collections.Generic.HashSet[string]]::new()

    # a) Arquivos de sessao
    foreach ($sid in $expiredSessionIds) {
        $safeSid = ($sid -replace '[^a-zA-Z0-9_-]', '_')
        $sessPath = Join-Path $sessoesDir "sessao_$safeSid.json"
        if (Test-Path -LiteralPath $sessPath) {
            Remove-Item -LiteralPath $sessPath -Force -ErrorAction SilentlyContinue
        }
    }

    # b) Catalogo de sessoes
    if (Test-Path -LiteralPath $catFile) {
        try {
            $catExisting = Get-Content -LiteralPath $catFile -Raw -Encoding UTF8 | ConvertFrom-Json
            $survivingCatalog = [System.Collections.Generic.List[object]]::new()
            $items = if ($catExisting -is [System.Collections.IEnumerable]) { $catExisting } elseif ($catExisting) { @($catExisting) } else { @() }
            foreach ($it in $items) {
                if ($it.session_id -and -not $expiredSessionIds.Contains([string]$it.session_id)) {
                    $survivingCatalog.Add($it)
                }
            }
            $catJson = $survivingCatalog | ConvertTo-Json -Depth 5
            $catTmp = Join-Path $DataDir "catalogo_sessoes.tmp.$([System.Guid]::NewGuid().ToString('N'))"
            [System.IO.File]::WriteAllText($catTmp, $catJson, [System.Text.Encoding]::UTF8)
            Move-BridgeAtomicFile -SourcePath $catTmp -DestinationPath $catFile
        } catch {
            Write-BridgeLog "Aviso ao expurgar catalogo na retencao: $($_.Exception.Message)" "WARN"
        }
    }

    # c) events.jsonl
    $eventsFile = Join-Path $DataDir "events.jsonl"
    if (Test-Path -LiteralPath $eventsFile) {
        try {
            $allLines = [System.IO.File]::ReadAllLines($eventsFile, [System.Text.Encoding]::UTF8)
            $survivingLines = [System.Collections.Generic.List[string]]::new()
            foreach ($line in $allLines) {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                try {
                    $evObj = $line | ConvertFrom-Json
                    if ($evObj.session_id -and $expiredSessionIds.Contains([string]$evObj.session_id)) {
                        $purgedEventsCount++
                        if ($evObj.event_id) { [void]$purgedEventIds.Add([string]$evObj.event_id) }
                        continue
                    }
                    $survivingLines.Add($line)
                } catch {
                    $survivingLines.Add($line)
                }
            }
            $eventsTmp = Join-Path $DataDir "events.tmp.$([System.Guid]::NewGuid().ToString('N'))"
            [System.IO.File]::WriteAllLines($eventsTmp, $survivingLines, [System.Text.Encoding]::UTF8)
            Move-BridgeAtomicFile -SourcePath $eventsTmp -DestinationPath $eventsFile
        } catch {
            Write-BridgeLog "Aviso ao expurgar events.jsonl na retencao: $($_.Exception.Message)" "WARN"
        }
    }

    # d) events_archive.jsonl
    $archiveFile = Join-Path $DataDir "events_archive.jsonl"
    if (Test-Path -LiteralPath $archiveFile) {
        try {
            $allLines = [System.IO.File]::ReadAllLines($archiveFile, [System.Text.Encoding]::UTF8)
            $survivingLines = [System.Collections.Generic.List[string]]::new()
            foreach ($line in $allLines) {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                try {
                    $evObj = $line | ConvertFrom-Json
                    if ($evObj.session_id -and $expiredSessionIds.Contains([string]$evObj.session_id)) {
                        if ($evObj.event_id) { [void]$purgedEventIds.Add([string]$evObj.event_id) }
                        continue
                    }
                    $survivingLines.Add($line)
                } catch {
                    $survivingLines.Add($line)
                }
            }
            $archTmp = Join-Path $DataDir "events_archive.tmp.$([System.Guid]::NewGuid().ToString('N'))"
            [System.IO.File]::WriteAllLines($archTmp, $survivingLines, [System.Text.Encoding]::UTF8)
            Move-BridgeAtomicFile -SourcePath $archTmp -DestinationPath $archiveFile
        } catch {}
    }

    # e) Payloads completos de quarentena seguem a mesma retencao conjunta.
    $quarantineJsonlFile = Join-Path $DataDir "events_quarantine.jsonl"
    if (Test-Path -LiteralPath $quarantineJsonlFile) {
        try {
            $allLines = [System.IO.File]::ReadAllLines($quarantineJsonlFile, [System.Text.Encoding]::UTF8)
            $survivingLines = [System.Collections.Generic.List[string]]::new()
            foreach ($line in $allLines) {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                try {
                    $qObj = $line | ConvertFrom-Json
                    $qSessionId = if ($qObj.session_id) { [string]$qObj.session_id } elseif ($qObj.event -and $qObj.event.session_id) { [string]$qObj.event.session_id } else { "" }
                    if ($qSessionId -and $expiredSessionIds.Contains($qSessionId)) {
                        if ($qObj.event_id) { [void]$purgedEventIds.Add([string]$qObj.event_id) }
                        continue
                    }
                    $survivingLines.Add($line)
                } catch {
                    $survivingLines.Add($line)
                }
            }
            $quarantineTmp = Join-Path $DataDir "events_quarantine_payloads.tmp.$([System.Guid]::NewGuid().ToString('N'))"
            [System.IO.File]::WriteAllLines($quarantineTmp, $survivingLines, [System.Text.Encoding]::UTF8)
            Move-BridgeAtomicFile -SourcePath $quarantineTmp -DestinationPath $quarantineJsonlFile
        } catch {
            Write-BridgeLog "Aviso ao expurgar events_quarantine.jsonl na retencao: $($_.Exception.Message)" "WARN"
        }
    }

    # f) Trackers de eventos
    if ($purgedEventIds.Count -gt 0) {
        foreach ($purgedId in $purgedEventIds) {
            [void]$script:SyncedEventIds.Remove($purgedId)
            [void]$script:QuarantinedEventIds.Remove($purgedId)
        }
        if (Test-Path -LiteralPath $script:SyncedTrackerFile) {
            try {
                $syncTmp = Join-Path $DataDir "events_synced.tmp.$([System.Guid]::NewGuid().ToString('N'))"
                [System.IO.File]::WriteAllLines($syncTmp, [string[]]$script:SyncedEventIds, [System.Text.Encoding]::UTF8)
                Move-BridgeAtomicFile -SourcePath $syncTmp -DestinationPath $script:SyncedTrackerFile
            } catch {}
        }
        if (Test-Path -LiteralPath $script:QuarantinedTrackerFile) {
            try {
                $quarTmp = Join-Path $DataDir "events_quarantine.tmp.$([System.Guid]::NewGuid().ToString('N'))"
                [System.IO.File]::WriteAllLines($quarTmp, [string[]]$script:QuarantinedEventIds, [System.Text.Encoding]::UTF8)
                Move-BridgeAtomicFile -SourcePath $quarTmp -DestinationPath $script:QuarantinedTrackerFile
            } catch {}
        }
    }

    Write-BridgeLog "Limpeza de retencao concluida: $($expiredSessionIds.Count) sessao(oes) expirada(s) e $purgedEventsCount evento(s) expurgados (limite 7 dias)." "INFO"
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

    $marks = @()
    if ($null -ne $script:ActiveSession.marks) {
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

function Read-BoundedRequestBody {
    param(
        $Request,
        [int]$MaxBytes = 5242880
    )
    if ($Request.ContentLength64 -lt 0) {
        return @{ Success = $false; StatusCode = 411; Error = "Length required" }
    }
    if ($Request.ContentLength64 -gt $MaxBytes) {
        return @{ Success = $false; StatusCode = 413; Error = "Payload too large" }
    }
    $encoding = if ($Request.ContentEncoding) { $Request.ContentEncoding } else { [System.Text.Encoding]::UTF8 }
    $ms = [System.IO.MemoryStream]::new()
    $buffer = [byte[]]::new(8192)
    $totalRead = 0
    $stream = $Request.InputStream
    try {
        while ($true) {
            $read = $stream.Read($buffer, 0, $buffer.Length)
            if ($read -le 0) { break }
            $totalRead += $read
            if ($totalRead -gt $MaxBytes) {
                return @{ Success = $false; StatusCode = 413; Error = "Payload too large" }
            }
            $ms.Write($buffer, 0, $read)
        }
        $raw = $encoding.GetString($ms.ToArray())
        return @{ Success = $true; Body = $raw; BytesRead = $totalRead }
    } catch {
        return @{ Success = $false; StatusCode = 400; Error = $_.Exception.Message }
    } finally {
        $ms.Dispose()
    }
}

function Send-BridgeResponse {
    param(
        $Response,
        [int]$StatusCode = 200,
        [object]$Payload = $null
    )
    $Response.StatusCode = $StatusCode
    $Response.ContentType = "application/json; charset=utf-8"
    if ($null -ne $Payload) {
        $json = if ($Payload -is [string]) { $Payload } else { $Payload | ConvertTo-Json -Depth 10 }
        $buf = [System.Text.Encoding]::UTF8.GetBytes($json)
        $Response.ContentLength64 = $buf.Length
        $Response.OutputStream.Write($buf, 0, $buf.Length)
    } else {
        $Response.ContentLength64 = 0
    }
    $Response.Close()
}

# Executar limpeza de retencao absoluta de 7 dias na inicializacao
try {
    Invoke-BridgeRetentionCleanup -MaxAgeDays 7
} catch {
    Write-BridgeLog "Aviso na limpeza inicial de retencao: $($_.Exception.Message)" "WARN"
}

# 5. Transporte HTTP sobre TcpListener (loopback)
# HttpListener depende do http.sys, que exige reserva de URL (netsh urlacl) ou administrador
# para http://127.0.0.1:<porta>/ em contas padrao. TcpListener em loopback nao exige nada disso.
# As classes abaixo expoem o subconjunto da API de HttpListenerRequest/Response usado pelas rotas.
class PulseLabHttpRequest {
    [string]$HttpMethod = ""
    [string]$RawUrl = "/"
    [Uri]$Url
    [hashtable]$Headers = [hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)
    [long]$ContentLength64 = 0
    [string]$ContentType
    [System.Text.Encoding]$ContentEncoding = [System.Text.Encoding]::UTF8
    [System.IO.Stream]$InputStream = [System.IO.MemoryStream]::new()
}

class PulseLabHttpResponse {
    [int]$StatusCode = 200
    [string]$ContentType
    [long]$ContentLength64 = 0
    [string]$RedirectLocation
    [System.IO.MemoryStream]$OutputStream = [System.IO.MemoryStream]::new()
    hidden [System.Collections.Generic.List[string]]$ExtraHeaders = [System.Collections.Generic.List[string]]::new()
    hidden [System.Net.Sockets.TcpClient]$Client
    hidden [bool]$SuppressBody = $false
    hidden [bool]$IsClosed = $false

    PulseLabHttpResponse([System.Net.Sockets.TcpClient]$client, [bool]$suppressBody) {
        $this.Client = $client
        $this.SuppressBody = $suppressBody
    }

    [void] AddHeader([string]$name, [string]$value) {
        if ($name -match '[\r\n:]' -or $value -match '[\r\n]') { return }
        $this.ExtraHeaders.Add("${name}: $value")
    }

    # Content-Length e sempre calculado a partir do corpo bufferizado; uma conexao por requisicao.
    [void] Close() {
        if ($this.IsClosed) { return }
        $this.IsClosed = $true
        try {
            $body = $this.OutputStream.ToArray()
            $reason = [System.Enum]::GetName([System.Net.HttpStatusCode], $this.StatusCode)
            $reason = if ($reason) { $reason -creplace '([a-z])([A-Z])', '$1 $2' } else { "Status" }
            $sb = [System.Text.StringBuilder]::new()
            [void]$sb.Append("HTTP/1.1 $($this.StatusCode) $reason`r`n")
            if ($this.ContentType) { [void]$sb.Append("Content-Type: $($this.ContentType)`r`n") }
            if ($this.RedirectLocation) { [void]$sb.Append("Location: $($this.RedirectLocation)`r`n") }
            foreach ($h in $this.ExtraHeaders) { [void]$sb.Append("$h`r`n") }
            [void]$sb.Append("Content-Length: $($body.Length)`r`n")
            [void]$sb.Append("Connection: close`r`n`r`n")
            $head = [System.Text.Encoding]::ASCII.GetBytes($sb.ToString())
            $stream = $this.Client.GetStream()
            $stream.Write($head, 0, $head.Length)
            if (-not $this.SuppressBody -and $body.Length -gt 0) {
                $stream.Write($body, 0, $body.Length)
            }
            $stream.Flush()
            try { $this.Client.Client.Shutdown([System.Net.Sockets.SocketShutdown]::Send) } catch {}
        } catch {
            # Cliente desconectou antes da resposta; nada a fazer.
        } finally {
            try { $this.OutputStream.Dispose() } catch {}
            try { $this.Client.Close() } catch {}
        }
    }
}

function Read-PulseLabHttpContext {
    param(
        [System.Net.Sockets.TcpClient]$Client,
        [int]$Port,
        [int]$MaxHeaderBytes = 32768,
        [long]$MaxBodyBytes = 5242880
    )
    $stream = $Client.GetStream()
    $stream.ReadTimeout = 5000
    $stream.WriteTimeout = 5000

    # Latin-1 mapeia byte -> char 1:1, entao indices da string equivalem a indices do buffer.
    $latin1 = [System.Text.Encoding]::GetEncoding(28591)
    $buffer = [byte[]]::new(8192)
    $acc = [System.IO.MemoryStream]::new()
    $headerEnd = -1
    while ($headerEnd -lt 0) {
        $read = $stream.Read($buffer, 0, $buffer.Length)
        if ($read -le 0) { return $null }
        $acc.Write($buffer, 0, $read)
        $headerEnd = $latin1.GetString($acc.GetBuffer(), 0, [int]$acc.Length).IndexOf("`r`n`r`n")
        if ($headerEnd -lt 0 -and $acc.Length -gt $MaxHeaderBytes) { return $null }
    }
    $data = $acc.GetBuffer()
    $dataLen = [int]$acc.Length

    $req = [PulseLabHttpRequest]::new()
    $valid = $false
    $lines = $latin1.GetString($data, 0, $headerEnd) -split "`r`n"
    if ($lines[0] -match '^([A-Z]+) (\S+) HTTP/1\.[01]$') {
        $req.HttpMethod = $Matches[1]
        $req.RawUrl = $Matches[2]
        $valid = $true
    }
    for ($i = 1; $i -lt $lines.Count; $i++) {
        $sep = $lines[$i].IndexOf(':')
        if ($sep -le 0) { $valid = $false; continue }
        $name = $lines[$i].Substring(0, $sep).Trim()
        $value = $lines[$i].Substring($sep + 1).Trim()
        if ($req.Headers.ContainsKey($name)) {
            $req.Headers[$name] = "$($req.Headers[$name]), $value"
        } else {
            $req.Headers[$name] = $value
        }
    }

    # Host estrito (como o http.sys fazia com os prefixos): bloqueia DNS rebinding.
    $hostHeader = ([string]$req.Headers["Host"]).ToLowerInvariant()
    if ($hostHeader -notin @("127.0.0.1:$Port", "localhost:$Port")) { $valid = $false }

    if ($valid) {
        if ($req.RawUrl.StartsWith("/") -and -not $req.RawUrl.StartsWith("//")) {
            try { $req.Url = [Uri]::new("http://127.0.0.1:$Port$($req.RawUrl)") } catch { $valid = $false }
        } else {
            $valid = $false
        }
    }

    $req.ContentType = [string]$req.Headers["Content-Type"]
    if ($req.ContentType -match 'charset\s*=\s*"?([A-Za-z0-9._-]+)') {
        try { $req.ContentEncoding = [System.Text.Encoding]::GetEncoding($Matches[1]) } catch {}
    }

    $clHeader = [string]$req.Headers["Content-Length"]
    if ($req.Headers["Transfer-Encoding"]) {
        $req.ContentLength64 = -1
    } elseif ($clHeader) {
        $parsedLength = [long]0
        if ([long]::TryParse($clHeader, [ref]$parsedLength) -and $parsedLength -ge 0) {
            $req.ContentLength64 = $parsedLength
        } else {
            $valid = $false
        }
    }

    # Corpo acima do limite nao e lido; as rotas respondem 413 a partir de ContentLength64.
    if ($valid -and $req.ContentLength64 -gt 0 -and $req.ContentLength64 -le $MaxBodyBytes) {
        $bodyStart = $headerEnd + 4
        $bodyMs = [System.IO.MemoryStream]::new()
        $take = [int][Math]::Min([long]($dataLen - $bodyStart), $req.ContentLength64)
        if ($take -gt 0) { $bodyMs.Write($data, $bodyStart, $take) }
        $remaining = $req.ContentLength64 - $take
        while ($remaining -gt 0) {
            $read = $stream.Read($buffer, 0, [int][Math]::Min([long]$buffer.Length, $remaining))
            if ($read -le 0) { break }
            $bodyMs.Write($buffer, 0, $read)
            $remaining -= $read
        }
        if ($remaining -gt 0) { $valid = $false }
        $bodyMs.Position = 0
        $req.InputStream = $bodyMs
    }
    $acc.Dispose()

    $resp = [PulseLabHttpResponse]::new($Client, ($req.HttpMethod -eq "HEAD"))
    return [PSCustomObject]@{ Request = $req; Response = $resp; IsValid = $valid }
}

$script:PendingClients = [System.Collections.Generic.List[object]]::new()
$script:LastPeriodicTick = [DateTime]::MinValue

function Invoke-BridgePeriodicTasks {
    if (([DateTime]::UtcNow - $script:LastPeriodicTick).TotalMilliseconds -lt 1000) { return }
    $script:LastPeriodicTick = [DateTime]::UtcNow
    Check-SessionSchedule
    if (([DateTime]::UtcNow - $script:LastRetentionCleanup).TotalHours -ge 1) {
        $script:LastRetentionCleanup = [DateTime]::UtcNow
        try { Invoke-BridgeRetentionCleanup -MaxAgeDays 7 } catch {}
    }
    if (([DateTime]::UtcNow - $script:LastSyncAttempt).TotalSeconds -ge 30) {
        $script:LastSyncAttempt = [DateTime]::UtcNow
        Sync-EventsToSupabase
        Sync-SessionSnapshotsToSupabase
    }
}

# Bloqueia ate haver uma requisicao completa. Conexoes abertas sem dados (preconnect do
# navegador) ficam em espera sem travar as demais; ociosas por mais de 60s sao descartadas.
function Get-NextBridgeContext {
    param(
        [System.Net.Sockets.TcpListener]$Listener,
        [int]$Port
    )
    while ($true) {
        # Saida descartada: tudo que a funcao emitir viraria parte do valor de retorno.
        try { $null = Invoke-BridgePeriodicTasks } catch { Write-BridgeLog "Aviso em tarefa periodica: $($_.Exception.Message)" "WARN" }
        while ($Listener.Pending()) {
            $script:PendingClients.Add([PSCustomObject]@{ Client = $Listener.AcceptTcpClient(); Since = [DateTime]::UtcNow })
        }
        for ($i = 0; $i -lt $script:PendingClients.Count; $i++) {
            $entry = $script:PendingClients[$i]
            $ready = $false
            $drop = $false
            try {
                if ($entry.Client.Client.Poll(0, [System.Net.Sockets.SelectMode]::SelectRead)) {
                    if ($entry.Client.Client.Available -gt 0) { $ready = $true } else { $drop = $true }
                } elseif (([DateTime]::UtcNow - $entry.Since).TotalSeconds -gt 60) {
                    $drop = $true
                }
            } catch {
                $drop = $true
            }
            if (-not $ready -and -not $drop) { continue }

            $script:PendingClients.RemoveAt($i)
            $i--
            $ctx = $null
            if ($ready) {
                try { $ctx = Read-PulseLabHttpContext -Client $entry.Client -Port $Port } catch { $ctx = $null }
            }
            if ($ctx) { return $ctx }
            try { $entry.Client.Close() } catch {}
        }
        Start-Sleep -Milliseconds 20
    }
}

$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
$listener.ExclusiveAddressUse = $true
$prefix = "http://127.0.0.1:$Port/"

try {
    $listener.Start()
    Write-BridgeLog "PulseLab Bridge v$($script:BridgeVersion) ativo em $prefix" "INFO"
    Write-BridgeLog "Pasta da WebApp: $AppRoot" "INFO"
    Write-BridgeLog "Armazenamento:   $DataDir" "INFO"
} catch {
    Write-BridgeLog "Falha ao iniciar servidor local na porta $Port`: $($_.Exception.ToString())" "ERROR"
    exit 1
}

# 6. Loop de Atendimento Resiliente
try {
    while ($true) {
        $context = Get-NextBridgeContext -Listener $listener -Port $Port
        if (-not $context.IsValid) {
            $context.Response.StatusCode = 400
            $context.Response.Close()
            continue
        }

        # Processar cada requisição com tratamento de erro individual para garantir 100% de estabilidade
        try {
            $request = $context.Request
            $response = $context.Response

            # CORS e Protecao de Origem Estrita
            $origin = $request.Headers["Origin"]
            $isAllowedOrigin = Test-PulseLabAllowedOrigin -Origin $origin -ExpectedPort $Port

            # Endurecimento: metodos mutantes (POST/PUT/DELETE/PATCH) exigem Origin exato da aplicacao local
            # Rejeita Origin null, ausente ou diferente para impedir paginas HTML locais arbitrarias
            # de inserir eventos, sobrescrever snapshot, resetar sessao ou disparar update.
            $isMutating = $request.HttpMethod -in @("POST", "PUT", "DELETE", "PATCH")
            if ($isMutating) {
                if (-not $isAllowedOrigin) {
                    Write-BridgeLog "Acesso negado para metodo mutante $($request.HttpMethod) com origem invalida ou ausente: '$origin'" "WARN"
                    $response.StatusCode = 403
                    $response.Close()
                    continue
                }
            }

            if ($isAllowedOrigin) {
                $response.AddHeader("Access-Control-Allow-Origin", $origin)
            }
            $response.AddHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
            $response.AddHeader("Access-Control-Allow-Headers", "Content-Type, Prefer, apikey, Authorization")

            if ($request.HttpMethod -eq "OPTIONS") {
                if (-not $isAllowedOrigin) {
                    $response.StatusCode = 403
                    $response.Close()
                    continue
                }
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

            # --- RESTRICAO DE METODOS E HEADERS POR ROTA ---
            # 1. Rotas estritamente GET
            if ($path -in @("/health", "/v1/health", "/config", "/v1/config", "/v1/spike/metrics")) {
                if ($request.HttpMethod -ne "GET") {
                    $response.StatusCode = 405
                    $response.AddHeader("Allow", "GET")
                    $response.Close()
                    continue
                }
            }

            # 2. Rotas estritamente POST
            $postRoutes = @(
                "/v1/sessions",
                "/v1/sessions/save",
                "/v1/events",
                "/v1/alert",
                "/v1/sessions/reset",
                "/update",
                "/v1/update"
            )
            if ($path -in $postRoutes -or $path -match "^/v1/sessions/([^/]+)/checkpoints/(\d+)/ack$") {
                if ($request.HttpMethod -ne "POST") {
                    $response.StatusCode = 405
                    $response.AddHeader("Allow", "POST")
                    $response.Close()
                    continue
                }
            }

            # 3. Endpoints que consomem corpo JSON: exigir Content-Type e limitar Content-Length
            $jsonBodyRoutes = @("/v1/sessions", "/v1/sessions/save", "/v1/events", "/v1/alert", "/v1/sessions/reset")
            if ($path -in $jsonBodyRoutes) {
                if ($request.ContentLength64 -lt 0) {
                    Write-BridgeLog "Rejeitada requisicao sem Content-Length definido em $path" "WARN"
                    $response.StatusCode = 411
                    $response.Close()
                    continue
                }
                if ($request.ContentLength64 -gt 5242880) {
                    Write-BridgeLog "Corpo da requisicao excede limite de 5MB ($($request.ContentLength64) bytes): $path" "WARN"
                    $response.StatusCode = 413
                    $response.Close()
                    continue
                }
                $ct = $request.ContentType
                if (-not $ct -or -not ($ct.ToLower().StartsWith("application/json"))) {
                    Write-BridgeLog "Content-Type rejeitado para endpoint JSON: '$ct' em $path" "WARN"
                    $response.StatusCode = 415
                    $response.Close()
                    continue
                }
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
                $response.StatusCode = 403
                $updateObj = @{
                    status = "disabled"
                    message = "Atualizacao automatica remota desabilitada por politica institucional de seguranca. Realize atualizacao manual por pacote previamente verificado."
                    version = $script:BridgeVersion
                }
                $buf = [System.Text.Encoding]::UTF8.GetBytes(($updateObj | ConvertTo-Json))
                $response.ContentType = "application/json; charset=utf-8"
                $response.ContentLength64 = $buf.Length
                $response.OutputStream.Write($buf, 0, $buf.Length)
                $response.Close()
                continue
            }

            if ($path -eq "/config" -or $path -eq "/v1/config") {
                $publicConfig = [ordered]@{
                    version = $script:BridgeVersion
                    protocol_version = "2.2.2"
                    group_size = 2
                    site_id = "CONFIGURE_SEDE"
                    activity_id = "atividade-01-spike"
                    regional_hub = "Nordeste"
                    school_code = "CONFIGURE_ESCOLA"
                    workshop_code = "CONFIGURE_OFICINA"
                    class_code = "CONFIGURE_TURMA"
                    questions = @{}
                }
                if (Test-Path $candidateConfig) {
                    try {
                        $cfg = Get-Content -Path $candidateConfig -Raw -Encoding UTF8 | ConvertFrom-Json
                        if ($cfg.version) { $publicConfig.version = $cfg.version }
                        if ($cfg.protocol_version) { $publicConfig.protocol_version = $cfg.protocol_version }
                        if ($cfg.group_size) { $publicConfig.group_size = $cfg.group_size }
                        if ($cfg.site_id) { $publicConfig.site_id = $cfg.site_id }
                        if ($cfg.activity_id) { $publicConfig.activity_id = $cfg.activity_id }
                        if ($cfg.regional_hub) { $publicConfig.regional_hub = $cfg.regional_hub }
                        if ($cfg.school_code) { $publicConfig.school_code = $cfg.school_code }
                        if ($cfg.workshop_code) { $publicConfig.workshop_code = $cfg.workshop_code }
                        if ($cfg.class_code) { $publicConfig.class_code = $cfg.class_code }
                        if ($cfg.questions) { $publicConfig.questions = $cfg.questions }
                    } catch {}
                }
                $buf = [System.Text.Encoding]::UTF8.GetBytes(($publicConfig | ConvertTo-Json -Depth 5))
                $response.ContentType = "application/json; charset=utf-8"
                $response.ContentLength64 = $buf.Length
                $response.OutputStream.Write($buf, 0, $buf.Length)
                $response.Close()
                continue
            }

            if ($path -eq "/v1/sessions" -and $request.HttpMethod -eq "POST") {
                $readRes = Read-BoundedRequestBody -Request $request -MaxBytes 5242880
                if (-not $readRes.Success) {
                    Send-BridgeResponse -Response $response -StatusCode $readRes.StatusCode -Payload @{ error = $readRes.Error }
                    continue
                }

                $body = $null
                try {
                    if (-not [string]::IsNullOrWhiteSpace($readRes.Body)) {
                        $body = $readRes.Body | ConvertFrom-Json
                    }
                } catch {
                    $body = $null
                }

                $sessId = if ($body -and $body.session_id) { [string]$body.session_id } else { $null }
                if (-not $body -or [string]::IsNullOrWhiteSpace($sessId)) {
                    Write-BridgeLog "Requisicao /v1/sessions rejeitada: JSON invalido ou session_id ausente" "WARN"
                    Send-BridgeResponse -Response $response -StatusCode 400 -Payload @{ error = "Bad Request"; message = "JSON must be valid object containing session_id" }
                    continue
                }

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

                $marks = @()
                if ($null -ne $body.marks) {
                    $marks = @($body.marks)
                }

                $script:ActiveSession = [PSCustomObject]@{
                    session_id = $sessId
                    started_at = $parsedStartedAt
                    marks = $marks
                    acks = @()
                    created_at = [DateTime]::UtcNow.ToString("o")
                }
                $schedTmp = Join-Path $DataDir "active_schedule.tmp.$([System.Guid]::NewGuid().ToString('N'))"
                $schedJson = $script:ActiveSession | ConvertTo-Json
                [System.IO.File]::WriteAllText($schedTmp, $schedJson, [System.Text.Encoding]::UTF8)
                Move-BridgeAtomicFile -SourcePath $schedTmp -DestinationPath $scheduleFile
                $script:LastAlertMark = 0
                $script:AlertCount = 0

                Send-BridgeResponse -Response $response -StatusCode 200 -Payload @{ status = "scheduled"; session_id = $script:ActiveSession.session_id }
                continue
            }

            if ($path -eq "/v1/sessions/save" -and $request.HttpMethod -eq "POST") {
                $readRes = Read-BoundedRequestBody -Request $request -MaxBytes 5242880
                if (-not $readRes.Success) {
                    Send-BridgeResponse -Response $response -StatusCode $readRes.StatusCode -Payload @{ error = $readRes.Error }
                    continue
                }

                $rawBody = $readRes.Body
                $saveObj = $null
                try {
                    if (-not [string]::IsNullOrWhiteSpace($rawBody)) {
                        $saveObj = $rawBody | ConvertFrom-Json
                    }
                } catch {
                    $saveObj = $null
                }

                $sessId = if ($saveObj -and $saveObj.session_id) { [string]$saveObj.session_id } else { $null }
                if (-not $saveObj -or [string]::IsNullOrWhiteSpace($sessId)) {
                    Write-BridgeLog "Payload de sessao rejeitado em /v1/sessions/save: JSON invalido ou session_id ausente" "WARN"
                    Send-BridgeResponse -Response $response -StatusCode 400 -Payload @{ error = "Bad Request"; message = "JSON must be valid object containing session_id" }
                    continue
                }

                $safeSessId = ($sessId -replace '[^a-zA-Z0-9_-]', '_')

                $sessoesDir = Join-Path $DataDir "sessoes"
                if (-not (Test-Path $sessoesDir)) {
                    New-Item -ItemType Directory -Path $sessoesDir -Force | Out-Null
                }

                $sessFile = Join-Path $sessoesDir "sessao_$safeSessId.json"
                $sessTmp = Join-Path $sessoesDir "sessao_$safeSessId.tmp.$([System.Guid]::NewGuid().ToString('N'))"
                [System.IO.File]::WriteAllText($sessTmp, $rawBody, [System.Text.Encoding]::UTF8)
                Move-BridgeAtomicFile -SourcePath $sessTmp -DestinationPath $sessFile

                # Atualiza catalogo local de sessoes (catalogo_sessoes.json)
                $catFile = Join-Path $DataDir "catalogo_sessoes.json"
                $catalogList = [System.Collections.Generic.List[object]]::new()
                if (Test-Path $catFile) {
                    try {
                        $existingJson = Get-Content -Path $catFile -Raw -Encoding UTF8
                        $existing = $existingJson | ConvertFrom-Json
                        if ($existing -is [System.Collections.IEnumerable]) {
                            foreach ($item in $existing) {
                                if ($item.session_id -ne $sessId) {
                                    $catalogList.Add($item)
                                }
                            }
                        } else {
                            if ($existing -and $existing.session_id -ne $sessId) {
                                $catalogList.Add($existing)
                            }
                        }
                    } catch {}
                }

                $evCount = 0
                if ($saveObj -and $saveObj.events) {
                    if ($saveObj.events -is [System.Collections.IEnumerable]) {
                        $evCount = $saveObj.events.Count
                    } else {
                        $evCount = 1
                    }
                }

                $summaryRecord = [PSCustomObject]@{
                    session_id = $sessId
                    group_id = if ($saveObj) { [string]$saveObj.group_id } else { "" }
                    school_code = if ($saveObj) { [string]$saveObj.school_code } else { "" }
                    class_code = if ($saveObj) { [string]$saveObj.class_code } else { "" }
                    workshop_code = if ($saveObj) { [string]$saveObj.workshop_code } else { "" }
                    started_at = if ($saveObj) { [string]$saveObj.started_at } else { "" }
                    completed_at = if ($saveObj) { [string]$saveObj.completed_at } else { "" }
                    duration_seconds = if ($saveObj -and $saveObj.duration_seconds) { [int]$saveObj.duration_seconds } else { 0 }
                    team_role = if ($saveObj) { [string]$saveObj.team_role } else { "" }
                    status = if ($saveObj) { [string]$saveObj.status } else { "completed" }
                    events_count = $evCount
                    saved_locally_at = [DateTime]::UtcNow.ToString("o")
                    file_path = "sessoes/sessao_$safeSessId.json"
                }
                $catalogList.Add($summaryRecord)

                $catJson = $catalogList | ConvertTo-Json -Depth 5
                $catTmp = Join-Path $DataDir "catalogo_sessoes.tmp.$([System.Guid]::NewGuid().ToString('N'))"
                [System.IO.File]::WriteAllText($catTmp, $catJson, [System.Text.Encoding]::UTF8)
                Move-BridgeAtomicFile -SourcePath $catTmp -DestinationPath $catFile

                # Persiste tambem todos os eventos da sessao no events.jsonl
                if ($saveObj -and $saveObj.events) {
                    $eventsFile = Join-Path $DataDir "events.jsonl"
                    $linesToAppend = [System.Collections.Generic.List[string]]::new()
                    if ($saveObj.events -is [System.Collections.IEnumerable]) {
                        foreach ($ev in $saveObj.events) {
                            $linesToAppend.Add(($ev | ConvertTo-Json -Compress -Depth 10))
                        }
                    } else {
                        $linesToAppend.Add(($saveObj.events | ConvertTo-Json -Compress -Depth 10))
                    }
                    if ($linesToAppend.Count -gt 0) {
                        [System.IO.File]::AppendAllLines($eventsFile, $linesToAppend, [System.Text.Encoding]::UTF8)
                        Sync-EventsToSupabase
                    }
                }
                Sync-SessionSnapshotsToSupabase

                Write-BridgeLog "Sessao $safeSessId salva com sucesso na base local ($sessFile)." "INFO"

                $respObj = @{
                    status = "saved"
                    session_id = $sessId
                    file = "sessao_$safeSessId.json"
                    data_dir = $DataDir
                    total_sessions = $catalogList.Count
                }
                $buf = [System.Text.Encoding]::UTF8.GetBytes(($respObj | ConvertTo-Json))
                $response.ContentType = "application/json; charset=utf-8"
                $response.ContentLength64 = $buf.Length
                $response.OutputStream.Write($buf, 0, $buf.Length)
                $response.Close()
                continue
            }

            if (($path -eq "/v1/database/summary" -or $path -eq "/v1/database/export") -and $request.HttpMethod -eq "GET") {
                $sessoesDir = Join-Path $DataDir "sessoes"
                $totalSessions = 0
                if (Test-Path $sessoesDir) {
                    $totalSessions = (Get-ChildItem -Path $sessoesDir -Filter "*.json" -ErrorAction SilentlyContinue | Measure-Object).Count
                }
                $eventsFile = Join-Path $DataDir "events.jsonl"
                $totalEvents = 0
                if (Test-Path $eventsFile) {
                    $totalEvents = (Get-Content -Path $eventsFile -ErrorAction SilentlyContinue | Measure-Object).Count
                }
                $dbSummary = @{
                    status = "ok"
                    data_dir = $DataDir
                    total_sessions = $totalSessions
                    total_events = $totalEvents
                    synced_events = $script:SyncedEventIds.Count
                    pending_sync = [Math]::Max(0, ($totalEvents - $script:SyncedEventIds.Count))
                    version = $script:BridgeVersion
                }
                $buf = [System.Text.Encoding]::UTF8.GetBytes(($dbSummary | ConvertTo-Json))
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
                        $schedTmp = Join-Path $DataDir "active_schedule.tmp.$([System.Guid]::NewGuid().ToString('N'))"
                        $schedJson = $script:ActiveSession | ConvertTo-Json
                        [System.IO.File]::WriteAllText($schedTmp, $schedJson, [System.Text.Encoding]::UTF8)
                        Move-BridgeAtomicFile -SourcePath $schedTmp -DestinationPath $scheduleFile
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
                $readRes = Read-BoundedRequestBody -Request $request -MaxBytes 5242880
                if (-not $readRes.Success) {
                    Send-BridgeResponse -Response $response -StatusCode $readRes.StatusCode -Payload @{ error = $readRes.Error }
                    continue
                }

                $mark = 20
                if (-not [string]::IsNullOrWhiteSpace($readRes.Body)) {
                    try {
                        $body = $readRes.Body | ConvertFrom-Json
                        if ($body -and $body.mark) { $mark = [int]$body.mark }
                    } catch {
                        Send-BridgeResponse -Response $response -StatusCode 400 -Payload @{ error = "Bad Request"; message = "Invalid JSON in alert request" }
                        continue
                    }
                }

                Show-NativeCheckpointAlert -mark $mark
                Send-BridgeResponse -Response $response -StatusCode 200 -Payload @{ status = "triggered"; mark = $mark }
                continue
            }

            if ($path -eq "/v1/events" -and $request.HttpMethod -eq "POST") {
                $readRes = Read-BoundedRequestBody -Request $request -MaxBytes 5242880
                if (-not $readRes.Success) {
                    Send-BridgeResponse -Response $response -StatusCode $readRes.StatusCode -Payload @{ error = $readRes.Error }
                    continue
                }

                $rawJson = $readRes.Body
                $eventObj = $null
                try {
                    if (-not [string]::IsNullOrWhiteSpace($rawJson)) {
                        $eventObj = $rawJson | ConvertFrom-Json
                    }
                } catch {
                    $eventObj = $null
                }

                $evId = if ($eventObj -and $eventObj.event_id) { [string]$eventObj.event_id } else { $null }
                $sessId = if ($eventObj -and $eventObj.session_id) { [string]$eventObj.session_id } else { $null }

                if (-not $eventObj -or [string]::IsNullOrWhiteSpace($evId) -or [string]::IsNullOrWhiteSpace($sessId)) {
                    Write-BridgeLog "Evento rejeitado por JSON invalido ou ausencia de event_id/session_id" "WARN"
                    Send-BridgeResponse -Response $response -StatusCode 400 -Payload @{ error = "Bad Request"; message = "JSON must be valid object containing event_id and session_id" }
                    continue
                }

                try {
                    $eventsFile = Join-Path $DataDir "events.jsonl"
                    $compactJson = $eventObj | ConvertTo-Json -Depth 10 -Compress
                    [System.IO.File]::AppendAllText($eventsFile, "$compactJson`r`n", [System.Text.Encoding]::UTF8)
                    Sync-EventsToSupabase
                    Send-BridgeResponse -Response $response -StatusCode 200 -Payload @{ status = "persisted"; event_id = $evId; session_id = $sessId }
                } catch {
                    Write-BridgeLog "Falha ao gravar evento no disco: $($_.Exception.Message)" "WARN"
                    Send-BridgeResponse -Response $response -StatusCode 500 -Payload @{ error = "Internal Server Error" }
                }
                continue
            }

            if ($path -eq "/v1/sessions/reset" -and $request.HttpMethod -eq "POST") {
                $readRes = Read-BoundedRequestBody -Request $request -MaxBytes 5242880
                if (-not $readRes.Success) {
                    Send-BridgeResponse -Response $response -StatusCode $readRes.StatusCode -Payload @{ error = $readRes.Error }
                    continue
                }

                $reqObj = $null
                try {
                    if (-not [string]::IsNullOrWhiteSpace($readRes.Body)) {
                        $reqObj = $readRes.Body | ConvertFrom-Json
                    }
                } catch {
                    $reqObj = $null
                }

                $reqSessId = if ($reqObj -and $reqObj.session_id) { [string]$reqObj.session_id } else { $null }
                if ([string]::IsNullOrWhiteSpace($reqSessId)) {
                    Write-BridgeLog "Requisicao /v1/sessions/reset rejeitada: session_id e obrigatorio" "WARN"
                    Send-BridgeResponse -Response $response -StatusCode 400 -Payload @{ error = "Bad Request"; message = "session_id is required" }
                    continue
                }

                $reason = if ($reqObj -and $reqObj.reason) { [string]$reqObj.reason } else { "" }
                $explicitPurge = ($reqObj -and ($reqObj.purge -eq $true -or $reqObj.action -eq "purge" -or $reason -in @("ethical_refusal", "abandonment", "withdraw", "refusal", "purge")))
                $explicitCompleted = ($reqObj -and ($reqObj.completed -eq $true -or $reason -eq "prepare_next"))

                # Verificar se sessao consta como concluida no catalogo local
                $catFile = Join-Path $DataDir "catalogo_sessoes.json"
                $isCatalogCompleted = $false
                if (Test-Path $catFile) {
                    try {
                        $catJson = Get-Content -Path $catFile -Raw -Encoding UTF8 | ConvertFrom-Json
                        if ($catJson -is [System.Collections.IEnumerable]) {
                            foreach ($item in $catJson) {
                                if ($item.session_id -eq $reqSessId -and $item.status -eq "completed") {
                                    $isCatalogCompleted = $true
                                    break
                                }
                            }
                        } elseif ($catJson -and $catJson.session_id -eq $reqSessId -and $catJson.status -eq "completed") {
                            $isCatalogCompleted = $true
                        }
                    } catch {}
                }

                $shouldPurge = $explicitPurge -or (-not $explicitCompleted -and -not $isCatalogCompleted)

                # Resetar estado ativo em memoria e agenda
                $script:ActiveSession = $null
                $script:LastAlertMark = 0
                $script:AlertCount = 0
                if (Test-Path $scheduleFile) {
                    try { Remove-Item -LiteralPath $scheduleFile -Force -ErrorAction SilentlyContinue } catch {}
                }

                if (-not $shouldPurge) {
                    Write-BridgeLog "Preparando proxima oficina. Sessao concluida $reqSessId preservada na base local." "INFO"
                    Send-BridgeResponse -Response $response -StatusCode 200 -Payload @{ status = "preserved"; session_id = $reqSessId; purged = $false }
                    continue
                }

                # PURGA ATOMICA
                $safeSessId = ($reqSessId -replace '[^a-zA-Z0-9_-]', '_')

                # Snapshot/arquivo da sessao
                $sessoesDir = Join-Path $DataDir "sessoes"
                $sessFile = Join-Path $sessoesDir "sessao_$safeSessId.json"
                if (Test-Path $sessFile) {
                    try { Remove-Item -LiteralPath $sessFile -Force -ErrorAction SilentlyContinue } catch {}
                }

                # Eventos de events.jsonl
                $purgedEventIds = [System.Collections.Generic.HashSet[string]]::new()
                $eventsFile = Join-Path $DataDir "events.jsonl"
                if (Test-Path $eventsFile) {
                    try {
                        $allLines = [System.IO.File]::ReadAllLines($eventsFile, [System.Text.Encoding]::UTF8)
                        $survivingLines = [System.Collections.Generic.List[string]]::new()
                        foreach ($line in $allLines) {
                            if ([string]::IsNullOrWhiteSpace($line)) { continue }
                            try {
                                $evObj = $line | ConvertFrom-Json
                                if ($evObj.session_id -eq $reqSessId) {
                                    if ($evObj.event_id) { [void]$purgedEventIds.Add([string]$evObj.event_id) }
                                    continue
                                }
                                $survivingLines.Add($line)
                            } catch {
                                $survivingLines.Add($line)
                            }
                        }
                        $eventsTmp = Join-Path $DataDir "events.tmp.$([System.Guid]::NewGuid().ToString('N'))"
                        [System.IO.File]::WriteAllLines($eventsTmp, $survivingLines, [System.Text.Encoding]::UTF8)
                        Move-BridgeAtomicFile -SourcePath $eventsTmp -DestinationPath $eventsFile
                    } catch {
                        Write-BridgeLog "Aviso ao purgar eventos de $safeSessId`: $($_.Exception.Message)" "WARN"
                    }
                }

                # Eventos arquivados e payloads de quarentena pertencem ao mesmo registro da sessao.
                foreach ($jsonlSpec in @(
                    @{ Path = (Join-Path $DataDir "events_archive.jsonl"); Nested = $false; TempPrefix = "events_archive_purge" },
                    @{ Path = (Join-Path $DataDir "events_quarantine.jsonl"); Nested = $true; TempPrefix = "events_quarantine_payloads_purge" }
                )) {
                    if (-not (Test-Path -LiteralPath $jsonlSpec.Path)) { continue }
                    try {
                        $allLines = [System.IO.File]::ReadAllLines($jsonlSpec.Path, [System.Text.Encoding]::UTF8)
                        $survivingLines = [System.Collections.Generic.List[string]]::new()
                        foreach ($line in $allLines) {
                            if ([string]::IsNullOrWhiteSpace($line)) { continue }
                            try {
                                $recordObj = $line | ConvertFrom-Json
                                $recordSessionId = if ($jsonlSpec.Nested) {
                                    if ($recordObj.session_id) { [string]$recordObj.session_id } elseif ($recordObj.event -and $recordObj.event.session_id) { [string]$recordObj.event.session_id } else { "" }
                                } else {
                                    [string]$recordObj.session_id
                                }
                                if ($recordSessionId -eq $reqSessId) {
                                    if ($recordObj.event_id) { [void]$purgedEventIds.Add([string]$recordObj.event_id) }
                                    continue
                                }
                                $survivingLines.Add($line)
                            } catch {
                                $survivingLines.Add($line)
                            }
                        }
                        $jsonlTmp = Join-Path $DataDir "$($jsonlSpec.TempPrefix).tmp.$([System.Guid]::NewGuid().ToString('N'))"
                        [System.IO.File]::WriteAllLines($jsonlTmp, $survivingLines, [System.Text.Encoding]::UTF8)
                        Move-BridgeAtomicFile -SourcePath $jsonlTmp -DestinationPath $jsonlSpec.Path
                    } catch {
                        Write-BridgeLog "Aviso ao purgar $($jsonlSpec.Path) para $safeSessId`: $($_.Exception.Message)" "WARN"
                    }
                }

                # Catalogo de sessoes
                if (Test-Path $catFile) {
                    try {
                        $catExisting = Get-Content -Path $catFile -Raw -Encoding UTF8 | ConvertFrom-Json
                        $survivingCatalog = [System.Collections.Generic.List[object]]::new()
                        if ($catExisting -is [System.Collections.IEnumerable]) {
                            foreach ($item in $catExisting) {
                                if ($item.session_id -ne $reqSessId) {
                                    $survivingCatalog.Add($item)
                                }
                            }
                        } elseif ($catExisting -and $catExisting.session_id -ne $reqSessId) {
                            $survivingCatalog.Add($catExisting)
                        }
                        $catJson = $survivingCatalog | ConvertTo-Json -Depth 5
                        $catTmp = Join-Path $DataDir "catalogo_sessoes.tmp.$([System.Guid]::NewGuid().ToString('N'))"
                        [System.IO.File]::WriteAllText($catTmp, $catJson, [System.Text.Encoding]::UTF8)
                        Move-BridgeAtomicFile -SourcePath $catTmp -DestinationPath $catFile
                    } catch {
                        Write-BridgeLog "Aviso ao purgar catalogo para $safeSessId`: $($_.Exception.Message)" "WARN"
                    }
                }

                # Trackers locais
                if ($purgedEventIds.Count -gt 0) {
                    foreach ($purgedId in $purgedEventIds) {
                        [void]$script:SyncedEventIds.Remove($purgedId)
                        [void]$script:QuarantinedEventIds.Remove($purgedId)
                    }
                    if (Test-Path $script:SyncedTrackerFile) {
                        try {
                            $syncTmp = Join-Path $DataDir "events_synced.tmp.$([System.Guid]::NewGuid().ToString('N'))"
                            [System.IO.File]::WriteAllLines($syncTmp, [string[]]$script:SyncedEventIds, [System.Text.Encoding]::UTF8)
                            Move-BridgeAtomicFile -SourcePath $syncTmp -DestinationPath $script:SyncedTrackerFile
                        } catch {}
                    }
                    if (Test-Path $script:QuarantinedTrackerFile) {
                        try {
                            $quarTmp = Join-Path $DataDir "events_quarantine.tmp.$([System.Guid]::NewGuid().ToString('N'))"
                            [System.IO.File]::WriteAllLines($quarTmp, [string[]]$script:QuarantinedEventIds, [System.Text.Encoding]::UTF8)
                            Move-BridgeAtomicFile -SourcePath $quarTmp -DestinationPath $script:QuarantinedTrackerFile
                        } catch {}
                    }
                }

                [void]$script:SyncedSessionIds.Remove($reqSessId)
                [void]$script:QuarantinedSessionIds.Remove($reqSessId)
                if (Test-Path $script:SyncedSessionsTrackerFile) {
                    try {
                        $sessSyncTmp = Join-Path $DataDir "sessions_synced.tmp.$([System.Guid]::NewGuid().ToString('N'))"
                        [System.IO.File]::WriteAllLines($sessSyncTmp, [string[]]$script:SyncedSessionIds, [System.Text.Encoding]::UTF8)
                        Move-BridgeAtomicFile -SourcePath $sessSyncTmp -DestinationPath $script:SyncedSessionsTrackerFile
                    } catch {}
                }
                if (Test-Path $script:QuarantinedSessionsTrackerFile) {
                    try {
                        $sessQuarTmp = Join-Path $DataDir "sessions_quarantine.tmp.$([System.Guid]::NewGuid().ToString('N'))"
                        [System.IO.File]::WriteAllLines($sessQuarTmp, [string[]]$script:QuarantinedSessionIds, [System.Text.Encoding]::UTF8)
                        Move-BridgeAtomicFile -SourcePath $sessQuarTmp -DestinationPath $script:QuarantinedSessionsTrackerFile
                    } catch {}
                }

                Write-BridgeLog "Sessao $safeSessId expurgada com sucesso (motivo: $reason). Nenhum payload mantido." "INFO"
                Send-BridgeResponse -Response $response -StatusCode 200 -Payload @{ status = "purged"; session_id = $reqSessId; purged = $true; purged_events = $purgedEventIds.Count }
                continue
            }

            if ($path -eq "/v1/spike/metrics" -and $request.HttpMethod -eq "GET") {
                $minTime = [DateTime]::MinValue
                if ($script:ActiveSession -and $script:ActiveSession.started_at) {
                    try {
                        $minTime = [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$script:ActiveSession.started_at).UtcDateTime
                    } catch {}
                }
                $metrics = if (Get-Command Get-SpikeProjectMetrics -ErrorAction SilentlyContinue) {
                    Get-SpikeProjectMetrics -MinLastWriteTime $minTime
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
            } else {
                $reqExt = [System.IO.Path]::GetExtension($fullPath)
                # Fallback SPA routing somente para rotas de navegacao sem extensao de arquivo
                if ([string]::IsNullOrWhiteSpace($reqExt) -and (Test-Path (Join-Path $AppRoot "index.html"))) {
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
        } catch {
            Write-BridgeLog "Aviso ao atender requisicao $($request.HttpMethod) $path`: $($_.Exception.Message)" "WARN"
            try {
                if ($context -and $context.Response) {
                    $context.Response.StatusCode = 500
                    $context.Response.Close()
                }
            } catch {}
        } finally {
            # Garante resposta e fechamento do socket mesmo se uma rota nao fechou a resposta.
            try { $context.Response.Close() } catch {}
        }
    }
} catch {
    Write-BridgeLog "Excecao no loop do Bridge: $($_.Exception.ToString())" "ERROR"
} finally {
    Write-BridgeLog "Finalizando listener HTTP do PulseLab..." "INFO"
    foreach ($entry in $script:PendingClients) {
        try { $entry.Client.Close() } catch {}
    }
    if ($listener) {
        try { $listener.Stop() } catch {}
    }
}
