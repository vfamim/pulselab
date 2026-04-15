#Requires -Version 5.1
# =============================================================================
# pulselab-agent.ps1
# Version    : 1.1.0
# Description: Pulselab engagement collection daemon for LEGO Spike robotics
#              education sessions in public schools. Runs invisibly in the
#              background, displays a difficulty rating popup at fixed intervals
#              (5, 15, and 30 minutes), and persists responses to Supabase with
#              full offline resilience.
#
# Execution  : powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File pulselab-agent.ps1
# Author     : Pulselab Project
# =============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# =============================================================================
# P/INVOKE: Win32 API for window focus restoration (LEGO Spike compatibility)
# =============================================================================

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32NativeMethods {
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@

# =============================================================================
# CONSTANTS
# =============================================================================

$script:VERSION        = "1.1.0"
$script:SCRIPT_DIR     = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:LOG_FILE       = Join-Path $script:SCRIPT_DIR "pulselab.log"
$script:CACHE_DIR      = Join-Path $script:SCRIPT_DIR ".cache"
$script:CACHE_FILE     = Join-Path $script:CACHE_DIR "queue.json"
$script:LOCAL_CONFIG   = Join-Path $script:SCRIPT_DIR "config\config.json"

# =============================================================================
# FUNCTION: Write-PulseLog
# =============================================================================

function Write-PulseLog {
    param(
        [ValidateSet("INFO", "WARN", "ERROR", "DEBUG")]
        [string]$Level,
        [string]$Message
    )

    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $entry     = "[$timestamp] [$Level] $Message"

    # Console output only if running interactively (debug sessions)
    if ($script:Config -and $script:Config.debug_mode) {
        Write-Host $entry
    }

    # Log rotation
    if (Test-Path $script:LOG_FILE) {
        $maxBytes = if ($script:Config) { $script:Config.log_max_size_mb * 1MB } else { 5MB }
        if ((Get-Item $script:LOG_FILE).Length -gt $maxBytes) {
            $bakFile = $script:LOG_FILE + ".bak"
            if (Test-Path $bakFile) { Remove-Item $bakFile -Force }
            Rename-Item -Path $script:LOG_FILE -NewName ($bakFile) -Force
        }
    }

    Add-Content -Path $script:LOG_FILE -Value $entry -Encoding UTF8
}

# =============================================================================
# FUNCTION: Initialize-Session
# =============================================================================

function Initialize-Session {
    $script:SessionId  = [System.Guid]::NewGuid().ToString()
    $script:ComputerId = $env:COMPUTERNAME

    $script:SupabaseUrl = $null
    $script:SupabaseKey = $null
    $script:Config      = $null
    $script:SpikeHandle = [IntPtr]::Zero
    $script:SessionStudents = @()

    if (-not (Test-Path $script:CACHE_DIR)) {
        New-Item -ItemType Directory -Path $script:CACHE_DIR -Force | Out-Null
    }

    Write-PulseLog -Level "INFO" -Message "Session initialized. version=$script:VERSION session_id=$script:SessionId computer_id=$script:ComputerId"
}

# =============================================================================
# FUNCTION: Get-RemoteConfig
# Loads config from GitHub. Falls back to local config on failure.
# =============================================================================

function Get-RemoteConfig {
    # First load local config to get the remote URL (and as fallback)
    $localConfig = $null
    if (Test-Path $script:LOCAL_CONFIG) {
        try {
            $localConfig = Get-Content -Path $script:LOCAL_CONFIG -Raw -Encoding UTF8 | ConvertFrom-Json
        } catch {
            Write-PulseLog -Level "WARN" -Message "Local config parse failed: $_"
        }
    }

    if ($null -eq $localConfig) {
        Write-PulseLog -Level "ERROR" -Message "No local config found at $script:LOCAL_CONFIG. Cannot continue."
        throw "Configuration file missing."
    }

    $remoteUrl = $localConfig.config_remote_url

    try {
        $response = Invoke-WebRequest -Uri $remoteUrl -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        $remoteConfig = $response.Content | ConvertFrom-Json

        # Cache remote config locally
        $response.Content | Set-Content -Path $script:LOCAL_CONFIG -Encoding UTF8 -Force

        $script:Config = $remoteConfig
        Write-PulseLog -Level "INFO" -Message "Remote config loaded. version=$($remoteConfig.version) activity_id=$($remoteConfig.activity_id)"
    } catch {
        $script:Config = $localConfig
        Write-PulseLog -Level "WARN" -Message "Remote config unreachable. Using cached config. version=$($localConfig.version) error=$($_.Exception.Message)"
    }
}

# =============================================================================
# FUNCTION: Get-EnvCredentials
# Reads Supabase URL and key from environment variables.
# =============================================================================

function Get-EnvCredentials {
    $urlVarName = $script:Config.supabase_url_env_var
    $keyVarName = $script:Config.supabase_key_env_var

    $script:SupabaseUrl = [System.Environment]::GetEnvironmentVariable($urlVarName, "User")
    $script:SupabaseKey = [System.Environment]::GetEnvironmentVariable($keyVarName, "User")

    if ([string]::IsNullOrWhiteSpace($script:SupabaseUrl) -or [string]::IsNullOrWhiteSpace($script:SupabaseKey)) {
        Write-PulseLog -Level "ERROR" -Message "Supabase credentials not found in environment variables. url_var=$urlVarName key_var=$keyVarName"
        throw "Missing Supabase credentials. Run setup-startup.ps1 first."
    }

    Write-PulseLog -Level "INFO" -Message "Credentials loaded from environment. url_var=$urlVarName"
}

# =============================================================================
# FUNCTION: Get-SpikeWindowHandle
# Locates the LEGO Spike Education process main window handle.
# Returns [IntPtr]::Zero if Spike is not running.
# =============================================================================

function Get-SpikeWindowHandle {
    $spikeNames = @("Spike", "SPIKE", "LEGOEducationSPIKE", "LEGO Education SPIKE")

    foreach ($name in $spikeNames) {
        $proc = Get-Process -ErrorAction SilentlyContinue | Where-Object {
            $_.MainWindowTitle -match $name -and $_.MainWindowHandle -ne 0
        } | Select-Object -First 1

        if ($proc) {
            Write-PulseLog -Level "DEBUG" -Message "LEGO Spike process found. pid=$($proc.Id) title='$($proc.MainWindowTitle)'"
            return $proc.MainWindowHandle
        }
    }

    # Fallback: search by executable name
    $spikeProc = Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessName -match 'spike' -and $_.MainWindowHandle -ne 0 } |
        Select-Object -First 1

    if ($spikeProc) {
        Write-PulseLog -Level "DEBUG" -Message "LEGO Spike found by process name. pid=$($spikeProc.Id)"
        return $spikeProc.MainWindowHandle
    }

    Write-PulseLog -Level "DEBUG" -Message "LEGO Spike process not found. Focus restoration will be skipped."
    return [IntPtr]::Zero
}

