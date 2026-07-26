#Requires -Version 5.1
# =============================================================================
# pulselab-agent.ps1
# Version    : 1.4.0
# Description: Coletor de eventos de pesquisa para oficinas pontuais com LEGO
#              SPIKE. Produz respostas pseudonimizadas e uma linha do tempo
#              append-only para observação distribuída e controle de qualidade.
# =============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public class Win32 {
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern int GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

    [StructLayout(LayoutKind.Sequential)]
    public struct LASTINPUTINFO {
        public uint cbSize;
        public uint dwTime;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [DllImport("user32.dll")]
    public static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
}
"@

# =============================================================================
# ESTADO E CAMINHOS
# =============================================================================

$script:VERSION = "1.4.0"
$script:SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path

$localConfigInAgent = Join-Path $script:SCRIPT_DIR "config\config.json"
$localConfigInRepo = Join-Path (Split-Path -Parent $script:SCRIPT_DIR) "config\config.json"
$script:LOCAL_CONFIG = if (Test-Path $localConfigInAgent) { $localConfigInAgent } else { $localConfigInRepo }

$localDataRoot = [Environment]::GetFolderPath("LocalApplicationData")
if ([string]::IsNullOrWhiteSpace($localDataRoot)) { $localDataRoot = $env:TEMP }
$script:DATA_DIR = Join-Path $localDataRoot "PulseLab"
$script:LOG_FILE = Join-Path $script:DATA_DIR "pulselab.log"
$script:OFFLINE_CACHE_DIR = Join-Path $script:DATA_DIR "cache"
$script:OFFLINE_CACHE_FILE = Join-Path $script:OFFLINE_CACHE_DIR "research-queue.json"
$script:INSTALLATION_FILE = Join-Path $script:DATA_DIR "installation.json"

$script:SessionId = $null
$script:DyadId = $null
$script:InstallationId = $null
$script:SiteId = ""
$script:RegionalHub = ""
$script:ComputerId = $env:COMPUTERNAME
$script:ParticipantComputer = $null
$script:ParticipantAssembly = $null
$script:SchoolCode = ""
$script:WorkshopCode = ""
$script:ClassCode = ""
$script:GradeBand = ""
$script:ActivityId = ""
$script:SupabaseUrl = $null
$script:SupabaseKey = $null
$script:Config = $null
$script:ConfigHash = $null
$script:SpikeHandle = [IntPtr]::Zero
$script:TriggerEnding = $false
$script:EndingRequestedAt = $null
$script:NotifyIcon = $null
$script:CollectionAuthorized = $false
$script:ActivityStartedAt = $null
$script:ActivityStopwatch = $null
$script:NextHeartbeatElapsedMs = 0L
$script:ParticipantComputerRole = "computer"
$script:ParticipantAssemblyRole = "assembly"

# =============================================================================
# INFRAESTRUTURA
# =============================================================================

function Write-PulseLog {
    param(
        [ValidateSet("INFO", "WARN", "ERROR", "DEBUG")]
        [string]$Level,
        [string]$Message
    )

    if (-not (Test-Path $script:DATA_DIR)) {
        New-Item -ItemType Directory -Path $script:DATA_DIR -Force | Out-Null
    }

    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $entry = "[$timestamp] [$Level] $Message"

    if ($script:Config -and $script:Config.debug_mode) { Write-Host $entry }

    if (Test-Path $script:LOG_FILE) {
        $maxBytes = if ($script:Config) { [int]$script:Config.log_max_size_mb * 1MB } else { 5MB }
        if ((Get-Item $script:LOG_FILE).Length -gt $maxBytes) {
            $backup = $script:LOG_FILE + ".bak"
            if (Test-Path $backup) { Remove-Item $backup -Force }
            Move-Item $script:LOG_FILE $backup -Force
        }
    }

    Add-Content -Path $script:LOG_FILE -Value $entry -Encoding UTF8
}

function Get-Sha256Hex {
    param([string]$Value)

    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
        $hash = $sha256.ComputeHash($bytes)
        return (($hash | ForEach-Object { $_.ToString("x2") }) -join "")
    } finally {
        $sha256.Dispose()
    }
}

function Save-InstallationProfile {
    $profile = @{
        installation_id = $script:InstallationId
        site_id = $script:SiteId
        regional_hub = $script:RegionalHub
        school_code = $script:SchoolCode
        updated_at = [DateTimeOffset]::Now.ToString("o")
    }
    $profile | ConvertTo-Json -Depth 4 | Set-Content $script:INSTALLATION_FILE -Encoding UTF8 -Force
}

function Initialize-Installation {
    if (-not (Test-Path $script:DATA_DIR)) {
        New-Item -ItemType Directory -Path $script:DATA_DIR -Force | Out-Null
    }

    $local = $null
    if (Test-Path $script:LOCAL_CONFIG) {
        $local = Get-Content $script:LOCAL_CONFIG -Raw -Encoding UTF8 | ConvertFrom-Json
    }

    $profile = $null
    if (Test-Path $script:INSTALLATION_FILE) {
        try {
            $profile = Get-Content $script:INSTALLATION_FILE -Raw -Encoding UTF8 | ConvertFrom-Json
            [Guid]::Parse([string]$profile.installation_id) | Out-Null
        } catch {
            Write-PulseLog "WARN" "Installation profile is invalid and will be recreated."
            $profile = $null
        }
    }

    if ($profile) {
        $script:InstallationId = [string]$profile.installation_id
        $script:SiteId = [string]$profile.site_id
        $script:RegionalHub = [string]$profile.regional_hub
        $script:SchoolCode = [string]$profile.school_code
    } else {
        $script:InstallationId = [Guid]::NewGuid().ToString()
        $script:SiteId = if ($local -and $local.PSObject.Properties.Name -contains "site_id") {
            [string]$local.site_id
        } else {
            "CONFIGURE_SEDE"
        }
        $script:RegionalHub = if ($local) { [string]$local.regional_hub } else { "CONFIGURE_REGIONAL" }
        $script:SchoolCode = if ($local) { [string]$local.school_code } else { "CONFIGURE_ESCOLA" }
        Save-InstallationProfile
    }

    Write-PulseLog "INFO" "Installation initialized. installation_id=$($script:InstallationId) site_id=$($script:SiteId)"
}

function Initialize-Session {
    $script:SessionId = [Guid]::NewGuid().ToString()
    $script:DyadId = [Guid]::NewGuid().ToString()
    $shortId = $script:SessionId.Substring(0, 8).ToUpperInvariant()
    $script:ParticipantComputer = "$shortId-A"
    $script:ParticipantAssembly = "$shortId-B"
    $script:ParticipantComputerRole = "computer"
    $script:ParticipantAssemblyRole = "assembly"
    $script:CollectionAuthorized = $false
    $script:TriggerEnding = $false
    $script:EndingRequestedAt = $null

    New-Item -ItemType Directory -Path $script:OFFLINE_CACHE_DIR -Force | Out-Null
    Write-PulseLog "INFO" "Session initialized. version=$script:VERSION session_id=$script:SessionId dyad_id=$script:DyadId installation_id=$($script:InstallationId)"
}

function Get-RemoteConfig {
    if (-not (Test-Path $script:LOCAL_CONFIG)) {
        throw "Configuration file missing at $($script:LOCAL_CONFIG)."
    }

    $localRaw = Get-Content $script:LOCAL_CONFIG -Raw -Encoding UTF8
    $local = $localRaw | ConvertFrom-Json
    $selectedRaw = $localRaw
    try {
        $response = Invoke-WebRequest -Uri $local.config_remote_url -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        $remote = $response.Content | ConvertFrom-Json
        if (-not $remote.questions -or -not $remote.interval_marks_minutes -or
            -not ($remote.PSObject.Properties.Name -contains "protocol_version")) {
            throw "Remote config is not compatible with PulseLab 1.4.0."
        }
        $response.Content | Set-Content $script:LOCAL_CONFIG -Encoding UTF8 -Force
        $script:Config = $remote
        $selectedRaw = $response.Content
        Write-PulseLog "INFO" "Remote config loaded and frozen for session. version=$($remote.version)"
    } catch {
        $script:Config = $local
        Write-PulseLog "WARN" "Remote config unavailable; using local snapshot. error=$($_.Exception.Message)"
    }

    if (-not $script:Config.questions -or -not $script:Config.interval_marks_minutes -or
        -not ($script:Config.PSObject.Properties.Name -contains "protocol_version")) {
        throw "Config version is incompatible with PulseLab 1.4.0."
    }

    $marks = [int[]]$script:Config.interval_marks_minutes
    if ($marks.Count -eq 0 -or ($marks | Where-Object { $_ -le 0 }).Count -gt 0) {
        throw "Checkpoint marks must be positive integers."
    }
    for ($index = 1; $index -lt $marks.Count; $index++) {
        if ($marks[$index] -le $marks[$index - 1]) {
            throw "Checkpoint marks must be strictly increasing."
        }
    }

    $script:ConfigHash = Get-Sha256Hex $selectedRaw
    $script:ActivityId = [string]$script:Config.activity_id
    Write-PulseLog "INFO" "Configuration frozen. hash=$($script:ConfigHash) protocol=$($script:Config.protocol_version)"
}

function Get-EnvCredentials {
    $urlName = [string]$script:Config.supabase_url_env_var
    $keyName = [string]$script:Config.supabase_key_env_var
    $script:SupabaseUrl = [Environment]::GetEnvironmentVariable($urlName, "User")
    $script:SupabaseKey = [Environment]::GetEnvironmentVariable($keyName, "User")

    if ([string]::IsNullOrWhiteSpace($script:SupabaseUrl) -or [string]::IsNullOrWhiteSpace($script:SupabaseKey)) {
        throw "Missing Supabase credentials. Run the installer first."
    }
}

