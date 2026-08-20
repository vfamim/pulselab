#Requires -Version 5.1
# =============================================================================
# pulselab-agent.ps1
# Version    : 1.5.0
# Description: Coletor de eventos de pesquisa para oficinas pontuais com LEGO
#              SPIKE. Produz respostas pseudonimizadas e uma linha do tempo
#              append-only para observação distribuída e controle de qualidade.
# =============================================================================

[CmdletBinding()]
param(
    [switch]$DebugMode,
    [switch]$ProductionTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing, System.Security

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

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

public class ActivityTracker {
    public static long TotalMouseClicks = 0;
    public static long TotalKeystrokes = 0;
    private static bool _running = false;
    private static Thread _pollThread = null;

    [DllImport("user32.dll")]
    private static extern short GetAsyncKeyState(int vKey);

    public static void Start() {
        if (_running) return;
        _running = true;
        _pollThread = new Thread(PollInput);
        _pollThread.IsBackground = true;
        _pollThread.Priority = ThreadPriority.Lowest;
        _pollThread.Start();
    }

    public static void Stop() {
        _running = false;
    }

    public static void Reset() {
        Interlocked.Exchange(ref TotalMouseClicks, 0);
        Interlocked.Exchange(ref TotalKeystrokes, 0);
    }

    private static void PollInput() {
        bool leftDown = false;
        bool rightDown = false;
        bool[] keysDown = new bool[256];

        while (_running) {
            try {
                // Mouse left button (0x01)
                short leftState = GetAsyncKeyState(0x01);
                if ((leftState & 0x8000) != 0) {
                    if (!leftDown) {
                        Interlocked.Increment(ref TotalMouseClicks);
                        leftDown = true;
                    }
                } else {
                    leftDown = false;
                }

                // Mouse right button (0x02)
                short rightState = GetAsyncKeyState(0x02);
                if ((rightState & 0x8000) != 0) {
                    if (!rightDown) {
                        Interlocked.Increment(ref TotalMouseClicks);
                        rightDown = true;
                    }
                } else {
                    rightDown = false;
                }

                // Keyboard keys (0x08 Backspace to 0xFE)
                // Privacy note: Counts keypress events only, does not record key values or text.
                for (int k = 8; k <= 222; k++) {
                    if (k == 0x01 || k == 0x02 || k == 0x04) continue;
                    short keyState = GetAsyncKeyState(k);
                    if ((keyState & 0x8000) != 0) {
                        if (!keysDown[k]) {
                            Interlocked.Increment(ref TotalKeystrokes);
                            keysDown[k] = true;
                        }
                    } else {
                        keysDown[k] = false;
                    }
                }
            } catch { }

            Thread.Sleep(30);
        }
    }
}
"@

# =============================================================================
# ESTADO E CAMINHOS
# =============================================================================

$script:VERSION = "1.5.0"
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
$script:SESSION_STATE_FILE = Join-Path $script:DATA_DIR "session_state.json"
$script:AUTH_SESSION_FILE = Join-Path $script:DATA_DIR "device_session.dat"

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
$script:ActivityId = ""
$script:GroupSize = 2
$script:SupabaseUrl = $null
$script:SupabaseAnonKey = $null
$script:SupabaseKey = $null
$script:DeviceAccessToken = $null
$script:DeviceRefreshToken = $null
$script:DeviceTokenExpiresAt = 0L
$script:DeviceAuthUid = $null
$script:Config = $null
$script:ConfigHash = $null
$script:SpikeHandle = [IntPtr]::Zero
$script:TriggerEnding = $false
$script:EndingRequestedAt = $null
$script:NotifyIcon = $null
$script:CollectionAuthorized = $false
$script:SessionStartedAt = $null
$script:ActivityStartedAt = $null
$script:ActivityStopwatch = $null
$script:ElapsedOffsetMs = 0L
$script:NextHeartbeatElapsedMs = 0L
$script:ParticipantComputerRole = "computer"
$script:ParticipantAssemblyRole = "assembly"
$script:InstructorRubric = $null
$script:CompletedCheckpoints = @()
$script:IsResumedSession = $false
$script:AgentMutex = $null
$script:ResumeActionChoice = "new"
$script:DebugModeRequested = [bool]$DebugMode
$script:ProductionTest = [bool]$ProductionTest

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

function Write-AtomicUtf8Json {
    param(
        [string]$Path,
        $Data,
        [int]$Depth = 10
    )
    $dir = [System.IO.Path]::GetDirectoryName($Path)
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $tempPath = "$Path.$([Guid]::NewGuid().ToString('N')).tmp"
    $json = $Data | ConvertTo-Json -Depth $Depth
    [System.IO.File]::WriteAllText($tempPath, $json, [Text.Encoding]::UTF8)
    try {
        if (Test-Path $Path) {
            [System.IO.File]::Replace($tempPath, $Path, $null)
        } else {
            [System.IO.File]::Move($tempPath, $Path)
        }
    } catch {
        [System.IO.File]::Copy($tempPath, $Path, $true)
        [System.IO.File]::Delete($tempPath)
    }
}

function Protect-PulseSecret {
    param(
        [byte[]]$PlainBytes,
        [byte[]]$Entropy = $null
    )
    if ($null -eq $PlainBytes -or $PlainBytes.Length -eq 0) { return $null }
    try {
        Add-Type -AssemblyName System.Security -ErrorAction SilentlyContinue
        return [System.Security.Cryptography.ProtectedData]::Protect(
            $PlainBytes,
            $Entropy,
            [System.Security.Cryptography.DataProtectionScope]::CurrentUser
        )
    } catch {
        Write-PulseLog "WARN" "DPAPI Protect failed: $($_.Exception.Message)"
        return $null
    }
}

function Unprotect-PulseSecret {
    param(
        [byte[]]$EncryptedBytes,
        [byte[]]$Entropy = $null
    )
    if ($null -eq $EncryptedBytes -or $EncryptedBytes.Length -eq 0) { return $null }
    try {
        Add-Type -AssemblyName System.Security -ErrorAction SilentlyContinue
        return [System.Security.Cryptography.ProtectedData]::Unprotect(
            $EncryptedBytes,
            $Entropy,
            [System.Security.Cryptography.DataProtectionScope]::CurrentUser
        )
    } catch {
        Write-PulseLog "WARN" "DPAPI Unprotect failed: $($_.Exception.Message)"
        return $null
    }
}

function Save-DeviceSession {
    param(
        [hashtable]$SessionData
    )
    try {
        if (-not (Test-Path $script:DATA_DIR)) {
            New-Item -ItemType Directory -Path $script:DATA_DIR -Force | Out-Null
        }
        $json = $SessionData | ConvertTo-Json -Depth 5 -Compress
        $plainBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
        $encryptedBytes = Protect-PulseSecret $plainBytes
        if ($null -ne $encryptedBytes) {
            $tempPath = "$($script:AUTH_SESSION_FILE).$([Guid]::NewGuid().ToString('N')).tmp"
            [System.IO.File]::WriteAllBytes($tempPath, $encryptedBytes)
            try {
                if (Test-Path $script:AUTH_SESSION_FILE) {
                    [System.IO.File]::Replace($tempPath, $script:AUTH_SESSION_FILE, $null)
                } else {
                    [System.IO.File]::Move($tempPath, $script:AUTH_SESSION_FILE)
                }
            } catch {
                [System.IO.File]::Copy($tempPath, $script:AUTH_SESSION_FILE, $true)
                [System.IO.File]::Delete($tempPath)
            }
            Write-PulseLog "DEBUG" "Device session saved with DPAPI protection."
            return $true
        }
        return $false
    } catch {
        Write-PulseLog "WARN" "Could not save DPAPI device session: $($_.Exception.Message)"
        return $false
    }
}

function Load-DeviceSession {
    if (-not (Test-Path $script:AUTH_SESSION_FILE)) { return $null }
    try {
        $encryptedBytes = [System.IO.File]::ReadAllBytes($script:AUTH_SESSION_FILE)
        if ($null -eq $encryptedBytes -or $encryptedBytes.Length -eq 0) { return $null }
        $plainBytes = Unprotect-PulseSecret $encryptedBytes
        if ($null -eq $plainBytes -or $plainBytes.Length -eq 0) { return $null }
        $json = [System.Text.Encoding]::UTF8.GetString($plainBytes)
        if ([string]::IsNullOrWhiteSpace($json)) { return $null }
        $session = $json | ConvertFrom-Json
        if (-not $session) { return $null }

        if (-not ($session.PSObject.Properties.Name -contains "access_token") -or [string]::IsNullOrWhiteSpace([string]$session.access_token)) {
            Write-PulseLog "WARN" "DPAPI session missing or empty access_token."
            return $null
        }
        if (-not ($session.PSObject.Properties.Name -contains "refresh_token") -or [string]::IsNullOrWhiteSpace([string]$session.refresh_token)) {
            Write-PulseLog "WARN" "DPAPI session missing or empty refresh_token."
            return $null
        }
        if (-not ($session.PSObject.Properties.Name -contains "expires_at") -or [long]$session.expires_at -le 0) {
            Write-PulseLog "WARN" "DPAPI session missing or invalid expires_at timestamp."
            return $null
        }
        if (-not [string]::IsNullOrWhiteSpace($script:InstallationId)) {
            if (-not ($session.PSObject.Properties.Name -contains "installation_id") -or [string]$session.installation_id -ne [string]$script:InstallationId) {
                Write-PulseLog "WARN" "DPAPI session installation_id does not match current machine profile ($([string]$session.installation_id) != $($script:InstallationId))."
                return $null
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($script:SiteId)) {
            if (-not ($session.PSObject.Properties.Name -contains "site_id") -or [string]$session.site_id -ne [string]$script:SiteId) {
                Write-PulseLog "WARN" "DPAPI session site_id does not match current site profile ($([string]$session.site_id) != $($script:SiteId))."
                return $null
            }
        }

        return $session
    } catch {
        Write-PulseLog "WARN" "Could not load DPAPI device session: $($_.Exception.Message)"
        return $null
    }
}

function Clear-DeviceSession {
    try {
        if (Test-Path $script:AUTH_SESSION_FILE) {
            Remove-Item $script:AUTH_SESSION_FILE -Force -ErrorAction SilentlyContinue
        }
        $script:DeviceAccessToken = $null
        $script:DeviceRefreshToken = $null
        $script:DeviceTokenExpiresAt = 0L
        $script:DeviceAuthUid = $null
        Write-PulseLog "INFO" "Device session cleared."
    } catch {
        Write-PulseLog "WARN" "Could not clear device session: $($_.Exception.Message)"
    }
}

function Invoke-DeviceSessionRefresh {
    if ([string]::IsNullOrWhiteSpace($script:DeviceRefreshToken)) {
        Write-PulseLog "DEBUG" "No refresh token available to refresh device session."
        return $false
    }
    if ([string]::IsNullOrWhiteSpace($script:SupabaseUrl) -or [string]::IsNullOrWhiteSpace($script:SupabaseAnonKey)) {
        Write-PulseLog "WARN" "Supabase URL or anon key missing; cannot refresh device session."
        return $false
    }

    $endpoint = "$($script:SupabaseUrl)/auth/v1/token?grant_type=refresh_token"
    $headers = @{
        apikey = $script:SupabaseAnonKey
        "Content-Type" = "application/json"
    }
    $body = @{
        refresh_token = $script:DeviceRefreshToken
    } | ConvertTo-Json -Compress

    try {
        $timeout = if ($script:Config -and $script:Config.PSObject.Properties.Name -contains "network_timeout_seconds") {
            [int]$script:Config.network_timeout_seconds
        } else {
            10
        }
        $response = Invoke-RestMethod -Method Post -Uri $endpoint -Headers $headers -Body $body -ContentType "application/json" -TimeoutSec $timeout -ErrorAction Stop
        if ($response -and $response.access_token) {
            $script:DeviceAccessToken = [string]$response.access_token
            if ($response.refresh_token) {
                $script:DeviceRefreshToken = [string]$response.refresh_token
            }
            if ($response.expires_at) {
                $script:DeviceTokenExpiresAt = [long]$response.expires_at
            } elseif ($response.expires_in) {
                $nowSec = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
                $script:DeviceTokenExpiresAt = $nowSec + [long]$response.expires_in
            }
            if ($response.user -and $response.user.id) {
                $script:DeviceAuthUid = [string]$response.user.id
            }

            $sessionPayload = @{
                access_token = $script:DeviceAccessToken
                refresh_token = $script:DeviceRefreshToken
                expires_at = $script:DeviceTokenExpiresAt
                user_id = $script:DeviceAuthUid
                installation_id = $script:InstallationId
                site_id = $script:SiteId
                updated_at = [DateTimeOffset]::UtcNow.ToString("o")
            }
            Save-DeviceSession $sessionPayload | Out-Null
            Write-PulseLog "INFO" "Device session token refreshed successfully."
            return $true
        }
        return $false
    } catch {
        Write-PulseLog "WARN" "Device session refresh failed: $($_.Exception.Message)"
        return $false
    }
}

function Test-DeviceSessionValid {
    if ([string]::IsNullOrWhiteSpace($script:DeviceAccessToken) -or
        [string]::IsNullOrWhiteSpace($script:DeviceRefreshToken) -or
        $script:DeviceTokenExpiresAt -le 0) {
        return $false
    }

    $nowSec = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    if ($nowSec -ge $script:DeviceTokenExpiresAt) {
        Write-PulseLog "INFO" "Device token is expired; performing mandatory session refresh."
        if (-not (Invoke-DeviceSessionRefresh)) {
            Write-PulseLog "WARN" "Mandatory device session refresh failed; session is invalid."
            return $false
        }
    } elseif (($script:DeviceTokenExpiresAt - $nowSec) -lt 180) {
        Write-PulseLog "INFO" "Device token near expiration; performing mandatory session refresh."
        if (-not (Invoke-DeviceSessionRefresh)) {
            Write-PulseLog "WARN" "Mandatory device session refresh failed; session is invalid."
            return $false
        }
    }

    return (
        -not [string]::IsNullOrWhiteSpace($script:DeviceAccessToken) -and
        $script:DeviceTokenExpiresAt -gt [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    )
}

function Get-DeviceAuthHeader {
    if (-not (Test-DeviceSessionValid)) {
        return $null
    }
    return "Bearer $($script:DeviceAccessToken)"
}

function Save-InstallationProfile {
    $profile = @{
        installation_id = $script:InstallationId
        site_id = $script:SiteId
        regional_hub = $script:RegionalHub
        school_code = $script:SchoolCode
        workshop_code = $script:WorkshopCode
        class_code = $script:ClassCode
        activity_id = $script:ActivityId
        group_size = $script:GroupSize
        updated_at = [DateTimeOffset]::Now.ToString("o")
    }
    Write-AtomicUtf8Json $script:INSTALLATION_FILE $profile 4
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
        if ($profile.PSObject.Properties.Name -contains "workshop_code" -and -not [string]::IsNullOrWhiteSpace([string]$profile.workshop_code)) {
            $script:WorkshopCode = [string]$profile.workshop_code
        }
        if ($profile.PSObject.Properties.Name -contains "class_code" -and -not [string]::IsNullOrWhiteSpace([string]$profile.class_code)) {
            $script:ClassCode = [string]$profile.class_code
        }
        if ($profile.PSObject.Properties.Name -contains "activity_id" -and -not [string]::IsNullOrWhiteSpace([string]$profile.activity_id)) {
            $script:ActivityId = [string]$profile.activity_id
        }
        if ($profile.PSObject.Properties.Name -contains "group_size" -and $profile.group_size -gt 0) {
            $script:GroupSize = [int]$profile.group_size
        }
    } else {
        $script:InstallationId = [Guid]::NewGuid().ToString()
        $script:SiteId = if ($local -and $local.PSObject.Properties.Name -contains "site_id") {
            [string]$local.site_id
        } else {
            "CONFIGURE_SEDE"
        }
        $script:RegionalHub = if ($local -and $local.PSObject.Properties.Name -contains "regional_hub") { [string]$local.regional_hub } else { "CONFIGURE_REGIONAL" }
        $script:SchoolCode = if ($local -and $local.PSObject.Properties.Name -contains "school_code") { [string]$local.school_code } else { "CONFIGURE_ESCOLA" }
        $script:WorkshopCode = if ($local -and $local.PSObject.Properties.Name -contains "workshop_code") { [string]$local.workshop_code } else { "CONFIGURE_OFICINA" }
        $script:ClassCode = if ($local -and $local.PSObject.Properties.Name -contains "class_code") { [string]$local.class_code } else { "CONFIGURE_TURMA" }
        $script:ActivityId = if ($local -and $local.PSObject.Properties.Name -contains "activity_id") { [string]$local.activity_id } else { "atividade-01-spike" }
        $script:GroupSize = if ($local -and $local.PSObject.Properties.Name -contains "group_size" -and $local.group_size -gt 0) { [int]$local.group_size } else { 2 }
        Save-InstallationProfile
    }

    Write-PulseLog "INFO" "Installation initialized. installation_id=$($script:InstallationId) site_id=$($script:SiteId) group_size=$($script:GroupSize)"
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
    $script:CompletedCheckpoints = @()
    $script:IsResumedSession = $false
    $script:LastReportedClicks = 0L
    $script:LastReportedKeystrokes = 0L
    [ActivityTracker]::Reset()
    [ActivityTracker]::Start()

    New-Item -ItemType Directory -Path $script:OFFLINE_CACHE_DIR -Force | Out-Null
    Write-PulseLog "INFO" "Session initialized. version=$script:VERSION session_id=$script:SessionId dyad_id=$script:DyadId installation_id=$($script:InstallationId)"
}

function Save-SessionState {
    param(
        [string]$Phase = "in_progress",
        [int]$CompletedCheckpoint = 0
    )
    try {
        if (-not (Test-Path $script:DATA_DIR)) {
            New-Item -ItemType Directory -Path $script:DATA_DIR -Force | Out-Null
        }
        if ($CompletedCheckpoint -gt 0 -and -not ($script:CompletedCheckpoints -contains $CompletedCheckpoint)) {
            $script:CompletedCheckpoints = @($script:CompletedCheckpoints) + $CompletedCheckpoint
        }
        $configSnapshot = if ($script:Config) { $script:Config | ConvertTo-Json -Depth 10 } else { $null }
        $state = @{
            version = $script:VERSION
            session_id = $script:SessionId
            dyad_id = $script:DyadId
            installation_id = $script:InstallationId
            site_id = $script:SiteId
            regional_hub = $script:RegionalHub
            school_code = $script:SchoolCode
            workshop_code = $script:WorkshopCode
            class_code = $script:ClassCode
            activity_id = $script:ActivityId
            group_size = $script:GroupSize
            participant_computer = $script:ParticipantComputer
            participant_assembly = $script:ParticipantAssembly
            participant_computer_role = $script:ParticipantComputerRole
            participant_assembly_role = $script:ParticipantAssemblyRole
            started_at = if ($script:SessionStartedAt) { $script:SessionStartedAt.ToString("o") } else { [DateTimeOffset]::Now.ToString("o") }
            activity_started_at = if ($script:ActivityStartedAt) { $script:ActivityStartedAt.ToString("o") } else { [DateTimeOffset]::Now.ToString("o") }
            completed_checkpoints = $script:CompletedCheckpoints
            phase = $Phase
            status = "in_progress"
            config_hash = $script:ConfigHash
            config_snapshot = $configSnapshot
            protocol_version = [string]$script:Config.protocol_version
            updated_at = [DateTimeOffset]::Now.ToString("o")
        }
        Write-AtomicUtf8Json $script:SESSION_STATE_FILE $state 5
        Write-PulseLog "DEBUG" "Session state saved. phase=$Phase checkpoints=$($script:CompletedCheckpoints -join ',')"
    } catch {
        Write-PulseLog "WARN" "Could not save session state: $($_.Exception.Message)"
    }
}

function Get-ResumableSession {
    if (-not (Test-Path $script:SESSION_STATE_FILE)) { return $null }
    try {
        $raw = [System.IO.File]::ReadAllText($script:SESSION_STATE_FILE, [Text.Encoding]::UTF8)
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        $state = $raw | ConvertFrom-Json
        if (-not $state.session_id -or $state.status -ne "in_progress") { return $null }

        $started = [DateTimeOffset]::Parse([string]$state.started_at)
        $ageMinutes = ([DateTimeOffset]::Now - $started).TotalMinutes
        if ($ageMinutes -gt 150 -or $ageMinutes -lt 0) {
            Write-PulseLog "INFO" "Found expired session state ($([int]$ageMinutes) min old); clearing."
            Clear-SessionState
            return $null
        }
        return $state
    } catch {
        Write-PulseLog "WARN" "Could not read session state (possible corruption): $($_.Exception.Message)"
        try {
            $corruptedPath = "$($script:SESSION_STATE_FILE).corrupted.$([DateTimeOffset]::Now.ToUnixTimeSeconds()).json"
            Move-Item $script:SESSION_STATE_FILE $corruptedPath -Force -ErrorAction SilentlyContinue
        } catch {}
        return $null
    }
}

function Clear-SessionState {
    try {
        if (Test-Path $script:SESSION_STATE_FILE) {
            Remove-Item $script:SESSION_STATE_FILE -Force -ErrorAction SilentlyContinue
            Write-PulseLog "INFO" "Session state cleared."
        }
    } catch {}
}

function Show-WpfResumePrompt {
    param($ResumableState)

    $school = [Security.SecurityElement]::Escape([string]$ResumableState.school_code)
    $class = [Security.SecurityElement]::Escape([string]$ResumableState.class_code)
    $site = [Security.SecurityElement]::Escape([string]$ResumableState.site_id)
    $startedTime = try { [DateTimeOffset]::Parse([string]$ResumableState.started_at).ToString("HH:mm") } catch { "Recente" }

    $cpDone = if ($ResumableState.completed_checkpoints) { [int[]]$ResumableState.completed_checkpoints } else { @() }
    $cpText = if ($cpDone.Count -gt 0) {
        "Checkpoints concluidos: " + ($cpDone -join " min, ") + " min"
    } else {
        "Pre-oficina concluida (aguardando checkpoints)"
    }
    $cpTextEsc = [Security.SecurityElement]::Escape($cpText)

    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="PulseLab - Recuperacao de Sessao" Height="450" Width="600"
        WindowStartupLocation="CenterScreen" WindowStyle="None"
        AllowsTransparency="True" Background="Transparent" Topmost="True">
  <Window.Resources>
    <Style x:Key="ModernBtn" TargetType="Button">
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border Name="BtnBorder" Background="{TemplateBinding Background}" CornerRadius="12" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="BtnBorder" Property="Opacity" Value="0.88"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="BtnBorder" Property="Opacity" Value="0.35"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>
  <Border CornerRadius="24" Background="#110B27" BorderBrush="#5EEAD4" BorderThickness="2.5" Padding="28">
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>
      <StackPanel Grid.Row="0" Margin="0,0,0,16">
        <Border HorizontalAlignment="Left" Background="#201545" BorderBrush="#3D2D7A" BorderThickness="1" CornerRadius="8" Padding="10,4" Margin="0,0,0,8">
          <TextBlock Text="SESSÃO INTERROMPIDA ENCONTRADA" Foreground="#5EEAD4" FontSize="11" FontWeight="Bold"/>
        </Border>
        <TextBlock Text="Recuperar Sessão Anterior?" Foreground="White" FontSize="22" FontWeight="Bold"/>
        <TextBlock Text="Identificamos uma oficina iniciada nesta máquina que foi interrompida antes da conclusão." Foreground="#A499B8" FontSize="13" TextWrapping="Wrap" Margin="0,4,0,0"/>
      </StackPanel>
      <Border Grid.Row="1" Background="#201642" CornerRadius="14" Padding="18" Margin="0,0,0,18" BorderBrush="#3D2D7A" BorderThickness="1.5">
        <StackPanel>
          <TextBlock Text="DADOS DA OFICINA DETECTADA" Foreground="#5EEAD4" FontSize="11" FontWeight="Bold" Margin="0,0,0,12"/>
          <Grid Margin="0,0,0,8">
            <Grid.ColumnDefinitions><ColumnDefinition Width="130"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
            <TextBlock Grid.Column="0" Text="Escola / Sede:" Foreground="#A499B8" FontSize="13"/>
            <TextBlock Grid.Column="1" Text="$school ($site)" Foreground="White" FontWeight="Bold" FontSize="13"/>
          </Grid>
          <Grid Margin="0,0,0,8">
            <Grid.ColumnDefinitions><ColumnDefinition Width="130"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
            <TextBlock Grid.Column="0" Text="Turma / Início:" Foreground="#A499B8" FontSize="13"/>
            <TextBlock Grid.Column="1" Text="$class (Iniciada às $startedTime)" Foreground="White" FontWeight="Bold" FontSize="13"/>
          </Grid>
          <Grid Margin="0,0,0,8">
            <Grid.ColumnDefinitions><ColumnDefinition Width="130"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
            <TextBlock Grid.Column="0" Text="Progresso:" Foreground="#A499B8" FontSize="13"/>
            <TextBlock Grid.Column="1" Text="$cpTextEsc" Foreground="#5EEAD4" FontWeight="Bold" FontSize="13"/>
          </Grid>
        </StackPanel>
      </Border>
      <Grid Grid.Row="2">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="14"/>
          <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>
        <Button Name="BtnNew" Grid.Column="0" Content="Iniciar Nova Oficina" Style="{StaticResource ModernBtn}" Background="#241B4B" Height="48"/>
        <Button Name="BtnResume" Grid.Column="2" Content="Continuar Oficina" Style="{StaticResource ModernBtn}" Background="#00A7A0" Height="48"/>
      </Grid>
    </Grid>
  </Border>
</Window>
"@

    $window = [Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader ([xml]$xaml)))

    $btnNew = $window.FindName("BtnNew")
    $btnResume = $window.FindName("BtnResume")

    $script:ResumeActionChoice = "new"
    $btnNew.add_Click({
        $script:ResumeActionChoice = "new"
        $window.Close()
    })
    $btnResume.add_Click({
        $script:ResumeActionChoice = "resume"
        $window.Close()
    })

    $window.ShowDialog() | Out-Null
    return $script:ResumeActionChoice
}

function Get-RemoteConfig {
    if (-not (Test-Path $script:LOCAL_CONFIG)) {
        throw "Configuration file missing at $($script:LOCAL_CONFIG)."
    }

    $localRaw = Get-Content $script:LOCAL_CONFIG -Raw -Encoding UTF8
    $local = $localRaw | ConvertFrom-Json
    $selectedRaw = $localRaw
    if ($script:DebugModeRequested) {
        $script:Config = $local
        $script:Config.debug_mode = $true
        $script:Config.debug_no_wait = $true
        $selectedRaw = $script:Config | ConvertTo-Json -Depth 10
        Write-PulseLog "INFO" "Command line -DebugMode active; using local config with immediate checkpoints."
    } else {
        try {
            $response = Invoke-WebRequest -Uri $local.config_remote_url -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
            # Windows PowerShell 5.1 may decode raw.githubusercontent.com as
            # ANSI when no charset is present. Decode the response explicitly.
            $rawBytes = $response.RawContentStream.ToArray()
            $remoteRaw = [Text.Encoding]::UTF8.GetString($rawBytes)
            $remote = $remoteRaw | ConvertFrom-Json
            if (-not $remote.questions -or -not $remote.interval_marks_minutes -or
                -not ($remote.PSObject.Properties.Name -contains "protocol_version")) {
                throw "Remote config is not compatible with PulseLab 1.5.0."
            }

            # Remote protocol updates must not erase the identity embedded by a
            # site-specific installer. Keeping these fields in the local
            # snapshot also protects a second Windows user on the same machine.
            foreach ($identityField in @("site_id", "regional_hub", "school_code")) {
                if ($local.PSObject.Properties.Name -contains $identityField) {
                    $identityValue = [string]$local.$identityField
                    if (-not (Test-NeedsSetupValue $identityValue)) {
                        if ($remote.PSObject.Properties.Name -contains $identityField) {
                            $remote.$identityField = $identityValue
                        } else {
                            $remote | Add-Member -NotePropertyName $identityField -NotePropertyValue $identityValue
                        }
                    }
                }
            }
            $remoteRaw = $remote | ConvertTo-Json -Depth 10
            $remoteRaw | Set-Content $script:LOCAL_CONFIG -Encoding UTF8 -Force
            $script:Config = $remote
            $selectedRaw = $remoteRaw
            Write-PulseLog "INFO" "Remote config loaded and frozen for session. version=$($remote.version)"
        } catch {
            $script:Config = $local
            Write-PulseLog "WARN" "Remote config unavailable; using local snapshot. error=$($_.Exception.Message)"
        }
    }

    if ($script:ProductionTest) {
        $script:Config.debug_mode = $true
        $script:Config.debug_no_wait = $false
        Write-PulseLog "INFO" "Command line -ProductionTest active; treating checkpoint minutes as seconds."
    }

    if (-not $script:Config.questions -or -not $script:Config.interval_marks_minutes -or
        -not ($script:Config.PSObject.Properties.Name -contains "protocol_version")) {
        throw "Config version is incompatible with PulseLab 1.5.0."
    }

    $marks = [int[]]$script:Config.interval_marks_minutes
    if ($marks.Count -eq 0 -or @($marks | Where-Object { $_ -le 0 }).Count -gt 0) {
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
    if ($script:Config.PSObject.Properties.Name -contains "supabase_url" -and
        -not [string]::IsNullOrWhiteSpace([string]$script:Config.supabase_url)) {
        $script:SupabaseUrl = [string]$script:Config.supabase_url
    } else {
        $urlName = [string]$script:Config.supabase_url_env_var
        $script:SupabaseUrl = [Environment]::GetEnvironmentVariable($urlName, "User")
    }

    if ($script:Config.PSObject.Properties.Name -contains "supabase_anon_key" -and
        -not [string]::IsNullOrWhiteSpace([string]$script:Config.supabase_anon_key)) {
        $script:SupabaseAnonKey = [string]$script:Config.supabase_anon_key
    } elseif ($script:Config.PSObject.Properties.Name -contains "supabase_key" -and
        -not [string]::IsNullOrWhiteSpace([string]$script:Config.supabase_key)) {
        $script:SupabaseAnonKey = [string]$script:Config.supabase_key
    } else {
        $anonEnv = [Environment]::GetEnvironmentVariable("PULSELAB_ANON_KEY", "User")
        if (-not [string]::IsNullOrWhiteSpace($anonEnv)) {
            $script:SupabaseAnonKey = $anonEnv
        } else {
            $keyName = [string]$script:Config.supabase_key_env_var
            $script:SupabaseAnonKey = [Environment]::GetEnvironmentVariable($keyName, "User")
        }
    }
    $script:SupabaseKey = $script:SupabaseAnonKey

    if ([string]::IsNullOrWhiteSpace($script:SupabaseUrl) -or [string]::IsNullOrWhiteSpace($script:SupabaseAnonKey)) {
        throw "Missing Supabase credentials. Run the installer first."
    }

    $savedSession = Load-DeviceSession
    if (-not $savedSession) {
        throw "Device authentication missing or invalid for this installation. Execute enroll-device.ps1 with a valid single-use enrollment token before starting data collection."
    }

    $requiredSessionFields = @("access_token", "refresh_token", "expires_at", "installation_id", "site_id")
    foreach ($field in $requiredSessionFields) {
        if (-not ($savedSession.PSObject.Properties.Name -contains $field) -or
            [string]::IsNullOrWhiteSpace([string]($savedSession.$field))) {
            Clear-DeviceSession
            throw "Device authentication session is incomplete. Re-enroll the device."
        }
    }
    if ([string]$savedSession.installation_id -ne $script:InstallationId -or
        [string]$savedSession.site_id -ne $script:SiteId) {
        Clear-DeviceSession
        throw "Device authentication does not match this installation/site. Re-enroll the device."
    }

    $script:DeviceAccessToken = [string]$savedSession.access_token
    $script:DeviceRefreshToken = [string]$savedSession.refresh_token
    $script:DeviceTokenExpiresAt = [long]$savedSession.expires_at
    if ($savedSession.PSObject.Properties.Name -contains "user_id") {
        $script:DeviceAuthUid = [string]$savedSession.user_id
    }
    Write-PulseLog "INFO" "Device session loaded from DPAPI protected storage."

    if (-not (Test-DeviceSessionValid)) {
        throw "Device authentication session is invalid or token refresh failed. Re-enroll the device."
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

    $totalClicks = [long][ActivityTracker]::TotalMouseClicks
    $totalKeys = [long][ActivityTracker]::TotalKeystrokes
    $clicksInterval = [Math]::Max(0L, ($totalClicks - [long]$script:LastReportedClicks))
    $keysInterval = [Math]::Max(0L, ($totalKeys - [long]$script:LastReportedKeystrokes))

    return @{
        # Minimize telemetry at the source. Raw window titles and application
        # names can expose unrelated personal information.
        WindowTitle = $null
        ForegroundApp = $appCategory
        IdleSeconds = $idle
        MouseClicksTotal = $totalClicks
        KeystrokesTotal = $totalKeys
        MouseClicksInterval = $clicksInterval
        KeystrokesInterval = $keysInterval
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

    $bitmap = $null
    $graphics = $null
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

        Write-PulseLog "INFO" "SPIKE window captured."
        return $true
    } catch {
        Write-PulseLog "ERROR" "SPIKE window capture failed: $($_.Exception.Message)"
        return $false
    } finally {
        if ($graphics) { $graphics.Dispose() }
        if ($bitmap) { $bitmap.Dispose() }
    }
}

# =============================================================================
# ENVIO E CACHE OFFLINE
# =============================================================================

function Upload-ScreenshotToSupabase {
    param([string]$LocalFilePath, [int]$IntervalMark)

    if ([string]::IsNullOrWhiteSpace($LocalFilePath) -or -not (Test-Path $LocalFilePath)) { return $null }

    $authHeader = Get-DeviceAuthHeader
    if ([string]::IsNullOrWhiteSpace($authHeader)) {
        Write-PulseLog "WARN" "Device authentication missing or invalid (fail-closed); screenshot upload blocked."
        return $null
    }

    $objectPath = "$($script:InstallationId)/$($script:WorkshopCode)/$($script:SessionId)/checkpoint-$IntervalMark.jpg"
    $endpoint = "$($script:SupabaseUrl)/storage/v1/object/screenshots/$objectPath"
    $headers = @{
        apikey = $script:SupabaseAnonKey
        Authorization = $authHeader
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
        if ($statusCode -eq 401 -and -not [string]::IsNullOrWhiteSpace($script:DeviceRefreshToken)) {
            Write-PulseLog "WARN" "Screenshot upload received 401 Unauthorized; attempting session refresh."
            if (Invoke-DeviceSessionRefresh) {
                try {
                    $headers["Authorization"] = Get-DeviceAuthHeader
                    Invoke-RestMethod -Method Post -Uri $endpoint -Headers $headers -Body $bytes -ContentType "image/jpeg" -TimeoutSec $timeout -ErrorAction Stop | Out-Null
                    return $objectPath
                } catch {
                    Write-PulseLog "ERROR" "Screenshot upload retry after refresh failed: $($_.Exception.Message)"
                    return $null
                }
            }
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

    $authHeader = Get-DeviceAuthHeader
    if ([string]::IsNullOrWhiteSpace($authHeader)) {
        Write-PulseLog "WARN" "Device authentication missing or invalid (fail-closed); database submission blocked."
        return $false
    }

    $isIdempotent = $clean.ContainsKey("event_id")
    $endpoint = "$($script:SupabaseUrl)/rest/v1/$targetTable"
    if ($isIdempotent) { $endpoint += "?on_conflict=event_id" }
    $headers = @{
        apikey = $script:SupabaseAnonKey
        Authorization = $authHeader
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
        $statusCode = $null
        if ($_.Exception.Response) { $statusCode = [int]$_.Exception.Response.StatusCode }
        if ($statusCode -eq 401 -and -not [string]::IsNullOrWhiteSpace($script:DeviceRefreshToken)) {
            Write-PulseLog "WARN" "Database submission received 401 Unauthorized; attempting session refresh."
            if (Invoke-DeviceSessionRefresh) {
                try {
                    $headers["Authorization"] = Get-DeviceAuthHeader
                    Invoke-RestMethod -Method Post -Uri $endpoint -Headers $headers -Body $body -TimeoutSec $timeout -ErrorAction Stop | Out-Null
                    return $true
                } catch {
                    Write-PulseLog "ERROR" "Database submission retry after refresh failed: $($_.Exception.Message)"
                    return $false
                }
            }
        }
        Write-PulseLog "ERROR" "Database submission failed: $($_.Exception.Message)"
        return $false
    }
}

function Add-ToLocalQueue {
    param([hashtable]$Payload)
    try {
        $queue = @()
        if (Test-Path $script:OFFLINE_CACHE_FILE) {
            try {
                $raw = [System.IO.File]::ReadAllText($script:OFFLINE_CACHE_FILE, [Text.Encoding]::UTF8)
                if (-not [string]::IsNullOrWhiteSpace($raw)) {
                    $existing = $raw | ConvertFrom-Json
                    $queue = if ($existing -is [array]) { $existing } else { @($existing) }
                }
            } catch {
                Write-PulseLog "WARN" "Offline queue file corrupted; moving to quarantine."
                $corruptedPath = "$($script:OFFLINE_CACHE_FILE).corrupted.$([DateTimeOffset]::Now.ToUnixTimeSeconds()).json"
                Move-Item $script:OFFLINE_CACHE_FILE $corruptedPath -Force -ErrorAction SilentlyContinue
                $queue = @()
            }
        }
        $queue += New-Object PSCustomObject -Property $Payload
        if ($queue.Count -gt 500) {
            $queue = $queue | Select-Object -Last 500
        }
        Write-AtomicUtf8Json $script:OFFLINE_CACHE_FILE $queue 10
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
        $raw = [System.IO.File]::ReadAllText($script:OFFLINE_CACHE_FILE, [Text.Encoding]::UTF8)
        if ([string]::IsNullOrWhiteSpace($raw)) { return }
        $items = try {
            $raw | ConvertFrom-Json
        } catch {
            Write-PulseLog "WARN" "Corrupted offline queue in flush; moving to quarantine."
            $corruptedPath = "$($script:OFFLINE_CACHE_FILE).corrupted.$([DateTimeOffset]::Now.ToUnixTimeSeconds()).json"
            Move-Item $script:OFFLINE_CACHE_FILE $corruptedPath -Force -ErrorAction SilentlyContinue
            return
        }
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
                -not [string]::IsNullOrWhiteSpace([string]$localPath)) {
                if (Test-Path $localPath) {
                    $objectPath = Upload-ScreenshotToSupabase $localPath ([int]$payload["interval_mark"])
                    if (-not $objectPath) {
                        # Preserve the event and its local evidence together.
                        $remaining += $item
                        continue
                    }
                    $payload["screenshot_path"] = $objectPath
                    $payload["local_screenshot_path"] = $null
                    $uploadedScreenshots[[string]$localPath] = $objectPath
                    $filesToRemove += [string]$localPath
                } else {
                    Write-PulseLog "WARN" "Local screenshot file missing on disk: $localPath"
                    Submit-SessionEvent "quality_issue" "warning" ([int]$payload["interval_mark"]) $null $null $null (Get-CurrentElapsedMs) $null @{
                        code = "screenshot_missing_on_disk"
                        path = $localPath
                    }
                    $payload["screenshot_path"] = $null
                    $payload["local_screenshot_path"] = $null
                }
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
            Write-AtomicUtf8Json $script:OFFLINE_CACHE_FILE $remaining 10
        }
    } catch {
        Write-PulseLog "ERROR" "Cache flush failed: $($_.Exception.Message)"
    }
}

function New-ResearchEvent {
    param(
        [string]$ParticipantId,
        [ValidateSet("computer", "assembly", "individual", "member_3", "member_4")][string]$Role,
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

function Test-NeedsSetupValue {
    param([string]$Value)
    return ([string]::IsNullOrWhiteSpace($Value) -or $Value -match '^CONFIGURE_')
}

function Get-SetupDisplayValue {
    param([string]$Value)
    if (Test-NeedsSetupValue $Value) { return "a definir" }
    return $Value
}

function Show-WpfSessionSetup {
    $installationSummary = "Sede/cidade: $(Get-SetupDisplayValue $script:SiteId)  •  Escola: $(Get-SetupDisplayValue $script:SchoolCode)  •  Regional: $(Get-SetupDisplayValue $script:RegionalHub)"
    $sessionSummary = "Oficina: $(Get-SetupDisplayValue $script:WorkshopCode)  •  Turma: $(Get-SetupDisplayValue $script:ClassCode)  •  Atividade: $(Get-SetupDisplayValue $script:ActivityId)"
    $installationSummaryXaml = [Security.SecurityElement]::Escape($installationSummary)
    $sessionSummaryXaml = [Security.SecurityElement]::Escape($sessionSummary)
    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="PulseLab - Contexto da oficina"
        Width="580" Height="720" WindowStartupLocation="CenterScreen" WindowStyle="None"
        AllowsTransparency="True" Background="Transparent" Topmost="True">
  <Window.Resources>
    <Style x:Key="ModernBtn" TargetType="Button">
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border Name="BtnBorder" Background="{TemplateBinding Background}" CornerRadius="12" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="BtnBorder" Property="Opacity" Value="0.88"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="BtnBorder" Property="Opacity" Value="0.35"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="ModernInput" TargetType="TextBox">
      <Setter Property="Background" Value="#17102E"/>
      <Setter Property="Foreground" Value="#FFFFFF"/>
      <Setter Property="BorderBrush" Value="#3D2D7A"/>
      <Setter Property="BorderThickness" Value="1.5"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Padding" Value="10,6"/>
      <Setter Property="Height" Value="36"/>
      <Setter Property="Margin" Value="0,4,0,10"/>
    </Style>
  </Window.Resources>
  <Border CornerRadius="24" Background="#110B27" BorderBrush="#7C3AED" BorderThickness="2.5" Padding="26">
    <Grid>
      <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
      <StackPanel Grid.Row="0" Margin="0,0,0,14">
        <Border HorizontalAlignment="Left" Background="#201545" BorderBrush="#3D2D7A" BorderThickness="1" CornerRadius="8" Padding="10,4" Margin="0,0,0,8">
          <TextBlock Text="PREPARAÇÃO DA OFICINA" Foreground="#A78BFA" FontSize="11" FontWeight="Bold"/>
        </Border>
        <TextBlock Text="Contexto e Identificação" Foreground="White" FontSize="22" FontWeight="Bold"/>
        <TextBlock Text="Confira os códigos operacionais desta máquina antes de iniciar a oficina." Foreground="#A499B8" FontSize="12" Margin="0,3,0,0"/>
      </StackPanel>
      <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
        <StackPanel Margin="0,0,6,0">
          <Border Background="#201642" CornerRadius="12" Padding="14" Margin="0,0,0,14" BorderBrush="#3D2D7A" BorderThickness="1.5">
            <StackPanel>
              <TextBlock Text="$installationSummaryXaml" Foreground="White" TextWrapping="Wrap" FontSize="12"/>
              <TextBlock Text="$sessionSummaryXaml" Foreground="#C9C3D8" TextWrapping="Wrap" FontSize="11" Margin="0,6,0,0"/>
            </StackPanel>
          </Border>
          <TextBlock Name="TxtMissingIntro" Text="Revise os dados abaixo (serão salvos para as próximas oficinas):" Foreground="#A78BFA" FontSize="12" FontWeight="Bold" Margin="0,0,0,8"/>
          <StackPanel Name="PnlSite">
            <TextBlock Text="Sede / Cidade" Foreground="#E2DBED" FontSize="12" FontWeight="SemiBold"/>
            <TextBox Name="TxtSite" Style="{StaticResource ModernInput}"/>
          </StackPanel>
          <StackPanel Name="PnlRegional">
            <TextBlock Text="Polo / Regional" Foreground="#E2DBED" FontSize="12" FontWeight="SemiBold"/>
            <TextBox Name="TxtRegional" Style="{StaticResource ModernInput}"/>
          </StackPanel>
          <StackPanel Name="PnlSchool">
            <TextBlock Text="Código da Escola" Foreground="#E2DBED" FontSize="12" FontWeight="SemiBold"/>
            <TextBox Name="TxtSchool" Style="{StaticResource ModernInput}"/>
          </StackPanel>
          <StackPanel Name="PnlWorkshop">
            <TextBlock Text="Código da Oficina" Foreground="#E2DBED" FontSize="12" FontWeight="SemiBold"/>
            <TextBox Name="TxtWorkshop" Style="{StaticResource ModernInput}"/>
          </StackPanel>
          <StackPanel Name="PnlClass">
            <TextBlock Text="Código da Turma" Foreground="#E2DBED" FontSize="12" FontWeight="SemiBold"/>
            <TextBox Name="TxtClass" Style="{StaticResource ModernInput}"/>
          </StackPanel>
          <StackPanel Name="PnlActivity">
            <TextBlock Text="Código da Atividade" Foreground="#E2DBED" FontSize="12" FontWeight="SemiBold"/>
            <TextBox Name="TxtActivity" Style="{StaticResource ModernInput}"/>
          </StackPanel>
          <StackPanel Name="PnlGroupSize">
            <TextBlock Text="Integrantes por Computador (1 a 3)" Foreground="#E2DBED" FontSize="12" FontWeight="SemiBold"/>
            <TextBox Name="TxtGroupSize" Style="{StaticResource ModernInput}" Text="2"/>
          </StackPanel>
        </StackPanel>
      </ScrollViewer>
      <StackPanel Grid.Row="2" Margin="0,8,0,12">
        <CheckBox Name="ChkConsent" Content="Confirmo que as autorizações e o consentimento foram verificados." Foreground="White" FontSize="12" Margin="0,6,0,8"/>
        <Border Background="#201642" CornerRadius="8" Padding="10" BorderBrush="#3D2D7A" BorderThickness="1">
          <TextBlock Text="🔒 Não use nomes de estudantes. Os dados são salvos com pseudônimos no computador." Foreground="#A499B8" TextWrapping="Wrap" FontSize="11"/>
        </Border>
      </StackPanel>
      <Button Name="BtnStart" Grid.Row="3" Content="Confirmar e Iniciar Oficina" Style="{StaticResource ModernBtn}" Height="46" Background="#7C3AED" Foreground="White" FontSize="15" FontWeight="Bold" IsEnabled="False"/>
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
    $activity = $window.FindName("TxtActivity")
    $groupSizeTxt = $window.FindName("TxtGroupSize")
    $consent = $window.FindName("ChkConsent")
    $button = $window.FindName("BtnStart")

    $site.Text = $script:SiteId
    $regional.Text = $script:RegionalHub
    $school.Text = $script:SchoolCode
    $workshop.Text = $script:WorkshopCode
    $class.Text = $script:ClassCode
    $activity.Text = $script:ActivityId
    $groupSizeTxt.Text = [string][Math]::Max(1, [Math]::Min(3, $script:GroupSize))

    foreach ($field in @($site, $regional, $school, $workshop, $class, $activity)) {
        if (Test-NeedsSetupValue $field.Text) { $field.Clear() }
    }

    $validate = {
        $values = @(
            $site.Text.Trim(), $regional.Text.Trim(), $school.Text.Trim(),
            $workshop.Text.Trim(), $class.Text.Trim(), $activity.Text.Trim()
        )
        $parsedGroup = 0
        [int]::TryParse($groupSizeTxt.Text.Trim(), [ref]$parsedGroup) | Out-Null
        $button.IsEnabled = (@($values | Where-Object { [string]::IsNullOrWhiteSpace($_) -or $_ -match '^CONFIGURE_' }).Count -eq 0 -and $parsedGroup -ge 1 -and $parsedGroup -le 3 -and $consent.IsChecked -eq $true)
    }
    $site.add_TextChanged($validate); $regional.add_TextChanged($validate); $school.add_TextChanged($validate)
    $workshop.add_TextChanged($validate); $class.add_TextChanged($validate); $activity.add_TextChanged($validate)
    $groupSizeTxt.add_TextChanged($validate)
    $consent.add_Checked($validate); $consent.add_Unchecked($validate)
    & $validate

    $button.add_Click({
        $script:SiteId = $site.Text.Trim()
        $script:RegionalHub = $regional.Text.Trim()
        $script:SchoolCode = $school.Text.Trim()
        $script:WorkshopCode = $workshop.Text.Trim()
        $script:ClassCode = $class.Text.Trim()
        $script:ActivityId = $activity.Text.Trim()
        [int]$script:GroupSize = [Math]::Max(1, [Math]::Min(3, [int]$groupSizeTxt.Text.Trim()))
        Save-InstallationProfile
        $window.DialogResult = $true
        $window.Close()
    })
    return ($window.ShowDialog() -eq $true)
}

function Show-WpfGroupSizeSelection {
    $script:GroupSize = [Math]::Max(1, [Math]::Min(3, $script:GroupSize))
    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="PulseLab - Quantidade de alunos"
        Width="580" Height="360" WindowStartupLocation="CenterScreen" WindowStyle="None"
        AllowsTransparency="True" Background="Transparent" Topmost="True">
  <Window.Resources>
    <Style x:Key="ModernBtn" TargetType="Button">
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border Name="BtnBorder" Background="{TemplateBinding Background}" CornerRadius="12" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="BtnBorder" Property="Opacity" Value="0.88"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="BtnBorder" Property="Opacity" Value="0.35"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="CardRadio" TargetType="RadioButton">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Foreground" Value="#E2DBED"/>
      <Setter Property="Margin" Value="4"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RadioButton">
            <Border Name="CardBorder" Background="#201642" BorderBrush="#3D2D7A" BorderThickness="1.5" CornerRadius="14" Padding="12,14">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="CardBorder" Property="BorderBrush" Value="#5EEAD4"/>
                <Setter TargetName="CardBorder" Property="Background" Value="#2A1E54"/>
              </Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="CardBorder" Property="BorderBrush" Value="#5EEAD4"/>
                <Setter TargetName="CardBorder" Property="Background" Value="#094A46"/>
                <Setter Property="Foreground" Value="#FFFFFF"/>
                <Setter Property="FontWeight" Value="Bold"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>
  <Border CornerRadius="24" Background="#110B27" BorderBrush="#00A7A0" BorderThickness="2.5" Padding="28">
    <Grid>
      <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
      <StackPanel Grid.Row="0" Margin="0,0,0,16">
        <Border HorizontalAlignment="Left" Background="#201545" BorderBrush="#3D2D7A" BorderThickness="1" CornerRadius="8" Padding="10,4" Margin="0,0,0,8">
          <TextBlock Text="COMPOSIÇÃO DO GRUPO" Foreground="#5EEAD4" FontSize="11" FontWeight="Bold"/>
        </Border>
        <TextBlock Text="Integrantes no Computador" Foreground="White" FontSize="22" FontWeight="Bold"/>
        <TextBlock Text="Quantos alunos estão trabalhando nesta máquina hoje?" Foreground="#A499B8" FontSize="13" Margin="0,3,0,0"/>
      </StackPanel>
      <UniformGrid Grid.Row="1" Columns="3" Margin="0,0,0,18">
        <RadioButton Name="Rad1" GroupName="SizeGroup" Style="{StaticResource CardRadio}">
          <StackPanel HorizontalAlignment="Center">
            <TextBlock Text="👤" FontSize="28" HorizontalAlignment="Center" Margin="0,0,0,6"/>
            <TextBlock Text="1 Aluno" FontSize="14" FontWeight="Bold" HorizontalAlignment="Center"/>
            <TextBlock Text="Trabalho Solo" FontSize="11" Foreground="#A499B8" HorizontalAlignment="Center"/>
          </StackPanel>
        </RadioButton>
        <RadioButton Name="Rad2" GroupName="SizeGroup" Style="{StaticResource CardRadio}" IsChecked="True">
          <StackPanel HorizontalAlignment="Center">
            <TextBlock Text="👥" FontSize="28" HorizontalAlignment="Center" Margin="0,0,0,6"/>
            <TextBlock Text="2 Alunos" FontSize="14" FontWeight="Bold" HorizontalAlignment="Center"/>
            <TextBlock Text="Dupla (Padrão)" FontSize="11" Foreground="#A499B8" HorizontalAlignment="Center"/>
          </StackPanel>
        </RadioButton>
        <RadioButton Name="Rad3" GroupName="SizeGroup" Style="{StaticResource CardRadio}">
          <StackPanel HorizontalAlignment="Center">
            <TextBlock Text="👥👤" FontSize="28" HorizontalAlignment="Center" Margin="0,0,0,6"/>
            <TextBlock Text="3 Alunos" FontSize="14" FontWeight="Bold" HorizontalAlignment="Center"/>
            <TextBlock Text="Trio" FontSize="11" Foreground="#A499B8" HorizontalAlignment="Center"/>
          </StackPanel>
        </RadioButton>
      </UniformGrid>
      <Button Name="BtnConfirm" Grid.Row="2" Content="Confirmar e Continuar" Style="{StaticResource ModernBtn}" Height="46" Background="#00A7A0" Foreground="White" FontSize="15" FontWeight="Bold"/>
    </Grid>
  </Border>
</Window>
"@
    $window = [Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader ([xml]$xaml)))
    $r1 = $window.FindName("Rad1"); $r2 = $window.FindName("Rad2"); $r3 = $window.FindName("Rad3")
    if ($script:GroupSize -eq 1) { $r1.IsChecked = $true }
    elseif ($script:GroupSize -eq 3) { $r3.IsChecked = $true }
    else { $r2.IsChecked = $true }

    $window.FindName("BtnConfirm").add_Click({
        if ($r1.IsChecked) { $script:GroupSize = 1 }
        elseif ($r3.IsChecked) { $script:GroupSize = 3 }
        else { $script:GroupSize = 2 }
        Save-InstallationProfile
        $window.DialogResult = $true
        $window.Close()
    })
    $window.ShowDialog() | Out-Null
}

function Get-ParticipantList {
    $list = @()
    $size = [Math]::Max(1, [Math]::Min(3, [int]$script:GroupSize))
    $letters = @("A", "B", "C")
    $roles = @($script:ParticipantComputerRole, $script:ParticipantAssemblyRole, "member_3")
    if ($size -eq 1) {
        $roles = @("individual")
    }
    for ($i = 0; $i -lt $size; $i++) {
        $shortId = $script:SessionId.Substring(0, 8).ToUpperInvariant()
        $letter = $letters[$i]
        $role = $roles[$i]
        $label = if ($size -eq 1) {
            "Participante Único (A)"
        } elseif ($size -eq 2) {
            "Aluno $($i + 1) ($([string](Get-RoleLabel $role))/$letter)"
        } else {
            if ($i -eq 0) { "Aluno 1 ($([string](Get-RoleLabel $role))/A)" }
            elseif ($i -eq 1) { "Aluno 2 ($([string](Get-RoleLabel $role))/B)" }
            else { "Aluno 3 (Apoio/C)" }
        }
        $list += @{
            Id = "$shortId-$letter"
            Letter = $letter
            Label = $label
            Role = $role
        }
    }
    return $list
}

function Show-WpfAssent {
    param([string]$RoleLabel)
    $roleLabelXaml = [Security.SecurityElement]::Escape($RoleLabel)
    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="PulseLab - Convite para participar"
        Width="600" Height="460" WindowStartupLocation="CenterScreen" WindowStyle="None"
        AllowsTransparency="True" Background="Transparent" Topmost="True">
  <Window.Resources>
    <Style x:Key="ModernBtn" TargetType="Button">
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border Name="BtnBorder" Background="{TemplateBinding Background}" CornerRadius="12" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="BtnBorder" Property="Opacity" Value="0.88"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="BtnBorder" Property="Opacity" Value="0.35"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>
  <Border CornerRadius="24" Background="#110B27" BorderBrush="#5EEAD4" BorderThickness="2.5" Padding="28">
    <Grid>
      <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
      <StackPanel Grid.Row="0" Margin="0,0,0,16">
        <Border HorizontalAlignment="Left" Background="#201545" BorderBrush="#3D2D7A" BorderThickness="1" CornerRadius="8" Padding="10,4" Margin="0,0,0,8">
          <TextBlock Text="ETAPA 2 DE 6 · ASSENTIMENTO" Foreground="#5EEAD4" FontSize="11" FontWeight="Bold"/>
        </Border>
        <TextBlock Text="Convite para Participar da Pesquisa" Foreground="White" FontSize="22" FontWeight="Bold"/>
        <Border HorizontalAlignment="Left" Background="#241B4B" CornerRadius="12" Padding="12,4" Margin="0,6,0,0">
          <TextBlock Text="$roleLabelXaml" Foreground="#5EEAD4" FontSize="13" FontWeight="Bold"/>
        </Border>
      </StackPanel>
      <Border Grid.Row="1" Background="#201642" CornerRadius="14" Padding="18" Margin="0,0,0,18" BorderBrush="#3D2D7A" BorderThickness="1.5">
        <StackPanel VerticalAlignment="Center">
          <TextBlock Text="Durante a oficina, o PulseLab fará perguntas curtas e registrará sinais do computador, como uso do SPIKE e tempo da atividade. Você pode escolher participar ou não." Foreground="White" FontSize="14" TextWrapping="Wrap" Margin="0,0,0,12"/>
          <TextBlock Text="✨ Se escolher não participar, você continuará fazendo a oficina normalmente. Isso não altera suas notas ou atividades." Foreground="#C4B5FD" FontSize="13" TextWrapping="Wrap"/>
        </StackPanel>
      </Border>
      <Grid Grid.Row="2">
        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="14"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
        <Button Name="BtnNo" Grid.Column="0" Content="Não quero participar" Style="{StaticResource ModernBtn}" Height="48" Background="#241B4B" Foreground="#E2DBED"/>
        <Button Name="BtnYes" Grid.Column="2" Content="Quero participar" Style="{StaticResource ModernBtn}" Height="48" Background="#00A7A0" Foreground="White" FontWeight="Bold"/>
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
    param([string]$RoleLabel, [bool]$IsLastParticipant = $true, [string]$NextLabel = "")
    $roleLabelXaml = [Security.SecurityElement]::Escape($RoleLabel)
    $priorRoboticsXaml = [Security.SecurityElement]::Escape([string]$script:Config.questions.prior_robotics)
    $selfEfficacyXaml = [Security.SecurityElement]::Escape([string]$script:Config.questions.self_efficacy)

    $subtext = if ($script:GroupSize -le 1) {
        "Responda sozinho. Sua resposta é individual."
    } elseif (-not $IsLastParticipant -and -not [string]::IsNullOrWhiteSpace($NextLabel)) {
        "Sua vez ($RoleLabel). Após responder, passe o computador para o $NextLabel."
    } else {
        "Sua vez ($RoleLabel). Esta é a última resposta do grupo antes de começar."
    }
    $subtextXaml = [Security.SecurityElement]::Escape($subtext)
    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="PulseLab - Antes da oficina"
        Width="660" Height="620" WindowStartupLocation="CenterScreen" WindowStyle="None"
        AllowsTransparency="True" Background="Transparent" Topmost="True">
  <Window.Resources>
    <Style x:Key="ModernBtn" TargetType="Button">
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border Name="BtnBorder" Background="{TemplateBinding Background}" CornerRadius="12" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="BtnBorder" Property="Opacity" Value="0.88"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="BtnBorder" Property="Opacity" Value="0.35"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="CardRadio" TargetType="RadioButton">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Foreground" Value="#E2DBED"/>
      <Setter Property="Margin" Value="4"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RadioButton">
            <Border Name="CardBorder" Background="#201642" BorderBrush="#3D2D7A" BorderThickness="1.5" CornerRadius="12" Padding="8,10">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="CardBorder" Property="BorderBrush" Value="#5EEAD4"/>
                <Setter TargetName="CardBorder" Property="Background" Value="#2A1E54"/>
              </Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="CardBorder" Property="BorderBrush" Value="#5EEAD4"/>
                <Setter TargetName="CardBorder" Property="Background" Value="#094A46"/>
                <Setter Property="Foreground" Value="#FFFFFF"/>
                <Setter Property="FontWeight" Value="Bold"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>
  <Border CornerRadius="24" Background="#110B27" BorderBrush="#00A7A0" BorderThickness="2.5" Padding="26">
    <Grid>
      <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
      <StackPanel Grid.Row="0" Margin="0,0,0,16">
        <Border HorizontalAlignment="Left" Background="#201545" BorderBrush="#3D2D7A" BorderThickness="1" CornerRadius="8" Padding="10,4" Margin="0,0,0,8">
          <TextBlock Text="ETAPA 3 DE 6 · PRÉ-OFICINA" Foreground="#5EEAD4" FontSize="11" FontWeight="Bold"/>
        </Border>
        <TextBlock Text="Antes de Começar" Foreground="White" FontSize="22" FontWeight="Bold"/>
        <Border HorizontalAlignment="Left" Background="#241B4B" CornerRadius="10" Padding="10,4" Margin="0,6,0,4">
          <TextBlock Text="$roleLabelXaml" Foreground="#5EEAD4" FontSize="13" FontWeight="Bold"/>
        </Border>
        <TextBlock Text="$subtextXaml" Foreground="#A499B8" FontSize="12"/>
      </StackPanel>
      <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
        <StackPanel Margin="0,0,4,0">
          <TextBlock Text="$priorRoboticsXaml" Foreground="White" FontSize="15" FontWeight="Bold" TextWrapping="Wrap" Margin="0,0,0,8"/>
          <UniformGrid Columns="4" Margin="0,0,0,20">
            <RadioButton Name="Prior1" GroupName="Prior" Style="{StaticResource CardRadio}">
              <StackPanel HorizontalAlignment="Center">
                <TextBlock Text="1" FontSize="16" FontWeight="Bold" Foreground="#5EEAD4" HorizontalAlignment="Center" Margin="0,0,0,2"/>
                <TextBlock Text="Nunca" FontSize="12" HorizontalAlignment="Center"/>
              </StackPanel>
            </RadioButton>
            <RadioButton Name="Prior2" GroupName="Prior" Style="{StaticResource CardRadio}">
              <StackPanel HorizontalAlignment="Center">
                <TextBlock Text="2" FontSize="16" FontWeight="Bold" Foreground="#5EEAD4" HorizontalAlignment="Center" Margin="0,0,0,2"/>
                <TextBlock Text="Uma vez" FontSize="12" HorizontalAlignment="Center"/>
              </StackPanel>
            </RadioButton>
            <RadioButton Name="Prior3" GroupName="Prior" Style="{StaticResource CardRadio}">
              <StackPanel HorizontalAlignment="Center">
                <TextBlock Text="3" FontSize="16" FontWeight="Bold" Foreground="#5EEAD4" HorizontalAlignment="Center" Margin="0,0,0,2"/>
                <TextBlock Text="Algumas vezes" FontSize="12" HorizontalAlignment="Center"/>
              </StackPanel>
            </RadioButton>
            <RadioButton Name="Prior4" GroupName="Prior" Style="{StaticResource CardRadio}">
              <StackPanel HorizontalAlignment="Center">
                <TextBlock Text="4" FontSize="16" FontWeight="Bold" Foreground="#5EEAD4" HorizontalAlignment="Center" Margin="0,0,0,2"/>
                <TextBlock Text="Muitas vezes" FontSize="12" HorizontalAlignment="Center"/>
              </StackPanel>
            </RadioButton>
          </UniformGrid>
          <TextBlock Text="$selfEfficacyXaml" Foreground="White" FontSize="15" FontWeight="Bold" TextWrapping="Wrap" Margin="0,0,0,8"/>
          <UniformGrid Columns="4" Margin="0,0,0,8">
            <RadioButton Name="Self1" GroupName="Self" Style="{StaticResource CardRadio}">
              <StackPanel HorizontalAlignment="Center">
                <TextBlock Text="1" FontSize="16" FontWeight="Bold" Foreground="#5EEAD4" HorizontalAlignment="Center" Margin="0,0,0,2"/>
                <TextBlock Text="Discordo muito" FontSize="12" HorizontalAlignment="Center"/>
              </StackPanel>
            </RadioButton>
            <RadioButton Name="Self2" GroupName="Self" Style="{StaticResource CardRadio}">
              <StackPanel HorizontalAlignment="Center">
                <TextBlock Text="2" FontSize="16" FontWeight="Bold" Foreground="#5EEAD4" HorizontalAlignment="Center" Margin="0,0,0,2"/>
                <TextBlock Text="Discordo" FontSize="12" HorizontalAlignment="Center"/>
              </StackPanel>
            </RadioButton>
            <RadioButton Name="Self3" GroupName="Self" Style="{StaticResource CardRadio}">
              <StackPanel HorizontalAlignment="Center">
                <TextBlock Text="3" FontSize="16" FontWeight="Bold" Foreground="#5EEAD4" HorizontalAlignment="Center" Margin="0,0,0,2"/>
                <TextBlock Text="Concordo" FontSize="12" HorizontalAlignment="Center"/>
              </StackPanel>
            </RadioButton>
            <RadioButton Name="Self4" GroupName="Self" Style="{StaticResource CardRadio}">
              <StackPanel HorizontalAlignment="Center">
                <TextBlock Text="4" FontSize="16" FontWeight="Bold" Foreground="#5EEAD4" HorizontalAlignment="Center" Margin="0,0,0,2"/>
                <TextBlock Text="Concordo muito" FontSize="12" HorizontalAlignment="Center"/>
              </StackPanel>
            </RadioButton>
          </UniformGrid>
        </StackPanel>
      </ScrollViewer>
      <Grid Grid.Row="2" Margin="0,16,0,0">
        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="14"/><ColumnDefinition Width="2*"/></Grid.ColumnDefinitions>
        <Button Name="BtnSkip" Grid.Column="0" Content="Prefiro não responder" Style="{StaticResource ModernBtn}" Height="46" Background="#241B4B"/>
        <Button Name="BtnSave" Grid.Column="2" Content="Salvar minha resposta" Style="{StaticResource ModernBtn}" Height="46" Background="#00A7A0" IsEnabled="False"/>
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
        $priorSelected = (@($prior | Where-Object { $_.IsChecked -eq $true }).Count -eq 1)
        $selfSelected = (@($self | Where-Object { $_.IsChecked -eq $true }).Count -eq 1)
        $button.IsEnabled = ($priorSelected -and $selfSelected)
    }
    @($prior) + @($self) | ForEach-Object { $_.add_Checked($validate) }
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
    param([string]$RoleLabel, [int]$IntervalMark, [bool]$AskCollaboration, [bool]$IsLastParticipant = $true, [string]$NextLabel = "")
    $collabVisibility = if ($AskCollaboration) { "Visible" } else { "Collapsed" }
    $roleLabelXaml = [Security.SecurityElement]::Escape($RoleLabel)
    $mentalEffortXaml = [Security.SecurityElement]::Escape([string]$script:Config.questions.mental_effort)
    $progressStateXaml = [Security.SecurityElement]::Escape([string]$script:Config.questions.progress_state)
    $collaborationXaml = [Security.SecurityElement]::Escape([string]$script:Config.questions.collaboration)

    $subtext = if ($script:GroupSize -le 1) {
        "Responda à sua pergunta sobre a atividade."
    } elseif (-not $IsLastParticipant -and -not [string]::IsNullOrWhiteSpace($NextLabel)) {
        "Sua vez ($RoleLabel). Após responder, passe o computador para o $NextLabel."
    } else {
        "Sua vez ($RoleLabel). Esta é a última resposta do grupo neste checkpoint."
    }
    $subtextXaml = [Security.SecurityElement]::Escape($subtext)
    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="PulseLab - Checkpoint"
        Width="680" Height="780" WindowStartupLocation="CenterScreen" WindowStyle="None"
        AllowsTransparency="True" Background="Transparent" Topmost="True">
  <Window.Resources>
    <Style x:Key="ModernBtn" TargetType="Button">
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border Name="BtnBorder" Background="{TemplateBinding Background}" CornerRadius="12" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="BtnBorder" Property="Opacity" Value="0.88"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="BtnBorder" Property="Opacity" Value="0.35"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="CardRadio" TargetType="RadioButton">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Foreground" Value="#E2DBED"/>
      <Setter Property="Margin" Value="4"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RadioButton">
            <Border Name="CardBorder" Background="#201642" BorderBrush="#3D2D7A" BorderThickness="1.5" CornerRadius="12" Padding="8,10">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="CardBorder" Property="BorderBrush" Value="#FF686B"/>
                <Setter TargetName="CardBorder" Property="Background" Value="#2A1E54"/>
              </Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="CardBorder" Property="BorderBrush" Value="#FF686B"/>
                <Setter TargetName="CardBorder" Property="Background" Value="#4A1828"/>
                <Setter Property="Foreground" Value="#FFFFFF"/>
                <Setter Property="FontWeight" Value="Bold"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="OptionRowRadio" TargetType="RadioButton">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Foreground" Value="#E2DBED"/>
      <Setter Property="Margin" Value="0,4"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RadioButton">
            <Border Name="RowBorder" Background="#201642" BorderBrush="#3D2D7A" BorderThickness="1.5" CornerRadius="12" Padding="14,10">
              <ContentPresenter VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="RowBorder" Property="BorderBrush" Value="#5EEAD4"/>
                <Setter TargetName="RowBorder" Property="Background" Value="#2A1E54"/>
              </Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="RowBorder" Property="BorderBrush" Value="#5EEAD4"/>
                <Setter TargetName="RowBorder" Property="Background" Value="#094A46"/>
                <Setter Property="Foreground" Value="#FFFFFF"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="DangerOptionRadio" TargetType="RadioButton">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Foreground" Value="#FFA0A3"/>
      <Setter Property="Margin" Value="0,4"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RadioButton">
            <Border Name="RowBorder" Background="#291427" BorderBrush="#5A243D" BorderThickness="1.5" CornerRadius="12" Padding="14,10">
              <ContentPresenter VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="RowBorder" Property="BorderBrush" Value="#FF686B"/>
                <Setter TargetName="RowBorder" Property="Background" Value="#381834"/>
              </Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="RowBorder" Property="BorderBrush" Value="#FF686B"/>
                <Setter TargetName="RowBorder" Property="Background" Value="#5A1A24"/>
                <Setter Property="Foreground" Value="#FFFFFF"/>
                <Setter Property="FontWeight" Value="Bold"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>
  <Border CornerRadius="24" Background="#110B27" BorderBrush="#FF686B" BorderThickness="2.5" Padding="26">
    <Grid>
      <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
      <StackPanel Grid.Row="0" Margin="0,0,0,16">
        <Border HorizontalAlignment="Left" Background="#2A162B" BorderBrush="#5A243D" BorderThickness="1" CornerRadius="8" Padding="10,4" Margin="0,0,0,8">
          <TextBlock Text="ETAPA 4 DE 6 · CHECKPOINT $IntervalMark MIN" Foreground="#FF8B8E" FontSize="11" FontWeight="Bold"/>
        </Border>
        <TextBlock Text="Como está a atividade agora?" Foreground="White" FontSize="22" FontWeight="Bold"/>
        <Border HorizontalAlignment="Left" Background="#241B4B" CornerRadius="10" Padding="10,4" Margin="0,6,0,4">
          <TextBlock Text="$roleLabelXaml" Foreground="#FF8B8E" FontSize="13" FontWeight="Bold"/>
        </Border>
        <TextBlock Text="$subtextXaml" Foreground="#A499B8" FontSize="12"/>
      </StackPanel>
      <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
        <StackPanel Margin="0,0,4,0">
          <TextBlock Text="O que você mais fez desde o último checkpoint?" Foreground="White" FontSize="15" FontWeight="Bold" TextWrapping="Wrap" Margin="0,0,0,8"/>
          <UniformGrid Columns="3" Margin="0,0,0,20">
            <RadioButton Name="SelfRoleComputer" GroupName="SelfRole" Style="{StaticResource CardRadio}">
              <StackPanel HorizontalAlignment="Center">
                <TextBlock Text="💻" FontSize="24" HorizontalAlignment="Center" Margin="0,0,0,3"/>
                <TextBlock Text="Computador" FontSize="13" FontWeight="Bold" HorizontalAlignment="Center"/>
                <TextBlock Text="Programação" FontSize="10" Foreground="#A499B8" HorizontalAlignment="Center"/>
              </StackPanel>
            </RadioButton>
            <RadioButton Name="SelfRoleAssembly" GroupName="SelfRole" Style="{StaticResource CardRadio}">
              <StackPanel HorizontalAlignment="Center">
                <TextBlock Text="🔧" FontSize="24" HorizontalAlignment="Center" Margin="0,0,0,3"/>
                <TextBlock Text="Montagem" FontSize="13" FontWeight="Bold" HorizontalAlignment="Center"/>
                <TextBlock Text="Peças do robô" FontSize="10" Foreground="#A499B8" HorizontalAlignment="Center"/>
              </StackPanel>
            </RadioButton>
            <RadioButton Name="SelfRoleBoth" GroupName="SelfRole" Style="{StaticResource CardRadio}">
              <StackPanel HorizontalAlignment="Center">
                <TextBlock Text="👥" FontSize="24" HorizontalAlignment="Center" Margin="0,0,0,3"/>
                <TextBlock Text="Ambos" FontSize="13" FontWeight="Bold" HorizontalAlignment="Center"/>
                <TextBlock Text="Fizemos juntos" FontSize="10" Foreground="#A499B8" HorizontalAlignment="Center"/>
              </StackPanel>
            </RadioButton>
          </UniformGrid>

          <TextBlock Text="$mentalEffortXaml" Foreground="White" FontSize="15" FontWeight="Bold" TextWrapping="Wrap" Margin="0,0,0,8"/>
          <UniformGrid Columns="4" Margin="0,0,0,20">
            <RadioButton Name="Effort1" GroupName="Effort" Style="{StaticResource CardRadio}">
              <StackPanel HorizontalAlignment="Center">
                <TextBlock Text="1" FontSize="16" FontWeight="Bold" Foreground="#FF8B8E" HorizontalAlignment="Center" Margin="0,0,0,2"/>
                <TextBlock Text="Muito pouco" FontSize="12" HorizontalAlignment="Center"/>
              </StackPanel>
            </RadioButton>
            <RadioButton Name="Effort2" GroupName="Effort" Style="{StaticResource CardRadio}">
              <StackPanel HorizontalAlignment="Center">
                <TextBlock Text="2" FontSize="16" FontWeight="Bold" Foreground="#FF8B8E" HorizontalAlignment="Center" Margin="0,0,0,2"/>
                <TextBlock Text="Pouco" FontSize="12" HorizontalAlignment="Center"/>
              </StackPanel>
            </RadioButton>
            <RadioButton Name="Effort3" GroupName="Effort" Style="{StaticResource CardRadio}">
              <StackPanel HorizontalAlignment="Center">
                <TextBlock Text="3" FontSize="16" FontWeight="Bold" Foreground="#FF8B8E" HorizontalAlignment="Center" Margin="0,0,0,2"/>
                <TextBlock Text="Bastante" FontSize="12" HorizontalAlignment="Center"/>
              </StackPanel>
            </RadioButton>
            <RadioButton Name="Effort4" GroupName="Effort" Style="{StaticResource CardRadio}">
              <StackPanel HorizontalAlignment="Center">
                <TextBlock Text="4" FontSize="16" FontWeight="Bold" Foreground="#FF8B8E" HorizontalAlignment="Center" Margin="0,0,0,2"/>
                <TextBlock Text="Muito" FontSize="12" HorizontalAlignment="Center"/>
              </StackPanel>
            </RadioButton>
          </UniformGrid>

          <TextBlock Text="$progressStateXaml" Foreground="White" FontSize="15" FontWeight="Bold" TextWrapping="Wrap" Margin="0,0,0,8"/>
          <StackPanel Margin="0,0,0,20">
            <RadioButton Name="Progress1" GroupName="Progress" Style="{StaticResource OptionRowRadio}">
              <Grid>
                <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                <Border Grid.Column="0" Width="10" Height="10" CornerRadius="5" Background="#5EEAD4" Margin="0,0,12,0"/>
                <StackPanel Grid.Column="1">
                  <TextBlock Text="Avançando sem ajuda" FontSize="14" FontWeight="Bold" Foreground="White"/>
                  <TextBlock Text="Estamos conseguindo seguir sem ajuda." FontSize="12" Foreground="#A499B8" Margin="0,2,0,0"/>
                </StackPanel>
              </Grid>
            </RadioButton>
            <RadioButton Name="Progress2" GroupName="Progress" Style="{StaticResource OptionRowRadio}">
              <Grid>
                <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                <Border Grid.Column="0" Width="10" Height="10" CornerRadius="5" Background="#FFD166" Margin="0,0,12,0"/>
                <StackPanel Grid.Column="1">
                  <TextBlock Text="Avançando, mas com dúvida" FontSize="14" FontWeight="Bold" Foreground="White"/>
                  <TextBlock Text="Estamos progredindo, mas ainda inseguros." FontSize="12" Foreground="#A499B8" Margin="0,2,0,0"/>
                </StackPanel>
              </Grid>
            </RadioButton>
            <RadioButton Name="Progress3" GroupName="Progress" Style="{StaticResource OptionRowRadio}">
              <Grid>
                <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                <Border Grid.Column="0" Width="10" Height="10" CornerRadius="5" Background="#FFA066" Margin="0,0,12,0"/>
                <StackPanel Grid.Column="1">
                  <TextBlock Text="Tentando, mas sem conseguir avançar" FontSize="14" FontWeight="Bold" Foreground="White"/>
                  <TextBlock Text="Já tentamos caminhos, mas continuamos no mesmo ponto." FontSize="12" Foreground="#A499B8" Margin="0,2,0,0"/>
                </StackPanel>
              </Grid>
            </RadioButton>
            <RadioButton Name="Progress4" GroupName="Progress" Style="{StaticResource DangerOptionRadio}">
              <Grid>
                <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                <Border Grid.Column="0" Width="10" Height="10" CornerRadius="5" Background="#FF686B" Margin="0,0,12,0"/>
                <StackPanel Grid.Column="1">
                  <TextBlock Text="Precisamos de ajuda agora" FontSize="14" FontWeight="Bold" Foreground="#FFA0A3"/>
                  <TextBlock Text="Queremos chamar o instrutor para nos apoiar." FontSize="12" Foreground="#D199A0" Margin="0,2,0,0"/>
                </StackPanel>
              </Grid>
            </RadioButton>
          </StackPanel>

          <StackPanel Name="CollabPanel" Visibility="$collabVisibility" Margin="0,0,0,16">
            <TextBlock Text="$collaborationXaml" Foreground="White" FontSize="15" FontWeight="Bold" TextWrapping="Wrap" Margin="0,0,0,8"/>
            <UniformGrid Columns="4">
              <RadioButton Name="Collab1" GroupName="Collab" Style="{StaticResource CardRadio}">
                <StackPanel HorizontalAlignment="Center">
                  <TextBlock Text="1" FontSize="16" FontWeight="Bold" Foreground="#FF8B8E" HorizontalAlignment="Center" Margin="0,0,0,2"/>
                  <TextBlock Text="Nunca" FontSize="12" HorizontalAlignment="Center"/>
                </StackPanel>
              </RadioButton>
              <RadioButton Name="Collab2" GroupName="Collab" Style="{StaticResource CardRadio}">
                <StackPanel HorizontalAlignment="Center">
                  <TextBlock Text="2" FontSize="16" FontWeight="Bold" Foreground="#FF8B8E" HorizontalAlignment="Center" Margin="0,0,0,2"/>
                  <TextBlock Text="Algumas vezes" FontSize="12" HorizontalAlignment="Center"/>
                </StackPanel>
              </RadioButton>
              <RadioButton Name="Collab3" GroupName="Collab" Style="{StaticResource CardRadio}">
                <StackPanel HorizontalAlignment="Center">
                  <TextBlock Text="3" FontSize="16" FontWeight="Bold" Foreground="#FF8B8E" HorizontalAlignment="Center" Margin="0,0,0,2"/>
                  <TextBlock Text="Quase sempre" FontSize="12" HorizontalAlignment="Center"/>
                </StackPanel>
              </RadioButton>
              <RadioButton Name="Collab4" GroupName="Collab" Style="{StaticResource CardRadio}">
                <StackPanel HorizontalAlignment="Center">
                  <TextBlock Text="4" FontSize="16" FontWeight="Bold" Foreground="#FF8B8E" HorizontalAlignment="Center" Margin="0,0,0,2"/>
                  <TextBlock Text="Sempre" FontSize="12" HorizontalAlignment="Center"/>
                </StackPanel>
              </RadioButton>
            </UniformGrid>
          </StackPanel>
        </StackPanel>
      </ScrollViewer>
      <Grid Grid.Row="2" Margin="0,16,0,0">
        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="14"/><ColumnDefinition Width="2*"/></Grid.ColumnDefinitions>
        <Button Name="BtnSkip" Grid.Column="0" Content="Prefiro não responder" Style="{StaticResource ModernBtn}" Height="46" Background="#241B4B"/>
        <Button Name="BtnSave" Grid.Column="2" Content="Salvar minha resposta" Style="{StaticResource ModernBtn}" Height="46" Background="#FF686B" IsEnabled="False"/>
      </Grid>
    </Grid>
  </Border>
</Window>
"@
    $window = [Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader ([xml]$xaml)))
    $selfRoleComp = $window.FindName("SelfRoleComputer")
    $selfRoleAssy = $window.FindName("SelfRoleAssembly")
    $selfRoleBoth = $window.FindName("SelfRoleBoth")
    $effort = 1..4 | ForEach-Object { $window.FindName("Effort$_") }
    $progress = 1..4 | ForEach-Object { $window.FindName("Progress$_") }
    $collab = 1..4 | ForEach-Object { $window.FindName("Collab$_") }
    $button = $window.FindName("BtnSave")
    $skip = $window.FindName("BtnSkip")
    $result = @{ Status = $false; Declined = $false; SelfReportedRole = $null; MentalEffort = $null; ProgressState = $null; Collaboration = $null; LatencyMs = 0 }
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $validate = {
        $roleComplete = ($selfRoleComp.IsChecked -eq $true -or $selfRoleAssy.IsChecked -eq $true -or $selfRoleBoth.IsChecked -eq $true)
        $baseComplete = (@($effort | Where-Object { $_.IsChecked -eq $true }).Count -eq 1 -and @($progress | Where-Object { $_.IsChecked -eq $true }).Count -eq 1)
        $collabComplete = (-not $AskCollaboration -or @($collab | Where-Object { $_.IsChecked -eq $true }).Count -eq 1)
        $button.IsEnabled = ($roleComplete -and $baseComplete -and $collabComplete)
    }
    @($selfRoleComp, $selfRoleAssy, $selfRoleBoth) | ForEach-Object { $_.add_Checked($validate) }
    @($effort + $progress + $collab) | ForEach-Object { $_.add_Checked($validate) }
    $button.add_Click({
        if ($selfRoleComp.IsChecked) { $result.SelfReportedRole = "computer" }
        elseif ($selfRoleAssy.IsChecked) { $result.SelfReportedRole = "assembly" }
        elseif ($selfRoleBoth.IsChecked) { $result.SelfReportedRole = "both" }
        for ($i = 0; $i -lt 4; $i++) {
            if ($effort[$i].IsChecked) { $result.MentalEffort = $i + 1 }
        }
        $states = @("progressing_independently", "progressing_with_doubt", "trying_without_progress", "needs_help_now")
        for ($i = 0; $i -lt 4; $i++) {
            if ($progress[$i].IsChecked) { $result.ProgressState = $states[$i] }
        }
        if ($AskCollaboration) {
            for ($i = 0; $i -lt 4; $i++) {
                if ($collab[$i].IsChecked) { $result.Collaboration = $i + 1 }
            }
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

    $participantALabelXaml = [Security.SecurityElement]::Escape($ParticipantALabel)
    $participantBLabelXaml = [Security.SecurityElement]::Escape($ParticipantBLabel)
    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="PulseLab - Troca de papéis"
        Width="580" Height="400" WindowStartupLocation="CenterScreen" WindowStyle="None"
        AllowsTransparency="True" Background="Transparent" Topmost="True">
  <Window.Resources>
    <Style x:Key="ModernBtn" TargetType="Button">
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="FontSize" Value="15"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border Name="BtnBorder" Background="{TemplateBinding Background}" CornerRadius="12" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="BtnBorder" Property="Opacity" Value="0.88"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="BtnBorder" Property="Opacity" Value="0.35"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>
  <Border CornerRadius="24" Background="#110B27" BorderBrush="#FFD166" BorderThickness="2.5" Padding="28">
    <Grid>
      <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
      <StackPanel Grid.Row="0" Margin="0,0,0,16">
        <Border HorizontalAlignment="Left" Background="#2F2312" BorderBrush="#5E4317" BorderThickness="1" CornerRadius="8" Padding="10,4" Margin="0,0,0,8">
          <TextBlock Text="ETAPA 4 DE 6 · EQUILÍBRIO DE PARTICIPAÇÃO" Foreground="#FFD166" FontSize="11" FontWeight="Bold"/>
        </Border>
        <TextBlock Text="Troquem os Papéis" Foreground="White" FontSize="22" FontWeight="Bold"/>
        <TextBlock Text="A troca ajuda os dois integrantes a experimentar partes diferentes da atividade." Foreground="#A499B8" FontSize="13" TextWrapping="Wrap" Margin="0,4,0,0"/>
      </StackPanel>
      <Grid Grid.Row="1" VerticalAlignment="Center" Margin="0,10,0,16">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="60"/>
          <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>
        <Border Grid.Column="0" Background="#201642" BorderBrush="#3D2D7A" BorderThickness="1.5" CornerRadius="14" Padding="16,14">
          <StackPanel HorizontalAlignment="Center">
            <Border Width="34" Height="34" CornerRadius="17" Background="#3D2D7A" HorizontalAlignment="Center" Margin="0,0,0,8">
              <TextBlock Text="A" Foreground="#FFD166" FontWeight="Bold" FontSize="15" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <TextBlock Text="$participantALabelXaml" Foreground="White" FontSize="13" FontWeight="Bold" TextAlignment="Center" TextWrapping="Wrap"/>
          </StackPanel>
        </Border>
        <Border Grid.Column="1" Width="38" Height="38" CornerRadius="19" Background="#3A2800" BorderBrush="#FFD166" BorderThickness="1.5" HorizontalAlignment="Center" VerticalAlignment="Center">
          <TextBlock Text="⇄" Foreground="#FFD166" FontSize="18" FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Border>
        <Border Grid.Column="2" Background="#201642" BorderBrush="#3D2D7A" BorderThickness="1.5" CornerRadius="14" Padding="16,14">
          <StackPanel HorizontalAlignment="Center">
            <Border Width="34" Height="34" CornerRadius="17" Background="#3D2D7A" HorizontalAlignment="Center" Margin="0,0,0,8">
              <TextBlock Text="B" Foreground="#FFD166" FontWeight="Bold" FontSize="15" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <TextBlock Text="$participantBLabelXaml" Foreground="White" FontSize="13" FontWeight="Bold" TextAlignment="Center" TextWrapping="Wrap"/>
          </StackPanel>
        </Border>
      </Grid>
      <Button Name="BtnConfirm" Grid.Row="2" Content="Papéis trocados · Continuar" Style="{StaticResource ModernBtn}" Height="48" Background="#B78600" Foreground="White" FontWeight="Bold"/>
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
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="PulseLab - Registro do instrutor"
        Width="580" Height="520" WindowStartupLocation="CenterScreen" WindowStyle="None"
        AllowsTransparency="True" Background="Transparent" Topmost="True">
  <Window.Resources>
    <Style x:Key="ModernBtn" TargetType="Button">
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border Name="BtnBorder" Background="{TemplateBinding Background}" CornerRadius="12" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="BtnBorder" Property="Opacity" Value="0.88"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="BtnBorder" Property="Opacity" Value="0.35"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>
  <Border CornerRadius="24" Background="#110B27" BorderBrush="#7C3AED" BorderThickness="2.5" Padding="28">
    <Grid>
      <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
      <StackPanel Grid.Row="0" Margin="0,0,0,16">
        <Border HorizontalAlignment="Left" Background="#201545" BorderBrush="#3D2D7A" BorderThickness="1" CornerRadius="8" Padding="10,4" Margin="0,0,0,8">
          <TextBlock Text="ETAPA 5 DE 6 · SOMENTE INSTRUTOR" Foreground="#A78BFA" FontSize="11" FontWeight="Bold"/>
        </Border>
        <TextBlock Text="Registro do Instrutor" Foreground="White" FontSize="22" FontWeight="Bold"/>
        <TextBlock Text="Avalie a dupla antes de chamar os participantes para o encerramento." Foreground="#A499B8" FontSize="12" Margin="0,3,0,0"/>
      </StackPanel>
      <StackPanel Grid.Row="1">
        <TextBlock Text="Desempenho da missão" Foreground="White" FontWeight="Bold" FontSize="13" Margin="0,0,0,4"/>
        <ComboBox Name="Mission" Height="38" Margin="0,0,0,16" Background="#17102E" Foreground="Black">
          <ComboBoxItem Content="0 · Não executou a missão"/><ComboBoxItem Content="1 · Executou parcialmente"/>
          <ComboBoxItem Content="2 · Concluiu com muita ajuda"/><ComboBoxItem Content="3 · Concluiu com pouca ou nenhuma ajuda"/>
        </ComboBox>
        <TextBlock Text="Quantidade aproximada de intervenções" Foreground="White" FontWeight="Bold" FontSize="13" Margin="0,0,0,4"/>
        <ComboBox Name="Interventions" Height="38" Margin="0,0,0,16" Background="#17102E" Foreground="Black">
          <ComboBoxItem Content="0"/><ComboBoxItem Content="1"/><ComboBoxItem Content="2"/><ComboBoxItem Content="3 ou mais"/>
        </ComboBox>
        <TextBlock Text="Principal dificuldade observada" Foreground="White" FontWeight="Bold" FontSize="13" Margin="0,0,0,4"/>
        <ComboBox Name="Issue" Height="38" Margin="0,0,0,16" Background="#17102E" Foreground="Black">
          <ComboBoxItem Content="Nenhuma"/><ComboBoxItem Content="Montagem"/><ComboBoxItem Content="Lógica de programação"/>
          <ComboBoxItem Content="Sensor"/><ComboBoxItem Content="Problema técnico"/><ComboBoxItem Content="Colaboração"/><ComboBoxItem Content="Outra"/>
        </ComboBox>
      </StackPanel>
      <Button Name="BtnSave" Grid.Row="2" Content="Salvar Avaliação da Dupla" Style="{StaticResource ModernBtn}" Height="46" Background="#7C3AED" Foreground="White" IsEnabled="False"/>
    </Grid>
  </Border>
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
    param([string]$RoleLabel, [bool]$IsLastParticipant = $true, [string]$NextLabel = "")
    $roleLabelXaml = [Security.SecurityElement]::Escape($RoleLabel)
    $postUnderstandingXaml = [Security.SecurityElement]::Escape([string]$script:Config.questions.post_understanding)
    $postAffectXaml = [Security.SecurityElement]::Escape([string]$script:Config.questions.post_affect)
    $postReturnXaml = [Security.SecurityElement]::Escape([string]$script:Config.questions.post_return)

    $subtext = if ($script:GroupSize -le 1) {
        "Responda sozinho. Não existem respostas certas ou erradas."
    } elseif (-not $IsLastParticipant -and -not [string]::IsNullOrWhiteSpace($NextLabel)) {
        "Sua vez ($RoleLabel). Após responder, passe o computador para o $NextLabel."
    } else {
        "Sua vez ($RoleLabel). Esta é a última resposta do grupo no encerramento."
    }
    $subtextXaml = [Security.SecurityElement]::Escape($subtext)
    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="PulseLab - Encerramento"
        Width="680" Height="740" WindowStartupLocation="CenterScreen" WindowStyle="None"
        AllowsTransparency="True" Background="Transparent" Topmost="True">
  <Window.Resources>
    <Style x:Key="ModernBtn" TargetType="Button">
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border Name="BtnBorder" Background="{TemplateBinding Background}" CornerRadius="12" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="BtnBorder" Property="Opacity" Value="0.88"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="BtnBorder" Property="Opacity" Value="0.35"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="CardRadio" TargetType="RadioButton">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Foreground" Value="#E2DBED"/>
      <Setter Property="Margin" Value="4"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RadioButton">
            <Border Name="CardBorder" Background="#201642" BorderBrush="#3D2D7A" BorderThickness="1.5" CornerRadius="12" Padding="8,10">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="CardBorder" Property="BorderBrush" Value="#8B62E8"/>
                <Setter TargetName="CardBorder" Property="Background" Value="#2A1E54"/>
              </Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="CardBorder" Property="BorderBrush" Value="#8B62E8"/>
                <Setter TargetName="CardBorder" Property="Background" Value="#382062"/>
                <Setter Property="Foreground" Value="#FFFFFF"/>
                <Setter Property="FontWeight" Value="Bold"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="CardCheckbox" TargetType="CheckBox">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Foreground" Value="#E2DBED"/>
      <Setter Property="Margin" Value="4"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="CheckBox">
            <Border Name="CardBorder" Background="#201642" BorderBrush="#3D2D7A" BorderThickness="1.5" CornerRadius="12" Padding="12,10">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="CardBorder" Property="BorderBrush" Value="#8B62E8"/>
                <Setter TargetName="CardBorder" Property="Background" Value="#2A1E54"/>
              </Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="CardBorder" Property="BorderBrush" Value="#8B62E8"/>
                <Setter TargetName="CardBorder" Property="Background" Value="#382062"/>
                <Setter Property="Foreground" Value="#FFFFFF"/>
                <Setter Property="FontWeight" Value="Bold"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>
  <Border CornerRadius="24" Background="#110B27" BorderBrush="#8B62E8" BorderThickness="2.5" Padding="26">
    <Grid>
      <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
      <StackPanel Grid.Row="0" Margin="0,0,0,16">
        <Border HorizontalAlignment="Left" Background="#251745" BorderBrush="#4A2D87" BorderThickness="1" CornerRadius="8" Padding="10,4" Margin="0,0,0,8">
          <TextBlock Text="ETAPA 5 DE 6 · ENCERRAMENTO" Foreground="#B9A0FF" FontSize="11" FontWeight="Bold"/>
        </Border>
        <TextBlock Text="Como foi a experiência hoje?" Foreground="White" FontSize="22" FontWeight="Bold"/>
        <Border HorizontalAlignment="Left" Background="#241B4B" CornerRadius="10" Padding="10,4" Margin="0,6,0,4">
          <TextBlock Text="$roleLabelXaml" Foreground="#B9A0FF" FontSize="13" FontWeight="Bold"/>
        </Border>
        <TextBlock Text="$subtextXaml" Foreground="#A499B8" FontSize="12"/>
      </StackPanel>
      <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
        <StackPanel Margin="0,0,4,0">
          <TextBlock Text="$postUnderstandingXaml" Foreground="White" FontSize="15" FontWeight="Bold" TextWrapping="Wrap" Margin="0,0,0,8"/>
          <UniformGrid Columns="4" Margin="0,0,0,20">
            <RadioButton Name="Understand1" GroupName="Understand" Style="{StaticResource CardRadio}">
              <StackPanel HorizontalAlignment="Center">
                <TextBlock Text="1" FontSize="16" FontWeight="Bold" Foreground="#B9A0FF" HorizontalAlignment="Center" Margin="0,0,0,2"/>
                <TextBlock Text="Discordo muito" FontSize="12" HorizontalAlignment="Center"/>
              </StackPanel>
            </RadioButton>
            <RadioButton Name="Understand2" GroupName="Understand" Style="{StaticResource CardRadio}">
              <StackPanel HorizontalAlignment="Center">
                <TextBlock Text="2" FontSize="16" FontWeight="Bold" Foreground="#B9A0FF" HorizontalAlignment="Center" Margin="0,0,0,2"/>
                <TextBlock Text="Discordo" FontSize="12" HorizontalAlignment="Center"/>
              </StackPanel>
            </RadioButton>
            <RadioButton Name="Understand3" GroupName="Understand" Style="{StaticResource CardRadio}">
              <StackPanel HorizontalAlignment="Center">
                <TextBlock Text="3" FontSize="16" FontWeight="Bold" Foreground="#B9A0FF" HorizontalAlignment="Center" Margin="0,0,0,2"/>
                <TextBlock Text="Concordo" FontSize="12" HorizontalAlignment="Center"/>
              </StackPanel>
            </RadioButton>
            <RadioButton Name="Understand4" GroupName="Understand" Style="{StaticResource CardRadio}">
              <StackPanel HorizontalAlignment="Center">
                <TextBlock Text="4" FontSize="16" FontWeight="Bold" Foreground="#B9A0FF" HorizontalAlignment="Center" Margin="0,0,0,2"/>
                <TextBlock Text="Concordo muito" FontSize="12" HorizontalAlignment="Center"/>
              </StackPanel>
            </RadioButton>
          </UniformGrid>

          <TextBlock Text="$postAffectXaml" Foreground="White" FontSize="15" FontWeight="Bold" TextWrapping="Wrap" Margin="0,0,0,8"/>
          <UniformGrid Columns="3" Margin="0,0,0,4">
            <CheckBox Name="AffectCurious" Style="{StaticResource CardCheckbox}">
              <StackPanel HorizontalAlignment="Center">
                <TextBlock Text="🔍" FontSize="20" HorizontalAlignment="Center" Margin="0,0,0,2"/>
                <TextBlock Text="Curioso" FontSize="13" FontWeight="Bold" HorizontalAlignment="Center"/>
              </StackPanel>
            </CheckBox>
            <CheckBox Name="AffectConfident" Style="{StaticResource CardCheckbox}">
              <StackPanel HorizontalAlignment="Center">
                <TextBlock Text="💪" FontSize="20" HorizontalAlignment="Center" Margin="0,0,0,2"/>
                <TextBlock Text="Confiante" FontSize="13" FontWeight="Bold" HorizontalAlignment="Center"/>
              </StackPanel>
            </CheckBox>
            <CheckBox Name="AffectExcited" Style="{StaticResource CardCheckbox}">
              <StackPanel HorizontalAlignment="Center">
                <TextBlock Text="⚡" FontSize="20" HorizontalAlignment="Center" Margin="0,0,0,2"/>
                <TextBlock Text="Animado" FontSize="13" FontWeight="Bold" HorizontalAlignment="Center"/>
              </StackPanel>
            </CheckBox>
            <CheckBox Name="AffectFrustrated" Style="{StaticResource CardCheckbox}">
              <StackPanel HorizontalAlignment="Center">
                <TextBlock Text="😤" FontSize="20" HorizontalAlignment="Center" Margin="0,0,0,2"/>
                <TextBlock Text="Frustrado" FontSize="13" FontWeight="Bold" HorizontalAlignment="Center"/>
              </StackPanel>
            </CheckBox>
            <CheckBox Name="AffectTired" Style="{StaticResource CardCheckbox}">
              <StackPanel HorizontalAlignment="Center">
                <TextBlock Text="🥱" FontSize="20" HorizontalAlignment="Center" Margin="0,0,0,2"/>
                <TextBlock Text="Cansado" FontSize="13" FontWeight="Bold" HorizontalAlignment="Center"/>
              </StackPanel>
            </CheckBox>
            <CheckBox Name="AffectIndifferent" Style="{StaticResource CardCheckbox}">
              <StackPanel HorizontalAlignment="Center">
                <TextBlock Text="😐" FontSize="20" HorizontalAlignment="Center" Margin="0,0,0,2"/>
                <TextBlock Text="Indiferente" FontSize="13" FontWeight="Bold" HorizontalAlignment="Center"/>
              </StackPanel>
            </CheckBox>
          </UniformGrid>
          <TextBlock Name="AffectHint" Text="Escolha uma ou duas opções." Foreground="#BDB8D0" FontSize="12" Margin="4,0,0,20"/>

          <TextBlock Text="$postReturnXaml" Foreground="White" FontSize="15" FontWeight="Bold" TextWrapping="Wrap" Margin="0,0,0,8"/>
          <UniformGrid Columns="4" Margin="0,0,0,8">
            <RadioButton Name="Return1" GroupName="Return" Style="{StaticResource CardRadio}">
              <StackPanel HorizontalAlignment="Center">
                <TextBlock Text="1" FontSize="16" FontWeight="Bold" Foreground="#B9A0FF" HorizontalAlignment="Center" Margin="0,0,0,2"/>
                <TextBlock Text="Não" FontSize="12" HorizontalAlignment="Center"/>
              </StackPanel>
            </RadioButton>
            <RadioButton Name="Return2" GroupName="Return" Style="{StaticResource CardRadio}">
              <StackPanel HorizontalAlignment="Center">
                <TextBlock Text="2" FontSize="16" FontWeight="Bold" Foreground="#B9A0FF" HorizontalAlignment="Center" Margin="0,0,0,2"/>
                <TextBlock Text="Talvez não" FontSize="12" HorizontalAlignment="Center"/>
              </StackPanel>
            </RadioButton>
            <RadioButton Name="Return3" GroupName="Return" Style="{StaticResource CardRadio}">
              <StackPanel HorizontalAlignment="Center">
                <TextBlock Text="3" FontSize="16" FontWeight="Bold" Foreground="#B9A0FF" HorizontalAlignment="Center" Margin="0,0,0,2"/>
                <TextBlock Text="Talvez sim" FontSize="12" HorizontalAlignment="Center"/>
              </StackPanel>
            </RadioButton>
            <RadioButton Name="Return4" GroupName="Return" Style="{StaticResource CardRadio}">
              <StackPanel HorizontalAlignment="Center">
                <TextBlock Text="4" FontSize="16" FontWeight="Bold" Foreground="#B9A0FF" HorizontalAlignment="Center" Margin="0,0,0,2"/>
                <TextBlock Text="Sim" FontSize="12" HorizontalAlignment="Center"/>
              </StackPanel>
            </RadioButton>
          </UniformGrid>
        </StackPanel>
      </ScrollViewer>
      <Grid Grid.Row="2" Margin="0,16,0,0">
        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="14"/><ColumnDefinition Width="2*"/></Grid.ColumnDefinitions>
        <Button Name="BtnSkip" Grid.Column="0" Content="Prefiro não responder" Style="{StaticResource ModernBtn}" Height="46" Background="#241B4B"/>
        <Button Name="BtnSave" Grid.Column="2" Content="Salvar e concluir" Style="{StaticResource ModernBtn}" Height="46" Background="#8B62E8" IsEnabled="False"/>
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
        $button.IsEnabled = (@($understand | Where-Object { $_.IsChecked -eq $true }).Count -eq 1 -and
            @($returns | Where-Object { $_.IsChecked -eq $true }).Count -eq 1 -and $affectCount -ge 1 -and $affectCount -le 2)
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

function Show-WpfFinished {
    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="PulseLab - Oficina Concluída"
        Width="580" Height="360" WindowStartupLocation="CenterScreen" WindowStyle="None"
        AllowsTransparency="True" Background="Transparent" Topmost="True">
  <Window.Resources>
    <Style x:Key="ModernBtn" TargetType="Button">
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="FontSize" Value="15"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border Name="BtnBorder" Background="{TemplateBinding Background}" CornerRadius="12" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="BtnBorder" Property="Opacity" Value="0.88"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="BtnBorder" Property="Opacity" Value="0.35"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>
  <Border CornerRadius="24" Background="#110B27" BorderBrush="#00A7A0" BorderThickness="2.5" Padding="32">
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>
      <StackPanel Grid.Row="0" VerticalAlignment="Center" HorizontalAlignment="Center">
        <TextBlock Text="🚀" FontSize="52" HorizontalAlignment="Center" Margin="0,0,0,12"/>
        <TextBlock Text="OFICINA CONCLUÍDA!" Foreground="#5EEAD4" FontSize="24" FontWeight="Bold" HorizontalAlignment="Center"/>
        <TextBlock Text="Muito obrigado por sua participação na atividade de hoje!" Foreground="#E2DBED" FontSize="15" Margin="0,10,0,0" TextWrapping="Wrap" HorizontalAlignment="Center" TextAlignment="Center"/>
      </StackPanel>
      <Button Name="BtnClose" Grid.Row="1" Content="Fechar" Style="{StaticResource ModernBtn}" Height="46" Background="#00A7A0" Foreground="White" Margin="0,16,0,0"/>
    </Grid>
  </Border>
</Window>
"@
    $window = [Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader ([xml]$xaml)))
    $window.FindName("BtnClose").add_Click({
        $window.DialogResult = $true
        $window.Close()
    })
    $timer = New-Object Windows.Forms.Timer
    $timer.Interval = 5000
    $timer.add_Tick({ $timer.Stop(); $window.Close() })
    $timer.Start()
    $window.ShowDialog() | Out-Null
    $timer.Stop()
}

function Initialize-TrayIcon {
    $script:NotifyIcon = New-Object Windows.Forms.NotifyIcon
    $script:NotifyIcon.Icon = [Drawing.SystemIcons]::Application
    $script:NotifyIcon.Text = "PulseLab - Oficina em andamento"
    $script:NotifyIcon.Visible = $true
    $menu = New-Object Windows.Forms.ContextMenu
    $reconfig = New-Object Windows.Forms.MenuItem "Reconfigurar Contexto da Máquina"
    $reconfig.add_Click({
        if ($script:CollectionAuthorized) {
            [Windows.MessageBox]::Show(
                "O contexto está congelado para a sessão ativa para garantir a integridade científica da coleta.",
                "PulseLab",
                [Windows.MessageBoxButton]::OK,
                [Windows.MessageBoxImage]::Information
            ) | Out-Null
        } else {
            Show-WpfSessionSetup | Out-Null
        }
    })
    $finish = New-Object Windows.Forms.MenuItem "Concluir Oficina"
    $finish.add_Click({
        if (-not $script:TriggerEnding) {
            $script:EndingRequestedAt = [DateTimeOffset]::Now
            $script:TriggerEnding = $true
            Write-PulseLog "INFO" "Manual ending requested."
        }
    })
    $menu.MenuItems.Add($reconfig) | Out-Null
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
    param(
        [string]$ParticipantId, [string]$Role, [string]$Label,
        [bool]$IsLastParticipant = $true, [string]$NextLabel = ""
    )
    $result = Show-WpfPreSurvey $Label $IsLastParticipant $NextLabel
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
        [string]$ActivityStage,
        [bool]$IsLastParticipant = $true, [string]$NextLabel = ""
    )

    $promptedAt = [DateTimeOffset]::Now
    $elapsedAtPrompt = Get-CurrentElapsedMs
    $latenessMs = [Math]::Max(0, [int][Math]::Round(($promptedAt - $ScheduledAt).TotalMilliseconds))
    $result = Show-WpfCheckpoint $Label $Mark $AskCollaboration $IsLastParticipant $NextLabel
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
        if ($result.SelfReportedRole) { $event["self_reported_role"] = [string]$result.SelfReportedRole }
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
    param(
        [string]$ParticipantId, [string]$Role, [string]$Label,
        [Nullable[int]]$MissionPerformance = $null,
        [Nullable[int]]$InstructorInterventions = $null,
        [string]$PrimaryIssue = $null,
        [bool]$IsLastParticipant = $true, [string]$NextLabel = ""
    )
    $result = Show-WpfPostSurvey $Label $IsLastParticipant $NextLabel
    $event = New-ResearchEvent $ParticipantId $Role "post" $null
    $event["response_latency_ms"] = [int]$result.LatencyMs
    $event["elapsed_ms"] = Get-CurrentElapsedMs
    if ($null -ne $MissionPerformance) { $event["mission_performance"] = [int]$MissionPerformance }
    if ($null -ne $InstructorInterventions) { $event["instructor_interventions"] = [int]$InstructorInterventions }
    if (-not [string]::IsNullOrWhiteSpace($PrimaryIssue)) { $event["primary_issue"] = [string]$PrimaryIssue }
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
    if ($Role -eq "assembly") { return "montagem e testes" }
    if ($Role -eq "individual") { return "trabalho individual" }
    if ($Role -eq "member_3") { return "suporte e testes" }
    if ($Role -eq "member_4") { return "documentação e apoio" }
    return $Role
}

function Get-CurrentElapsedMs {
    if (-not $script:ActivityStartedAt) { return 0L }
    $elapsed = [long][Math]::Max(0L, [long][Math]::Round(([DateTimeOffset]::Now - $script:ActivityStartedAt).TotalMilliseconds))
    return $elapsed
}

function Get-CheckpointTargetMs {
    param([int]$Mark)

    $noWaitDebug = ($script:Config.PSObject.Properties.Name -contains "debug_no_wait" -and [bool]$script:Config.debug_no_wait)
    if ($noWaitDebug) { return 0L }
    if ($script:Config.debug_mode) { return [long]$Mark * 1000L }
    return [long]$Mark * 60000L
}

function Invoke-HeartbeatIfDue {
    $elapsed = Get-CurrentElapsedMs
    if ($elapsed -lt $script:NextHeartbeatElapsedMs) { return }

    $intervalSeconds = if ($script:Config -and $script:Config.PSObject.Properties.Name -contains "heartbeat_interval_seconds") {
        [Math]::Max(15, [int]$script:Config.heartbeat_interval_seconds)
    } else {
        60
    }
    $script:NextHeartbeatElapsedMs = $elapsed + ([long]$intervalSeconds * 1000L)

    $telemetry = Get-ActiveTelemetry
    $script:LastReportedClicks = $telemetry.MouseClicksTotal
    $script:LastReportedKeystrokes = $telemetry.KeystrokesTotal
    $spikeDetected = ((Get-SpikeWindowHandle) -ne [IntPtr]::Zero)
    Submit-SessionEvent "heartbeat" "info" $null $null $null $null $elapsed $null @{
        app_category = [string]$telemetry.ForegroundApp
        idle_seconds = [int]$telemetry.IdleSeconds
        spike_window_detected = $spikeDetected
        ending_requested = [bool]$script:TriggerEnding
        mouse_clicks_interval = [long]$telemetry.MouseClicksInterval
        keystrokes_interval = [long]$telemetry.KeystrokesInterval
        mouse_clicks_total = [long]$telemetry.MouseClicksTotal
        keystrokes_total = [long]$telemetry.KeystrokesTotal
    }
}

function Wait-UntilActivityTime {
    param([DateTimeOffset]$ScheduledAt)

    while ([DateTimeOffset]::Now -lt $ScheduledAt -and -not $script:TriggerEnding) {
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
        $elapsed = Get-CurrentElapsedMs
        Submit-SessionEvent "role_swapped" "info" $Mark $null $null $ActivityStage $elapsed $null @{
            participant_a_role = $script:ParticipantComputerRole
            participant_b_role = $script:ParticipantAssemblyRole
        }
        Save-SessionState "role_swap_$Mark" $Mark
    } else {
        $elapsed = Get-CurrentElapsedMs
        Submit-SessionEvent "quality_issue" "warning" $Mark $null $null $ActivityStage $elapsed $null @{
            code = "role_swap_not_confirmed"
        }
    }
}

function Start-ResearchLoop {
    $participants = Get-ParticipantList
    $marks = [int[]]$script:Config.interval_marks_minutes
    if (-not $script:IsResumedSession -or -not $script:ActivityStartedAt) {
        $script:ActivityStartedAt = [DateTimeOffset]::Now
    }
    $script:ActivityStopwatch = [Diagnostics.Stopwatch]::StartNew()
    $heartbeatSeconds = if ($script:Config.PSObject.Properties.Name -contains "heartbeat_interval_seconds") {
        [Math]::Max(15, [int]$script:Config.heartbeat_interval_seconds)
    } else {
        60
    }
    $initialElapsed = Get-CurrentElapsedMs
    $script:NextHeartbeatElapsedMs = $initialElapsed + ([long]$heartbeatSeconds * 1000L)

    if (-not $script:IsResumedSession) {
        Submit-SessionEvent "activity_started" "info" $null $null $null $null $initialElapsed $null @{
            interval_marks_minutes = $marks
            screenshot_enabled = [bool]$script:Config.screenshot_enabled
        }
        Save-SessionState "activity"
    }

    foreach ($mark in $marks) {
        if ($script:TriggerEnding) { break }
        if ($script:CompletedCheckpoints -contains $mark) {
            Write-PulseLog "INFO" "Checkpoint mark $mark min already completed in resumed session; skipping."
            continue
        }

        $targetElapsedMs = Get-CheckpointTargetMs $mark
        $scheduledAt = $script:ActivityStartedAt.AddMilliseconds($targetElapsedMs)
        Wait-UntilActivityTime $scheduledAt
        if ($script:TriggerEnding) { break }

        $script:SpikeHandle = Get-SpikeWindowHandle
        $telemetry = Get-ActiveTelemetry
        $fileSize = Get-LastSpikeFileSize
        $capturedAt = [DateTimeOffset]::Now
        $elapsedAtCapture = Get-CurrentElapsedMs
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
            mouse_clicks_interval = [long]$telemetry.MouseClicksInterval
            keystrokes_interval = [long]$telemetry.KeystrokesInterval
            mouse_clicks_total = [long]$telemetry.MouseClicksTotal
            keystrokes_total = [long]$telemetry.KeystrokesTotal
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

        $askCollaboration = ($script:GroupSize -gt 1 -and [int[]]$script:Config.collaboration_marks_minutes -contains $mark)
        $participants = Get-ParticipantList
        $checkpointStatuses = @{}
        for ($i = 0; $i -lt $participants.Count; $i++) {
            $p = $participants[$i]
            $isLast = ($i -eq $participants.Count - 1)
            $nextLabel = if ($isLast) { "" } else { [string]$participants[$i + 1].Label }
            $st = Save-CheckpointSurvey $p.Id $p.Role $p.Label $mark $askCollaboration $telemetry $fileSize $privatePath $localScreenshot $scheduledAt $capturedAt $activityStage $isLast $nextLabel
            $checkpointStatuses["participant_$($p.Letter.ToLower())_status"] = $st
        }
        Restore-SpikeFocus $script:SpikeHandle

        $elapsedAfterResponses = Get-CurrentElapsedMs
        Submit-SessionEvent "checkpoint_completed" "info" $mark $null $null $activityStage $elapsedAfterResponses $scheduledAt $checkpointStatuses
        Save-SessionState "checkpoint_$mark" $mark
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

    $elapsedAtEnding = Get-CurrentElapsedMs
    Submit-SessionEvent "ending_requested" "info" $null $null $null $null $elapsedAtEnding $null @{
        requested_at = if ($script:EndingRequestedAt) { $script:EndingRequestedAt.ToString("o") } else { $null }
    }

    # Instructor Rubric removed - proceed directly to student post-survey
    $rubricResult = $null

    # Refresh participant list (with swapped roles if applicable)
    $participants = Get-ParticipantList
    $postStatuses = @{ phase = "post" }
    for ($i = 0; $i -lt $participants.Count; $i++) {
        $p = $participants[$i]
        $isLast = ($i -eq $participants.Count - 1)
        $nextLabel = if ($isLast) { "" } else { [string]$participants[$i + 1].Label }
        $st = Save-PostSurvey $p.Id $p.Role $p.Label $null $null $null $isLast $nextLabel
        $postStatuses["participant_$($p.Letter.ToLower())_status"] = $st
    }
    $elapsedAfterPost = Get-CurrentElapsedMs
    Submit-SessionEvent "phase_completed" "info" $null $null $null "post" $elapsedAfterPost $null $postStatuses
    Submit-SessionEvent "session_completed" "info" $null $null $null $null $elapsedAfterPost $null @{
        checkpoint_count = $script:CompletedCheckpoints.Count
        completed_checkpoints = $script:CompletedCheckpoints
        expected_checkpoints = $marks
        expected_checkpoints_count = $marks.Count
        completion_reason = if ($script:TriggerEnding -and $script:CompletedCheckpoints.Count -lt $marks.Count) { "early_termination" } else { "finished_normally" }
        rubric_completed = $false
        mouse_clicks_total = [long][ActivityTracker]::TotalMouseClicks
        keystrokes_total = [long][ActivityTracker]::TotalKeystrokes
    }
    [ActivityTracker]::Stop()
    Clear-SessionState
    Invoke-FlushCache
    Show-WpfFinished
    if ($script:ActivityStopwatch -and $script:ActivityStopwatch.IsRunning) { $script:ActivityStopwatch.Stop() }
    return $true
}

# =============================================================================
# ENTRY POINT
# =============================================================================

$mutexCreated = $false
$agentMutex = $null
try {
    $agentMutex = New-Object System.Threading.Mutex($true, "Global\PulseLab_Agent_Singleton_Mutex", [ref]$mutexCreated)
} catch {
    $mutexCreated = $false
}
if (-not $mutexCreated) {
    Write-PulseLog "WARN" "Another instance of PulseLab agent is already running."
    [Windows.MessageBox]::Show(
        "Uma instância do PulseLab já está em execução neste computador.",
        "PulseLab",
        [Windows.MessageBoxButton]::OK,
        [Windows.MessageBoxImage]::Warning
    ) | Out-Null
    exit 0
}
$script:AgentMutex = $agentMutex

try {
    Initialize-Installation
    Initialize-Session
    Get-RemoteConfig
    Get-EnvCredentials

    $resumable = Get-ResumableSession
    $resuming = $false
    if ($resumable) {
        $userChoice = Show-WpfResumePrompt $resumable
        if ($userChoice -eq "resume") {
            $resuming = $true
            $script:IsResumedSession = $true
            $script:SessionId = [string]$resumable.session_id
            $script:DyadId = [string]$resumable.dyad_id
            $script:InstallationId = [string]$resumable.installation_id
            $script:SiteId = [string]$resumable.site_id
            $script:RegionalHub = [string]$resumable.regional_hub
            $script:SchoolCode = [string]$resumable.school_code
            $script:WorkshopCode = [string]$resumable.workshop_code
            $script:ClassCode = [string]$resumable.class_code
            $script:ActivityId = [string]$resumable.activity_id
            $script:GroupSize = [int]$resumable.group_size
            $script:ParticipantComputer = [string]$resumable.participant_computer
            $script:ParticipantAssembly = [string]$resumable.participant_assembly
            if ($resumable.PSObject.Properties.Name -contains "participant_computer_role" -and -not [string]::IsNullOrWhiteSpace([string]$resumable.participant_computer_role)) {
                $script:ParticipantComputerRole = [string]$resumable.participant_computer_role
            }
            if ($resumable.PSObject.Properties.Name -contains "participant_assembly_role" -and -not [string]::IsNullOrWhiteSpace([string]$resumable.participant_assembly_role)) {
                $script:ParticipantAssemblyRole = [string]$resumable.participant_assembly_role
            }
            $script:SessionStartedAt = [DateTimeOffset]::Parse([string]$resumable.started_at)
            $script:ActivityStartedAt = [DateTimeOffset]::Parse([string]$resumable.activity_started_at)
            $script:CompletedCheckpoints = if ($resumable.completed_checkpoints) { [int[]]$resumable.completed_checkpoints } else { @() }
            if ($resumable.PSObject.Properties.Name -contains "config_snapshot" -and -not [string]::IsNullOrWhiteSpace([string]$resumable.config_snapshot)) {
                try {
                    $savedCfg = [string]$resumable.config_snapshot | ConvertFrom-Json
                    if ($savedCfg -and $savedCfg.questions -and $savedCfg.interval_marks_minutes) {
                        $script:Config = $savedCfg
                        if ($resumable.PSObject.Properties.Name -contains "config_hash" -and -not [string]::IsNullOrWhiteSpace([string]$resumable.config_hash)) {
                            $script:ConfigHash = [string]$resumable.config_hash
                        }
                        Write-PulseLog "INFO" "Configuration snapshot restored from active session state."
                    }
                } catch {
                    Write-PulseLog "WARN" "Could not restore config snapshot: $($_.Exception.Message)"
                }
            }
            Write-PulseLog "INFO" "Session resumed. session_id=$script:SessionId checkpoints_done=$($script:CompletedCheckpoints -join ',')"
        } else {
            Clear-SessionState
        }
    }

    if (-not $resuming) {
        if (-not (Show-WpfSessionSetup)) {
            Write-PulseLog "WARN" "Session setup canceled."
            exit 0
        }

        Show-WpfGroupSizeSelection
        $participants = Get-ParticipantList

        $allAccepted = $true
        foreach ($p in $participants) {
            $accepted = Show-WpfAssent $p.Label
            if (-not $accepted) {
                $allAccepted = $false
                break
            }
        }

        if (-not $allAccepted) {
            Write-PulseLog "INFO" "Research collection canceled because assent was not granted by all group members."
            [Windows.MessageBox]::Show(
                "A coleta de pesquisa foi encerrada. O grupo pode continuar participando normalmente da oficina.",
                "PulseLab",
                [Windows.MessageBoxButton]::OK,
                [Windows.MessageBoxImage]::Information
            ) | Out-Null
            exit 0
        }

        $script:SessionStartedAt = [DateTimeOffset]::Now
        $script:CollectionAuthorized = $true
        Initialize-TrayIcon
        Invoke-FlushCache
        Submit-SessionEvent "session_started" "info" $null $null $null $null 0L $null @{
            participant_count = $script:GroupSize
            authorization_verified = $true
            assent_completed = $true
            expected_checkpoints = [int[]]$script:Config.interval_marks_minutes
        }

        $preStatuses = @{ phase = "pre" }
        for ($i = 0; $i -lt $participants.Count; $i++) {
            $p = $participants[$i]
            $isLast = ($i -eq $participants.Count - 1)
            $nextLabel = if ($isLast) { "" } else { [string]$participants[$i + 1].Label }
            $st = Save-PreSurvey $p.Id $p.Role $p.Label $isLast $nextLabel
            $preStatuses["participant_$($p.Letter.ToLower())_status"] = $st
        }
        Submit-SessionEvent "phase_completed" "info" $null $null $null "pre" 0L $null $preStatuses
        Save-SessionState "activity"
    } else {
        $script:CollectionAuthorized = $true
        Initialize-TrayIcon
        Invoke-FlushCache
        Submit-SessionEvent "phase_completed" "info" $null $null $null "resumed" 0L $null @{
            resumed_from_state = $true
            completed_checkpoints = $script:CompletedCheckpoints
        }
    }

    Start-ResearchLoop | Out-Null
} catch {
    Write-PulseLog "ERROR" "Fatal error: $($_.Exception.Message)"
    if ($script:CollectionAuthorized -and $script:Config -and $script:SupabaseUrl) {
        try {
            $elapsed = Get-CurrentElapsedMs
            Submit-SessionEvent "session_aborted" "error" $null $null $null $null $elapsed $null @{
                reason = "fatal_error"
                error_type = $_.Exception.GetType().Name
            }
            Clear-SessionState
            Invoke-FlushCache
        } catch {
            Write-PulseLog "ERROR" "Could not record aborted session: $($_.Exception.Message)"
        }
    }
} finally {
    if ($script:ActivityStopwatch -and $script:ActivityStopwatch.IsRunning) { $script:ActivityStopwatch.Stop() }
    Dispose-TrayIcon
    if ($script:AgentMutex) {
        try {
            $script:AgentMutex.ReleaseMutex()
            $script:AgentMutex.Dispose()
        } catch {}
        $script:AgentMutex = $null
    }
    Write-PulseLog "INFO" "PulseLab session finished."
}