# =============================================================================
# FUNCTION: Restore-SpikeFocus
# Returns focus to LEGO Spike after the popup closes.
# No-op if handle is zero (Spike not running).
# =============================================================================

function Restore-SpikeFocus {
    param([IntPtr]$Handle)

    if ($Handle -eq [IntPtr]::Zero) { return }

    try {
        [Win32NativeMethods]::SetForegroundWindow($Handle) | Out-Null
        Write-PulseLog -Level "DEBUG" -Message "Focus restored to LEGO Spike. handle=$Handle"
    } catch {
        Write-PulseLog -Level "WARN" -Message "Could not restore focus to LEGO Spike: $_"
    }
}

# =============================================================================
# FUNCTION: Show-StudentSelectForm
# Displays a WinForms dialog at session start to identify the students.
# Aluno 1 is mandatory. Returns an array of non-empty student names.
# =============================================================================

function Show-StudentSelectForm {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $maxStudents = [int]$script:Config.max_students_per_machine

    $form                  = New-Object System.Windows.Forms.Form
    $form.Text             = "Pulselab"
    $form.FormBorderStyle  = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.StartPosition    = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.Width            = 360
    $form.Height           = 60 + ($maxStudents * 50) + 80
    $form.BackColor        = [System.Drawing.ColorTranslator]::FromHtml("#1A1A2E")
    $form.ForeColor        = [System.Drawing.Color]::White
    $form.MaximizeBox      = $false
    $form.MinimizeBox      = $false
    $form.TopMost          = $true
    $form.Font             = New-Object System.Drawing.Font("Segoe UI", 10)

    $titleLabel            = New-Object System.Windows.Forms.Label
    $titleLabel.Text       = "Quem esta nessa maquina hoje?"
    $titleLabel.Font       = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    $titleLabel.ForeColor  = [System.Drawing.Color]::White
    $titleLabel.Location   = New-Object System.Drawing.Point(20, 16)
    $titleLabel.AutoSize   = $true
    $form.Controls.Add($titleLabel)

    $textBoxes = @()
    for ($i = 0; $i -lt $maxStudents; $i++) {
        $label           = New-Object System.Windows.Forms.Label
        $label.Text      = if ($i -eq 0) { "Aluno 1 (obrigatorio):" } else { "Aluno $($i + 1) (opcional):" }
        $label.ForeColor = [System.Drawing.Color]::FromArgb(180, 180, 180)
        $label.Location  = New-Object System.Drawing.Point(20, (55 + $i * 50))
        $label.AutoSize  = $true
        $form.Controls.Add($label)

        $tb              = New-Object System.Windows.Forms.TextBox
        $tb.Location     = New-Object System.Drawing.Point(20, (73 + $i * 50))
        $tb.Width        = 300
        $tb.BackColor    = [System.Drawing.ColorTranslator]::FromHtml("#2A2A4A")
        $tb.ForeColor    = [System.Drawing.Color]::White
        $tb.BorderStyle  = [System.Windows.Forms.BorderStyle]::FixedSingle
        $tb.Font         = New-Object System.Drawing.Font("Segoe UI", 10)
        $form.Controls.Add($tb)
        $textBoxes += $tb
    }

    $btnY   = 60 + ($maxStudents * 50) + 16
    $btnOk  = New-Object System.Windows.Forms.Button
    $btnOk.Text      = "Iniciar Atividade"
    $btnOk.Location  = New-Object System.Drawing.Point(20, $btnY)
    $btnOk.Width     = 300
    $btnOk.Height    = 36
    $btnOk.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#4A90E2")
    $btnOk.ForeColor = [System.Drawing.Color]::White
    $btnOk.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnOk.Font      = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnOk.Enabled   = $false
    $btnOk.FlatAppearance.BorderSize = 0
    $form.Controls.Add($btnOk)
    $form.AcceptButton = $btnOk

    # Enable Iniciar only when Aluno 1 has text
    $textBoxes[0].Add_TextChanged({
        $btnOk.Enabled = ($textBoxes[0].Text.Trim() -ne "")
    })

    $btnOk.Add_Click({ $form.DialogResult = [System.Windows.Forms.DialogResult]::OK; $form.Close() })

    $form.ShowDialog() | Out-Null

    $students = @()
    foreach ($tb in $textBoxes) {
        $name = $tb.Text.Trim()
        if ($name -ne "") { $students += $name }
    }

    Write-PulseLog -Level "INFO" -Message "Students registered for session. count=$($students.Count) students=$($students -join ',')"
    return $students
}