function Get-SpikeWindowHandle {
    $process = Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -match 'SPIKE|Spike|LEGO Education'
    } | Select-Object -First 1

    if ($process) { return $process.MainWindowHandle }
    return [IntPtr]::Zero
}

function Restore-SpikeFocus {
    param([IntPtr]$Handle)
    if ($Handle -ne [IntPtr]::Zero) {
        [Win32]::SetForegroundWindow($Handle) | Out-Null
    }
}

function Get-ActiveTelemetry {
    $handle = [Win32]::GetForegroundWindow()
    [uint32]$processId = 0
    [Win32]::GetWindowThreadProcessId($handle, [ref]$processId) | Out-Null

    $processName = ""
    if ($processId -ne 0) {
        $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
        if ($process) { $processName = [string]$process.ProcessName }
    }

    $title = New-Object Text.StringBuilder 256
    [Win32]::GetWindowText($handle, $title, 256) | Out-Null
    $windowTitle = $title.ToString()
    $appCategory = if ($windowTitle -match 'SPIKE|Spike|LEGO Education' -or $processName -match 'SPIKE|Spike') {
        "spike"
    } elseif ([string]::IsNullOrWhiteSpace($processName)) {
        "unknown"
    } else {
        "other"
    }

    $lastInput = New-Object Win32+LASTINPUTINFO
    $lastInput.cbSize = [Runtime.InteropServices.Marshal]::SizeOf($lastInput)
    $idle = 0
    if ([Win32]::GetLastInputInfo([ref]$lastInput)) {
        $elapsed = [Environment]::TickCount - $lastInput.dwTime
        if ($elapsed -lt 0) { $elapsed = 0 }
        $idle = [Math]::Round($elapsed / 1000)
    }

    return @{
        # Minimize telemetry at the source. Raw window titles and application
        # names can expose unrelated personal information.
        WindowTitle = $null
        ForegroundApp = $appCategory
        IdleSeconds = $idle
    }
}

function Get-LastSpikeFileSize {
    $directory = Join-Path $env:USERPROFILE "Documents\LEGO SPIKE"
    if (-not (Test-Path $directory)) { return 0.0 }

    $file = Get-ChildItem $directory -Include *.llsp, *.spk -File -Recurse -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $file) { return 0.0 }
    return [Math]::Round($file.Length / 1KB, 2)
}

function Get-SpikeWindowCapture {
    param([string]$FilePath, [IntPtr]$Handle)

    if ($Handle -eq [IntPtr]::Zero) {
        Write-PulseLog "WARN" "SPIKE window not found; screenshot skipped."
        return $false
    }

    try {
        $rect = New-Object Win32+RECT
        if (-not [Win32]::GetWindowRect($Handle, [ref]$rect)) { return $false }
        $width = $rect.Right - $rect.Left
        $height = $rect.Bottom - $rect.Top
        if ($width -le 0 -or $height -le 0) { return $false }

        $bitmap = New-Object Drawing.Bitmap $width, $height
        $graphics = [Drawing.Graphics]::FromImage($bitmap)
        $graphics.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $bitmap.Size)

        $encoder = [Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() |
            Where-Object { $_.FormatID -eq [Drawing.Imaging.ImageFormat]::Jpeg.Guid } |
            Select-Object -First 1
        $parameters = New-Object Drawing.Imaging.EncoderParameters 1
        $parameters.Param[0] = New-Object Drawing.Imaging.EncoderParameter ([Drawing.Imaging.Encoder]::Quality), 60L
        $bitmap.Save($FilePath, $encoder, $parameters)

        $graphics.Dispose()
        $bitmap.Dispose()
        Write-PulseLog "INFO" "SPIKE window captured."
        return $true
    } catch {
        Write-PulseLog "ERROR" "SPIKE window capture failed: $($_.Exception.Message)"
        return $false
    }
}

# =============================================================================
# ENVIO E CACHE OFFLINE
# =============================================================================

function Upload-ScreenshotToSupabase {
    param([string]$LocalFilePath, [int]$IntervalMark)

    if ([string]::IsNullOrWhiteSpace($LocalFilePath) -or -not (Test-Path $LocalFilePath)) { return $null }

    $objectPath = "$($script:InstallationId)/$($script:WorkshopCode)/$($script:SessionId)/checkpoint-$IntervalMark.jpg"
    $endpoint = "$($script:SupabaseUrl)/storage/v1/object/screenshots/$objectPath"
    $headers = @{
        apikey = $script:SupabaseKey
        Authorization = "Bearer $($script:SupabaseKey)"
        "x-upsert" = "false"
    }

    try {
        $bytes = [IO.File]::ReadAllBytes($LocalFilePath)
        $timeout = if ($script:Config.PSObject.Properties.Name -contains "network_timeout_seconds") {
            [int]$script:Config.network_timeout_seconds
        } else {
            10
        }
        Invoke-RestMethod -Method Post -Uri $endpoint -Headers $headers -Body $bytes -ContentType "image/jpeg" -TimeoutSec $timeout -ErrorAction Stop | Out-Null
        return $objectPath
    } catch {
        $statusCode = $null
        if ($_.Exception.Response) { $statusCode = [int]$_.Exception.Response.StatusCode }
        if ($statusCode -eq 409) {
            Write-PulseLog "WARN" "Screenshot already exists; reusing private object path."
            return $objectPath
        }
        Write-PulseLog "ERROR" "Screenshot upload failed: $($_.Exception.Message)"
        return $null
    }
}

function Convert-ToSchemaPayload {
    param([hashtable]$Payload)
    $clean = @{}
    foreach ($key in $Payload.Keys) {
        if ($key -ne "local_screenshot_path" -and -not ([string]$key).StartsWith("_")) {
            $clean[$key] = $Payload[$key]
        }
    }
    return $clean
}

function Send-ResponseToSupabase {
    param([hashtable]$Payload)

    $clean = Convert-ToSchemaPayload $Payload
    $targetTable = if ($Payload.ContainsKey("_target_table")) {
        [string]$Payload["_target_table"]
    } elseif ($clean.ContainsKey("event_id")) {
        "research_events"
    } else {
        "responses"
    }
    $allowedTables = @("research_events", "research_session_events", "responses")
    if ($allowedTables -notcontains $targetTable) { throw "Unsupported Supabase target table: $targetTable" }

    $isIdempotent = $clean.ContainsKey("event_id")
    $endpoint = "$($script:SupabaseUrl)/rest/v1/$targetTable"
    if ($isIdempotent) { $endpoint += "?on_conflict=event_id" }
    $headers = @{
        apikey = $script:SupabaseKey
        Authorization = "Bearer $($script:SupabaseKey)"
        "Content-Type" = "application/json"
        Prefer = if ($isIdempotent) { "resolution=ignore-duplicates,return=minimal" } else { "return=minimal" }
    }

    try {
        $body = $clean | ConvertTo-Json -Depth 10 -Compress
        $timeout = if ($script:Config.PSObject.Properties.Name -contains "network_timeout_seconds") {
            [int]$script:Config.network_timeout_seconds
        } else {
            10
        }
        Invoke-RestMethod -Method Post -Uri $endpoint -Headers $headers -Body $body -TimeoutSec $timeout -ErrorAction Stop | Out-Null
        return $true
    } catch {
        Write-PulseLog "ERROR" "Database submission failed: $($_.Exception.Message)"
        return $false
    }
}

function Add-ToLocalQueue {
    param([hashtable]$Payload)
    try {
        $queue = @()
        if (Test-Path $script:OFFLINE_CACHE_FILE) {
            $raw = Get-Content $script:OFFLINE_CACHE_FILE -Raw -Encoding UTF8
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $existing = $raw | ConvertFrom-Json
                $queue = if ($existing -is [array]) { $existing } else { @($existing) }
            }
        }
        $queue += New-Object PSCustomObject -Property $Payload
        $queue | ConvertTo-Json -Depth 10 | Set-Content $script:OFFLINE_CACHE_FILE -Encoding UTF8 -Force
        Write-PulseLog "WARN" "Event cached offline. count=$($queue.Count)"
    } catch {
        Write-PulseLog "ERROR" "Could not cache event: $($_.Exception.Message)"
    }
}

function Submit-Event {
    param([hashtable]$Payload)

    $localScreenshot = if ($Payload.ContainsKey("local_screenshot_path")) {
        [string]$Payload["local_screenshot_path"]
    } else {
        $null
    }
    $remoteScreenshot = if ($Payload.ContainsKey("screenshot_path")) {
        [string]$Payload["screenshot_path"]
    } else {
        $null
    }

    # Preserve the database row and its visual evidence as one delivery unit.
    # If Storage is temporarily unavailable but PostgREST is online, sending
    # the row now would orphan the local screenshot permanently.
    if (-not [string]::IsNullOrWhiteSpace($localScreenshot) -and
        [string]::IsNullOrWhiteSpace($remoteScreenshot) -and
        (Test-Path $localScreenshot)) {
        Add-ToLocalQueue $Payload
        return
    }

    if (-not (Send-ResponseToSupabase $Payload)) { Add-ToLocalQueue $Payload }
}

