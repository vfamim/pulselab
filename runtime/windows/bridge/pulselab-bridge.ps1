# ==============================================================================
# PulseLab — Bridge HTTP Local e Sessão da Turma (Windows Offline)
# ==============================================================================
# - Servidor local em http://127.0.0.1:43128 (questionário do fim da aula em /alunos/)
# - Dono da sessão da turma: início, sinal de vida, telemetria do SPIKE e encerramento
# - Sem alertas ou janelas durante a aula; só a aba opcional do questionário do fim da aula
# - Extração de métricas de telemetria do SPIKE via spike-parser.ps1
# ==============================================================================

[CmdletBinding()]
param(
    [int]$Port = 43128,
    [string]$AppRoot = "",
    [string]$DataDir = "",
    [switch]$EnableAutoUpdate
)

$script:AutoUpdateEnabled = $false
$script:ShutdownRequested = $false

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

# 3. Estado em memória (a sessão da turma é restaurada por Initialize-BridgeSession)
$script:StartTime = [DateTime]::UtcNow

# 3.1 Supabase Sync Configuration & Tracker (Store-and-forward)
$script:SupabaseUrl = "https://cylsqbmtglvdfubbarqe.supabase.co"
$script:SupabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImN5bHNxYm10Z2x2ZGZ1YmJhcnFlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzc5NjE1MzIsImV4cCI6MjA5MzUzNzUzMn0.tscU354WLjnYz6E6NOrDQK16ViWBc-Af5FYhvZikFbU"
$script:SupabaseOperationalJwt = ""
$script:InstallationId = ""
$script:SiteId = ""

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

$script:DeviceSession = $null
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
                        $script:DeviceSession = $devSess
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
                                $script:DeviceSession = $devSess
                                break
                            }
                        }
                    }
                }
            } catch {}
        }
    }
}

$script:BridgeVersion = "3.2.3"
$verCandidate = Join-Path $PSScriptRoot "..\VERSION"
if (Test-Path $verCandidate) {
    try { $script:BridgeVersion = (Get-Content $verCandidate -Raw).Trim() } catch {}
}
$script:LastSyncAttempt = [DateTime]::MinValue
$script:LastRetentionCleanup = [DateTime]::MinValue
$script:LastEnrollmentAttempt = [DateTime]::MinValue
$script:SyncIntervalSeconds = 30
if ($cfgJson -and $cfgJson.sync_interval_seconds) {
    try { $script:SyncIntervalSeconds = [Math]::Max(1, [int]$cfgJson.sync_interval_seconds) } catch {}
}
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

# Ate a versao 2.3.1 a URL de envio de eventos saia errada e todo envio recebia HTTP 404.
# Esses eventos nao foram rejeitados pelo servidor: voltam para a fila.
$legacyQuarantine = Join-Path $DataDir "events_quarantine.jsonl"
if ((Test-Path $legacyQuarantine) -and $script:QuarantinedEventIds.Count -gt 0) {
    try {
        foreach ($qLine in [System.IO.File]::ReadAllLines($legacyQuarantine)) {
            if ([string]::IsNullOrWhiteSpace($qLine)) { continue }
            try {
                $q = $qLine | ConvertFrom-Json
                if ([int]$q.status_code -eq 404 -and $q.event_id) { [void]$script:QuarantinedEventIds.Remove([string]$q.event_id) }
            } catch {}
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

# Tombstones de retirada (gravados ate a versao 3.0.x, quando "Nao registrar esta turma" apagava na hora)
# impedem que arquivos atrasados voltem a ser sincronizados. A fila pendente guarda apenas session_id e
# sobrevive a reinicios ate a exclusao remota.
$script:WithdrawnSessionIds = [System.Collections.Generic.HashSet[string]]::new()
$script:WithdrawnSessionsTrackerFile = Join-Path $DataDir "sessions_withdrawn.txt"
$script:PendingWithdrawalIds = [System.Collections.Generic.HashSet[string]]::new()
$script:PendingWithdrawalsTrackerFile = Join-Path $DataDir "withdrawals_pending.txt"

foreach ($trackerSpec in @(
    @{ Path = $script:WithdrawnSessionsTrackerFile; Set = $script:WithdrawnSessionIds },
    @{ Path = $script:PendingWithdrawalsTrackerFile; Set = $script:PendingWithdrawalIds }
)) {
    if (Test-Path $trackerSpec.Path) {
        try {
            Get-Content $trackerSpec.Path | ForEach-Object {
                $tracked = $_.Trim()
                if ($tracked) { [void]$trackerSpec.Set.Add($tracked) }
            }
        } catch {}
    }
}

function Save-WithdrawalTrackers {
    try { [System.IO.File]::WriteAllLines($script:WithdrawnSessionsTrackerFile, [string[]]$script:WithdrawnSessionIds, [System.Text.Encoding]::UTF8) } catch {}
    try { [System.IO.File]::WriteAllLines($script:PendingWithdrawalsTrackerFile, [string[]]$script:PendingWithdrawalIds, [System.Text.Encoding]::UTF8) } catch {}
}

function Invoke-RemoteSessionPurge {
    param([Parameter(Mandatory = $true)][string]$SessionId)
    if (-not $script:SupabaseOperationalJwt) { return $false }
    try {
        $headers = @{
            apikey = $script:SupabaseAnonKey
            Authorization = "Bearer $($script:SupabaseOperationalJwt)"
            "Content-Type" = "application/json"
        }
        $body = @{ p_session_id = $SessionId } | ConvertTo-Json -Compress
        $uri = "$($script:SupabaseUrl)/rest/v1/rpc/purge_own_research_session"
        Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $body -TimeoutSec 8 -ErrorAction Stop | Out-Null
        return $true
    } catch {
        Write-BridgeLog "Exclusao remota pendente para sessao $SessionId`: $($_.Exception.Message)" "WARN"
        return $false
    }
}

function Sync-PendingWithdrawals {
    if (-not $script:SupabaseOperationalJwt -or $script:PendingWithdrawalIds.Count -eq 0) { return }
    foreach ($pendingSessionId in @($script:PendingWithdrawalIds)) {
        if (Invoke-RemoteSessionPurge -SessionId $pendingSessionId) {
            [void]$script:PendingWithdrawalIds.Remove($pendingSessionId)
        }
    }
    Save-WithdrawalTrackers
}

# Aulas marcadas como nao autorizadas ("Nao registrar esta turma"). Os dados ficam no computador pela
# retencao normal e sobem a nuvem com authorization_status = "nao_autorizada"; nunca entram em analise
# e sao apagados de vez na revisao do pesquisador. Uma linha por aula: session_id<TAB>marked_at.
$script:UnauthorizedSessions = @{}
$script:UnauthorizedTrackerFile = Join-Path $DataDir "sessions_unauthorized.txt"
if (Test-Path $script:UnauthorizedTrackerFile) {
    try {
        Get-Content $script:UnauthorizedTrackerFile | ForEach-Object {
            $parts = @($_.Trim() -split '\s+')
            if ($parts[0]) { $script:UnauthorizedSessions[$parts[0]] = if ($parts.Count -gt 1) { $parts[1] } else { "" } }
        }
    } catch {}
}

function Save-UnauthorizedTracker {
    $text = (@($script:UnauthorizedSessions.Keys | Sort-Object) | ForEach-Object { "$_`t$($script:UnauthorizedSessions[$_])`r`n" }) -join ""
    Save-BridgeTextAtomic -Path $script:UnauthorizedTrackerFile -Text $text
}

$script:HasLoggedJwtWarning = $false

function Get-BridgeHttpStatus($ErrorRecord) {
    try { return [int]$ErrorRecord.Exception.Response.StatusCode } catch { return 0 }
}

function Save-BridgeJsonAtomic([string]$Path, $Data) {
    Save-BridgeTextAtomic -Path $Path -Text ($Data | ConvertTo-Json -Depth 6)
}

# Grava a sessao do dispositivo: DPAPI no Windows; JSON so fora do Windows (testes em pwsh).
function Save-BridgeDeviceSession($Session) {
    $json = $Session | ConvertTo-Json -Depth 4 -Compress
    $onWindows = (-not (Test-Path variable:IsWindows)) -or $IsWindows
    if ($onWindows) {
        Add-Type -AssemblyName System.Security -ErrorAction SilentlyContinue
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
        $enc = [System.Security.Cryptography.ProtectedData]::Protect($bytes, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
        $target = Join-Path $DataDir "device_session.dat"
        [System.IO.File]::WriteAllBytes("$target.tmp", $enc)
        Move-BridgeAtomicFile -SourcePath "$target.tmp" -DestinationPath $target
    } else {
        Save-BridgeJsonAtomic -Path (Join-Path $DataDir "device_session.json") -Data $Session
    }
}

# Cadastro automatico: usa o token do polo (provisionamento.json) no primeiro contato com a internet.
function Invoke-BridgeDeviceEnrollment {
    if ($script:SupabaseOperationalJwt) { return }
    if (([DateTime]::UtcNow - $script:LastEnrollmentAttempt).TotalSeconds -lt [Math]::Max(60, $script:SyncIntervalSeconds) -and $script:LastEnrollmentAttempt -ne [DateTime]::MinValue) { return }
    $script:LastEnrollmentAttempt = [DateTime]::UtcNow

    $installationFile = Join-Path $DataDir "installation.json"
    if (-not (Test-Path -LiteralPath $installationFile)) { return }
    $inst = $null
    try { $inst = Get-Content -LiteralPath $installationFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return }
    if (-not $inst.enrollment_token -or -not $inst.installation_id -or -not $inst.site_id) { return }

    $body = [ordered]@{
        installation_id = [string]$inst.installation_id
        site_id = [string]$inst.site_id
        enrollment_token = [string]$inst.enrollment_token
        machine_label = [string]$inst.machine_label
    } | ConvertTo-Json -Compress
    $headers = @{
        apikey = $script:SupabaseAnonKey
        Authorization = "Bearer $($script:SupabaseAnonKey)"
        "Content-Type" = "application/json"
    }

    $resp = $null
    try {
        $resp = Invoke-RestMethod -Method Post -Uri "$($script:SupabaseUrl)/functions/v1/enroll-device" -Headers $headers -Body $body -TimeoutSec 15 -ErrorAction Stop
    } catch {
        $status = Get-BridgeHttpStatus $_
        if ($status -in @(400, 401, 403, 409)) {
            # Token invalido, esgotado, revogado ou maquina ja cadastrada: nao insiste.
            $data = [ordered]@{}
            foreach ($prop in $inst.PSObject.Properties) { if ($prop.Name -ne "enrollment_token") { $data[$prop.Name] = $prop.Value } }
            $data["enrollment_error"] = "HTTP $status em $([DateTime]::UtcNow.ToString('o'))"
            try { Save-BridgeJsonAtomic -Path $installationFile -Data $data } catch {}
            Write-BridgeLog "Cadastro na nuvem recusado (HTTP $status). Gere um novo pacote do polo com token de cadastro." "WARN"
        }
        return
    }
    if (-not $resp -or -not $resp.access_token) { return }

    $session = [ordered]@{
        access_token = [string]$resp.access_token
        refresh_token = [string]$resp.refresh_token
        expires_at = $resp.expires_at
        installation_id = [string]$inst.installation_id
        site_id = [string]$inst.site_id
        user_id = [string]$resp.user_id
        enrolled_at = [DateTime]::UtcNow.ToString("o")
    }
    try {
        Save-BridgeDeviceSession $session
    } catch {
        Write-BridgeLog "Cadastro concluido, mas a sessao do dispositivo nao foi salva: $($_.Exception.Message)" "WARN"
    }
    $script:DeviceSession = [pscustomobject]$session
    $script:SupabaseOperationalJwt = $session.access_token
    $script:InstallationId = $session.installation_id
    $script:SiteId = $session.site_id

    $data = [ordered]@{}
    foreach ($prop in $inst.PSObject.Properties) { if ($prop.Name -notin @("enrollment_token", "enrollment_error")) { $data[$prop.Name] = $prop.Value } }
    $data["enrolled_at"] = $session.enrolled_at
    try { Save-BridgeJsonAtomic -Path $installationFile -Data $data } catch {}
    Write-BridgeLog "Maquina cadastrada na nuvem (polo $($session.site_id))." "INFO"
}

# Renova o token de acesso (validade de 1 hora) com o refresh token do cadastro.
function Update-BridgeDeviceToken([switch]$Force) {
    $sess = $script:DeviceSession
    if (-not $sess -or -not $sess.refresh_token) { return [bool]$script:SupabaseOperationalJwt }
    $expiresAt = 0L
    [void][long]::TryParse([string]$sess.expires_at, [ref]$expiresAt)
    $nowEpoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    if (-not $Force -and $expiresAt -gt 0 -and ($expiresAt - $nowEpoch) -gt 300) { return $true }

    $resp = $null
    try {
        $resp = Invoke-RestMethod -Method Post -Uri "$($script:SupabaseUrl)/auth/v1/token?grant_type=refresh_token" -Headers @{ apikey = $script:SupabaseAnonKey; "Content-Type" = "application/json" } -Body (@{ refresh_token = [string]$sess.refresh_token } | ConvertTo-Json -Compress) -TimeoutSec 10 -ErrorAction Stop
    } catch {
        $status = Get-BridgeHttpStatus $_
        if ($status -in @(400, 401, 403)) {
            Write-BridgeLog "Refresh token recusado (HTTP $status). Envio a nuvem suspenso ate novo cadastro da maquina." "WARN"
            $script:SupabaseOperationalJwt = ""
            $script:DeviceSession = $null
        }
        return $false
    }
    if (-not $resp -or -not $resp.access_token) { return $false }

    $newExpires = if ($resp.expires_at) { $resp.expires_at } elseif ($resp.expires_in) { $nowEpoch + [int]$resp.expires_in } else { $nowEpoch + 3600 }
    $updated = [ordered]@{}
    foreach ($prop in $sess.PSObject.Properties) { $updated[$prop.Name] = $prop.Value }
    $updated["access_token"] = [string]$resp.access_token
    if ($resp.refresh_token) { $updated["refresh_token"] = [string]$resp.refresh_token }
    $updated["expires_at"] = $newExpires
    try { Save-BridgeDeviceSession $updated } catch {}
    $script:DeviceSession = [pscustomobject]$updated
    $script:SupabaseOperationalJwt = [string]$resp.access_token
    return $true
}

function Set-BridgeSyncError([int]$StatusCode, [string]$Kind) {
    $script:LastSyncError = [ordered]@{ status_code = $StatusCode; kind = $Kind; at = ConvertTo-BridgeIso ([DateTime]::UtcNow) }
}

function Start-BridgeSyncBackoff([int]$StatusCode) {
    $script:SyncBackoffSeconds = if ($script:SyncBackoffSeconds -le 0) { [Math]::Min(60, $script:SyncBackoffMaxSeconds) } else { [Math]::Min($script:SyncBackoffSeconds * 2, $script:SyncBackoffMaxSeconds) }
    $script:SyncBackoffUntil = [DateTime]::UtcNow.AddSeconds($script:SyncBackoffSeconds)
    Set-BridgeSyncError $StatusCode "nuvem"
    Write-BridgeLog "Envio pausado por $($script:SyncBackoffSeconds) s: a nuvem respondeu HTTP $StatusCode. Os dados continuam pendentes." "WARN"
}

function Reset-BridgeSyncBackoff {
    $script:SyncBackoffSeconds = 0
    $script:SyncBackoffUntil = [DateTime]::MinValue
}

function Test-BridgeSyncPaused { return ([DateTime]::UtcNow -lt $script:SyncBackoffUntil) }

# A quarentena nao e definitiva: uma vez por dia e a cada nova versao do bridge, eventos e sessoes
# recusados voltam para a fila. Uma correcao na nuvem ou no bridge recupera os dados sozinha.
function Invoke-BridgeQuarantineRetry {
    if ($script:QuarantinedEventIds.Count -eq 0 -and $script:QuarantinedSessionIds.Count -eq 0) { return }
    $last = $null
    try {
        if (Test-Path -LiteralPath $script:QuarantineRetryFile) { $last = Get-Content -LiteralPath $script:QuarantineRetryFile -Raw -Encoding UTF8 | ConvertFrom-Json }
    } catch { $last = $null }
    $lastAt = [DateTime]::MinValue
    if ($last -and $last.retried_at) {
        try { $lastAt = [DateTime]::Parse([string]$last.retried_at, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal) } catch {}
    }
    $versionChanged = (-not $last) -or ([string]$last.bridge_version -ne $script:BridgeVersion)
    if (-not $versionChanged -and ([DateTime]::UtcNow - $lastAt).TotalSeconds -lt $script:QuarantineRetrySeconds) { return }

    $eventCount = $script:QuarantinedEventIds.Count
    $sessionCount = $script:QuarantinedSessionIds.Count
    foreach ($id in $script:QuarantinedEventIds) { [void]$script:QuarantineReleasedIds.Add($id) }
    foreach ($id in $script:QuarantinedSessionIds) { [void]$script:QuarantineReleasedIds.Add($id) }
    $script:QuarantinedEventIds.Clear()
    $script:QuarantinedSessionIds.Clear()
    try {
        Save-BridgeTextAtomic -Path $script:QuarantinedTrackerFile -Text ""
        Save-BridgeTextAtomic -Path $script:QuarantinedSessionsTrackerFile -Text ""
        Save-BridgeTextAtomic -Path $script:QuarantineRetryFile -Text (([ordered]@{ retried_at = ConvertTo-BridgeIso ([DateTime]::UtcNow); bridge_version = $script:BridgeVersion }) | ConvertTo-Json -Compress)
    } catch { Write-BridgeLog "Aviso ao devolver a quarentena para a fila: $($_.Exception.Message)" "WARN" }
    Write-BridgeLog "Quarentena devolvida para a fila: $eventCount evento(s) e $sessionCount sessao(oes)." "INFO"
}

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
    if (-not (Update-BridgeDeviceToken)) { return }

    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls11 -bor [System.Net.SecurityProtocolType]::Tls
    } catch {}

    try {
        $lines = [System.IO.File]::ReadAllLines($eventsFile)
        $syncedCount = 0
        $networkAttempts = 0
        foreach ($line in $lines) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            # Linha corrompida nao trava a fila: pula (Repair-BridgeEventsFile a separa na inicializacao).
            $ev = $null
            try { $ev = $line | ConvertFrom-Json -ErrorAction Stop } catch { $ev = $null }
            if (-not $ev -or -not $ev.event_id) { continue }
            # Limite por ciclo: com a rede ruim, o envio nao segura o atendimento local por muito tempo.
            if ($networkAttempts -ge 50) { break }
            try {
                $eventId = [string]$ev.event_id
                $eventSessionId = [string]$ev.session_id
                if (-not $eventId -or $script:SyncedEventIds.Contains($eventId) -or $script:QuarantinedEventIds.Contains($eventId) -or $script:WithdrawnSessionIds.Contains($eventSessionId)) {
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

                $uri = "$($script:SupabaseUrl)/rest/v1/$($targetTable)?on_conflict=event_id"
                $networkAttempts++
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

                if ($statusCode -eq 401) {
                    # Token expirado ou invalido: renova e tenta de novo no proximo ciclo, sem quarentena.
                    [void](Update-BridgeDeviceToken -Force)
                    break
                }

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

                # Problema da nuvem, nao do evento: fica pendente e o envio pausa.
                if ($script:SyncRetryStatusCodes -contains $statusCode) {
                    Start-BridgeSyncBackoff $statusCode
                    break
                }

                # Falha 10: Erros 4xx não idempotentes (incluindo 409 por check constraint/FK, 400, 422, etc):
                # quarentena observável em arquivo; Invoke-BridgeQuarantineRetry devolve à fila uma vez por dia.
                if ($statusCode -ge 400 -and $statusCode -lt 500) {
                    try {
                        if (-not $script:QuarantineReleasedIds.Contains($eventId)) {
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
                        }
                        [void]$script:QuarantinedEventIds.Add($eventId)
                        [System.IO.File]::AppendAllText($script:QuarantinedTrackerFile, "$eventId`r`n", [System.Text.Encoding]::UTF8)
                        Set-BridgeSyncError $statusCode "evento_recusado"
                        Write-BridgeLog "[QUARENTENA] Evento $eventId rejeitado com HTTP $statusCode (salvo em events_quarantine.jsonl): $errBody" "WARN"
                    } catch {}
                    continue
                }

                # Offline (sem resposta) ou erro 5xx de servidor: interrompe para retentar na próxima janela
                break
            }
        }
        if ($syncedCount -gt 0) {
            Reset-BridgeSyncBackoff
            $script:LastSyncOkAt = ConvertTo-BridgeIso ([DateTime]::UtcNow)
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
                    # Arquivo temporario + troca: uma queda no meio nao perde eventos pendentes.
                    $unsyncedText = if ($unsynced.Count -gt 0) { ($unsynced -join "`r`n") + "`r`n" } else { "" }
                    Save-BridgeTextAtomic -Path $eventsFile -Text $unsyncedText
                    Write-BridgeLog "Compactada fila local: $($archived.Count) evento(s) arquivados com sucesso." "INFO"
                }
            } catch {}
        }
    } catch {}
}