# =============================================================================
# FUNCTION: Show-PulseForm
# Displays the difficulty rating popup. Returns integer 1-5 or $null on timeout.
# Restores LEGO Spike focus after closing.
# =============================================================================

function Show-PulseForm {
    param(
        [string]$QuestionText,
        [int]$ScaleMin,
        [int]$ScaleMax,
        [int]$TimeoutSeconds,
        [string[]]$Students,
        [IntPtr]$SpikeHandle
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $result = $null
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    # Position: bottom-right corner of primary screen working area
    $screen    = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $formW     = 390
    $formH     = 185
    $posX      = $screen.Right  - $formW - 12
    $posY      = $screen.Bottom - $formH - 12

    $form                 = New-Object System.Windows.Forms.Form
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $form.StartPosition   = [System.Windows.Forms.FormStartPosition]::Manual
    $form.Location        = New-Object System.Drawing.Point($posX, $posY)
    $form.Width           = $formW
    $form.Height          = $formH
    $form.BackColor       = [System.Drawing.ColorTranslator]::FromHtml("#1A1A2E")
    $form.TopMost         = $true
    $form.ShowInTaskbar   = $false

    # Student names subtitle
    $subtitleText = if ($Students.Count -gt 0) { $Students -join " / " } else { "" }
    $subtitle                 = New-Object System.Windows.Forms.Label
    $subtitle.Text            = $subtitleText
    $subtitle.Font            = New-Object System.Drawing.Font("Segoe UI", 9)
    $subtitle.ForeColor       = [System.Drawing.Color]::FromArgb(140, 140, 180)
    $subtitle.Location        = New-Object System.Drawing.Point(14, 10)
    $subtitle.AutoSize        = $true
    $form.Controls.Add($subtitle)

    # Question label
    $question                 = New-Object System.Windows.Forms.Label
    $question.Text            = $QuestionText
    $question.Font            = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $question.ForeColor       = [System.Drawing.Color]::White
    $question.Location        = New-Object System.Drawing.Point(14, 32)
    $question.AutoSize        = $true
    $form.Controls.Add($question)

    # Scale labels (1 = Facil, 5 = Dificil)
    $labelEasy                = New-Object System.Windows.Forms.Label
    $labelEasy.Text           = "Facil"
    $labelEasy.Font           = New-Object System.Drawing.Font("Segoe UI", 8)
    $labelEasy.ForeColor      = [System.Drawing.Color]::FromArgb(120, 120, 160)
    $labelEasy.Location       = New-Object System.Drawing.Point(14, 72)
    $labelEasy.AutoSize       = $true
    $form.Controls.Add($labelEasy)

    $labelHard                = New-Object System.Windows.Forms.Label
    $labelHard.Text           = "Dificil"
    $labelHard.Font           = New-Object System.Drawing.Font("Segoe UI", 8)
    $labelHard.ForeColor      = [System.Drawing.Color]::FromArgb(120, 120, 160)
    $labelHard.TextAlign      = [System.Drawing.ContentAlignment]::MiddleRight
    $labelHard.Location       = New-Object System.Drawing.Point(310, 72)
    $labelHard.AutoSize       = $true
    $form.Controls.Add($labelHard)

    # Difficulty buttons: 1 through 5
    $buttonColors = @("#2ECC71", "#82C341", "#F39C12", "#E67E22", "#E74C3C")
    $btnW         = 62
    $btnH         = 52
    $btnSpacing   = 6
    $totalW       = ($ScaleMax - $ScaleMin + 1) * ($btnW + $btnSpacing) - $btnSpacing
    $startX       = [int](($formW - $totalW) / 2)
    $btnY         = 90

    for ($i = $ScaleMin; $i -le $ScaleMax; $i++) {
        $value           = $i
        $colorHex        = $buttonColors[$i - 1]
        $btn             = New-Object System.Windows.Forms.Button
        $btn.Text        = "$i"
        $btn.Font        = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
        $btn.Location    = New-Object System.Drawing.Point(($startX + ($i - $ScaleMin) * ($btnW + $btnSpacing)), $btnY)
        $btn.Width       = $btnW
        $btn.Height      = $btnH
        $btn.BackColor   = [System.Drawing.ColorTranslator]::FromHtml($colorHex)
        $btn.ForeColor   = [System.Drawing.Color]::White
        $btn.FlatStyle   = [System.Windows.Forms.FlatStyle]::Flat
        $btn.FlatAppearance.BorderSize = 0
        $btn.Cursor      = [System.Windows.Forms.Cursors]::Hand

        $btn.Add_Click({
            $result = $value
            $form.Tag = $value
            $stopwatch.Stop()
            $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $form.Close()
        }.GetNewClosure())

        $form.Controls.Add($btn)
    }

    # Auto-close timer
    $timer          = New-Object System.Windows.Forms.Timer
    $timer.Interval = $TimeoutSeconds * 1000
    $timer.Add_Tick({
        $form.Tag = $null
        $form.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $form.Close()
        $timer.Stop()
    })
    $timer.Start()

    $form.ShowDialog() | Out-Null
    $timer.Stop()
    $timer.Dispose()

    $elapsedMs = $stopwatch.ElapsedMilliseconds
    $tagValue  = $form.Tag

    Restore-SpikeFocus -Handle $SpikeHandle

    if ($null -ne $tagValue) {
        Write-PulseLog -Level "INFO" -Message "Popup response received. difficulty=$tagValue elapsed_ms=$elapsedMs"
        return [int]$tagValue
    } else {
        Write-PulseLog -Level "INFO" -Message "Popup timed out after $TimeoutSeconds seconds."
        return $null
    }
}

# =============================================================================
# FUNCTION: Add-ToLocalQueue
# Appends a payload object to the local offline cache queue.
# =============================================================================

function Add-ToLocalQueue {
    param([hashtable]$Payload)

    try {
        $queue = @()
        if (Test-Path $script:CACHE_FILE) {
            $raw = Get-Content -Path $script:CACHE_FILE -Raw -Encoding UTF8
            if ($raw.Trim() -ne "") {
                $existing = $raw | ConvertFrom-Json
                if ($existing -is [array]) {
                    $queue = $existing
                } else {
                    $queue = @($existing)
                }
            }
        }

        $queue += $Payload
        $queue | ConvertTo-Json -Depth 10 | Set-Content -Path $script:CACHE_FILE -Encoding UTF8 -Force

        Write-PulseLog -Level "WARN" -Message "Response queued offline. queue_size=$($queue.Count) session_id=$($Payload.session_id)"
    } catch {
        Write-PulseLog -Level "ERROR" -Message "Failed to write to local queue: $_"
    }
}

# =============================================================================
# FUNCTION: Send-ResponseToSupabase
# POSTs a single payload to the Supabase REST API.
# Returns $true on success, $false on failure.
# =============================================================================

function Send-ResponseToSupabase {
    param([hashtable]$Payload)

    $endpoint = "$($script:SupabaseUrl)/rest/v1/responses"
    $headers  = @{
        "apikey"        = $script:SupabaseKey
        "Authorization" = "Bearer $($script:SupabaseKey)"
        "Content-Type"  = "application/json"
        "Prefer"        = "return=minimal"
    }
    $body = $Payload | ConvertTo-Json -Depth 10 -Compress

    try {
        Invoke-RestMethod -Method POST -Uri $endpoint -Headers $headers -Body $body -ErrorAction Stop | Out-Null
        Write-PulseLog -Level "INFO" -Message "Response sent to Supabase. difficulty=$($Payload.difficulty) interval_mark=$($Payload.interval_mark)"
        return $true
    } catch {
        Write-PulseLog -Level "ERROR" -Message "Supabase POST failed: $($_.Exception.Message)"
        return $false
    }
}

# =============================================================================
# FUNCTION: Invoke-FlushCache
# Attempts to send all queued offline payloads to Supabase.
# Removes successfully sent entries from the queue.
# =============================================================================

function Invoke-FlushCache {
    if (-not (Test-Path $script:CACHE_FILE)) { return }

    $raw = Get-Content -Path $script:CACHE_FILE -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) { return }

    $queue = $raw | ConvertFrom-Json
    if ($null -eq $queue) { return }

    if (-not ($queue -is [array])) { $queue = @($queue) }
    if ($queue.Count -eq 0) { return }

    Write-PulseLog -Level "INFO" -Message "Flushing offline cache. pending_count=$($queue.Count)"

    $remaining = @()
    foreach ($item in $queue) {
        $ht = @{}
        $item.PSObject.Properties | ForEach-Object { $ht[$_.Name] = $_.Value }

        $sent = Send-ResponseToSupabase -Payload $ht
        if (-not $sent) {
            $remaining += $item
        }
    }

    if ($remaining.Count -eq 0) {
        Remove-Item -Path $script:CACHE_FILE -Force
        Write-PulseLog -Level "INFO" -Message "Cache fully flushed and cleared."
    } else {
        $remaining | ConvertTo-Json -Depth 10 | Set-Content -Path $script:CACHE_FILE -Encoding UTF8 -Force
        Write-PulseLog -Level "WARN" -Message "Cache partially flushed. remaining=$($remaining.Count)"
    }
}