function Invoke-FlushCache {
    if (-not (Test-Path $script:OFFLINE_CACHE_FILE)) { return }
    try {
        $raw = Get-Content $script:OFFLINE_CACHE_FILE -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) { return }
        $items = $raw | ConvertFrom-Json
        if (-not ($items -is [array])) { $items = @($items) }

        $remaining = @()
        $uploadedScreenshots = @{}
        $filesToRemove = @()
        foreach ($item in $items) {
            $payload = @{}
            $item.PSObject.Properties | ForEach-Object { $payload[$_.Name] = $_.Value }

            $localPath = $payload["local_screenshot_path"]
            if (-not [string]::IsNullOrWhiteSpace([string]$localPath) -and $uploadedScreenshots.ContainsKey([string]$localPath)) {
                $payload["screenshot_path"] = $uploadedScreenshots[[string]$localPath]
                $payload["local_screenshot_path"] = $null
            } elseif ($payload.ContainsKey("screenshot_path") -and [string]::IsNullOrWhiteSpace([string]$payload["screenshot_path"]) -and
                -not [string]::IsNullOrWhiteSpace([string]$localPath) -and (Test-Path $localPath)) {
                $objectPath = Upload-ScreenshotToSupabase $localPath ([int]$payload["interval_mark"])
                if (-not $objectPath) {
                    # Preserve the event and its local evidence together. Sending
                    # the row now with a null screenshot_path would silently lose
                    # the visual modality while leaving an orphan file on disk.
                    $remaining += $item
                    continue
                }
                $payload["screenshot_path"] = $objectPath
                $payload["local_screenshot_path"] = $null
                $uploadedScreenshots[[string]$localPath] = $objectPath
                $filesToRemove += [string]$localPath
            }

            if (-not (Send-ResponseToSupabase $payload)) {
                $remaining += New-Object PSCustomObject -Property $payload
            }
        }

        $filesToRemove | Select-Object -Unique | ForEach-Object {
            Remove-Item $_ -Force -ErrorAction SilentlyContinue
        }

        if ($remaining.Count -eq 0) {
            Remove-Item $script:OFFLINE_CACHE_FILE -Force -ErrorAction SilentlyContinue
        } else {
            $remaining | ConvertTo-Json -Depth 10 | Set-Content $script:OFFLINE_CACHE_FILE -Encoding UTF8 -Force
        }
    } catch {
        Write-PulseLog "ERROR" "Cache flush failed: $($_.Exception.Message)"
    }
}

function New-ResearchEvent {
    param(
        [string]$ParticipantId,
        [ValidateSet("computer", "assembly")][string]$Role,
        [ValidateSet("pre", "checkpoint", "post")][string]$EventType,
        [Nullable[int]]$IntervalMark
    )

    $event = @{
        _target_table = "research_events"
        event_id = [Guid]::NewGuid().ToString()
        session_id = $script:SessionId
        dyad_id = $script:DyadId
        installation_id = $script:InstallationId
        site_id = $script:SiteId
        participant_id = $ParticipantId
        participant_role = $Role
        event_type = $EventType
        response_status = "completed"
        interval_mark = $null
        regional_hub = $script:RegionalHub
        school_code = $script:SchoolCode
        workshop_code = $script:WorkshopCode
        class_code = $script:ClassCode
        grade_band = $script:GradeBand
        activity_id = $script:ActivityId
        computer_id = $script:ComputerId
        protocol_version = [string]$script:Config.protocol_version
        config_version = [string]$script:Config.version
        config_hash = $script:ConfigHash
        client_version = $script:VERSION
        occurred_at = [DateTimeOffset]::Now.ToString("o")
    }
    if ($null -ne $IntervalMark) { $event["interval_mark"] = [int]$IntervalMark }
    return $event
}

function Get-CheckpointStage {
    param([int]$Mark)

    if (-not ($script:Config.PSObject.Properties.Name -contains "checkpoint_stages") -or
        -not $script:Config.checkpoint_stages) {
        return $null
    }

    $property = $script:Config.checkpoint_stages.PSObject.Properties |
        Where-Object { $_.Name -eq [string]$Mark } |
        Select-Object -First 1
    if ($property) { return [string]$property.Value }
    return $null
}

function New-SessionEvent {
    param(
        [ValidateSet(
            "session_started", "phase_completed", "activity_started", "heartbeat",
            "checkpoint_started", "checkpoint_completed", "help_requested",
            "role_swapped", "ending_requested", "rubric_completed",
            "session_completed", "session_aborted", "quality_issue"
        )]
        [string]$EventType,
        [ValidateSet("info", "warning", "error")]
        [string]$Severity = "info",
        [Nullable[int]]$IntervalMark = $null,
        [string]$ParticipantId = $null,
        [string]$ParticipantRole = $null,
        [string]$ActivityStage = $null,
        [Nullable[long]]$ElapsedMs = $null,
        [Nullable[DateTimeOffset]]$ScheduledAt = $null,
        [hashtable]$Details = @{}
    )

    $event = @{
        _target_table = "research_session_events"
        event_id = [Guid]::NewGuid().ToString()
        session_id = $script:SessionId
        dyad_id = $script:DyadId
        installation_id = $script:InstallationId
        site_id = $script:SiteId
        regional_hub = $script:RegionalHub
        school_code = $script:SchoolCode
        workshop_code = $script:WorkshopCode
        class_code = $script:ClassCode
        grade_band = $script:GradeBand
        activity_id = $script:ActivityId
        computer_id = $script:ComputerId
        protocol_version = [string]$script:Config.protocol_version
        config_version = [string]$script:Config.version
        config_hash = $script:ConfigHash
        client_version = $script:VERSION
        event_type = $EventType
        severity = $Severity
        interval_mark = $null
        participant_id = $null
        participant_role = $null
        activity_stage = $ActivityStage
        elapsed_ms = $null
        scheduled_at = $null
        occurred_at = [DateTimeOffset]::Now.ToString("o")
        details = $Details
    }

    if ($null -ne $IntervalMark) { $event["interval_mark"] = [int]$IntervalMark }
    if (-not [string]::IsNullOrWhiteSpace($ParticipantId)) { $event["participant_id"] = $ParticipantId }
    if (-not [string]::IsNullOrWhiteSpace($ParticipantRole)) { $event["participant_role"] = $ParticipantRole }
    if ($null -ne $ElapsedMs) { $event["elapsed_ms"] = [long]$ElapsedMs }
    if ($null -ne $ScheduledAt) {
        $event["scheduled_at"] = ([DateTimeOffset]$ScheduledAt).ToString("o")
    }
    return $event
}

function Submit-SessionEvent {
    param(
        [string]$EventType,
        [string]$Severity = "info",
        [Nullable[int]]$IntervalMark = $null,
        [string]$ParticipantId = $null,
        [string]$ParticipantRole = $null,
        [string]$ActivityStage = $null,
        [Nullable[long]]$ElapsedMs = $null,
        [Nullable[DateTimeOffset]]$ScheduledAt = $null,
        [hashtable]$Details = @{}
    )

    $event = New-SessionEvent $EventType $Severity $IntervalMark $ParticipantId $ParticipantRole $ActivityStage $ElapsedMs $ScheduledAt $Details
    Submit-Event $event
}

# =============================================================================
# INTERFACES WPF
# =============================================================================