function Sync-SessionSnapshotsToSupabase {
    if (-not $script:SupabaseOperationalJwt) { return }
    if (-not (Update-BridgeDeviceToken)) { return }

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
            if ($script:SyncedSessionIds.Contains($sid) -or $script:QuarantinedSessionIds.Contains($sid) -or $script:WithdrawnSessionIds.Contains($sid)) {
                continue
            }
            # A marca do registro local vale mesmo se o snapshot nao chegou a ser regravado com ela.
            if ($script:UnauthorizedSessions.ContainsKey($sid) -and $sdata.authorization_status -ne "nao_autorizada") {
                $sdata | Add-Member -NotePropertyName authorization_status -NotePropertyValue "nao_autorizada" -Force
                $sdata | Add-Member -NotePropertyName marked_at -NotePropertyValue $script:UnauthorizedSessions[$sid] -Force
            }
            # Snapshots sao so de insercao para o dispositivo: envia uma vez, com a turma encerrada
            # ou abandonada ha mais de 12 horas, para nao congelar o estado inicial.
            $isClosed = ($sdata.status -eq "completed")
            $isStale = (([DateTime]::UtcNow - $sfile.LastWriteTimeUtc).TotalHours -ge 12)
            if (-not $isClosed -and -not $isStale) { continue }

            $instId = if ($sdata.installation_id) { [string]$sdata.installation_id } else { $script:InstallationId }
            $siteVal = if ($sdata.site_id) { [string]$sdata.site_id } else { $script:SiteId }
            # Sem identidade da maquina ou da bancada a sessao fica so no computador: nada de valores inventados.
            if (-not $instId -or -not $siteVal -or -not $sdata.group_id) { continue }

            $sessRecord = [System.Collections.Specialized.OrderedDictionary]::new()
            $sessRecord["session_id"] = $sid
            $sessRecord["group_id"] = [string]$sdata.group_id
            $sessRecord["installation_id"] = $instId
            $sessRecord["site_id"] = $siteVal
            # Sem valor informado, registra "nao_informado" em vez de um codigo generico que pareca real.
            $sessRecord["school_code"] = if ($sdata.school_code) { [string]$sdata.school_code } else { "nao_informado" }
            $sessRecord["workshop_code"] = if ($sdata.workshop_code) { [string]$sdata.workshop_code } else { "nao_informado" }
            $sessRecord["class_code"] = if ($sdata.class_code) { [string]$sdata.class_code } else { "nao_informado" }
            $sessRecord["environment"] = if ($sdata.is_synthetic) { "test" } else { "production" }
            # Proveniencia vem do snapshot da PWA; versao do software nao substitui versao do protocolo.
            $sessRecord["protocol_version"] = if ($sdata.protocol_version) { [string]$sdata.protocol_version } else { $null }
            $sessRecord["instrument_version"] = if ($sdata.instrument_version) { [string]$sdata.instrument_version } else { $null }
            $sessRecord["group_size"] = if ($sdata.group_size) { [int]$sdata.group_size } else { 2 }
            $sessRecord["phase"] = if ($sdata.phase) { [string]$sdata.phase } elseif ($sdata.status -eq "completed") { "completed" } else { "in_progress" }
            $sessRecord["ended_by"] = if ($sdata.ended_by) { [string]$sdata.ended_by } else { $null }
            $sessRecord["interrupted"] = if ($null -ne $sdata.interrupted) { [bool]$sdata.interrupted } else { $null }
            $sessRecord["data_quality"] = if ($sdata.data_quality) { $sdata.data_quality } else { $null }
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

            if ($statusCode -eq 401) {
                [void](Update-BridgeDeviceToken -Force)
                break
            }

            if ($statusCode -eq 409) {
                $errLower = "$errBody".ToLower()
                if ($errLower -match "23505" -or $errLower -match "duplicate key" -or $errLower -match "research_bancada_sessions_pkey" -or $errLower -match "already exists") {
                    [void]$script:SyncedSessionIds.Add($sid)
                    [System.IO.File]::AppendAllText($script:SyncedSessionsTrackerFile, "$sid`r`n", [System.Text.Encoding]::UTF8)
                    $syncedSessCount++
                    continue
                }
            }

            if ($script:SyncRetryStatusCodes -contains $statusCode) {
                Start-BridgeSyncBackoff $statusCode
                break
            }

            if ($statusCode -ge 400 -and $statusCode -lt 500) {
                try {
                    if (-not $script:QuarantineReleasedIds.Contains($sid)) {
                        $quarantineFile = Join-Path $DataDir "sessions_quarantine.jsonl"
                        $qObj = [PSCustomObject]@{
                            session_id = $sid
                            status_code = $statusCode
                            error = $errBody
                            quarantined_at = [DateTime]::UtcNow.ToString("o")
                        }
                        $qJson = $qObj | ConvertTo-Json -Compress -Depth 5
                        [System.IO.File]::AppendAllText($quarantineFile, "$qJson`r`n", [System.Text.Encoding]::UTF8)
                    }
                    [void]$script:QuarantinedSessionIds.Add($sid)
                    [System.IO.File]::AppendAllText($script:QuarantinedSessionsTrackerFile, "$sid`r`n", [System.Text.Encoding]::UTF8)
                    Set-BridgeSyncError $statusCode "sessao_recusada"
                    Write-BridgeLog "[QUARENTENA] Sessao $sid rejeitada com HTTP ${statusCode}: $errBody" "WARN"
                } catch {}
                continue
            }

            break
        }
    }

    if ($syncedSessCount -gt 0) {
        Reset-BridgeSyncBackoff
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
            # Replace troca o arquivo numa unica operacao do sistema de arquivos (ReplaceFile no NTFS).
            # Move-Item -Force apagava o destino antes de mover: uma queda nesse intervalo perdia o arquivo.
            $backupPath = "$DestinationPath.bak"
            [System.IO.File]::Replace($SourcePath, $DestinationPath, $backupPath, $true)
            try { [System.IO.File]::Delete($backupPath) } catch {}
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

# Prazo de retencao local: retention_days do provisionamento do polo (1 a 365) ou 180 dias.
function Get-BridgeRetentionDays {
    $installationFile = Join-Path $DataDir "installation.json"
    if (Test-Path -LiteralPath $installationFile) {
        try {
            $inst = Get-Content -LiteralPath $installationFile -Raw -Encoding UTF8 | ConvertFrom-Json
            $days = 0
            if ($null -ne $inst.retention_days -and [int]::TryParse([string]$inst.retention_days, [ref]$days) -and $days -ge 1 -and $days -le 365) {
                return $days
            }
        } catch {}
    }
    return 180
}

# Aula que ainda nao saiu do computador (nem para a nuvem nem por pendrive) fica guardada alem de
# retention_days, ate o prazo de guarda da pesquisa (31/12/2032, o mesmo de research_archive_deadline).
# Assim nenhum dado se perde por falta de internet ou de exportacao; o TCLE declara isso.
$script:ArchiveDeleteAfterUtc = [DateTime]::new(2033, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)
$script:PendriveExportFile = Join-Path $DataDir "ultima_exportacao_pendrive.json"
$script:RetentionKeptSessions = 0

# Aulas com algum evento em events.jsonl que ainda nao subiu (pendente ou em quarentena).
function Get-BridgeUnsentSessionIds {
    $unsent = [System.Collections.Generic.HashSet[string]]::new()
    $eventsFile = Join-Path $DataDir "events.jsonl"
    if (-not (Test-Path -LiteralPath $eventsFile)) { return ,$unsent }
    try {
        foreach ($line in [System.IO.File]::ReadAllLines($eventsFile)) {
            if ($line -match '"event_id":"([^"]+)"' -and -not $script:SyncedEventIds.Contains($Matches[1]) -and $line -match '"session_id":"([^"]+)"') {
                [void]$unsent.Add($Matches[1])
            }
        }
    } catch {}
    return ,$unsent
}

# Inicio da ultima exportacao para pendrive (gravado por exportar-pendrive.ps1), ou $null.
function Get-BridgeLastPendriveExportUtc {
    try {
        if (Test-Path -LiteralPath $script:PendriveExportFile) {
            $mark = Get-Content -LiteralPath $script:PendriveExportFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($mark.exported_at) {
                return [DateTime]::Parse([string]$mark.exported_at, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal)
            }
        }
    } catch {}
    return $null
}

function Test-BridgeSessionLeftMachine {
    param([string]$SessionId, $Unsent, $ExportedAtUtc)
    if ($script:WithdrawnSessionIds.Contains($SessionId)) { return $true }
    if ($script:SyncedSessionIds.Contains($SessionId) -and -not $Unsent.Contains($SessionId)) { return $true }
    if ($ExportedAtUtc) {
        $safeSid = ($SessionId -replace '[^a-zA-Z0-9_-]', '_')
        $sessPath = Join-Path (Join-Path $DataDir "sessoes") "sessao_$safeSid.json"
        if ((Test-Path -LiteralPath $sessPath) -and (Get-Item -LiteralPath $sessPath).LastWriteTimeUtc -le $ExportedAtUtc) { return $true }
    }
    return $false
}

function Invoke-BridgeRetentionCleanup {
    [CmdletBinding()]
    param([int]$MaxAgeDays = 180)

    $cutoffUtc = [DateTime]::UtcNow.AddDays(-$MaxAgeDays)
    $expiredSessionIds = [System.Collections.Generic.HashSet[string]]::new()
    $keptSessionIds = [System.Collections.Generic.HashSet[string]]::new()
    # Depois do prazo de guarda da pesquisa, tudo e apagado, inclusive o que nao saiu.
    $deadlinePassed = [DateTime]::UtcNow -ge $script:ArchiveDeleteAfterUtc
    if ($deadlinePassed) { $cutoffUtc = [DateTime]::UtcNow.AddMinutes(1) }
    $unsent = Get-BridgeUnsentSessionIds
    $exportedAtUtc = Get-BridgeLastPendriveExportUtc

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

                # Prazo absoluto: retention_days desde a criacao, sem extensao por retomada; so para aula que ja saiu
                if ($createdUtc -lt $cutoffUtc) {
                    $sid = if ($sessJson.session_id) { $sessJson.session_id } else { $sf.BaseName -replace '^sessao_', '' }
                    if ($sid) {
                        if ($deadlinePassed -or (Test-BridgeSessionLeftMachine -SessionId ([string]$sid) -Unsent $unsent -ExportedAtUtc $exportedAtUtc)) {
                            [void]$expiredSessionIds.Add([string]$sid)
                        } else {
                            [void]$keptSessionIds.Add([string]$sid)
                        }
                    }
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
                                if ($deadlinePassed -or (Test-BridgeSessionLeftMachine -SessionId ([string]$it.session_id) -Unsent $unsent -ExportedAtUtc $exportedAtUtc)) {
                                    [void]$expiredSessionIds.Add([string]$it.session_id)
                                } else {
                                    [void]$keptSessionIds.Add([string]$it.session_id)
                                }
                            }
                        } catch {}
                    }
                }
            }
        } catch {}
    }

    # 2.1 A turma em andamento existe em active_session.json.
    # A retomada nunca estende o prazo absoluto contado desde started_at/created_at.
    if (Test-Path -LiteralPath $script:SessionStateFile) {
        try {
            $activeSchedule = Get-Content -LiteralPath $script:SessionStateFile -Raw -Encoding UTF8 | ConvertFrom-Json
            $activeSid = [string]$activeSchedule.session_id
            $activeCreatedStr = if ($activeSchedule.created_at) { $activeSchedule.created_at } elseif ($activeSchedule.started_at) { $activeSchedule.started_at } elseif ($activeSchedule.startedAt) { $activeSchedule.startedAt } else { $null }
            if ($activeSid -and $activeCreatedStr) {
                $activeCreatedUtc = if ($activeCreatedStr -match '^\d+$') { [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$activeCreatedStr).UtcDateTime } else { [DateTime]::Parse($activeCreatedStr, $null, [System.Globalization.DateTimeStyles]::AdjustToUniversal) }
                if ($activeCreatedUtc -lt $cutoffUtc -and ($deadlinePassed -or (Test-BridgeSessionLeftMachine -SessionId $activeSid -Unsent $unsent -ExportedAtUtc $exportedAtUtc))) {
                    [void]$expiredSessionIds.Add($activeSid)
                    Remove-Item -LiteralPath $script:SessionStateFile -Force -ErrorAction SilentlyContinue
                    if ($script:ActiveSession -and [string]$script:ActiveSession.session_id -eq $activeSid) {
                        $script:ActiveSession = $null
                        $script:SessionTimeline = [System.Collections.Generic.List[object]]::new()
                    }
                }
            }
        } catch {
            Write-BridgeLog "Aviso ao avaliar agenda ativa na retencao: $($_.Exception.Message)" "WARN"
        }
    }

    $keptSessionIds.ExceptWith($expiredSessionIds)
    if ($keptSessionIds.Count -ne $script:RetentionKeptSessions -and $keptSessionIds.Count -gt 0) {
        Write-BridgeLog "Retencao: $($keptSessionIds.Count) aula(s) passaram do prazo local mas ainda nao sairam do computador (nuvem ou pendrive); ficam guardadas." "WARN"
    }
    $script:RetentionKeptSessions = $keptSessionIds.Count

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

    Write-BridgeLog "Limpeza de retencao concluida: $($expiredSessionIds.Count) sessao(oes) expirada(s) e $purgedEventsCount evento(s) expurgados (limite $MaxAgeDays dias)." "INFO"
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