# =============================================================================
# FUNCTION: Build-Payload
# Constructs the response payload hashtable.
# =============================================================================

function Build-Payload {
    param(
        [int]$Difficulty,
        [int]$IntervalMark
    )

    return @{
        session_id     = $script:SessionId
        computer_id    = $script:ComputerId
        activity_id    = $script:Config.activity_id
        students       = $script:SessionStudents
        difficulty     = $Difficulty
        interval_mark  = $IntervalMark
        responded_at   = (Get-Date).ToString("yyyy-MM-ddTHH:mm:sszzz")
        client_version = $script:VERSION
    }
}

# =============================================================================
# FUNCTION: Invoke-IntervalSleep
# Sleeps until the next interval mark. Returns the interval mark value.
# Sequence: 5 -> 15 -> 30 -> 30 -> 30 ...
# =============================================================================

function Invoke-IntervalSleep {
    param(
        [int[]]$Marks,
        [int]$CurrentIndex
    )

    $mark = $Marks[$CurrentIndex]

    # Gap calculation: time between last mark and this one
    if ($CurrentIndex -eq 0) {
        $sleepMinutes = $mark
    } else {
        $sleepMinutes = $mark - $Marks[$CurrentIndex - 1]
    }

    # In debug mode use seconds instead of minutes
    if ($script:Config.debug_mode) {
        $sleepSeconds = $sleepMinutes  # 1 minute -> 1 second in debug
        Write-PulseLog -Level "DEBUG" -Message "DEBUG MODE: sleeping $sleepSeconds seconds instead of $sleepMinutes minutes."
        Start-Sleep -Seconds $sleepSeconds
    } else {
        Write-PulseLog -Level "INFO" -Message "Sleeping until interval mark. minutes=$sleepMinutes mark=$mark"
        Start-Sleep -Seconds ($sleepMinutes * 60)
    }

    return $mark
}