function Show-WpfSessionSetup {
    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Title="PulseLab - Contexto da oficina"
        Width="540" Height="790" WindowStartupLocation="CenterScreen" WindowStyle="None"
        AllowsTransparency="True" Background="Transparent" Topmost="True">
  <Border CornerRadius="22" Background="#171128" BorderBrush="#6D5BD0" BorderThickness="3" Padding="26">
    <Grid>
      <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
      <StackPanel Grid.Row="0" Margin="0,0,0,18">
        <TextBlock Text="PULSELAB · CONTEXTO DA OFICINA" Foreground="#A99AF5" FontSize="20" FontWeight="Bold"/>
        <TextBlock Text="Use apenas códigos institucionais. Não digite nomes de estudantes." Foreground="#D1CCE2" FontSize="13" TextWrapping="Wrap" Margin="0,7,0,0"/>
      </StackPanel>
      <StackPanel Grid.Row="1">
        <TextBlock Text="Código da sede" Foreground="White" FontWeight="Bold"/>
        <TextBox Name="TxtSite" Height="36" Margin="0,5,0,10" Padding="8" FontSize="14"/>
        <TextBlock Text="Polo ou regional" Foreground="White" FontWeight="Bold"/>
        <TextBox Name="TxtRegional" Height="36" Margin="0,5,0,10" Padding="8" FontSize="14"/>
        <TextBlock Text="Código da escola" Foreground="White" FontWeight="Bold"/>
        <TextBox Name="TxtSchool" Height="36" Margin="0,5,0,10" Padding="8" FontSize="14"/>
        <TextBlock Text="Código desta oficina" Foreground="White" FontWeight="Bold"/>
        <TextBox Name="TxtWorkshop" Height="36" Margin="0,5,0,10" Padding="8" FontSize="14"/>
        <TextBlock Text="Código da turma" Foreground="White" FontWeight="Bold"/>
        <TextBox Name="TxtClass" Height="36" Margin="0,5,0,10" Padding="8" FontSize="14"/>
        <TextBlock Text="Ano ou faixa escolar" Foreground="White" FontWeight="Bold"/>
        <TextBox Name="TxtGrade" Height="36" Margin="0,5,0,10" Padding="8" FontSize="14"/>
        <TextBlock Text="Código da atividade" Foreground="White" FontWeight="Bold"/>
        <TextBox Name="TxtActivity" Height="36" Margin="0,5,0,10" Padding="8" FontSize="14"/>
        <Border Background="#27203D" CornerRadius="10" Padding="12" Margin="0,8,0,0">
          <TextBlock Text="Sede, regional e escola ficam associados a esta instalação. Os participantes recebem códigos temporários A e B." Foreground="#C9C3D8" TextWrapping="Wrap" FontSize="12"/>
        </Border>
        <CheckBox Name="ChkConsent" Content="Confirmo que a equipe verificou as autorizações e o consentimento aplicáveis para esta dupla." Foreground="White" FontSize="12" Margin="0,14,0,0"/>
      </StackPanel>
      <Button Name="BtnStart" Grid.Row="2" Content="Confirmar e iniciar" Height="48" Background="#6D5BD0" Foreground="White" FontSize="16" FontWeight="Bold" IsEnabled="False"/>
    </Grid>
  </Border>
</Window>
"@
    $window = [Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader ([xml]$xaml)))
    $site = $window.FindName("TxtSite")
    $regional = $window.FindName("TxtRegional")
    $school = $window.FindName("TxtSchool")
    $workshop = $window.FindName("TxtWorkshop")
    $class = $window.FindName("TxtClass")
    $grade = $window.FindName("TxtGrade")
    $activity = $window.FindName("TxtActivity")
    $consent = $window.FindName("ChkConsent")
    $button = $window.FindName("BtnStart")
    $site.Text = $script:SiteId
    $regional.Text = $script:RegionalHub
    $school.Text = $script:SchoolCode
    $workshop.Text = [string]$script:Config.workshop_code
    $class.Text = [string]$script:Config.class_code
    $grade.Text = [string]$script:Config.grade_band
    $activity.Text = [string]$script:Config.activity_id

    $validate = {
        $values = @(
            $site.Text.Trim(), $regional.Text.Trim(), $school.Text.Trim(),
            $workshop.Text.Trim(), $class.Text.Trim(), $activity.Text.Trim()
        )
        $button.IsEnabled = (($values | Where-Object { [string]::IsNullOrWhiteSpace($_) -or $_ -match '^CONFIGURE_' }).Count -eq 0 -and $consent.IsChecked -eq $true)
    }
    $site.add_TextChanged($validate); $regional.add_TextChanged($validate); $school.add_TextChanged($validate)
    $workshop.add_TextChanged($validate); $class.add_TextChanged($validate); $activity.add_TextChanged($validate)
    $consent.add_Checked($validate); $consent.add_Unchecked($validate)
    & $validate

    $button.add_Click({
        $script:SiteId = $site.Text.Trim()
        $script:RegionalHub = $regional.Text.Trim()
        $script:SchoolCode = $school.Text.Trim()
        $script:WorkshopCode = $workshop.Text.Trim()
        $script:ClassCode = $class.Text.Trim()
        $script:GradeBand = $grade.Text.Trim()
        $script:ActivityId = $activity.Text.Trim()
        Save-InstallationProfile
        $window.DialogResult = $true
        $window.Close()
    })
    return ($window.ShowDialog() -eq $true)
}

function Show-WpfAssent {
    param([string]$RoleLabel)
    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Title="PulseLab - Convite para participar"
        Width="570" Height="430" WindowStartupLocation="CenterScreen" WindowStyle="None"
        AllowsTransparency="True" Background="Transparent" Topmost="True">
  <Border CornerRadius="22" Background="#15102A" BorderBrush="#57E0D5" BorderThickness="3" Padding="28">
    <Grid>
      <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
      <StackPanel Grid.Row="0">
        <TextBlock Text="CONVITE PARA A PESQUISA" Foreground="#57E0D5" FontSize="22" FontWeight="Bold"/>
        <TextBlock Text="$RoleLabel" Foreground="White" FontSize="16" Margin="0,7,0,0"/>
      </StackPanel>
      <StackPanel Grid.Row="1" VerticalAlignment="Center">
        <TextBlock Text="Durante a oficina, o PulseLab fará perguntas curtas e registrará sinais do computador, como uso do SPIKE, tempo sem mexer e imagens da janela do projeto quando autorizadas. Você pode escolher participar ou não." Foreground="White" FontSize="15" TextWrapping="Wrap" Margin="0,0,0,14"/>
        <TextBlock Text="Se escolher não participar, você continuará fazendo a oficina normalmente. Isso não muda sua nota, seu atendimento ou sua participação na aula." Foreground="#D2CCDF" FontSize="14" TextWrapping="Wrap"/>
      </StackPanel>
      <Grid Grid.Row="2">
        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="12"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
        <Button Name="BtnNo" Grid.Column="0" Content="Não quero participar" Height="48" Background="#3B344B" Foreground="White"/>
        <Button Name="BtnYes" Grid.Column="2" Content="Quero participar" Height="48" Background="#00A7A0" Foreground="White" FontWeight="Bold"/>
      </Grid>
    </Grid>
  </Border>
</Window>
"@
    $window = [Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader ([xml]$xaml)))
    # Use a mutable object because WPF event handlers execute in a child
    # scope; assigning a captured scalar there would not reliably update the
    # value returned by this function on PowerShell 5.1.
    $result = @{ Accepted = $false }
    $window.FindName("BtnYes").add_Click({ $result.Accepted = $true; $window.DialogResult = $true; $window.Close() })
    $window.FindName("BtnNo").add_Click({ $result.Accepted = $false; $window.DialogResult = $false; $window.Close() })
    $window.ShowDialog() | Out-Null
    return [bool]$result.Accepted
}

function Show-WpfPreSurvey {
    param([string]$RoleLabel)
    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Title="PulseLab - Antes da oficina"
        Width="610" Height="570" WindowStartupLocation="CenterScreen" WindowStyle="None"
        AllowsTransparency="True" Background="Transparent" Topmost="True">
  <Border CornerRadius="22" Background="#15102A" BorderBrush="#00A7A0" BorderThickness="3" Padding="26">
    <Grid>
      <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
      <StackPanel Grid.Row="0" Margin="0,0,0,15">
        <TextBlock Text="ANTES DE COMEÇAR" Foreground="#57E0D5" FontSize="23" FontWeight="Bold"/>
        <TextBlock Text="$RoleLabel" Foreground="White" FontSize="16" Margin="0,5,0,0"/>
        <TextBlock Text="Responda sozinho. Sua resposta não será mostrada à sua dupla." Foreground="#BDB8D0" FontSize="12" Margin="0,5,0,0"/>
      </StackPanel>
      <StackPanel Grid.Row="1">
        <TextBlock Text="$($script:Config.questions.prior_robotics)" Foreground="White" FontSize="15" FontWeight="Bold" TextWrapping="Wrap"/>
        <StackPanel Margin="10,8,0,20">
          <RadioButton Name="Prior1" GroupName="Prior" Content="Nunca" Foreground="White" Margin="0,4"/>
          <RadioButton Name="Prior2" GroupName="Prior" Content="Uma vez" Foreground="White" Margin="0,4"/>
          <RadioButton Name="Prior3" GroupName="Prior" Content="Algumas vezes" Foreground="White" Margin="0,4"/>
          <RadioButton Name="Prior4" GroupName="Prior" Content="Muitas vezes" Foreground="White" Margin="0,4"/>
        </StackPanel>
        <TextBlock Text="$($script:Config.questions.self_efficacy)" Foreground="White" FontSize="15" FontWeight="Bold" TextWrapping="Wrap"/>
        <StackPanel Margin="10,8,0,0">
          <RadioButton Name="Self1" GroupName="Self" Content="Discordo muito" Foreground="White" Margin="0,4"/>
          <RadioButton Name="Self2" GroupName="Self" Content="Discordo" Foreground="White" Margin="0,4"/>
          <RadioButton Name="Self3" GroupName="Self" Content="Concordo" Foreground="White" Margin="0,4"/>
          <RadioButton Name="Self4" GroupName="Self" Content="Concordo muito" Foreground="White" Margin="0,4"/>
        </StackPanel>
      </StackPanel>
      <Grid Grid.Row="2">
        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="10"/><ColumnDefinition Width="2*"/></Grid.ColumnDefinitions>
        <Button Name="BtnSkip" Grid.Column="0" Content="Prefiro não responder" Height="46" Background="#3B344B" Foreground="White"/>
        <Button Name="BtnSave" Grid.Column="2" Content="Salvar minha resposta" Height="46" Background="#00A7A0" Foreground="White" FontWeight="Bold" IsEnabled="False"/>
      </Grid>
    </Grid>
  </Border>
</Window>
"@
    $window = [Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader ([xml]$xaml)))
    $prior = 1..4 | ForEach-Object { $window.FindName("Prior$_") }
    $self = 1..4 | ForEach-Object { $window.FindName("Self$_") }
    $button = $window.FindName("BtnSave")
    $skip = $window.FindName("BtnSkip")
    $result = @{ Status = $false; Declined = $false; PriorRobotics = $null; SelfEfficacy = $null; LatencyMs = 0 }
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $validate = {
        $button.IsEnabled = (($prior | Where-Object { $_.IsChecked -eq $true }).Count -eq 1 -and ($self | Where-Object { $_.IsChecked -eq $true }).Count -eq 1)
    }
    @($prior + $self) | ForEach-Object { $_.add_Checked($validate) }
    $button.add_Click({
        for ($i = 0; $i -lt 4; $i++) {
            if ($prior[$i].IsChecked) { $result.PriorRobotics = $i + 1 }
            if ($self[$i].IsChecked) { $result.SelfEfficacy = $i + 1 }
        }
        $result.Status = $true
        $result.LatencyMs = [int]$watch.ElapsedMilliseconds
        $window.Close()
    })
    $skip.add_Click({ $result.Declined = $true; $result.LatencyMs = [int]$watch.ElapsedMilliseconds; $window.Close() })
    $window.ShowDialog() | Out-Null
    $watch.Stop()
    return $result
}

