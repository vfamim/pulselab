#Requires -Version 5.1
# =============================================================================
# setup-startup.ps1
# Version    : 1.1.0
# Description: Pulselab one-time setup script. Configures environment variables
#              for Supabase credentials and creates a Windows startup shortcut
#              to run the daemon invisibly on every login.
#
# Usage      : .\setup-startup.ps1 -SupabaseUrl "https://..." -SupabaseKey "..."
# Permissions: Runs as a standard user. No UAC/Admin required.
# =============================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SupabaseUrl,

    [Parameter(Mandatory = $true)]
    [string]$SupabaseKey,

    [Parameter(Mandatory = $false)]
    [string]$AgentPath = $null
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-SetupLog {
    param([string]$Level, [string]$Message)
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Write-Host "[$timestamp] [$Level] $Message"
}

# =============================================================================
# STEP 1: Resolve agent path
# =============================================================================

Write-SetupLog "INFO" "Pulselab setup starting. version=1.1.0"

if ([string]::IsNullOrWhiteSpace($AgentPath)) {
    $AgentPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "..\agent\pulselab-agent.ps1"
}

$AgentPath = Resolve-Path $AgentPath -ErrorAction SilentlyContinue

if (-not $AgentPath -or -not (Test-Path $AgentPath)) {
    Write-SetupLog "ERROR" "Agent script not found at resolved path: $AgentPath"
    Write-SetupLog "ERROR" "Run setup-startup.ps1 from the installer/ directory, or pass -AgentPath explicitly."
    exit 1
}

Write-SetupLog "INFO" "Agent path resolved. path=$AgentPath"

# =============================================================================
# STEP 2: Set user-scoped environment variables (no UAC required)
# =============================================================================

[System.Environment]::SetEnvironmentVariable("PULSELAB_URL", $SupabaseUrl, "User")
[System.Environment]::SetEnvironmentVariable("PULSELAB_KEY", $SupabaseKey, "User")

Write-SetupLog "INFO" "Environment variables set for current user. vars=PULSELAB_URL,PULSELAB_KEY"

# Verify they can be read back
$verifyUrl = [System.Environment]::GetEnvironmentVariable("PULSELAB_URL", "User")
$verifyKey = [System.Environment]::GetEnvironmentVariable("PULSELAB_KEY", "User")

if ($verifyUrl -ne $SupabaseUrl -or $verifyKey -ne $SupabaseKey) {
    Write-SetupLog "ERROR" "Environment variable verification failed. Values do not match after write."
    exit 1
}

Write-SetupLog "INFO" "Environment variables verified successfully."

# =============================================================================
# STEP 3: Create Windows startup shortcut (.lnk)
# Uses COM WSScript.Shell - available on all Windows versions, no UAC.
# =============================================================================

$startupDir  = [System.Environment]::GetFolderPath("Startup")
$shortcutPath = Join-Path $startupDir "Pulselab.lnk"

$wshell   = New-Object -ComObject WScript.Shell
$shortcut = $wshell.CreateShortcut($shortcutPath)

$shortcut.TargetPath       = "powershell.exe"
$shortcut.Arguments        = "-ExecutionPolicy Bypass -WindowStyle Hidden -NonInteractive -File `"$AgentPath`""
$shortcut.WorkingDirectory = Split-Path -Parent $AgentPath
$shortcut.WindowStyle      = 7    # 7 = Minimized (hidden; -WindowStyle Hidden handles actual invisibility)
$shortcut.Description      = "Pulselab Engagement Daemon"
$shortcut.IconLocation     = "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe,0"

$shortcut.Save()

Write-SetupLog "INFO" "Startup shortcut created. path=$shortcutPath"

# Verify shortcut was created
if (-not (Test-Path $shortcutPath)) {
    Write-SetupLog "ERROR" "Shortcut creation verification failed. File not found at $shortcutPath"
    exit 1
}

Write-SetupLog "INFO" "Shortcut creation verified."

# =============================================================================
# STEP 4: Summary
# =============================================================================

Write-SetupLog "INFO" "---------------------------------------------"
Write-SetupLog "INFO" "Setup complete. Pulselab is ready."
Write-SetupLog "INFO" "  Daemon       : $AgentPath"
Write-SetupLog "INFO" "  Startup link : $shortcutPath"
Write-SetupLog "INFO" "  Supabase URL : $($SupabaseUrl.Substring(0, [Math]::Min(30, $SupabaseUrl.Length)))..."
Write-SetupLog "INFO" "---------------------------------------------"
Write-SetupLog "INFO" "The daemon will start automatically on next Windows login."
Write-SetupLog "INFO" "To start immediately without rebooting, run:"
Write-SetupLog "INFO" "  powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$AgentPath`""