# ------------------------------------------------------------------------------
# Sessao da turma (v2.4.0): o bridge e o dono da sessao. Nenhuma pagina fica aberta
# durante a aula. A sessao abre quando o PulseLab inicia (ou, depois de uma turma
# encerrada, no primeiro programa SPIKE salvo), registra o programa e um sinal de vida
# a cada 5 minutos e fecha pelo formulario final (Encerrar turma na bandeja), depois de
# 3 horas, ou quando o computador ficou desligado/suspenso por mais de 20 minutos.
# ------------------------------------------------------------------------------

# Proveniencia do instrumento: mesmos valores de apps/student-pwa/lib/contracts.js (teste garante).
$script:ProtocolVersion = "protocolo-oficinas-rotativas-v2"
$script:InstrumentVersion = "bancada-3.2.0"
$script:InstrumentConfigHash = "3e1e3423a7468044ec6bbcc28db81959f0fa3f1a5ee1c7bff97e7e54ef482ba3"

# Questionario do fim da aula (aba do navegador em /alunos/): item_id e codigos aceitos, os mesmos de
# questionario_fim_aula em apps/student-pwa/lib/contracts.js (teste garante). Sem nome, idade ou texto livre.
$script:QuestionarioRecusa = "recusou"
$script:QuestionarioBancadaItems = [ordered]@{
    "bancada_linha_v1" = @("sim", "em_parte", "nao")
    "bancada_corrida_v1" = @("ganhamos", "terminamos_sem_ganhar", "nao_terminamos", "nao_participamos")
    "bancada_quiz_v1" = @("quase_todas", "metade", "poucas", "sem_quiz")
}
$script:QuestionarioCriancaItems = [ordered]@{
    "crianca_gostou_v1" = @("sim", "mais_ou_menos", "nao")
    "crianca_outra_aula_v1" = @("sim", "mais_ou_menos", "nao")
    "crianca_confianca_antes_v1" = @("sim", "mais_ou_menos", "nao")
    "crianca_confianca_agora_v1" = @("sim", "mais_ou_menos", "nao")
    "crianca_ajudou_v1" = @("sim", "mais_ou_menos", "nao")
}

function Get-BridgeIntSetting([string]$EnvName, [int]$Default, [int]$Min, [int]$Max) {
    $raw = [Environment]::GetEnvironmentVariable($EnvName)
    $parsed = 0
    if ($raw -and [int]::TryParse($raw, [ref]$parsed) -and $parsed -ge $Min -and $parsed -le $Max) { return $parsed }
    return $Default
}

# Variaveis de ambiente existem so para os testes automatizados encurtarem os prazos.
$script:SessionMaxMinutes = Get-BridgeIntSetting "PULSELAB_SESSION_MAX_MINUTES" 180 1 720
$script:SessionIdleMinutes = Get-BridgeIntSetting "PULSELAB_SESSION_IDLE_MINUTES" 40 1 720
$script:ResumeGapMinutes = Get-BridgeIntSetting "PULSELAB_RESUME_GAP_MINUTES" 20 1 240
$script:HeartbeatSeconds = Get-BridgeIntSetting "PULSELAB_HEARTBEAT_SECONDS" 300 1 3600
$script:SpikePollSeconds = Get-BridgeIntSetting "PULSELAB_SPIKE_POLL_SECONDS" 15 1 600
$script:SyncBackoffMaxSeconds = Get-BridgeIntSetting "PULSELAB_SYNC_BACKOFF_MAX_SECONDS" 3600 1 86400
$script:QuarantineRetrySeconds = Get-BridgeIntSetting "PULSELAB_QUARANTINE_RETRY_SECONDS" 86400 1 2592000

# Respostas da nuvem que dependem dela, nao do evento (maquina desativada ou de outro polo, rota
# ausente, tempo esgotado, limite de requisicoes): os dados ficam pendentes e o envio pausa com
# espera crescente ate SyncBackoffMaxSeconds. Nunca vao para a quarentena.
$script:SyncRetryStatusCodes = @(403, 404, 408, 429)
$script:SyncBackoffSeconds = 0
$script:SyncBackoffUntil = [DateTime]::MinValue
$script:LastSyncError = $null
$script:QuarantineRetryFile = Join-Path $DataDir "quarantine_retry.json"
# Ids devolvidos a fila por Invoke-BridgeQuarantineRetry: se voltarem a ser recusados, nao se repetem no log.
$script:QuarantineReleasedIds = [System.Collections.Generic.HashSet[string]]::new()

$script:SessionStateFile = Join-Path $DataDir "active_session.json"
# Ultima turma encerrada; apagado quando outra turma comeca (alvo de "Nao registrar esta turma").
$script:LastClosedFile = Join-Path $DataDir "last_closed_session.json"
$script:PauseFile = Join-Path $DataDir "collection_pause.json"
$script:ActiveSession = $null
$script:SessionTimeline = [System.Collections.Generic.List[object]]::new()
$script:CollectionPause = $null
$script:AwaitingActivity = $false
$script:PendingBaseline = $null
$script:LastClosedAtUtc = [DateTime]::UtcNow
$script:LastSessionTick = [DateTime]::UtcNow
$script:LastHeartbeat = [DateTime]::UtcNow
$script:LastSpikePoll = [DateTime]::MinValue
$script:CorruptedLinesFound = 0
$script:LastSyncOkAt = $null
$script:SpikeEnvironmentCache = $null
$script:SpikeEnvironmentCheckedAt = [DateTime]::MinValue
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Get-BridgeNowMs { return [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() }

function ConvertFrom-BridgeMs([int64]$Ms) { return [DateTimeOffset]::FromUnixTimeMilliseconds($Ms).UtcDateTime }

function ConvertTo-BridgeIso([DateTime]$Utc) { return $Utc.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ") }

# Escrita com WriteThrough: o dado chega ao disco antes de seguir (queda de energia ao fim da aula).
function Write-BridgeFileDurable([string]$Path, [string]$Text) {
    $bytes = $script:Utf8NoBom.GetBytes($Text)
    $fs = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None, 4096, [System.IO.FileOptions]::WriteThrough)
    try {
        $fs.Write($bytes, 0, $bytes.Length)
        $fs.Flush($true)
    } finally {
        $fs.Dispose()
    }
}

function Save-BridgeTextAtomic([string]$Path, [string]$Text) {
    $tmp = "$Path.tmp.$([System.Guid]::NewGuid().ToString('N'))"
    Write-BridgeFileDurable -Path $tmp -Text $Text
    Move-BridgeAtomicFile -SourcePath $tmp -DestinationPath $Path
}

function Add-BridgeEventLine([string]$Json) {
    $eventsFile = Join-Path $DataDir "events.jsonl"
    $bytes = $script:Utf8NoBom.GetBytes("$Json`r`n")
    $fs = New-Object System.IO.FileStream($eventsFile, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read, 4096, [System.IO.FileOptions]::WriteThrough)
    try {
        $fs.Write($bytes, 0, $bytes.Length)
        $fs.Flush($true)
    } finally {
        $fs.Dispose()
    }
}

# Linha cortada por desligamento brusco: vai para events_corrupted.jsonl e a fila segue.
# Se um evento inteiro ficou colado depois do pedaco cortado, ele e recuperado.
function Repair-BridgeEventsFile {
    $eventsFile = Join-Path $DataDir "events.jsonl"
    if (-not (Test-Path -LiteralPath $eventsFile)) { return 0 }
    $raw = ""
    try { $raw = [System.IO.File]::ReadAllText($eventsFile, [System.Text.Encoding]::UTF8) } catch { return 0 }
    $good = [System.Collections.Generic.List[string]]::new()
    $bad = [System.Collections.Generic.List[string]]::new()
    foreach ($line in ($raw -split "`r?`n")) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parsed = $null
        try { $parsed = $line | ConvertFrom-Json -ErrorAction Stop } catch { $parsed = $null }
        if ($parsed -and $parsed.event_id) {
            $good.Add($line)
            continue
        }
        $bad.Add($line)
        $idx = $line.IndexOf('{"', 1)
        while ($idx -gt 0) {
            $tail = $line.Substring($idx)
            $salvaged = $null
            try { $salvaged = $tail | ConvertFrom-Json -ErrorAction Stop } catch { $salvaged = $null }
            if ($salvaged -and $salvaged.event_id) {
                $good.Add($tail)
                break
            }
            $idx = $line.IndexOf('{"', $idx + 1)
        }
    }
    $endsClean = ($raw.Length -eq 0) -or $raw.EndsWith("`n")
    if ($bad.Count -eq 0 -and $endsClean) { return 0 }
    if ($bad.Count -gt 0) {
        $foundAt = ConvertTo-BridgeIso ([DateTime]::UtcNow)
        $records = foreach ($b in $bad) { ([ordered]@{ found_at = $foundAt; line = $b } | ConvertTo-Json -Compress) }
        [System.IO.File]::AppendAllText((Join-Path $DataDir "events_corrupted.jsonl"), (($records -join "`r`n") + "`r`n"), $script:Utf8NoBom)
        Write-BridgeLog "$($bad.Count) linha(s) corrompida(s) em events.jsonl separada(s) em events_corrupted.jsonl; a fila de envio segue." "WARN"
    }
    $text = if ($good.Count -gt 0) { ($good -join "`r`n") + "`r`n" } else { "" }
    Save-BridgeTextAtomic -Path $eventsFile -Text $text
    return $bad.Count
}