function Show-WpfCheckpoint {
    param([string]$RoleLabel, [int]$IntervalMark, [bool]$AskCollaboration)
    $collabVisibility = if ($AskCollaboration) { "Visible" } else { "Collapsed" }
    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Title="PulseLab - Checkpoint"
        Width="650" Height="720" WindowStartupLocation="CenterScreen" WindowStyle="None"
        AllowsTransparency="True" Background="Transparent" Topmost="True">
  <Border CornerRadius="22" Background="#15102A" BorderBrush="#FF686B" BorderThickness="3" Padding="26">
    <Grid>
      <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
      <StackPanel Grid.Row="0" Margin="0,0,0,14">
        <TextBlock Text="CHECKPOINT · $IntervalMark MIN" Foreground="#FF8B8E" FontSize="22" FontWeight="Bold"/>
        <TextBlock Text="$RoleLabel" Foreground="White" FontSize="16" Margin="0,5,0,0"/>
        <TextBlock Text="Responda sozinho. Depois, passe o computador para sua dupla." Foreground="#BDB8D0" FontSize="12" Margin="0,5,0,0"/>
      </StackPanel>
      <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
        <StackPanel>
          <TextBlock Text="$($script:Config.questions.mental_effort)" Foreground="White" FontSize="15" FontWeight="Bold" TextWrapping="Wrap"/>
          <StackPanel Margin="10,7,0,17">
            <RadioButton Name="Effort1" GroupName="Effort" Content="Muito pouco" Foreground="White" Margin="0,3"/>
            <RadioButton Name="Effort2" GroupName="Effort" Content="Pouco" Foreground="White" Margin="0,3"/>
            <RadioButton Name="Effort3" GroupName="Effort" Content="Bastante" Foreground="White" Margin="0,3"/>
            <RadioButton Name="Effort4" GroupName="Effort" Content="Muito" Foreground="White" Margin="0,3"/>
          </StackPanel>
          <TextBlock Text="$($script:Config.questions.progress_state)" Foreground="White" FontSize="15" FontWeight="Bold" TextWrapping="Wrap"/>
          <StackPanel Margin="10,7,0,17">
            <RadioButton Name="Progress1" GroupName="Progress" Content="Avançando sem ajuda" Foreground="White" Margin="0,3"/>
            <RadioButton Name="Progress2" GroupName="Progress" Content="Avançando, mas com dúvida" Foreground="White" Margin="0,3"/>
            <RadioButton Name="Progress3" GroupName="Progress" Content="Tentando, mas sem conseguir avançar" Foreground="White" Margin="0,3"/>
            <RadioButton Name="Progress4" GroupName="Progress" Content="Precisamos de ajuda agora" Foreground="#FFB5B6" FontWeight="Bold" Margin="0,3"/>
          </StackPanel>
          <StackPanel Name="CollabPanel" Visibility="$collabVisibility">
            <TextBlock Text="$($script:Config.questions.collaboration)" Foreground="White" FontSize="15" FontWeight="Bold" TextWrapping="Wrap"/>
            <StackPanel Margin="10,7,0,12">
              <RadioButton Name="Collab1" GroupName="Collab" Content="Nunca" Foreground="White" Margin="0,3"/>
              <RadioButton Name="Collab2" GroupName="Collab" Content="Algumas vezes" Foreground="White" Margin="0,3"/>
              <RadioButton Name="Collab3" GroupName="Collab" Content="Quase sempre" Foreground="White" Margin="0,3"/>
              <RadioButton Name="Collab4" GroupName="Collab" Content="Sempre" Foreground="White" Margin="0,3"/>
            </StackPanel>
          </StackPanel>
        </StackPanel>
      </ScrollViewer>
      <Grid Grid.Row="2" Margin="0,12,0,0">
        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="10"/><ColumnDefinition Width="2*"/></Grid.ColumnDefinitions>
        <Button Name="BtnSkip" Grid.Column="0" Content="Prefiro não responder" Height="46" Background="#3B344B" Foreground="White"/>
        <Button Name="BtnSave" Grid.Column="2" Content="Salvar minha resposta" Height="46" Background="#FF686B" Foreground="White" FontWeight="Bold" IsEnabled="False"/>
      </Grid>
    </Grid>
  </Border>
</Window>
"@
    $window = [Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader ([xml]$xaml)))
    $effort = 1..4 | ForEach-Object { $window.FindName("Effort$_") }
    $progress = 1..4 | ForEach-Object { $window.FindName("Progress$_") }
    $collab = 1..4 | ForEach-Object { $window.FindName("Collab$_") }
    $button = $window.FindName("BtnSave")
    $skip = $window.FindName("BtnSkip")
    $result = @{ Status = $false; Declined = $false; MentalEffort = $null; ProgressState = $null; Collaboration = $null; LatencyMs = 0 }
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $validate = {
        $baseComplete = (($effort | Where-Object { $_.IsChecked -eq $true }).Count -eq 1 -and ($progress | Where-Object { $_.IsChecked -eq $true }).Count -eq 1)
        $collabComplete = (-not $AskCollaboration -or ($collab | Where-Object { $_.IsChecked -eq $true }).Count -eq 1)
        $button.IsEnabled = ($baseComplete -and $collabComplete)
    }
    @($effort + $progress + $collab) | ForEach-Object { $_.add_Checked($validate) }
    $button.add_Click({
        for ($i = 0; $i -lt 4; $i++) {
            if ($effort[$i].IsChecked) { $result.MentalEffort = $i + 1 }
            if ($progress[$i].IsChecked) {
                $result.ProgressState = @('progressing_independently','progressing_with_doubt','trying_without_progress','needs_help_now')[$i]
            }
            if ($AskCollaboration -and $collab[$i].IsChecked) { $result.Collaboration = $i + 1 }
        }
        $result.Status = $true
        $result.LatencyMs = [int]$watch.ElapsedMilliseconds
        $window.Close()
    })
    $skip.add_Click({ $result.Declined = $true; $result.LatencyMs = [int]$watch.ElapsedMilliseconds; $window.Close() })

    $timer = New-Object Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromSeconds([int]$script:Config.timeout_seconds)
    $timer.add_Tick({ $timer.Stop(); $result.LatencyMs = [int]$watch.ElapsedMilliseconds; $window.Close() })
    $timer.Start(); $window.ShowDialog() | Out-Null; $timer.Stop(); $watch.Stop()
    return $result
}

function Show-WpfRoleSwap {
    param([string]$ParticipantALabel, [string]$ParticipantBLabel)

    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Title="PulseLab - Troca de papéis"
        Width="560" Height="360" WindowStartupLocation="CenterScreen" WindowStyle="None"
        AllowsTransparency="True" Background="Transparent" Topmost="True">
  <Border CornerRadius="22" Background="#15102A" BorderBrush="#FFD166" BorderThickness="3" Padding="28">
    <Grid>
      <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
      <StackPanel Grid.Row="0">
        <TextBlock Text="TROQUEM OS PAPÉIS" Foreground="#FFD166" FontSize="23" FontWeight="Bold"/>
        <TextBlock Text="A troca ajuda as duas pessoas a experimentar partes diferentes da atividade." Foreground="#D2CCDF" FontSize="13" TextWrapping="Wrap" Margin="0,7,0,0"/>
      </StackPanel>
      <StackPanel Grid.Row="1" VerticalAlignment="Center">
        <TextBlock Text="$ParticipantALabel" Foreground="White" FontSize="16" FontWeight="Bold" Margin="0,5"/>
        <TextBlock Text="$ParticipantBLabel" Foreground="White" FontSize="16" FontWeight="Bold" Margin="0,5"/>
      </StackPanel>
      <Button Name="BtnConfirm" Grid.Row="2" Content="Papéis trocados · continuar" Height="48" Background="#B78600" Foreground="White" FontWeight="Bold"/>
    </Grid>
  </Border>
</Window>
"@
    $window = [Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader ([xml]$xaml)))
    $window.FindName("BtnConfirm").add_Click({
        $window.DialogResult = $true
        $window.Close()
    })
    return ($window.ShowDialog() -eq $true)
}