# =============================================================================
# FUNCTION: Start-DaemonLoop
# Main event loop. Executes the fixed sequence of interval marks,
# then keeps repeating the last mark value (30 min) indefinitely.
# =============================================================================

function Start-DaemonLoop {
    $marks     = [int[]]$script:Config.interval_marks_minutes
    $markCount = $marks.Count

    # The last mark repeats after the sequence is exhausted
    $lastMark  = $marks[$markCount - 1]
    $gapAfterLast = if ($markCount -gt 1) { $lastMark - $marks[$markCount - 2] } else { $lastMark }

    Write-PulseLog -Level "INFO" -Message "Daemon loop started. marks=$($marks -join ',') activity=$($script:Config.activity_id)"

    # Refresh Spike handle before the loop
    $script:SpikeHandle = Get-SpikeWindowHandle

    $cycleIndex = 0

    while ($true) {
        # Determine current interval
        if ($cycleIndex -lt $markCount) {
            $currentMark = Invoke-IntervalSleep -Marks $marks -CurrentIndex $cycleIndex
        } else {
            # Beyond the defined marks: repeat last interval gap
            Write-PulseLog -Level "INFO" -Message "Interval sequence complete. Repeating last mark gap. minutes=$gapAfterLast"
            if ($script:Config.debug_mode) {
                Start-Sleep -Seconds $gapAfterLast
            } else {
                Start-Sleep -Seconds ($gapAfterLast * 60)
            }
            $currentMark = $lastMark
        }

        # Refresh Spike handle (Spike may have been restarted)
        $script:SpikeHandle = Get-SpikeWindowHandle

        # Reload config (picks up GitOps updates between cycles)
        Get-RemoteConfig

        # Attempt to flush any offline-queued responses
        Invoke-FlushCache

        # Show rating popup
        $difficulty = Show-PulseForm `
            -QuestionText   $script:Config.question_text `
            -ScaleMin       ([int]$script:Config.scale_min) `
            -ScaleMax       ([int]$script:Config.scale_max) `
            -TimeoutSeconds ([int]$script:Config.timeout_seconds) `
            -Students       $script:SessionStudents `
            -SpikeHandle    $script:SpikeHandle

        if ($null -ne $difficulty) {
            $payload = Build-Payload -Difficulty $difficulty -IntervalMark $currentMark
            $sent    = Send-ResponseToSupabase -Payload $payload
            if (-not $sent) {
                Add-ToLocalQueue -Payload $payload
            }
        }

        Write-PulseLog -Level "INFO" -Message "Cycle complete. mark=$currentMark"

        $cycleIndex++
    }
}

# =============================================================================
# ENTRY POINT
# =============================================================================

try {
    Initialize-Session
    Get-RemoteConfig
    Get-EnvCredentials

    # Load WinForms early to avoid first-popup delay
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    # Identify students for this session
    $script:SessionStudents = Show-StudentSelectForm

    # Attempt initial cache flush before entering the loop
    Invoke-FlushCache

    # Start the main event loop
    Start-DaemonLoop

} catch {
    Write-PulseLog -Level "ERROR" -Message "Fatal error. Daemon terminated. error=$($_.Exception.Message)"
    exit 1
}