function ConvertTo-BridgeContextValue([object]$Value) {
    $text = if ($null -ne $Value) { ([string]$Value).Trim() } else { "" }
    if (-not $text -or $text.StartsWith("CONFIGURE_")) { return "nao_informado" }
    return $text
}

function Read-BridgeInstallation {
    $installationFile = Join-Path $DataDir "installation.json"
    if (-not (Test-Path -LiteralPath $installationFile)) { return $null }
    try { return (Get-Content -LiteralPath $installationFile -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}

function Read-BridgePackageConfig {
    if (-not (Test-Path -LiteralPath $candidateConfig)) { return $null }
    try { return (Get-Content -LiteralPath $candidateConfig -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}

# Missao do dia: catalogo config\missoes.json do pacote + calendario_missoes do provisionamento do polo.
function Get-BridgeMissionForToday($Installation) {
    if (-not (Get-Command Resolve-SpikeMission -ErrorAction SilentlyContinue)) { return $null }
    if (-not $Installation -or -not $Installation.calendario_missoes) { return $null }
    $catalogFile = Join-Path (Split-Path -Path $candidateConfig -Parent) "missoes.json"
    if (-not (Test-Path -LiteralPath $catalogFile)) { return $null }
    try {
        $catalog = Get-Content -LiteralPath $catalogFile -Raw -Encoding UTF8 | ConvertFrom-Json
        return (Resolve-SpikeMission -Catalog $catalog -Calendar @($Installation.calendario_missoes) -Date (Get-Date))
    } catch {
        return $null
    }
}

# Mesmos criterios fail-closed do PWA (isResearchAuthorized): sem provisionamento valido, nada e registrado.
function Get-BridgeResearchContext {
    $inst = Read-BridgeInstallation
    if (-not $inst) { return $null }
    if (-not ($inst.research_collection_enabled -is [bool]) -or -not $inst.research_collection_enabled) { return $null }
    $authVersion = if ($inst.research_authorization_version) { ([string]$inst.research_authorization_version).Trim() } else { "" }
    # CAAE no formato oficial e diferente do numero de exemplo da documentacao.
    if ($authVersion -notmatch '^\d{8}\.\d\.\d{4}\.\d{4}$' -or $authVersion -eq "12345678.9.0000.1234") { return $null }
    if (@($inst.research_authorized_purposes) -notcontains "academic_research") { return $null }

    $cfg = Read-BridgePackageConfig
    $groupSize = 0
    if ($cfg -and $null -ne $cfg.group_size) { [void][int]::TryParse([string]$cfg.group_size, [ref]$groupSize) }
    if ($groupSize -lt 2 -or $groupSize -gt 8) { return $null }

    $installationId = if ($script:InstallationId) { $script:InstallationId } else { [string]$inst.installation_id }
    if ($installationId -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') { return $null }
    $siteRaw = if ($inst.site_id) { $inst.site_id } else { $script:SiteId }
    if (-not $siteRaw) { return $null }

    $context = [ordered]@{
        installation_id = $installationId
        computer_id = if ($inst.machine_label) { [string]$inst.machine_label } else { "PC-" + $installationId.Substring(0, 6).ToUpperInvariant() }
        site_id = ConvertTo-BridgeContextValue $siteRaw
        regional_hub = ConvertTo-BridgeContextValue $(if ($inst.regional_hub) { $inst.regional_hub } elseif ($cfg) { $cfg.regional_hub } else { $null })
        school_code = ConvertTo-BridgeContextValue $(if ($inst.school_code) { $inst.school_code } elseif ($cfg) { $cfg.school_code } else { $null })
        workshop_code = ConvertTo-BridgeContextValue $(if ($cfg) { $cfg.workshop_code } else { $null })
        class_code = ConvertTo-BridgeContextValue $(if ($cfg) { $cfg.class_code } else { $null })
        activity_id = ConvertTo-BridgeContextValue $(if ($cfg) { $cfg.activity_id } else { $null })
        group_size = $groupSize
        research_authorization_version = $authVersion
        mission = $null
    }
    $mission = Get-BridgeMissionForToday $inst
    if ($mission -and $mission.mission_id) {
        $context.mission = $mission
        $context.activity_id = [string]$mission.mission_id
    }
    $missing = @()
    foreach ($field in @("site_id", "regional_hub", "school_code", "workshop_code", "class_code", "activity_id")) {
        if ($context[$field] -eq "nao_informado") { $missing += $field }
    }
    $context.context_missing = $missing
    return $context
}

function Get-BridgeSpikeEnvironment([switch]$Refresh) {
    if (-not (Get-Command Get-SpikeEnvironmentStatus -ErrorAction SilentlyContinue)) {
        return [ordered]@{ status = "leitor_indisponivel"; directories_found = 0; project_count = 0 }
    }
    if ($Refresh -or -not $script:SpikeEnvironmentCache -or ([DateTime]::UtcNow - $script:SpikeEnvironmentCheckedAt).TotalSeconds -ge 60) {
        try { $script:SpikeEnvironmentCache = Get-SpikeEnvironmentStatus } catch { $script:SpikeEnvironmentCache = [ordered]@{ status = "leitor_indisponivel"; directories_found = 0; project_count = 0 } }
        $script:SpikeEnvironmentCheckedAt = [DateTime]::UtcNow
    }
    return $script:SpikeEnvironmentCache
}

# Chave do arquivo so para uso local (o caminho contem o usuario do Windows e nunca e exportado).
function Get-BridgeFileKey([string]$Path) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes("$($script:InstallationId)|$($Path.ToLowerInvariant())")
        return (([System.BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '').Substring(0, 16).ToLowerInvariant())
    } finally {
        $sha.Dispose()
    }
}

function Get-BridgeSpikeFiles([DateTime]$SinceUtc) {
    if (-not (Get-Command Get-SpikeProjectFiles -ErrorAction SilentlyContinue)) { return @() }
    try { return @(Get-SpikeProjectFiles -MinLastWriteTime $SinceUtc) } catch { return @() }
}

# Linha de base: projetos que ja existiam no inicio da turma. Se a turma continuar um deles,
# a telemetria informa quantos blocos ja estavam la (nao conta o trabalho da turma anterior).
function Get-BridgeSpikeBaseline([Nullable[DateTime]]$NotAfterUtc = $null) {
    $baseline = @()
    if (-not (Get-Command Get-SpikeProjectMetrics -ErrorAction SilentlyContinue)) { return $baseline }
    $files = @(Get-BridgeSpikeFiles ([DateTime]::MinValue))
    if ($NotAfterUtc) { $files = @($files | Where-Object { $_.LastWriteTimeUtc -le $NotAfterUtc.Value }) }
    foreach ($file in ($files | Select-Object -First 3)) {
        try {
            $m = Get-SpikeProjectMetrics -ProjectPath $file.FullName
            $baseline += [pscustomobject][ordered]@{
                key = Get-BridgeFileKey $file.FullName
                executable_blocks = [int]$m.executable_blocks
                structure_hash = [string]$m.structure_hash
            }
        } catch {}
    }
    return $baseline
}

function Save-BridgeSessionState {
    if (-not $script:ActiveSession) { return }
    Save-BridgeTextAtomic -Path $script:SessionStateFile -Text ($script:ActiveSession | ConvertTo-Json -Depth 10)
}

function Get-BridgeSessionFile([string]$SessionId) {
    $safeSessId = ($SessionId -replace '[^a-zA-Z0-9_-]', '_')
    return (Join-Path (Join-Path $DataDir "sessoes") "sessao_$safeSessId.json")
}

function New-BridgeSnapshot([string]$Status, [hashtable]$Extra = @{}) {
    $s = $script:ActiveSession
    $snapshot = [ordered]@{
        session_id = $s.session_id
        group_id = $s.group_id
        installation_id = $s.context.installation_id
        computer_id = $s.context.computer_id
        site_id = $s.context.site_id
        regional_hub = $s.context.regional_hub
        school_code = $s.context.school_code
        workshop_code = $s.context.workshop_code
        class_code = $s.context.class_code
        activity_id = $s.context.activity_id
        protocol_version = $script:ProtocolVersion
        instrument_version = $script:InstrumentVersion
        config_hash = $script:InstrumentConfigHash
        client_version = "bridge/$($script:BridgeVersion)"
        start_mode = $s.start_mode
        started_at = $s.started_at
        group_size = $s.context.group_size
        status = $Status
        phase = if ($Status -eq "completed") { "completed" } else { "in_progress" }
        saved_at = ConvertTo-BridgeIso ([DateTime]::UtcNow)
        timeline = @($script:SessionTimeline)
    }
    foreach ($k in $Extra.Keys) { $snapshot[$k] = $Extra[$k] }
    return $snapshot
}

function Save-BridgeSnapshot($Snapshot) {
    $sessoesDir = Join-Path $DataDir "sessoes"
    if (-not (Test-Path -LiteralPath $sessoesDir)) { New-Item -ItemType Directory -Path $sessoesDir -Force | Out-Null }
    Save-BridgeTextAtomic -Path (Get-BridgeSessionFile ([string]$Snapshot.session_id)) -Text ($Snapshot | ConvertTo-Json -Depth 12)
}

function Update-BridgeSessionCatalog($Snapshot) {
    $catFile = Join-Path $DataDir "catalogo_sessoes.json"
    $catalogList = [System.Collections.Generic.List[object]]::new()
    if (Test-Path -LiteralPath $catFile) {
        try {
            foreach ($item in @(Get-Content -LiteralPath $catFile -Raw -Encoding UTF8 | ConvertFrom-Json)) {
                if ($item -and $item.session_id -ne $Snapshot.session_id) { $catalogList.Add($item) }
            }
        } catch {}
    }
    $catalogList.Add([pscustomobject][ordered]@{
        session_id = $Snapshot.session_id
        group_id = $Snapshot.group_id
        school_code = $Snapshot.school_code
        class_code = $Snapshot.class_code
        workshop_code = $Snapshot.workshop_code
        started_at = $Snapshot.started_at
        completed_at = $Snapshot.completed_at
        duration_seconds = $Snapshot.duration_seconds
        status = $Snapshot.status
        ended_by = $Snapshot.ended_by
        interrupted = $Snapshot.interrupted
        events_count = @($Snapshot.timeline).Count
        saved_locally_at = ConvertTo-BridgeIso ([DateTime]::UtcNow)
        file_path = "sessoes/" + [System.IO.Path]::GetFileName((Get-BridgeSessionFile ([string]$Snapshot.session_id)))
    })
    Save-BridgeTextAtomic -Path $catFile -Text (ConvertTo-Json -InputObject $catalogList.ToArray() -Depth 5)
}

function Add-BridgeSessionEvent {
    param(
        [Parameter(Mandatory = $true)][string]$EventType,
        [string]$Stage = "oficina_coletiva",
        $Details = $null,
        [string]$Severity = "info",
        [string]$ParticipantId = $null,
        [string]$ParticipantRole = $null,
        [int64]$OccurredAtMs = 0
    )
    $s = $script:ActiveSession
    if (-not $s) { return $null }
    $s.sequence = [int]$s.sequence + 1
    $event = New-BridgeEventRecord -Session $s -Sequence ([int]$s.sequence) -EventType $EventType -Stage $Stage -Details $Details -Severity $Severity -ParticipantId $ParticipantId -ParticipantRole $ParticipantRole -OccurredAtMs $OccurredAtMs
    Add-BridgeEventLine -Json ($event | ConvertTo-Json -Depth 10 -Compress)
    $script:SessionTimeline.Add([pscustomobject]$event)
    $s.last_alive_ms = [Math]::Max([int64]$s.last_alive_ms, (Get-BridgeNowMs))
    Save-BridgeSessionState
    Save-BridgeSnapshot (New-BridgeSnapshot "in_progress")
    return $event
}

# Evento no formato de research_session_events. $Session tem session_id, group_id, started_at_ms e
# context (installation_id, site_id, ..., group_size): a turma ativa ou uma encerrada lida do snapshot.
function New-BridgeEventRecord {
    param(
        [Parameter(Mandatory = $true)]$Session,
        [int]$Sequence,
        [Parameter(Mandatory = $true)][string]$EventType,
        [string]$Stage = "oficina_coletiva",
        $Details = $null,
        [string]$Severity = "info",
        [string]$ParticipantId = $null,
        [string]$ParticipantRole = $null,
        [int64]$OccurredAtMs = 0
    )
    $s = $Session
    $occurredMs = if ($OccurredAtMs -gt 0) { $OccurredAtMs } else { Get-BridgeNowMs }
    $mergedDetails = [ordered]@{
        runtime = "bridge"
        group_size = $s.context.group_size
        collective_unit = "bancada"
    }
    if ($Details) { foreach ($k in $Details.Keys) { $mergedDetails[$k] = $Details[$k] } }
    $event = [ordered]@{
        event_id = [System.Guid]::NewGuid().ToString()
        session_id = $s.session_id
        dyad_id = $s.group_id
        group_id = $s.group_id
        installation_id = $s.context.installation_id
        site_id = $s.context.site_id
        regional_hub = $s.context.regional_hub
        school_code = $s.context.school_code
        workshop_code = $s.context.workshop_code
        class_code = $s.context.class_code
        activity_id = $s.context.activity_id
        computer_id = $s.context.computer_id
        protocol_version = $script:ProtocolVersion
        config_version = $script:InstrumentVersion
        config_hash = $script:InstrumentConfigHash
        client_version = "bridge/$($script:BridgeVersion)"
        event_type = $EventType
        severity = $Severity
        interval_mark = $null
        participant_id = if ($ParticipantId) { $ParticipantId } else { $null }
        participant_role = if ($ParticipantRole) { $ParticipantRole } else { $null }
        activity_stage = $Stage
        occurred_at = ConvertTo-BridgeIso (ConvertFrom-BridgeMs $occurredMs)
        elapsed_ms = [Math]::Max([int64]0, $occurredMs - [int64]$s.started_at_ms)
        scheduled_at = $null
        details = $mergedDetails
        _target_table = "research_session_events"
        _sequence = $Sequence
    }
    return $event
}

function Start-BridgeSession {
    param(
        [string]$StartMode = "abertura_app",
        [int64]$StartedAtMs = 0,
        [int64]$SpikeSinceMs = 0
    )
    if ($script:ActiveSession) { return $true }
    if (Test-BridgeCollectionPaused) { return $false }
    $ctx = Get-BridgeResearchContext
    if (-not $ctx) { return $false }
    $nowMs = Get-BridgeNowMs
    $startMs = if ($StartedAtMs -gt 0) { $StartedAtMs } else { $nowMs }
    $sinceMs = if ($SpikeSinceMs -gt 0) { $SpikeSinceMs } else { $startMs }
    # Depois de uma turma encerrada, a linha de base foi tirada no encerramento: quando o primeiro
    # programa da nova turma e salvo, o arquivo da turma anterior ja foi sobrescrito.
    $baseline = if ($null -ne $script:PendingBaseline) { @($script:PendingBaseline) } else { @(Get-BridgeSpikeBaseline -NotAfterUtc (ConvertFrom-BridgeMs $sinceMs)) }
    $script:PendingBaseline = $null
    $spikeEnv = Get-BridgeSpikeEnvironment -Refresh

    $script:SessionTimeline = [System.Collections.Generic.List[object]]::new()
    $script:ActiveSession = [pscustomobject][ordered]@{
        session_id = [System.Guid]::NewGuid().ToString()
        group_id = [System.Guid]::NewGuid().ToString()
        start_mode = $StartMode
        started_at = ConvertTo-BridgeIso (ConvertFrom-BridgeMs $startMs)
        started_at_ms = $startMs
        spike_since_ms = $sinceMs
        context = [pscustomobject]$ctx
        sequence = 0
        last_alive_ms = $nowMs
        heartbeat_count = 0
        max_gap_min = 0
        bridge_restarts = 0
        corrupted_lines = 0
        spike_status = [string]$spikeEnv.status
        telemetry_events = 0
        first_program_at = $null
        last_program_ms = 0
        baseline = $baseline
        files = @()
        last_file_key = $null
        last_write_ticks = 0
        last_telemetry_file_key = $null
        last_structure_hash = $null
        last_summary = $null
    }
    Remove-Item -LiteralPath $script:LastClosedFile -Force -ErrorAction SilentlyContinue
    $script:AwaitingActivity = $false
    $script:LastHeartbeat = [DateTime]::UtcNow
    $script:LastSpikePoll = [DateTime]::MinValue

    $missionId = if ($ctx.mission) { [string]$ctx.mission.mission_id } else { $null }
    [void](Add-BridgeSessionEvent -EventType "session_started" -OccurredAtMs $startMs -Details ([ordered]@{
        start_mode = $StartMode
        research_authorization_version = $ctx.research_authorization_version
        context_missing = @($ctx.context_missing)
        instrument_version = $script:InstrumentVersion
        spike_environment = $spikeEnv
        baseline_projects = $baseline.Count
        mission_id = $missionId
        session_max_minutes = $script:SessionMaxMinutes
        session_idle_minutes = $script:SessionIdleMinutes
    }))
    Write-BridgeLog "Turma iniciada nesta bancada ($StartMode)." "INFO"
    return $true
}

function Get-BridgeDataQuality {
    $s = $script:ActiveSession
    return [ordered]@{
        heartbeat_count = [int]$s.heartbeat_count
        max_heartbeat_gap_min = [Math]::Round([double]$s.max_gap_min, 1)
        bridge_restarts = [int]$s.bridge_restarts
        corrupted_lines = [int]$s.corrupted_lines
        spike_status = [string]$s.spike_status
        telemetry_events = [int]$s.telemetry_events
        last_activity_at = ConvertTo-BridgeIso (ConvertFrom-BridgeMs ([int64]$s.last_alive_ms))
    }
}

function Close-BridgeSession {
    param(
        [Parameter(Mandatory = $true)][ValidateSet("instrutor", "tempo", "sem_encerramento", "inatividade")][string]$EndedBy,
        [int64]$EndedAtMs = 0,
        $Experience = $null,
        $Rubric = $null
    )
    $s = $script:ActiveSession
    if (-not $s) { return $null }
    $nowMs = Get-BridgeNowMs
    $endMs = if ($EndedAtMs -gt 0) { [Math]::Max([int64]$s.started_at_ms, $EndedAtMs) } else { $nowMs }

    $assessmentSkipped = $null
    if ($EndedBy -eq "instrutor") {
        if ($Experience -or $Rubric) {
            $value = $null
            $label = $null
            $refused = $true
            if ($Experience -and -not $Experience.refused -and $null -ne $Experience.value) {
                $value = [int]$Experience.value
                $label = [string]$Experience.label
                $refused = $false
            }
            [void](Add-BridgeSessionEvent -EventType "experience_recorded" -Stage "encerramento" -ParticipantId "BANCADA" -ParticipantRole "group" -Details ([ordered]@{
                item_id = "experiencia_bancada_v1"
                instrument_version = $script:InstrumentVersion
                value = $value
                label = $label
                refused = $refused
            }))
            $assessmentSkipped = (-not $Rubric) -or ($Rubric.skipped -eq $true)
            [void](Add-BridgeSessionEvent -EventType "rubric_completed" -Stage "encerramento" -ParticipantId "INSTRUTOR" -ParticipantRole "instructor" -Details ([ordered]@{
                result_item_id = "resultado_bancada_v1"
                support_item_id = "apoio_instrutor_v1"
                instrument_version = $script:InstrumentVersion
                result_level = if ($assessmentSkipped) { $null } else { [int]$Rubric.result_level }
                support_level = if ($assessmentSkipped) { $null } else { [string]$Rubric.support_level }
                skipped = $assessmentSkipped
            }))
        } else {
            # Encerramento silencioso (bandeja ou automatico): sem questionarios no PC do aluno.
            # A avaliacao pedagogica do instrutor e realizada externamente no portal/celular.
            $assessmentSkipped = $true
        }
    }

    # Lacunas de sinal de vida acima de dois intervalos indicam computador desligado ou PulseLab parado.
    $gapLimitMin = 2 * $script:HeartbeatSeconds / 60.0
    $interrupted = ([int]$s.bridge_restarts -gt 0) -or ([double]$s.max_gap_min -gt $gapLimitMin) -or ([int]$s.corrupted_lines -gt 0)
    $quality = Get-BridgeDataQuality
    $durationSeconds = [int][Math]::Round(($endMs - [int64]$s.started_at_ms) / 1000.0)
    $completedDetails = [ordered]@{
        ended_by = $EndedBy
        duration_min = [Math]::Round($durationSeconds / 60.0, 1)
        interrupted = $interrupted
        data_quality = $quality
        recorded_at = ConvertTo-BridgeIso (ConvertFrom-BridgeMs $nowMs)
    }
    if ($null -ne $assessmentSkipped) { $completedDetails.assessment_skipped = $assessmentSkipped }
    [void](Add-BridgeSessionEvent -EventType "session_completed" -Stage "encerramento" -OccurredAtMs $endMs -Details $completedDetails)

    $firstProgramMin = $null
    if ($s.first_program_at) {
        try {
            $firstUtc = [DateTime]::Parse([string]$s.first_program_at, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal)
            $firstProgramMin = [Math]::Round(($firstUtc - (ConvertFrom-BridgeMs ([int64]$s.started_at_ms))).TotalMinutes, 1)
        } catch {}
    }
    $snapshot = New-BridgeSnapshot "completed" @{
        completed_at = ConvertTo-BridgeIso (ConvertFrom-BridgeMs $endMs)
        duration_seconds = $durationSeconds
        ended_by = $EndedBy
        interrupted = $interrupted
        data_quality = $quality
        summary = [ordered]@{
            first_program_at = $s.first_program_at
            first_program_min = $firstProgramMin
            telemetry_events = [int]$s.telemetry_events
            final = $s.last_summary
        }
    }
    Save-BridgeSnapshot $snapshot
    try { Update-BridgeSessionCatalog $snapshot } catch { Write-BridgeLog "Aviso ao atualizar catalogo: $($_.Exception.Message)" "WARN" }
    try {
        Save-BridgeTextAtomic -Path $script:LastClosedFile -Text ([ordered]@{
            session_id = [string]$s.session_id
            started_at_ms = [int64]$s.started_at_ms
            ended_at_ms = [int64]$endMs
        } | ConvertTo-Json)
    } catch { Write-BridgeLog "Aviso ao guardar a ultima turma encerrada: $($_.Exception.Message)" "WARN" }

    Remove-Item -LiteralPath $script:SessionStateFile -Force -ErrorAction SilentlyContinue
    $script:ActiveSession = $null
    $script:SessionTimeline = [System.Collections.Generic.List[object]]::new()
    $script:LastClosedAtUtc = [DateTime]::UtcNow
    $script:AwaitingActivity = $true
    try { $script:PendingBaseline = @(Get-BridgeSpikeBaseline) } catch { $script:PendingBaseline = $null }
    Write-BridgeLog "Turma encerrada ($EndedBy, $([Math]::Round($durationSeconds / 60.0)) min)." "INFO"
    return $snapshot
}

function Restore-BridgeSessionState {
    if (-not (Test-Path -LiteralPath $script:SessionStateFile)) { return $false }
    $state = $null
    try { $state = Get-Content -LiteralPath $script:SessionStateFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $state = $null }
    if (-not $state -or -not $state.session_id -or -not $state.context -or -not $state.started_at_ms) {
        Write-BridgeLog "Estado de turma ilegivel em active_session.json; descartado." "WARN"
        Remove-Item -LiteralPath $script:SessionStateFile -Force -ErrorAction SilentlyContinue
        return $false
    }
    $timeline = [System.Collections.Generic.List[object]]::new()
    $sessFile = Get-BridgeSessionFile ([string]$state.session_id)
    if (Test-Path -LiteralPath $sessFile) {
        try {
            $snap = Get-Content -LiteralPath $sessFile -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($ev in @($snap.timeline)) { if ($ev) { $timeline.Add($ev) } }
        } catch {}
    }
    $script:ActiveSession = $state
    $script:SessionTimeline = $timeline
    return $true
}

function Read-BridgeCollectionPause {
    if (-not (Test-Path -LiteralPath $script:PauseFile)) { return $null }
    try { return (Get-Content -LiteralPath $script:PauseFile -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}

function Clear-BridgeCollectionPause {
    $script:CollectionPause = $null
    Remove-Item -LiteralPath $script:PauseFile -Force -ErrorAction SilentlyContinue
}

function Test-BridgeCollectionPaused {
    $pause = $script:CollectionPause
    if (-not $pause) { return $false }
    if ((Get-BridgeNowMs) -ge [int64]$pause.until_ms) {
        Clear-BridgeCollectionPause
        $script:LastClosedAtUtc = [DateTime]::UtcNow
        $script:AwaitingActivity = $true
        try { $script:PendingBaseline = @(Get-BridgeSpikeBaseline) } catch { $script:PendingBaseline = $null }
        Write-BridgeLog "Pausa do registro encerrada pelo prazo; a proxima turma volta a ser registrada." "INFO"
        return $false
    }
    return $true
}

# Alvo de "Nao registrar esta turma": a turma em andamento ou, sem ela, a ultima turma encerrada,
# desde que nenhuma turma tenha comecado depois (Start-BridgeSession apaga last_closed_session.json).
# Devolve so dados tecnicos da sessao (id interno, inicio e duracao), nunca dados das criancas.
function Get-BridgeMarkTarget {
    $nowMs = Get-BridgeNowMs
    $s = $script:ActiveSession
    $active = [bool]$s
    if ($s) {
        $sid = [string]$s.session_id
        $startMs = [int64]$s.started_at_ms
        $endMs = $nowMs
    } else {
        if (-not (Test-Path -LiteralPath $script:LastClosedFile)) { return $null }
        $last = $null
        try { $last = Get-Content -LiteralPath $script:LastClosedFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $last = $null }
        if (-not $last -or -not $last.session_id) { return $null }
        $sid = [string]$last.session_id
        if ($script:UnauthorizedSessions.ContainsKey($sid)) { return $null }
        if (-not (Test-Path -LiteralPath (Get-BridgeSessionFile $sid))) { return $null }
        $startMs = [int64]$last.started_at_ms
        $endMs = [int64]$last.ended_at_ms
    }
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $startLocal = (ConvertFrom-BridgeMs $startMs).ToLocalTime()
    return [ordered]@{
        session_id = $sid
        active = $active
        started_at = ConvertTo-BridgeIso (ConvertFrom-BridgeMs $startMs)
        started_local = $startLocal.ToString("HH:mm", $inv)
        started_local_date = $startLocal.ToString("dd/MM/yyyy", $inv)
        started_today = ($startLocal.Date -eq (Get-Date).Date)
        duration_min = [int][Math]::Round([Math]::Max(0, $endMs - $startMs) / 60000.0)
    }
}

# Marca a aula como nao autorizada: registro local, snapshot e novo envio a nuvem. Nada e apagado.
function Set-BridgeSessionUnauthorized {
    param([Parameter(Mandatory = $true)][string]$SessionId)
    $markedAt = ConvertTo-BridgeIso ([DateTime]::UtcNow)
    # Registro local primeiro: se a gravacao do snapshot falhar, o envio aplica a marca mesmo assim.
    $script:UnauthorizedSessions[$SessionId] = $markedAt
    Save-UnauthorizedTracker
    try {
        $snap = Get-Content -LiteralPath (Get-BridgeSessionFile $SessionId) -Raw -Encoding UTF8 | ConvertFrom-Json
        $snap | Add-Member -NotePropertyName authorization_status -NotePropertyValue "nao_autorizada" -Force
        $snap | Add-Member -NotePropertyName marked_at -NotePropertyValue $markedAt -Force
        Save-BridgeSnapshot $snap
    } catch {
        Write-BridgeLog "Aviso ao marcar o snapshot da aula $SessionId`: $($_.Exception.Message)" "WARN"
    }
    # Aula ja enviada: sai da lista de enviadas e sobe de novo, agora com a marca.
    if ($script:SyncedSessionIds.Remove($SessionId)) {
        try {
            $sessSyncTmp = Join-Path $DataDir "sessions_synced.tmp.$([System.Guid]::NewGuid().ToString('N'))"
            [System.IO.File]::WriteAllLines($sessSyncTmp, [string[]]$script:SyncedSessionIds, [System.Text.Encoding]::UTF8)
            Move-BridgeAtomicFile -SourcePath $sessSyncTmp -DestinationPath $script:SyncedSessionsTrackerFile
        } catch {}
    }
    Write-BridgeLog "Aula $SessionId marcada como nao autorizada pelo instrutor; dados mantidos ate a revisao do pesquisador." "INFO"
    return $markedAt
}

# "Nao registrar esta turma" (bandeja): marca a aula alvo como nao autorizada e pausa ate a proxima aula.
function Suspend-BridgeCollection {
    $target = Get-BridgeMarkTarget
    $markedAt = $null
    if ($target) {
        if ($target.active) { [void](Close-BridgeSession -EndedBy "instrutor") }
        $markedAt = Set-BridgeSessionUnauthorized -SessionId $target.session_id
    }
    $script:ActiveSession = $null
    $script:SessionTimeline = [System.Collections.Generic.List[object]]::new()
    Remove-Item -LiteralPath $script:SessionStateFile -Force -ErrorAction SilentlyContinue
    $nowMs = Get-BridgeNowMs
    $script:CollectionPause = [pscustomobject][ordered]@{
        paused_at = ConvertTo-BridgeIso (ConvertFrom-BridgeMs $nowMs)
        until_ms = $nowMs + ([int64]$script:SessionMaxMinutes * 60000)
        last_alive_ms = $nowMs
    }
    Save-BridgeTextAtomic -Path $script:PauseFile -Text ($script:CollectionPause | ConvertTo-Json)
    $script:AwaitingActivity = $false
    if (-not $target) { Write-BridgeLog "Nao registrar esta turma: nenhuma aula para marcar; coleta pausada ate a proxima aula." "INFO" }
    return [ordered]@{ marked = [bool]$target; target = $target; marked_at = $markedAt }
}

# ------------------------------------------------------------------------------
# Questionario do fim da aula (aba do navegador). As respostas vao para a turma ativa ou, sem ela,
# para a ultima encerrada (o mesmo alvo de mark_target). Nada e gravado em Modo Livre, com o
# registro pausado, em aula marcada como nao autorizada ou sem aula: a pagina so agradece.
# ------------------------------------------------------------------------------

function Get-BridgeQuestionarioTarget {
    if (-not (Get-BridgeResearchContext)) { return [ordered]@{ motivo = "modo_livre" } }
    if (Test-BridgeCollectionPaused) { return [ordered]@{ motivo = "pausado" } }
    $s = $script:ActiveSession
    if ($s) {
        $pseudo = [pscustomobject]@{ session_id = [string]$s.session_id; group_id = $s.group_id; started_at_ms = [int64]$s.started_at_ms; context = $s.context }
        return [ordered]@{ motivo = $null; active = $true; session = $pseudo; timeline = @($script:SessionTimeline); snapshot = $null }
    }
    if (-not (Test-Path -LiteralPath $script:LastClosedFile)) { return [ordered]@{ motivo = "sem_aula" } }
    $last = $null
    try { $last = Get-Content -LiteralPath $script:LastClosedFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $last = $null }
    if (-not $last -or -not $last.session_id) { return [ordered]@{ motivo = "sem_aula" } }
    $sid = [string]$last.session_id
    if ($script:UnauthorizedSessions.ContainsKey($sid) -or $script:WithdrawnSessionIds.Contains($sid)) { return [ordered]@{ motivo = "nao_autorizada" } }
    $snap = $null
    try { $snap = Get-Content -LiteralPath (Get-BridgeSessionFile $sid) -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $snap = $null }
    if (-not $snap -or -not $snap.installation_id) { return [ordered]@{ motivo = "sem_aula" } }
    if ($snap.authorization_status -eq "nao_autorizada") { return [ordered]@{ motivo = "nao_autorizada" } }
    $context = [pscustomobject]@{
        installation_id = $snap.installation_id
        computer_id = $snap.computer_id
        site_id = $snap.site_id
        regional_hub = $snap.regional_hub
        school_code = $snap.school_code
        workshop_code = $snap.workshop_code
        class_code = $snap.class_code
        activity_id = $snap.activity_id
        group_size = $snap.group_size
    }
    $pseudo = [pscustomobject]@{ session_id = $sid; group_id = $snap.group_id; started_at_ms = [int64]$last.started_at_ms; context = $context }
    return [ordered]@{ motivo = $null; active = $false; session = $pseudo; timeline = @($snap.timeline); snapshot = $snap }
}

function Test-BridgeBancadaRespondida($Target) {
    if (-not $Target -or $Target.motivo) { return $false }
    return [bool](@($Target.timeline) | Where-Object { $_ -and $_.event_type -eq "bancada_result_recorded" } | Select-Object -First 1)
}

# Corpo esperado: { submission_id: <uuid aleatorio do envio>, answers: [{ item_id, value }, ...] }, com
# todos os itens da tela exatamente uma vez. Devolve as respostas na ordem do instrumento ou $null.
function ConvertTo-BridgeQuestionarioAnswers($Body, $Items) {
    if (-not $Body -or -not ($Body -is [System.Management.Automation.PSCustomObject])) { return $null }
    if ([string]$Body.submission_id -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') { return $null }
    $answers = @($Body.answers)
    if ($answers.Count -ne $Items.Count) { return $null }
    $byItem = @{}
    foreach ($a in $answers) {
        if (-not $a -or -not ($a -is [System.Management.Automation.PSCustomObject])) { return $null }
        $itemId = [string]$a.item_id
        $value = [string]$a.value
        if (-not $Items.Contains($itemId) -or $byItem.ContainsKey($itemId)) { return $null }
        if ($value -cne $script:QuestionarioRecusa -and @($Items[$itemId]) -cnotcontains $value) { return $null }
        $byItem[$itemId] = $value
    }
    $ordered = @()
    foreach ($itemId in $Items.Keys) { $ordered += [pscustomobject]@{ item_id = $itemId; value = $byItem[$itemId] } }
    return [ordered]@{ submission_id = ([string]$Body.submission_id).ToLowerInvariant(); answers = $ordered }
}

# Grava um evento por pergunta na turma alvo. Na turma ativa usa Add-BridgeSessionEvent; na ultima
# encerrada acrescenta a linha em events.jsonl e o evento na timeline do snapshot.
function Save-BridgeQuestionario {
    param(
        [Parameter(Mandatory = $true)]$Target,
        [Parameter(Mandatory = $true)][string]$EventType,
        [Parameter(Mandatory = $true)]$Parsed
    )
    $isBancada = $EventType -eq "bancada_result_recorded"
    $nowMs = Get-BridgeNowMs
    $minutesSinceStart = [Math]::Round([Math]::Max(0, $nowMs - [int64]$Target.session.started_at_ms) / 60000.0, 1)
    # Respostas das criancas levam o horario do inicio da aula e nao levam minutos desde o inicio:
    # com o horario de cada rodada, quem estava na sala ligaria a rodada a uma crianca.
    $occurredAtMs = if ($isBancada) { [int64]0 } else { [int64]$Target.session.started_at_ms }
    $snap = $Target.snapshot
    # Atribuicao direta: uma lista vazia devolvida por "if" seria desenrolada e viraria $null.
    $timeline = [System.Collections.Generic.List[object]]::new()
    $sequence = 0
    if ($snap) {
        foreach ($ev in @($snap.timeline)) {
            if (-not $ev) { continue }
            $timeline.Add($ev)
            if ($null -ne $ev._sequence -and [int]$ev._sequence -gt $sequence) { $sequence = [int]$ev._sequence }
        }
    }
    $order = 0
    foreach ($answer in $Parsed.answers) {
        $order++
        $details = [ordered]@{
            item_id = $answer.item_id
            value = $answer.value
            refused = ($answer.value -ceq $script:QuestionarioRecusa)
            instrument_version = $script:InstrumentVersion
            submission_id = $Parsed.submission_id
            item_order = $order
            session_active = [bool]$Target.active
        }
        if ($isBancada) { $details["minutes_since_session_start"] = $minutesSinceStart }
        $participantId = if ($isBancada) { "BANCADA" } else { $null }
        $participantRole = if ($isBancada) { "group" } else { "individual" }
        if ($Target.active) {
            [void](Add-BridgeSessionEvent -EventType $EventType -Stage "questionario_fim_aula" -ParticipantId $participantId -ParticipantRole $participantRole -Details $details -OccurredAtMs $occurredAtMs)
        } else {
            $sequence++
            $event = New-BridgeEventRecord -Session $Target.session -Sequence $sequence -EventType $EventType -Stage "questionario_fim_aula" -ParticipantId $participantId -ParticipantRole $participantRole -Details $details -OccurredAtMs $occurredAtMs
            Add-BridgeEventLine -Json ($event | ConvertTo-Json -Depth 10 -Compress)
            $timeline.Add([pscustomobject]$event)
        }
    }
    if ($snap) {
        $snap | Add-Member -NotePropertyName timeline -NotePropertyValue $timeline.ToArray() -Force
        try { Save-BridgeSnapshot $snap } catch { Write-BridgeLog "Aviso ao guardar respostas no snapshot da aula $($Target.session.session_id): $($_.Exception.Message)" "WARN" }
    }
    return $order
}

function Add-BridgeHeartbeat {
    $s = $script:ActiveSession
    $s.heartbeat_count = [int]$s.heartbeat_count + 1
    [void](Add-BridgeSessionEvent -EventType "heartbeat" -Details ([ordered]@{
        spike_status = [string]$s.spike_status
        uptime_min = [Math]::Round(([DateTime]::UtcNow - $script:StartTime).TotalMinutes, 1)
        pending_sync = Get-BridgePendingSyncCount
        # O pesquisador ve na nuvem (research_installation_last_seen) qual maquina tem envio recusado.
        quarantined_events = $script:QuarantinedEventIds.Count
        quarantined_sessions = $script:QuarantinedSessionIds.Count
        last_sync_error_status = if ($script:LastSyncError) { [int]$script:LastSyncError.status_code } else { $null }
    }))
}

function Set-BridgeSpikeStatus([string]$Status) {
    $s = $script:ActiveSession
    if ($s.spike_status -eq $Status) { return }
    $s.spike_status = $Status
    if ($Status -in @("pasta_nao_encontrada", "arquivo_invalido", "arquivo_bloqueado", "leitor_indisponivel")) {
        [void](Add-BridgeSessionEvent -EventType "quality_issue" -Severity "warning" -Details ([ordered]@{ issue = "spike_$Status" }))
    } else {
        Save-BridgeSessionState
    }
}

function Update-BridgeSpikeTelemetry {
    $s = $script:ActiveSession
    if (-not $s -or -not (Get-Command Get-SpikeProjectMetrics -ErrorAction SilentlyContinue)) { return }
    $files = @(Get-BridgeSpikeFiles (ConvertFrom-BridgeMs ([int64]$s.spike_since_ms)))
    if ($files.Count -eq 0) {
        $envStatus = [string](Get-BridgeSpikeEnvironment).status
        if ($envStatus -eq "pasta_nao_encontrada") { Set-BridgeSpikeStatus "pasta_nao_encontrada" }
        elseif ($s.telemetry_events -eq 0) { Set-BridgeSpikeStatus "sem_alteracao" }
        return
    }
    $newest = $files[0]
    $key = Get-BridgeFileKey $newest.FullName
    $ticks = [int64]$newest.LastWriteTimeUtc.Ticks
    if ($s.last_file_key -eq $key -and [int64]$s.last_write_ticks -eq $ticks) { return }

    $m = Get-SpikeProjectMetrics -ProjectPath $newest.FullName
    $status = if ($m.spike_status) { [string]$m.spike_status } else { "ok" }
    $s.last_file_key = $key
    # Arquivo em uso pelo SPIKE: tenta de novo na proxima leitura.
    $s.last_write_ticks = if ($status -eq "arquivo_bloqueado") { 0 } else { $ticks }
    Set-BridgeSpikeStatus $status
    if ($status -notin @("ok", "python")) { Save-BridgeSessionState; return }

    $hash = [string]$m.structure_hash
    if ($status -eq "ok" -and $hash -and $hash -eq $s.last_structure_hash -and $key -eq $s.last_telemetry_file_key) {
        Save-BridgeSessionState
        return
    }

    $files = @($s.files)
    $fileEntry = $files | Where-Object { $_.key -eq $key } | Select-Object -First 1
    if (-not $fileEntry) {
        $fileEntry = [pscustomobject]@{ key = $key; seq = $files.Count + 1 }
        $s.files = @($files + $fileEntry)
    }
    $base = @($s.baseline) | Where-Object { $_ -and $_.key -eq $key } | Select-Object -First 1
    $blocks = [int]$m.executable_blocks
    $baselineBlocks = if ($base) { [int]$base.executable_blocks } else { 0 }
    $first = (-not $s.first_program_at) -and (($blocks -gt $baselineBlocks) -or ($status -eq "python"))
    if ($first) { $s.first_program_at = ConvertTo-BridgeIso $newest.LastWriteTimeUtc }

    $details = [ordered]@{
        file_seq = [int]$fileEntry.seq
        continued_previous_file = [bool]$base
        language = [string]$m.language
        spike_status = $status
        saved_at = ConvertTo-BridgeIso $newest.LastWriteTimeUtc
        first_coding_detected = $first
        executable_blocks = $blocks
        top_level_stacks = [int]$m.top_level_stacks
        uses_motor = [bool]$m.uses_motor
        uses_sensor = [bool]$m.uses_sensor
        uses_loop = [bool]$m.uses_loop
        uses_condition = [bool]$m.uses_condition
        uses_variable = [bool]$m.uses_variable
        uses_procedure = [bool]$m.uses_procedure
        opcode_counts = $m.opcode_counts
        structure_hash = $m.structure_hash
        ct_score = $m.ct_score
        ct_score_version = $m.ct_score_version
    }
    if ($base) {
        $details.baseline_executable_blocks = $baselineBlocks
        $details.blocks_delta_from_baseline = $blocks - $baselineBlocks
    }
    $coverage = $null
    if ($s.context.mission -and (Get-Command Measure-SpikeMissionCoverage -ErrorAction SilentlyContinue)) {
        try { $coverage = Measure-SpikeMissionCoverage -Metrics $m -Mission $s.context.mission } catch { $coverage = $null }
        if ($coverage) { $details.mission_coverage = $coverage }
    }
    $s.telemetry_events = [int]$s.telemetry_events + 1
    # Nova versao salva no SPIKE: zera o relogio de inatividade (Add-Member: estado salvo por versoes antigas nao tem o campo).
    $savedMs = [DateTimeOffset]::new([DateTime]::SpecifyKind($newest.LastWriteTimeUtc, [DateTimeKind]::Utc)).ToUnixTimeMilliseconds()
    $s | Add-Member -NotePropertyName last_program_ms -NotePropertyValue ([Math]::Max([int64]$s.started_at_ms, [Math]::Max([int64]$s.last_program_ms, $savedMs))) -Force
    $s.last_structure_hash = $hash
    $s.last_telemetry_file_key = $key
    $s.last_summary = [ordered]@{
        executable_blocks = $blocks
        ct_total = if ($m.ct_score) { $m.ct_score.total } else { $null }
        mission_coverage = if ($coverage) { $coverage.coverage } else { $null }
    }
    $stage = if ($first) { "primeira_programacao_detectada" } else { "atualizacao_codigo_spike" }
    [void](Add-BridgeSessionEvent -EventType "spike_telemetry" -Stage $stage -Details $details)
}

# Fim por inatividade: limite contado da ultima versao salva no SPIKE ou, sem nenhuma, do inicio da turma.
# Ultimo sinal de atividade da turma: ultima versao salva no SPIKE ou, sem nenhuma, o inicio.
function Get-BridgeLastActivityMs($Session) {
    return [Math]::Max([int64]$Session.started_at_ms, [int64]$Session.last_program_ms)
}

function Get-BridgeIdleDeadlineMs($Session) {
    return (Get-BridgeLastActivityMs $Session) + [int64]$script:SessionIdleMinutes * 60000
}

function Initialize-BridgeSession {
    $legacySchedule = Join-Path $DataDir "active_schedule.json"
    if (Test-Path -LiteralPath $legacySchedule) { Remove-Item -LiteralPath $legacySchedule -Force -ErrorAction SilentlyContinue }

    $nowMs = Get-BridgeNowMs
    $script:CollectionPause = Read-BridgeCollectionPause
    if ($script:CollectionPause) {
        # Computador desligado por mais de 20 minutos: e outra aula, a pausa acabou.
        $pauseGapMin = ($nowMs - [int64]$script:CollectionPause.last_alive_ms) / 60000.0
        if ($pauseGapMin -ge $script:ResumeGapMinutes -or $nowMs -ge [int64]$script:CollectionPause.until_ms) { Clear-BridgeCollectionPause }
    }

    if (Restore-BridgeSessionState) {
        $s = $script:ActiveSession
        $s.corrupted_lines = [int]$s.corrupted_lines + $script:CorruptedLinesFound
        $gapMin = ($nowMs - [int64]$s.last_alive_ms) / 60000.0
        $ageMin = ($nowMs - [int64]$s.started_at_ms) / 60000.0
        $idleEndMs = Get-BridgeIdleDeadlineMs $s
        if ($gapMin -ge $script:ResumeGapMinutes) {
            [void](Close-BridgeSession -EndedBy "sem_encerramento" -EndedAtMs ([int64]$s.last_alive_ms))
        } elseif ($nowMs -ge $idleEndMs -and $idleEndMs -lt ([int64]$s.started_at_ms + [int64]$script:SessionMaxMinutes * 60000)) {
            # Sem programa salvo pelo limite: a turma acabou e a proxima abre no primeiro programa salvo.
            [void](Close-BridgeSession -EndedBy "inatividade" -EndedAtMs (Get-BridgeLastActivityMs $s))
            return
        } elseif ($ageMin -ge $script:SessionMaxMinutes) {
            [void](Close-BridgeSession -EndedBy "tempo" -EndedAtMs ([int64]$s.started_at_ms + [int64]$script:SessionMaxMinutes * 60000))
        } else {
            $s.bridge_restarts = [int]$s.bridge_restarts + 1
            $s.max_gap_min = [Math]::Max([double]$s.max_gap_min, $gapMin)
            [void](Add-BridgeSessionEvent -EventType "quality_issue" -Severity "warning" -Details ([ordered]@{
                issue = "pulselab_reiniciado"
                gap_min = [Math]::Round($gapMin, 1)
            }))
            Write-BridgeLog "Turma em andamento retomada apos reinicio ($([Math]::Round($gapMin, 1)) min sem sinal)." "INFO"
            return
        }
    }
    [void](Start-BridgeSession -StartMode "abertura_app")
}

function Invoke-BridgeSessionTick {
    $now = [DateTime]::UtcNow
    $sinceLastTickMin = ($now - $script:LastSessionTick).TotalMinutes
    $script:LastSessionTick = $now
    $s = $script:ActiveSession

    if ($s) {
        $nowMs = Get-BridgeNowMs
        if ($sinceLastTickMin -ge $script:ResumeGapMinutes) {
            # Computador suspenso entre aulas: a turma acabou quando ele parou.
            [void](Close-BridgeSession -EndedBy "sem_encerramento" -EndedAtMs ([int64]$s.last_alive_ms))
            return
        }
        if (($nowMs - [int64]$s.started_at_ms) -ge ([int64]$script:SessionMaxMinutes * 60000)) {
            [void](Close-BridgeSession -EndedBy "tempo")
            return
        }
        # No limite de inatividade le o SPIKE antes de encerrar: um programa salvo nos ultimos segundos ainda conta.
        if (($now - $script:LastSpikePoll).TotalSeconds -ge $script:SpikePollSeconds -or $nowMs -ge (Get-BridgeIdleDeadlineMs $s)) {
            $script:LastSpikePoll = $now
            try { Update-BridgeSpikeTelemetry } catch { Write-BridgeLog "Aviso na leitura do SPIKE: $($_.Exception.Message)" "WARN" }
        }
        # Turma esquecida aberta: sem nova versao salva no SPIKE pelo limite, encerra e espera o proximo programa.
        $idleEndMs = Get-BridgeIdleDeadlineMs $script:ActiveSession
        if ($nowMs -ge $idleEndMs) {
            [void](Close-BridgeSession -EndedBy "inatividade" -EndedAtMs (Get-BridgeLastActivityMs $script:ActiveSession))
            return
        }
        if ($script:ActiveSession -and ($now - $script:LastHeartbeat).TotalSeconds -ge $script:HeartbeatSeconds) {
            $script:LastHeartbeat = $now
            Add-BridgeHeartbeat
        }
        return
    }

    if ($script:CollectionPause) {
        if (-not (Test-BridgeCollectionPaused)) { return }
        if (($now - $script:LastHeartbeat).TotalSeconds -ge $script:HeartbeatSeconds) {
            $script:LastHeartbeat = $now
            $script:CollectionPause.last_alive_ms = Get-BridgeNowMs
            try { Save-BridgeTextAtomic -Path $script:PauseFile -Text ($script:CollectionPause | ConvertTo-Json) } catch {}
        }
        return
    }

    # Depois de uma turma encerrada, a proxima abre no primeiro programa salvo.
    if ($script:AwaitingActivity -and ($now - $script:LastSpikePoll).TotalSeconds -ge $script:SpikePollSeconds) {
        $script:LastSpikePoll = $now
        $files = @(Get-BridgeSpikeFiles $script:LastClosedAtUtc)
        if ($files.Count -gt 0) {
            $firstSave = ($files | Sort-Object LastWriteTimeUtc | Select-Object -First 1).LastWriteTimeUtc
            $closedMs = [DateTimeOffset]::new($script:LastClosedAtUtc).ToUnixTimeMilliseconds()
            $startMs = [DateTimeOffset]::new([DateTime]::SpecifyKind($firstSave, [DateTimeKind]::Utc)).ToUnixTimeMilliseconds()
            [void](Start-BridgeSession -StartMode "atividade_spike" -StartedAtMs $startMs -SpikeSinceMs $closedMs)
        }
    }
}

function Get-BridgePendingSyncCount {
    $eventsFile = Join-Path $DataDir "events.jsonl"
    if (-not (Test-Path -LiteralPath $eventsFile)) { return 0 }
    $pending = 0
    try {
        foreach ($line in [System.IO.File]::ReadAllLines($eventsFile)) {
            if ($line -match '"event_id":"([^"]+)"' -and -not $script:SyncedEventIds.Contains($Matches[1]) -and -not $script:QuarantinedEventIds.Contains($Matches[1])) { $pending++ }
        }
    } catch {}
    return $pending
}

function Get-BridgeStatus {
    $s = $script:ActiveSession
    $ctx = Get-BridgeResearchContext
    $session = $null
    if ($s) {
        $session = [ordered]@{
            session_id = $s.session_id
            started_at = $s.started_at
            elapsed_min = [Math]::Round(((Get-BridgeNowMs) - [int64]$s.started_at_ms) / 60000.0, 1)
            start_mode = $s.start_mode
            telemetry_events = [int]$s.telemetry_events
            heartbeat_count = [int]$s.heartbeat_count
            spike_status = [string]$s.spike_status
            mission_id = if ($s.context.mission) { [string]$s.context.mission.mission_id } else { $null }
        }
    }
    return [ordered]@{
        status = "ok"
        version = $script:BridgeVersion
        research_active = [bool]$ctx
        machine_label = if ($ctx) { $ctx.computer_id } else { $null }
        paused = [bool]$script:CollectionPause
        awaiting_activity = [bool]$script:AwaitingActivity
        session = $session
        # Aula que "Nao registrar esta turma" marcaria agora (a bandeja mostra antes de confirmar).
        mark_target = if ($ctx) { Get-BridgeMarkTarget } else { $null }
        session_max_minutes = $script:SessionMaxMinutes
        spike_environment = Get-BridgeSpikeEnvironment
        cloud_enabled = [bool]$script:SupabaseOperationalJwt
        pending_sync = Get-BridgePendingSyncCount
        last_sync_ok_at = $script:LastSyncOkAt
        quarantined_events = $script:QuarantinedEventIds.Count
        quarantined_sessions = $script:QuarantinedSessionIds.Count
        sync_paused_until = if (Test-BridgeSyncPaused) { ConvertTo-BridgeIso $script:SyncBackoffUntil } else { $null }
        last_sync_error = $script:LastSyncError
        # Aulas alem de retention_days guardadas porque ainda nao sairam do computador.
        retention_kept_sessions = $script:RetentionKeptSessions
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

# Executar limpeza de retencao absoluta na inicializacao
try {
    Invoke-BridgeRetentionCleanup -MaxAgeDays (Get-BridgeRetentionDays)
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
    try { Invoke-BridgeSessionTick } catch { Write-BridgeLog "Aviso na sessao da turma: $($_.Exception.Message)" "WARN" }
    if (([DateTime]::UtcNow - $script:LastRetentionCleanup).TotalHours -ge 1) {
        $script:LastRetentionCleanup = [DateTime]::UtcNow
        try { Invoke-BridgeRetentionCleanup -MaxAgeDays (Get-BridgeRetentionDays) } catch {}
    }
    if (([DateTime]::UtcNow - $script:LastSyncAttempt).TotalSeconds -ge $script:SyncIntervalSeconds) {
        $script:LastSyncAttempt = [DateTime]::UtcNow
        Invoke-BridgeDeviceEnrollment
        try { Invoke-BridgeQuarantineRetry } catch {}
        if (-not (Test-BridgeSyncPaused)) {
            Sync-EventsToSupabase
            Sync-SessionSnapshotsToSupabase
        }
        Sync-PendingWithdrawals
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

# Fila local integra e sessao da turma antes de atender requisicoes.
try { $script:CorruptedLinesFound = Repair-BridgeEventsFile } catch { Write-BridgeLog "Aviso ao verificar events.jsonl: $($_.Exception.Message)" "WARN" }
try { Initialize-BridgeSession } catch { Write-BridgeLog "Aviso ao iniciar a sessao da turma: $($_.Exception.Message)" "WARN" }

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
            if ($path -in @("/health", "/v1/health", "/config", "/v1/config", "/v1/status", "/v1/session/current", "/v1/questionario/estado")) {
                if ($request.HttpMethod -ne "GET") {
                    $response.StatusCode = 405
                    $response.AddHeader("Allow", "GET")
                    $response.Close()
                    continue
                }
            }

            # 2. Rotas estritamente POST
            $postRoutes = @(
                "/v1/session/close",
                "/v1/session/pause",
                "/v1/questionario/bancada",
                "/v1/questionario/crianca",
                "/v1/shutdown",
                "/update",
                "/v1/update"
            )
            if ($path -in $postRoutes) {
                if ($request.HttpMethod -ne "POST") {
                    $response.StatusCode = 405
                    $response.AddHeader("Allow", "POST")
                    $response.Close()
                    continue
                }
            }

            # 3. Endpoints que consomem corpo JSON: exigir Content-Type e limitar Content-Length
            $jsonBodyRoutes = @("/v1/session/close", "/v1/session/pause", "/v1/questionario/bancada", "/v1/questionario/crianca")
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
                $spikeDetected = ([int](Get-BridgeSpikeEnvironment).project_count) -gt 0
                $healthObj = @{
                    status = "ok"
                    version = $script:BridgeVersion
                    uptime_seconds = [Math]::Round($uptime, 1)
                    port = $Port
                    spike_detected = $spikeDetected
                    has_active_session = ($null -ne $script:ActiveSession)
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
                    protocol_version = $null
                    group_size = 2
                    research_collection_enabled = $false
                    research_authorization_version = $null
                    research_authorized_purposes = @()
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
                        if ($null -ne $cfg.group_size) { $publicConfig.group_size = $cfg.group_size }
                        if ($null -ne $cfg.research_collection_enabled) { $publicConfig.research_collection_enabled = $cfg.research_collection_enabled }
                        if ($null -ne $cfg.research_authorization_version) { $publicConfig.research_authorization_version = $cfg.research_authorization_version }
                        if ($null -ne $cfg.research_authorized_purposes) { $publicConfig.research_authorized_purposes = $cfg.research_authorized_purposes }
                        if ($cfg.site_id) { $publicConfig.site_id = $cfg.site_id }
                        if ($cfg.activity_id) { $publicConfig.activity_id = $cfg.activity_id }
                        if ($cfg.regional_hub) { $publicConfig.regional_hub = $cfg.regional_hub }
                        if ($cfg.school_code) { $publicConfig.school_code = $cfg.school_code }
                        if ($cfg.workshop_code) { $publicConfig.workshop_code = $cfg.workshop_code }
                        if ($cfg.class_code) { $publicConfig.class_code = $cfg.class_code }
                        if ($cfg.questions) { $publicConfig.questions = $cfg.questions }
                    } catch {}
                }

                # A autorizacao de pesquisa vem somente do provisionamento do polo (dados_locais\installation.json).
                # O config.json do pacote e igual para todas as maquinas e nunca liga a coleta.
                $publicConfig.research_collection_enabled = $false
                $publicConfig.research_authorization_version = $null
                $publicConfig.research_authorized_purposes = @()
                $publicConfig.installation_id = $script:InstallationId
                $publicConfig.machine_label = $null
                $installationFile = Join-Path $DataDir "installation.json"
                if (Test-Path -LiteralPath $installationFile) {
                    try {
                        $inst = Get-Content -LiteralPath $installationFile -Raw -Encoding UTF8 | ConvertFrom-Json
                        if ($inst.machine_label) { $publicConfig.machine_label = [string]$inst.machine_label }
                        if (-not $publicConfig.installation_id -and $inst.installation_id) { $publicConfig.installation_id = [string]$inst.installation_id }
                        if ($inst.site_id) { $publicConfig.site_id = [string]$inst.site_id }
                        if ($inst.regional_hub) { $publicConfig.regional_hub = [string]$inst.regional_hub }
                        if ($inst.school_code) { $publicConfig.school_code = [string]$inst.school_code }
                        $publicConfig.retention_days = Get-BridgeRetentionDays
                        if ($inst.research_collection_enabled -eq $true -and $inst.research_authorization_version) {
                            $publicConfig.research_collection_enabled = $true
                            $publicConfig.research_authorization_version = [string]$inst.research_authorization_version
                            $publicConfig.research_authorized_purposes = @($inst.research_authorized_purposes)
                        }
                    } catch {}
                }
                $buf = [System.Text.Encoding]::UTF8.GetBytes(($publicConfig | ConvertTo-Json -Depth 5))
                $response.ContentType = "application/json; charset=utf-8"
                $response.ContentLength64 = $buf.Length
                $response.OutputStream.Write($buf, 0, $buf.Length)
                $response.Close()
                continue
            }

            if ($path -eq "/v1/status" -and $request.HttpMethod -eq "GET") {
                Send-BridgeResponse -Response $response -StatusCode 200 -Payload (Get-BridgeStatus)
                continue
            }

            if ($path -eq "/v1/session/current" -and $request.HttpMethod -eq "GET") {
                $s = $script:ActiveSession
                $current = [ordered]@{
                    research_active = [bool](Get-BridgeResearchContext)
                    paused = [bool]$script:CollectionPause
                    active = [bool]$s
                    session_id = if ($s) { $s.session_id } else { $null }
                    started_at = if ($s) { $s.started_at } else { $null }
                    elapsed_min = if ($s) { [Math]::Round(((Get-BridgeNowMs) - [int64]$s.started_at_ms) / 60000.0, 1) } else { $null }
                }
                Send-BridgeResponse -Response $response -StatusCode 200 -Payload $current
                continue
            }

            # Formulario final ou comando silencioso da bandeja: encerra a turma.
            if ($path -eq "/v1/session/close" -and $request.HttpMethod -eq "POST") {
                $readRes = Read-BoundedRequestBody -Request $request -MaxBytes 65536
                if (-not $readRes.Success) {
                    Send-BridgeResponse -Response $response -StatusCode $readRes.StatusCode -Payload @{ error = $readRes.Error }
                    continue
                }
                $closeObj = $null
                try {
                    if (-not [string]::IsNullOrWhiteSpace($readRes.Body)) { $closeObj = $readRes.Body | ConvertFrom-Json }
                } catch {
                    $closeObj = $null
                }
                if (-not $closeObj -and -not [string]::IsNullOrWhiteSpace($readRes.Body) -and $readRes.Body.Trim() -ne "{}") {
                    Send-BridgeResponse -Response $response -StatusCode 400 -Payload @{ error = "Bad Request"; message = "JSON invalido" }
                    continue
                }
                if ($script:CollectionPause) {
                    Send-BridgeResponse -Response $response -StatusCode 409 -Payload @{ error = "Conflict"; message = "Este computador nao esta registrando turmas agora." }
                    continue
                }
                # A turma precisa ser a mesma que o formulario mostrou (caso session_id tenha sido informado explicitamente)
                $expectedSessId = if ($script:ActiveSession) { [string]$script:ActiveSession.session_id } else { $null }
                $requestedSessId = if ($closeObj -and $closeObj.session_id) { [string]$closeObj.session_id } else { $null }
                if ($requestedSessId -and ($requestedSessId -ne $expectedSessId)) {
                    Send-BridgeResponse -Response $response -StatusCode 409 -Payload @{ error = "Conflict"; message = "A turma mudou desde que o formulario foi aberto."; session_id = $expectedSessId }
                    continue
                }

                $exp = if ($closeObj) { $closeObj.experience } else { $null }
                $rub = if ($closeObj) { $closeObj.rubric } else { $null }
                $validClose = $true
                if ($exp -and -not $exp.refused) {
                    $expValue = 0
                    if (-not [int]::TryParse([string]$exp.value, [ref]$expValue) -or $expValue -lt 1 -or $expValue -gt 4) { $validClose = $false }
                    if ($exp.label -and ([string]$exp.label).Length -gt 30) { $validClose = $false }
                }
                if ($rub -and -not $rub.skipped) {
                    $resultLevel = -1
                    if (-not [int]::TryParse([string]$rub.result_level, [ref]$resultLevel) -or $resultLevel -lt 0 -or $resultLevel -gt 3) { $validClose = $false }
                    if ([string]$rub.support_level -notin @("nenhum", "algum", "muito")) { $validClose = $false }
                }
                if (-not $validClose) {
                    Send-BridgeResponse -Response $response -StatusCode 400 -Payload @{ error = "Bad Request"; message = "Respostas fora da escala do instrumento" }
                    continue
                }

                if (-not (Get-BridgeResearchContext)) {
                    # Modo Livre: permite testar e concluir a dinamica pedagogica de encerramento sem persistencia de pesquisa.
                    Write-BridgeLog "Encerramento de turma recebido em Modo Livre (sem persistencia de pesquisa)" "INFO"
                    if ($script:ActiveSession) {
                        $script:ActiveSession = $null
                    }
                    Send-BridgeResponse -Response $response -StatusCode 200 -Payload @{ status = "closed"; session_id = "modo_livre"; modo_livre = $true }
                    continue
                }

                if (-not $expectedSessId) {
                    if ($exp -or $rub) {
                        # Nenhum programa foi salvo desde a turma anterior mas respostas foram enviadas: abre a sessao para guardar respostas.
                        [void](Start-BridgeSession -StartMode "encerramento_sem_atividade")
                    } else {
                        # Encerramento silencioso quando nao ha sessao ativa: nenhuma sessao a encerrar.
                        Send-BridgeResponse -Response $response -StatusCode 200 -Payload @{ status = "no_active_session"; session_id = $null }
                        continue
                    }
                }
                $closedSnapshot = Close-BridgeSession -EndedBy "instrutor" -Experience $exp -Rubric $rub
                if (-not $closedSnapshot) {
                    Send-BridgeResponse -Response $response -StatusCode 409 -Payload @{ error = "Conflict"; message = "Nao foi possivel abrir a turma para registrar as respostas." }
                    continue
                }
                Send-BridgeResponse -Response $response -StatusCode 200 -Payload @{ status = "closed"; session_id = $closedSnapshot.session_id }
                continue
            }

            # "Nao registrar esta turma" (bandeja): marca a aula como nao autorizada e pausa ate a proxima aula.
            if ($path -eq "/v1/session/pause" -and $request.HttpMethod -eq "POST") {
                $readRes = Read-BoundedRequestBody -Request $request -MaxBytes 4096
                if (-not $readRes.Success) {
                    Send-BridgeResponse -Response $response -StatusCode $readRes.StatusCode -Payload @{ error = $readRes.Error }
                    continue
                }
                $pauseObj = $null
                try {
                    if (-not [string]::IsNullOrWhiteSpace($readRes.Body)) { $pauseObj = $readRes.Body | ConvertFrom-Json }
                } catch {
                    Send-BridgeResponse -Response $response -StatusCode 400 -Payload @{ error = "Bad Request"; message = "JSON invalido" }
                    continue
                }
                if (-not (Get-BridgeResearchContext)) {
                    Send-BridgeResponse -Response $response -StatusCode 409 -Payload @{ error = "Conflict"; message = "Este computador nao registra dados de pesquisa." }
                    continue
                }
                # A aula precisa ser a mesma que a bandeja mostrou ao instrutor ("" = nenhuma aula).
                if ($null -ne $pauseObj -and $pauseObj.PSObject.Properties["session_id"]) {
                    $currentTarget = Get-BridgeMarkTarget
                    $shownSessId = if ($pauseObj.session_id) { [string]$pauseObj.session_id } else { "" }
                    $targetSessId = if ($currentTarget) { [string]$currentTarget.session_id } else { "" }
                    if ($shownSessId -ne $targetSessId) {
                        Send-BridgeResponse -Response $response -StatusCode 409 -Payload @{ error = "Conflict"; message = "A aula mudou desde que a janela foi aberta."; mark_target = $currentTarget }
                        continue
                    }
                }
                $pauseResult = Suspend-BridgeCollection
                Send-BridgeResponse -Response $response -StatusCode 200 -Payload ([ordered]@{ status = "paused"; marked = $pauseResult.marked; marked_at = $pauseResult.marked_at; target = $pauseResult.target })
                continue
            }

            # Encerramento total do aplicativo (PWA ou bandeja)
            if ($path -eq "/v1/shutdown" -and $request.HttpMethod -eq "POST") {
                Write-BridgeLog "Requisicao de encerramento do PulseLab recebida." "INFO"
                $signalFile = Join-Path $DataDir "shutdown.signal"
                try { [System.IO.File]::WriteAllText($signalFile, "shutdown") } catch {}
                Send-BridgeResponse -Response $response -StatusCode 200 -Payload @{ status = "shutting_down"; message = "PulseLab encerrando..." }
                $script:ShutdownRequested = $true
                break
            }

            # Questionario do fim da aula: o que a aba mostra (sem ids de sessao nem dados das criancas).
            if ($path -eq "/v1/questionario/estado" -and $request.HttpMethod -eq "GET") {
                $qTarget = Get-BridgeQuestionarioTarget
                Send-BridgeResponse -Response $response -StatusCode 200 -Payload ([ordered]@{
                    coleta_ativa = -not $qTarget.motivo
                    motivo = $qTarget.motivo
                    bancada_respondida = (Test-BridgeBancadaRespondida $qTarget)
                    instrument_version = $script:InstrumentVersion
                })
                continue
            }

            # Respostas do questionario: validadas antes de qualquer gravacao; fora de uma aula registrada
            # nada e gravado e a pagina so agradece. O resultado da bancada vale uma vez por aula.
            if ($path -in @("/v1/questionario/bancada", "/v1/questionario/crianca") -and $request.HttpMethod -eq "POST") {
                $readRes = Read-BoundedRequestBody -Request $request -MaxBytes 8192
                if (-not $readRes.Success) {
                    Send-BridgeResponse -Response $response -StatusCode $readRes.StatusCode -Payload @{ error = $readRes.Error }
                    continue
                }
                $qBody = $null
                try {
                    if (-not [string]::IsNullOrWhiteSpace($readRes.Body)) { $qBody = $readRes.Body | ConvertFrom-Json }
                } catch {
                    $qBody = $null
                }
                $qIsBancada = $path -eq "/v1/questionario/bancada"
                $qItems = if ($qIsBancada) { $script:QuestionarioBancadaItems } else { $script:QuestionarioCriancaItems }
                $qParsed = ConvertTo-BridgeQuestionarioAnswers $qBody $qItems
                if (-not $qParsed) {
                    Send-BridgeResponse -Response $response -StatusCode 400 -Payload @{ error = "Bad Request"; message = "Respostas fora do instrumento" }
                    continue
                }
                $qTarget = Get-BridgeQuestionarioTarget
                if ($qTarget.motivo) {
                    Send-BridgeResponse -Response $response -StatusCode 200 -Payload ([ordered]@{ status = "nao_gravado"; motivo = $qTarget.motivo })
                    continue
                }
                if ($qIsBancada -and (Test-BridgeBancadaRespondida $qTarget)) {
                    Send-BridgeResponse -Response $response -StatusCode 200 -Payload ([ordered]@{ status = "ja_respondido" })
                    continue
                }
                $qEventType = if ($qIsBancada) { "bancada_result_recorded" } else { "student_feedback_recorded" }
                $qCount = Save-BridgeQuestionario -Target $qTarget -EventType $qEventType -Parsed $qParsed
                Send-BridgeResponse -Response $response -StatusCode 200 -Payload ([ordered]@{ status = "gravado"; respostas = $qCount })
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
    if ($script:ShutdownRequested) {
        # Só a bandeja: o navegador é do usuário e não é encerrado (a página pode ser fechada à mão).
        Write-BridgeLog "Encerramento completo do PulseLab solicitado. Finalizando a bandeja..." "INFO"
        try {
            Get-CimInstance Win32_Process -Filter "CommandLine LIKE '%pulselab-tray.ps1%'" -ErrorAction SilentlyContinue | ForEach-Object {
                Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
            }
        } catch {}
    }
}