function Show-WpfInstructorRubric {
    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Title="PulseLab - Registro do instrutor"
        Width="560" Height="500" WindowStartupLocation="CenterScreen" Topmost="True">
  <Grid Margin="26">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <StackPanel Grid.Row="0" Margin="0,0,0,18">
      <TextBlock Text="REGISTRO DO INSTRUTOR" Foreground="#4C35A3" FontSize="22" FontWeight="Bold"/>
      <TextBlock Text="Avalie a dupla antes de chamar os participantes para o encerramento." Foreground="#555" TextWrapping="Wrap"/>
    </StackPanel>
    <StackPanel Grid.Row="1">
      <TextBlock Text="Desempenho da missão" FontWeight="Bold"/>
      <ComboBox Name="Mission" Height="36" Margin="0,6,0,16">
        <ComboBoxItem Content="0 · Não executou a missão"/><ComboBoxItem Content="1 · Executou parcialmente"/>
        <ComboBoxItem Content="2 · Concluiu com muita ajuda"/><ComboBoxItem Content="3 · Concluiu com pouca ou nenhuma ajuda"/>
      </ComboBox>
      <TextBlock Text="Quantidade aproximada de intervenções" FontWeight="Bold"/>
      <ComboBox Name="Interventions" Height="36" Margin="0,6,0,16">
        <ComboBoxItem Content="0"/><ComboBoxItem Content="1"/><ComboBoxItem Content="2"/><ComboBoxItem Content="3 ou mais"/>
      </ComboBox>
      <TextBlock Text="Principal dificuldade observada" FontWeight="Bold"/>
      <ComboBox Name="Issue" Height="36" Margin="0,6,0,16">
        <ComboBoxItem Content="Nenhuma"/><ComboBoxItem Content="Montagem"/><ComboBoxItem Content="Lógica de programação"/>
        <ComboBoxItem Content="Sensor"/><ComboBoxItem Content="Problema técnico"/><ComboBoxItem Content="Colaboração"/><ComboBoxItem Content="Outra"/>
      </ComboBox>
    </StackPanel>
    <Button Name="BtnSave" Grid.Row="2" Content="Salvar avaliação da dupla" Height="44" Background="#4C35A3" Foreground="White" IsEnabled="False"/>
  </Grid>
</Window>
"@
    $window = [Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader ([xml]$xaml)))
    $mission = $window.FindName("Mission"); $interventions = $window.FindName("Interventions"); $issue = $window.FindName("Issue")
    $button = $window.FindName("BtnSave")
    $result = @{ Status = $false; Mission = $null; Interventions = $null; Issue = $null }
    $validate = { $button.IsEnabled = ($mission.SelectedIndex -ge 0 -and $interventions.SelectedIndex -ge 0 -and $issue.SelectedIndex -ge 0) }
    $mission.add_SelectionChanged($validate); $interventions.add_SelectionChanged($validate); $issue.add_SelectionChanged($validate)
    $button.add_Click({
        $result.Mission = $mission.SelectedIndex
        $result.Interventions = $interventions.SelectedIndex
        $result.Issue = @('none','assembly','logic','sensor','technical','collaboration','other')[$issue.SelectedIndex]
        $result.Status = $true
        $window.DialogResult = $true
        $window.Close()
    })
    $window.ShowDialog() | Out-Null
    return $result
}

function Show-WpfPostSurvey {
    param([string]$RoleLabel)
    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Title="PulseLab - Encerramento"
        Width="660" Height="710" WindowStartupLocation="CenterScreen" WindowStyle="None"
        AllowsTransparency="True" Background="Transparent" Topmost="True">
  <Border CornerRadius="22" Background="#171128" BorderBrush="#8B62E8" BorderThickness="3" Padding="26">
    <Grid>
      <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
      <StackPanel Grid.Row="0" Margin="0,0,0,14">
        <TextBlock Text="ENCERRAMENTO" Foreground="#B9A0FF" FontSize="23" FontWeight="Bold"/>
        <TextBlock Text="$RoleLabel" Foreground="White" FontSize="16" Margin="0,5,0,0"/>
        <TextBlock Text="Responda sozinho. Não existem respostas certas ou erradas." Foreground="#BDB8D0" FontSize="12"/>
      </StackPanel>
      <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
        <StackPanel>
          <TextBlock Text="$($script:Config.questions.post_understanding)" Foreground="White" FontSize="15" FontWeight="Bold" TextWrapping="Wrap"/>
          <StackPanel Margin="10,7,0,17">
            <RadioButton Name="Understand1" GroupName="Understand" Content="Discordo muito" Foreground="White" Margin="0,3"/>
            <RadioButton Name="Understand2" GroupName="Understand" Content="Discordo" Foreground="White" Margin="0,3"/>
            <RadioButton Name="Understand3" GroupName="Understand" Content="Concordo" Foreground="White" Margin="0,3"/>
            <RadioButton Name="Understand4" GroupName="Understand" Content="Concordo muito" Foreground="White" Margin="0,3"/>
          </StackPanel>
          <TextBlock Text="$($script:Config.questions.post_affect)" Foreground="White" FontSize="15" FontWeight="Bold" TextWrapping="Wrap"/>
          <UniformGrid Columns="2" Margin="10,7,0,5">
            <CheckBox Name="AffectCurious" Content="Curioso" Foreground="White" Margin="0,4"/>
            <CheckBox Name="AffectConfident" Content="Confiante" Foreground="White" Margin="0,4"/>
            <CheckBox Name="AffectExcited" Content="Animado" Foreground="White" Margin="0,4"/>
            <CheckBox Name="AffectFrustrated" Content="Frustrado" Foreground="White" Margin="0,4"/>
            <CheckBox Name="AffectTired" Content="Cansado" Foreground="White" Margin="0,4"/>
            <CheckBox Name="AffectIndifferent" Content="Indiferente" Foreground="White" Margin="0,4"/>
          </UniformGrid>
          <TextBlock Name="AffectHint" Text="Escolha uma ou duas opções." Foreground="#BDB8D0" FontSize="12" Margin="10,0,0,17"/>
          <TextBlock Text="$($script:Config.questions.post_return)" Foreground="White" FontSize="15" FontWeight="Bold" TextWrapping="Wrap"/>
          <StackPanel Margin="10,7,0,10">
            <RadioButton Name="Return1" GroupName="Return" Content="Não" Foreground="White" Margin="0,3"/>
            <RadioButton Name="Return2" GroupName="Return" Content="Talvez não" Foreground="White" Margin="0,3"/>
            <RadioButton Name="Return3" GroupName="Return" Content="Talvez sim" Foreground="White" Margin="0,3"/>
            <RadioButton Name="Return4" GroupName="Return" Content="Sim" Foreground="White" Margin="0,3"/>
          </StackPanel>
        </StackPanel>
      </ScrollViewer>
      <Grid Grid.Row="2" Margin="0,12,0,0">
        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="10"/><ColumnDefinition Width="2*"/></Grid.ColumnDefinitions>
        <Button Name="BtnSkip" Grid.Column="0" Content="Prefiro não responder" Height="46" Background="#3B344B" Foreground="White"/>
        <Button Name="BtnSave" Grid.Column="2" Content="Salvar e concluir" Height="46" Background="#8B62E8" Foreground="White" FontWeight="Bold" IsEnabled="False"/>
      </Grid>
    </Grid>
  </Border>
</Window>
"@
    $window = [Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader ([xml]$xaml)))
    $understand = 1..4 | ForEach-Object { $window.FindName("Understand$_") }
    $returns = 1..4 | ForEach-Object { $window.FindName("Return$_") }
    $affects = @(
        @{ Box = $window.FindName("AffectCurious"); Value = 'curious' },
        @{ Box = $window.FindName("AffectConfident"); Value = 'confident' },
        @{ Box = $window.FindName("AffectExcited"); Value = 'excited' },
        @{ Box = $window.FindName("AffectFrustrated"); Value = 'frustrated' },
        @{ Box = $window.FindName("AffectTired"); Value = 'tired' },
        @{ Box = $window.FindName("AffectIndifferent"); Value = 'indifferent' }
    )
    $hint = $window.FindName("AffectHint"); $button = $window.FindName("BtnSave")
    $skip = $window.FindName("BtnSkip")
    $result = @{ Status = $false; Declined = $false; Understanding = $null; Affects = @(); ReturnIntent = $null; LatencyMs = 0 }
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $validate = {
        $affectCount = @($affects | Where-Object { $_.Box.IsChecked -eq $true }).Count
        $hint.Text = if ($affectCount -gt 2) { "Escolha no máximo duas opções." } else { "Escolha uma ou duas opções." }
        $hint.Foreground = if ($affectCount -gt 2) { "#FF9B9D" } else { "#BDB8D0" }
        $button.IsEnabled = (($understand | Where-Object { $_.IsChecked -eq $true }).Count -eq 1 -and
            ($returns | Where-Object { $_.IsChecked -eq $true }).Count -eq 1 -and $affectCount -ge 1 -and $affectCount -le 2)
    }
    @($understand + $returns) | ForEach-Object { $_.add_Checked($validate) }
    $affects | ForEach-Object { $_.Box.add_Checked($validate); $_.Box.add_Unchecked($validate) }
    $button.add_Click({
        for ($i = 0; $i -lt 4; $i++) {
            if ($understand[$i].IsChecked) { $result.Understanding = $i + 1 }
            if ($returns[$i].IsChecked) { $result.ReturnIntent = $i + 1 }
        }
        $result.Affects = @($affects | Where-Object { $_.Box.IsChecked -eq $true } | ForEach-Object { $_.Value })
        $result.Status = $true
        $result.LatencyMs = [int]$watch.ElapsedMilliseconds
        $window.Close()
    })
    $skip.add_Click({ $result.Declined = $true; $result.LatencyMs = [int]$watch.ElapsedMilliseconds; $window.Close() })
    $window.ShowDialog() | Out-Null
    $watch.Stop()
    return $result
}

# =============================================================================
# TRAY E ORQUESTRAÇÃO
# =============================================================================

function Initialize-TrayIcon {
    $script:NotifyIcon = New-Object Windows.Forms.NotifyIcon
    $script:NotifyIcon.Icon = [Drawing.SystemIcons]::Application
    $script:NotifyIcon.Text = "PulseLab - Oficina em andamento"
    $script:NotifyIcon.Visible = $true
    $menu = New-Object Windows.Forms.ContextMenu
    $finish = New-Object Windows.Forms.MenuItem "Concluir Oficina"
    $finish.add_Click({
        if (-not $script:TriggerEnding) {
            $script:EndingRequestedAt = [DateTimeOffset]::Now
            $script:TriggerEnding = $true
            Write-PulseLog "INFO" "Manual ending requested."
        }
    })
    $menu.MenuItems.Add($finish) | Out-Null
    $script:NotifyIcon.ContextMenu = $menu
}

function Show-HelpAlert {
    param([string]$RoleLabel)
    Write-PulseLog "WARN" "Participant requested help. role=$RoleLabel"
    if ($script:NotifyIcon) {
        $script:NotifyIcon.BalloonTipTitle = "Dupla precisa de ajuda"
        $script:NotifyIcon.BalloonTipText = "$RoleLabel solicitou apoio do instrutor."
        $script:NotifyIcon.BalloonTipIcon = [Windows.Forms.ToolTipIcon]::Warning
        $script:NotifyIcon.ShowBalloonTip(8000)
    }
}

function Dispose-TrayIcon {
    if ($script:NotifyIcon) {
        $script:NotifyIcon.Visible = $false
        $script:NotifyIcon.Dispose()
        $script:NotifyIcon = $null
    }
}

function Save-PreSurvey {
    param([string]$ParticipantId, [string]$Role, [string]$Label)
    $result = Show-WpfPreSurvey $Label
    $event = New-ResearchEvent $ParticipantId $Role "pre" $null
    $event["response_latency_ms"] = [int]$result.LatencyMs
    if ($result.Status) {
        $event["prior_robotics"] = [int]$result.PriorRobotics
        $event["self_efficacy_pre"] = [int]$result.SelfEfficacy
    } else {
        $event["response_status"] = if ($result.Declined) { "declined" } else { "timeout" }
    }
    Submit-Event $event
    return [string]$event["response_status"]
}

function Save-CheckpointSurvey {
    param(
        [string]$ParticipantId, [string]$Role, [string]$Label, [int]$Mark,
        [bool]$AskCollaboration, [hashtable]$Telemetry, [decimal]$FileSize,
        [string]$ScreenshotPath, [string]$LocalScreenshotPath,
        [DateTimeOffset]$ScheduledAt, [DateTimeOffset]$CapturedAt,
        [string]$ActivityStage
    )

    $promptedAt = [DateTimeOffset]::Now
    $elapsedAtPrompt = if ($script:ActivityStopwatch) { [long]$script:ActivityStopwatch.ElapsedMilliseconds } else { 0L }
    $latenessMs = [Math]::Max(0, [int][Math]::Round(($promptedAt - $ScheduledAt).TotalMilliseconds))
    $result = Show-WpfCheckpoint $Label $Mark $AskCollaboration
    $event = New-ResearchEvent $ParticipantId $Role "checkpoint" $Mark
    $event["telemetry_window_title"] = $null
    $event["telemetry_foreground_app"] = $Telemetry.ForegroundApp
    $event["telemetry_idle_seconds"] = [int]$Telemetry.IdleSeconds
    $event["telemetry_file_size_kb"] = $FileSize
    $event["screenshot_path"] = $ScreenshotPath
    $event["local_screenshot_path"] = $LocalScreenshotPath
    $event["response_latency_ms"] = [int]$result.LatencyMs
    $event["activity_stage"] = $ActivityStage
    $event["elapsed_ms"] = $elapsedAtPrompt + [long]$result.LatencyMs
    $event["checkpoint_lateness_ms"] = $latenessMs
    $event["scheduled_at"] = $ScheduledAt.ToString("o")
    $event["prompted_at"] = $promptedAt.ToString("o")
    $event["captured_at"] = $CapturedAt.ToString("o")

    if ($result.Status) {
        $event["mental_effort"] = [int]$result.MentalEffort
        $event["progress_state"] = [string]$result.ProgressState
        $event["help_requested"] = ($result.ProgressState -eq "needs_help_now")
        if ($null -ne $result.Collaboration) { $event["collaboration"] = [int]$result.Collaboration }
        if ($event["help_requested"]) {
            Show-HelpAlert $Label
            Submit-SessionEvent "help_requested" "warning" $Mark $ParticipantId $Role $ActivityStage $event["elapsed_ms"] $ScheduledAt @{
                source = "participant_self_report"
            }
        }
    } else {
        $event["response_status"] = if ($result.Declined) { "declined" } else { "timeout" }
    }
    Submit-Event $event
    return [string]$event["response_status"]
}

function Save-PostSurvey {
    param([string]$ParticipantId, [string]$Role, [string]$Label, [hashtable]$Rubric)
    $result = Show-WpfPostSurvey $Label
    $event = New-ResearchEvent $ParticipantId $Role "post" $null
    $event["mission_performance"] = [int]$Rubric.Mission
    $event["instructor_interventions"] = [int]$Rubric.Interventions
    $event["primary_issue"] = [string]$Rubric.Issue
    $event["response_latency_ms"] = [int]$result.LatencyMs
    if ($script:ActivityStopwatch) { $event["elapsed_ms"] = [long]$script:ActivityStopwatch.ElapsedMilliseconds }
    if ($result.Status) {
        $event["post_understanding"] = [int]$result.Understanding
        $event["post_affects"] = [string[]]$result.Affects
        $event["post_return_intent"] = [int]$result.ReturnIntent
    } else {
        $event["response_status"] = if ($result.Declined) { "declined" } else { "timeout" }
    }
    Submit-Event $event
    return [string]$event["response_status"]
}

function Get-RoleLabel {
    param([string]$Role)
    if ($Role -eq "computer") { return "computador e programação" }
    return "montagem e testes"
}

function Get-CheckpointTargetMs {
    param([int]$Mark)

    $noWaitDebug = ($script:Config.PSObject.Properties.Name -contains "debug_no_wait" -and [bool]$script:Config.debug_no_wait)
    if ($noWaitDebug) { return 0L }
    if ($script:Config.debug_mode) { return [long]$Mark * 1000L }
    return [long]$Mark * 60000L
}

function Invoke-HeartbeatIfDue {
    if (-not $script:ActivityStopwatch) { return }
    $elapsed = [long]$script:ActivityStopwatch.ElapsedMilliseconds
    if ($elapsed -lt $script:NextHeartbeatElapsedMs) { return }

    $intervalSeconds = if ($script:Config.PSObject.Properties.Name -contains "heartbeat_interval_seconds") {
        [Math]::Max(15, [int]$script:Config.heartbeat_interval_seconds)
    } else {
        60
    }
    $script:NextHeartbeatElapsedMs = $elapsed + ([long]$intervalSeconds * 1000L)

    $telemetry = Get-ActiveTelemetry
    $spikeDetected = ((Get-SpikeWindowHandle) -ne [IntPtr]::Zero)
    Submit-SessionEvent "heartbeat" "info" $null $null $null $null $elapsed $null @{
        app_category = [string]$telemetry.ForegroundApp
        idle_seconds = [int]$telemetry.IdleSeconds
        spike_window_detected = $spikeDetected
        ending_requested = [bool]$script:TriggerEnding
    }
}

function Wait-UntilActivityTime {
    param([long]$TargetElapsedMs)

    while ($script:ActivityStopwatch.ElapsedMilliseconds -lt $TargetElapsedMs -and -not $script:TriggerEnding) {
        [Windows.Forms.Application]::DoEvents()
        Invoke-HeartbeatIfDue
        Start-Sleep -Milliseconds 100
    }
}

function Invoke-ConfiguredRoleSwap {
    param([int]$Mark, [string]$ActivityStage)

    if (-not ($script:Config.PSObject.Properties.Name -contains "role_swap_after_marks_minutes")) { return }
    if (-not ([int[]]$script:Config.role_swap_after_marks_minutes -contains $Mark)) { return }

    $nextComputerRole = if ($script:ParticipantComputerRole -eq "computer") { "assembly" } else { "computer" }
    $nextAssemblyRole = if ($script:ParticipantAssemblyRole -eq "computer") { "assembly" } else { "computer" }
    $labelA = "Participante A: agora em $(Get-RoleLabel $nextComputerRole)"
    $labelB = "Participante B: agora em $(Get-RoleLabel $nextAssemblyRole)"

    if (Show-WpfRoleSwap $labelA $labelB) {
        $script:ParticipantComputerRole = $nextComputerRole
        $script:ParticipantAssemblyRole = $nextAssemblyRole
        $elapsed = if ($script:ActivityStopwatch) { [long]$script:ActivityStopwatch.ElapsedMilliseconds } else { 0L }
        Submit-SessionEvent "role_swapped" "info" $Mark $null $null $ActivityStage $elapsed $null @{
            participant_a_role = $script:ParticipantComputerRole
            participant_b_role = $script:ParticipantAssemblyRole
        }
    } else {
        $elapsed = if ($script:ActivityStopwatch) { [long]$script:ActivityStopwatch.ElapsedMilliseconds } else { 0L }
        Submit-SessionEvent "quality_issue" "warning" $Mark $null $null $ActivityStage $elapsed $null @{
            code = "role_swap_not_confirmed"
        }
    }
}

function Start-ResearchLoop {
    $marks = [int[]]$script:Config.interval_marks_minutes
    $script:ActivityStartedAt = [DateTimeOffset]::Now
    $script:ActivityStopwatch = [Diagnostics.Stopwatch]::StartNew()
    $heartbeatSeconds = if ($script:Config.PSObject.Properties.Name -contains "heartbeat_interval_seconds") {
        [Math]::Max(15, [int]$script:Config.heartbeat_interval_seconds)
    } else {
        60
    }
    $script:NextHeartbeatElapsedMs = [long]$heartbeatSeconds * 1000L

    Submit-SessionEvent "activity_started" "info" $null $null $null $null 0L $null @{
        interval_marks_minutes = $marks
        screenshot_enabled = [bool]$script:Config.screenshot_enabled
    }

    foreach ($mark in $marks) {
        if ($script:TriggerEnding) { break }

        $targetElapsedMs = Get-CheckpointTargetMs $mark
        $scheduledAt = $script:ActivityStartedAt.AddMilliseconds($targetElapsedMs)
        Wait-UntilActivityTime $targetElapsedMs
        if ($script:TriggerEnding) { break }

        $script:SpikeHandle = Get-SpikeWindowHandle
        $telemetry = Get-ActiveTelemetry
        $fileSize = Get-LastSpikeFileSize
        $capturedAt = [DateTimeOffset]::Now
        $elapsedAtCapture = [long]$script:ActivityStopwatch.ElapsedMilliseconds
        $captureLatenessMs = [Math]::Max(0, [int][Math]::Round(($capturedAt - $scheduledAt).TotalMilliseconds))
        $activityStage = Get-CheckpointStage $mark
        $localScreenshot = $null
        $privatePath = $null
        $screenshotCaptured = $false

        if ($script:Config.screenshot_enabled) {
            $candidate = Join-Path $script:OFFLINE_CACHE_DIR "screenshot-$($script:SessionId)-$mark.jpg"
            if (Get-SpikeWindowCapture $candidate $script:SpikeHandle) {
                $screenshotCaptured = $true
                $localScreenshot = $candidate
                $privatePath = Upload-ScreenshotToSupabase $candidate $mark
                if ($privatePath) {
                    Remove-Item $candidate -Force -ErrorAction SilentlyContinue
                    $localScreenshot = $null
                }
            }
        }

        Submit-SessionEvent "checkpoint_started" "info" $mark $null $null $activityStage $elapsedAtCapture $scheduledAt @{
            app_category = [string]$telemetry.ForegroundApp
            idle_seconds = [int]$telemetry.IdleSeconds
            spike_window_detected = ($script:SpikeHandle -ne [IntPtr]::Zero)
            screenshot_captured = $screenshotCaptured
            screenshot_uploaded = (-not [string]::IsNullOrWhiteSpace($privatePath))
            lateness_ms = $captureLatenessMs
        }

        $maxLatenessSeconds = if ($script:Config.PSObject.Properties.Name -contains "max_checkpoint_lateness_seconds") {
            [int]$script:Config.max_checkpoint_lateness_seconds
        } else {
            120
        }
        if ($captureLatenessMs -gt ($maxLatenessSeconds * 1000)) {
            Submit-SessionEvent "quality_issue" "warning" $mark $null $null $activityStage $elapsedAtCapture $scheduledAt @{
                code = "checkpoint_late"
                lateness_ms = $captureLatenessMs
                threshold_ms = $maxLatenessSeconds * 1000
            }
        }
        if ($script:SpikeHandle -eq [IntPtr]::Zero) {
            Submit-SessionEvent "quality_issue" "warning" $mark $null $null $activityStage $elapsedAtCapture $scheduledAt @{
                code = "spike_window_not_found"
            }
        }
        if ($script:Config.screenshot_enabled -and -not $screenshotCaptured) {
            Submit-SessionEvent "quality_issue" "warning" $mark $null $null $activityStage $elapsedAtCapture $scheduledAt @{
                code = "screenshot_not_captured"
            }
        }

        $askCollaboration = ([int[]]$script:Config.collaboration_marks_minutes -contains $mark)
        $labelA = "Participante A · papel atual: $(Get-RoleLabel $script:ParticipantComputerRole)"
        $labelB = "Participante B · papel atual: $(Get-RoleLabel $script:ParticipantAssemblyRole)"
        $statusA = Save-CheckpointSurvey $script:ParticipantComputer $script:ParticipantComputerRole $labelA $mark $askCollaboration $telemetry $fileSize $privatePath $localScreenshot $scheduledAt $capturedAt $activityStage
        $statusB = Save-CheckpointSurvey $script:ParticipantAssembly $script:ParticipantAssemblyRole $labelB $mark $askCollaboration $telemetry $fileSize $privatePath $localScreenshot $scheduledAt $capturedAt $activityStage
        Restore-SpikeFocus $script:SpikeHandle

        $elapsedAfterResponses = [long]$script:ActivityStopwatch.ElapsedMilliseconds
        Submit-SessionEvent "checkpoint_completed" "info" $mark $null $null $activityStage $elapsedAfterResponses $scheduledAt @{
            participant_a_status = $statusA
            participant_b_status = $statusB
        }
        Invoke-ConfiguredRoleSwap $mark $activityStage
        Invoke-FlushCache
    }

    if (-not $script:TriggerEnding) {
        Write-PulseLog "INFO" "All checkpoints completed. Waiting for instructor to finish the workshop."
        while (-not $script:TriggerEnding) {
            [Windows.Forms.Application]::DoEvents()
            Invoke-HeartbeatIfDue
            Start-Sleep -Milliseconds 150
        }
    }

    $elapsedAtEnding = if ($script:ActivityStopwatch) { [long]$script:ActivityStopwatch.ElapsedMilliseconds } else { 0L }
    Submit-SessionEvent "ending_requested" "info" $null $null $null $null $elapsedAtEnding $null @{
        requested_at = if ($script:EndingRequestedAt) { $script:EndingRequestedAt.ToString("o") } else { $null }
    }

    $rubric = Show-WpfInstructorRubric
    if (-not $rubric.Status) {
        Write-PulseLog "WARN" "Instructor rubric canceled; session aborted before post-survey."
        Submit-SessionEvent "session_aborted" "warning" $null $null $null $null $elapsedAtEnding $null @{
            reason = "instructor_rubric_canceled"
        }
        Invoke-FlushCache
        return $false
    }

    Submit-SessionEvent "rubric_completed" "info" $null $null $null $null ([long]$script:ActivityStopwatch.ElapsedMilliseconds) $null @{
        mission_performance = [int]$rubric.Mission
        interventions_band = [int]$rubric.Interventions
        primary_issue = [string]$rubric.Issue
    }

    $postLabelA = "Participante A · papel final: $(Get-RoleLabel $script:ParticipantComputerRole)"
    $postLabelB = "Participante B · papel final: $(Get-RoleLabel $script:ParticipantAssemblyRole)"
    $postStatusA = Save-PostSurvey $script:ParticipantComputer $script:ParticipantComputerRole $postLabelA $rubric
    $postStatusB = Save-PostSurvey $script:ParticipantAssembly $script:ParticipantAssemblyRole $postLabelB $rubric
    Submit-SessionEvent "phase_completed" "info" $null $null $null "post" ([long]$script:ActivityStopwatch.ElapsedMilliseconds) $null @{
        phase = "post"
        participant_a_status = $postStatusA
        participant_b_status = $postStatusB
    }
    Submit-SessionEvent "session_completed" "info" $null $null $null $null ([long]$script:ActivityStopwatch.ElapsedMilliseconds) $null @{
        checkpoint_count = $marks.Count
    }
    Invoke-FlushCache
    $script:ActivityStopwatch.Stop()
    return $true
}

# =============================================================================
# ENTRY POINT
# =============================================================================

try {
    Initialize-Installation
    Initialize-Session
    Get-RemoteConfig
    Get-EnvCredentials

    if (-not (Show-WpfSessionSetup)) {
        Write-PulseLog "WARN" "Session setup canceled."
        exit 0
    }

    $computerAssent = Show-WpfAssent "Participante A"
    $assemblyAssent = Show-WpfAssent "Participante B"
    if (-not $computerAssent -or -not $assemblyAssent) {
        Write-PulseLog "INFO" "Research collection canceled because assent was not granted by all members of the dyad."
        [Windows.MessageBox]::Show(
            "A coleta de pesquisa foi encerrada. A dupla pode continuar participando normalmente da oficina.",
            "PulseLab",
            [Windows.MessageBoxButton]::OK,
            [Windows.MessageBoxImage]::Information
        ) | Out-Null
        exit 0
    }

    $script:CollectionAuthorized = $true
    Initialize-TrayIcon
    Invoke-FlushCache
    Submit-SessionEvent "session_started" "info" $null $null $null $null 0L $null @{
        participant_count = 2
        authorization_verified = $true
        assent_completed = $true
        expected_checkpoints = [int[]]$script:Config.interval_marks_minutes
    }
    $preStatusA = Save-PreSurvey $script:ParticipantComputer $script:ParticipantComputerRole "Participante A"
    $preStatusB = Save-PreSurvey $script:ParticipantAssembly $script:ParticipantAssemblyRole "Participante B"
    Submit-SessionEvent "phase_completed" "info" $null $null $null "pre" 0L $null @{
        phase = "pre"
        participant_a_status = $preStatusA
        participant_b_status = $preStatusB
    }
    Start-ResearchLoop | Out-Null
} catch {
    Write-PulseLog "ERROR" "Fatal error: $($_.Exception.Message)"
    if ($script:CollectionAuthorized -and $script:Config -and $script:SupabaseUrl) {
        try {
            $elapsed = if ($script:ActivityStopwatch) { [long]$script:ActivityStopwatch.ElapsedMilliseconds } else { 0L }
            Submit-SessionEvent "session_aborted" "error" $null $null $null $null $elapsed $null @{
                reason = "fatal_error"
                error_type = $_.Exception.GetType().Name
            }
            Invoke-FlushCache
        } catch {
            Write-PulseLog "ERROR" "Could not record aborted session: $($_.Exception.Message)"
        }
    }
} finally {
    if ($script:ActivityStopwatch -and $script:ActivityStopwatch.IsRunning) { $script:ActivityStopwatch.Stop() }
    Dispose-TrayIcon
    Write-PulseLog "INFO" "PulseLab session finished."
}
