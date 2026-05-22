#Requires -Version 5.1
# =============================================================================
# pulselab-agent.ps1
# Version    : 1.2.0
# Description: Pulselab MMLA engagement collection daemon for LEGO Spike robotics.
#              Runs under-demand in the background, displays rich kid-friendly
#              WPF popup windows at fixed intervals, and captures deep system
#              telemetry, file activity, and compressed screen captures with
#              resilient offline local caching.
#
# Execution  : powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File pulselab-agent.ps1
# Author     : Pulselab Project
# =============================================================================

[CmdletBinding()]
param(
    [switch]$DebugMode,
    [switch]$ProductionTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Load WPF and WinForms early
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing

# =============================================================================
# P/INVOKE: Win32 API for OS telemetry and LEGO Spike compatibility
# =============================================================================

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public class Win32 {
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

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

    [DllImport("user32.dll")]
    public static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);
}
"@

# =============================================================================
# CONSTANTS & CONFIGURATION
# =============================================================================

$script:VERSION           = "1.2.0"
$script:SCRIPT_DIR        = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:LOG_FILE          = Join-Path $script:SCRIPT_DIR "pulselab.log"
$script:LOCAL_CONFIG      = Join-Path (Split-Path -Parent $script:SCRIPT_DIR) "config\config.json"
$script:OFFLINE_CACHE_DIR = "C:\Users\Public\Pulselab\cache"
$script:OFFLINE_CACHE_FILE = Join-Path $script:OFFLINE_CACHE_DIR "queue.json"

# State variables
$script:SessionId         = $null
$script:ComputerId        = $env:COMPUTERNAME
$script:SupabaseUrl       = $null
$script:SupabaseKey       = $null
$script:Config            = $null
$script:SpikeHandle       = [IntPtr]::Zero
$script:StudentPC         = ""
$script:StudentDesk       = ""
$script:TriggerEnding     = $false
$script:NotifyIcon        = $null
$script:ProductionTest    = $ProductionTest

# =============================================================================
# LOGGING FUNCTION
# =============================================================================

function Write-PulseLog {
    param(
        [ValidateSet("INFO", "WARN", "ERROR", "DEBUG")]
        [string]$Level,
        [string]$Message
    )

    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $entry     = "[$timestamp] [$Level] $Message"

    if ($script:Config -and $script:Config.debug_mode) {
        Write-Host $entry
    }

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
# ENVIRONMENT & SESSION INITIALIZATION
# =============================================================================

function Initialize-Session {
    $script:SessionId = [System.Guid]::NewGuid().ToString()
    
    if (-not (Test-Path $script:OFFLINE_CACHE_DIR)) {
        New-Item -ItemType Directory -Path $script:OFFLINE_CACHE_DIR -Force | Out-Null
    }

    Write-PulseLog -Level "INFO" -Message "Session manual launch initialized. version=$script:VERSION session_id=$script:SessionId computer_id=$script:ComputerId"

    if ($script:ProductionTest) {
        Write-PulseLog -Level "INFO" -Message "Command line -ProductionTest switch active. Syncing with remote production config but forcing fast intervals (treating minutes as seconds) to test Supabase integration."
    }
}

function Get-RemoteConfig {
    $localConfig = $null
    if (Test-Path $script:LOCAL_CONFIG) {
        try {
            $localConfig = Get-Content -Path $script:LOCAL_CONFIG -Raw -Encoding UTF8 | ConvertFrom-Json
        } catch {
            Write-PulseLog -Level "WARN" -Message "Local config parse failed: $_"
        }
    }

    if ($null -eq $localConfig) {
        Write-PulseLog -Level "ERROR" -Message "No local config found at $script:LOCAL_CONFIG. Terminating."
        throw "Configuration file missing."
    }

    if ($DebugMode) {
        $localConfig.debug_mode = $true
        $localConfig.interval_marks_minutes = @(1, 2)
        Write-PulseLog -Level "INFO" -Message "Command line -DebugMode switch active. Forcing fast interval marks [1, 2] and bypassing remote config sync."
        $script:Config = $localConfig
        return
    }

    if ($localConfig.debug_mode -eq $true) {
        Write-PulseLog -Level "INFO" -Message "Local debug mode is active. Bypassing remote GitOps config sync."
        $script:Config = $localConfig
        return
    }

    $remoteUrl = $localConfig.config_remote_url

    try {
        $response = Invoke-WebRequest -Uri $remoteUrl -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        $remoteConfig = $response.Content | ConvertFrom-Json

        # Cache locally
        $response.Content | Set-Content -Path $script:LOCAL_CONFIG -Encoding UTF8 -Force

        $script:Config = $remoteConfig
        Write-PulseLog -Level "INFO" -Message "Remote config synced. version=$($remoteConfig.version) hub=$($remoteConfig.regional_hub)"
    } catch {
        $script:Config = $localConfig
        Write-PulseLog -Level "WARN" -Message "Remote config unreachable. Using cached local config. version=$($localConfig.version) error=$($_.Exception.Message)"
    }
}

function Get-EnvCredentials {
    $urlVarName = $script:Config.supabase_url_env_var
    $keyVarName = $script:Config.supabase_key_env_var

    $script:SupabaseUrl = [System.Environment]::GetEnvironmentVariable($urlVarName, "User")
    $script:SupabaseKey = [System.Environment]::GetEnvironmentVariable($keyVarName, "User")

    if ([string]::IsNullOrWhiteSpace($script:SupabaseUrl) -or [string]::IsNullOrWhiteSpace($script:SupabaseKey)) {
        Write-PulseLog -Level "ERROR" -Message "Supabase credentials missing. url_var=$urlVarName key_var=$keyVarName"
        throw "Missing Supabase credentials. Run setup-startup.ps1 first."
    }

    Write-PulseLog -Level "INFO" -Message "Credentials loaded from Windows environment. url_var=$urlVarName"
}

# =============================================================================
# TELEMETRY IMPLEMENTATIONS
# =============================================================================

function Get-SpikeWindowHandle {
    $spikeNames = @("Spike", "SPIKE", "LEGOEducationSPIKE", "LEGO Education SPIKE")
    foreach ($name in $spikeNames) {
        $proc = Get-Process -ErrorAction SilentlyContinue | Where-Object {
            $_.MainWindowTitle -match $name -and $_.MainWindowHandle -ne 0
        } | Select-Object -First 1

        if ($proc) {
            Write-PulseLog -Level "DEBUG" -Message "LEGO Spike window found. pid=$($proc.Id)"
            return $proc.MainWindowHandle
        }
    }
    return [IntPtr]::Zero
}

function Restore-SpikeFocus {
    param([IntPtr]$Handle)
    if ($Handle -eq [IntPtr]::Zero) { return }
    try {
        [Win32]::SetForegroundWindow($Handle) | Out-Null
        Write-PulseLog -Level "DEBUG" -Message "Active window focus returned to LEGO Spike."
    } catch {
        Write-PulseLog -Level "WARN" -Message "Failed to return focus to LEGO Spike: $_"
    }
}

function Get-ActiveTelemetry {
    $fgHWnd = [Win32]::GetForegroundWindow()
    $processId = 0
    [Win32]::GetWindowThreadProcessId($fgHWnd, [ref]$processId) | Out-Null
    
    $appName = "Unknown"
    $windowTitle = ""
    
    if ($processId -ne 0) {
        $fgProcess = Get-Process -Id $processId -ErrorAction SilentlyContinue
        if ($fgProcess) { $appName = $fgProcess.ProcessName }
    }

    $titleBuilder = New-Object System.Text.StringBuilder(256)
    [Win32]::GetWindowText($fgHWnd, $titleBuilder, 256) | Out-Null
    $windowTitle = $titleBuilder.ToString()

    # System Idle Duration
    $lastInput = New-Object Win32+LASTINPUTINFO
    $lastInput.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf($lastInput)
    $idleSeconds = 0
    if ([Win32]::GetLastInputInfo([ref]$lastInput)) {
        $elapsedTicks = [Environment]::TickCount - $lastInput.dwTime
        if ($elapsedTicks -lt 0) { $elapsedTicks = 0 }
        $idleSeconds = [math]::Round($elapsedTicks / 1000)
    }

    return @{
        WindowTitle   = $windowTitle
        ForegroundApp = $appName
        IdleSeconds   = $idleSeconds
    }
}

function Get-LastSpikeFileSize {
    $spikeDir = Join-Path $env:USERPROFILE "Documents\LEGO SPIKE"
    $fileSizeKb = 0.0
    if (Test-Path $spikeDir) {
        $lastFile = Get-ChildItem -Path $spikeDir -Filter *.llsp -Recurse -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTime -Descending |
                    Select-Object -First 1
        if (-not $lastFile) {
            $lastFile = Get-ChildItem -Path $spikeDir -Filter *.spk -Recurse -ErrorAction SilentlyContinue |
                        Sort-Object LastWriteTime -Descending |
                        Select-Object -First 1
        }
        if ($lastFile) {
            $fileSizeKb = [math]::Round($lastFile.Length / 1KB, 2)
        }
    }
    return $fileSizeKb
}

# =============================================================================
# SCREEN CAPTURE & COMPRESSION (GDI+)
# =============================================================================

function Get-ScreenCapture {
    param([string]$FilePath)

    try {
        $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        $bmp = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height)
        $graphics = [System.Drawing.Graphics]::FromImage($bmp)
        
        # Capture Desktop screen content
        $graphics.CopyFromScreen($bounds.X, $bounds.Y, 0, 0, $bounds.Size)
        
        # Configure compressed JPEG encoder
        $encoder = [System.Drawing.Imaging.ImageCodecInfo]::GetImageDecoders() | Where-Object { $_.FormatID -eq [System.Drawing.Imaging.ImageFormat]::Jpeg.Guid }
        $encoderParams = New-Object System.Drawing.Imaging.EncoderParameters(1)
        $encoderParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, 60) # 60% quality ratio
        
        $bmp.Save($FilePath, $encoder, $encoderParams)
        
        $graphics.Dispose()
        $bmp.Dispose()
        
        Write-PulseLog -Level "INFO" -Message "Desktop screen captured and compressed to local cache: $FilePath"
        return $true
    } catch {
        Write-PulseLog -Level "ERROR" -Message "Pre-popup screen capture failed: $_"
        return $false
    }
}

# =============================================================================
# SUPABASE STORAGE & DATABASE INTEGRATION
# =============================================================================

function Upload-ScreenshotToSupabase {
    param(
        [string]$LocalFilePath,
        [string]$IntervalMark
    )

    $fileName = "$($script:SessionId)_$($IntervalMark).jpg"
    $endpoint = "$($script:SupabaseUrl)/storage/v1/object/screenshots/$fileName"
    
    $headers  = @{
        "apikey"        = $script:SupabaseKey
        "Authorization" = "Bearer $($script:SupabaseKey)"
    }

    try {
        $bytes = [System.IO.File]::ReadAllBytes($LocalFilePath)
        $response = Invoke-RestMethod -Method POST -Uri $endpoint -Headers $headers -Body $bytes -ContentType "image/jpeg" -ErrorAction Stop
        
        # Standard Supabase Storage public asset link format
        $publicUrl = "$($script:SupabaseUrl)/storage/v1/object/public/screenshots/$fileName"
        
        Write-PulseLog -Level "INFO" -Message "Screenshot uploaded to Supabase Storage. Link=$publicUrl"
        return $publicUrl
    } catch {
        Write-PulseLog -Level "ERROR" -Message "Screenshot storage upload failed: $($_.Exception.Message)"
        return $null
    }
}

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
        Write-PulseLog -Level "INFO" -Message "Payload successfully posted to Supabase. Mark=$($Payload.interval_mark)"
        return $true
    } catch {
        Write-PulseLog -Level "ERROR" -Message "Supabase REST request failed: $($_.Exception.Message)"
        return $false
    }
}

# =============================================================================
# RESILIENT OFFLINE CACHE MECHANISMS
# =============================================================================

function Add-ToLocalQueue {
    param([hashtable]$Payload)

    try {
        $queue = @()
        if (Test-Path $script:OFFLINE_CACHE_FILE) {
            $raw = Get-Content -Path $script:OFFLINE_CACHE_FILE -Raw -Encoding UTF8
            if ($raw.Trim() -ne "") {
                $existing = $raw | ConvertFrom-Json
                if ($existing -is [array]) { $queue = $existing } else { $queue = @($existing) }
            }
        }

        # Convert hashtable to PSCustomObject for serialization
        $obj = New-Object PSCustomObject -Property $Payload
        $queue += $obj

        $queue | ConvertTo-Json -Depth 10 | Set-Content -Path $script:OFFLINE_CACHE_FILE -Encoding UTF8 -Force
        Write-PulseLog -Level "WARN" -Message "Data cached offline in local storage. Cache size: $($queue.Count)"
    } catch {
        Write-PulseLog -Level "ERROR" -Message "Failed to write payload to cache file: $_"
    }
}

function Invoke-FlushCache {
    if (-not (Test-Path $script:OFFLINE_CACHE_FILE)) { return }

    try {
        $raw = Get-Content -Path $script:OFFLINE_CACHE_FILE -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) { return }

        $queue = $raw | ConvertFrom-Json
        if ($null -eq $queue) { return }

        if (-not ($queue -is [array])) { $queue = @($queue) }
        if ($queue.Count -eq 0) { return }

        Write-PulseLog -Level "INFO" -Message "Checking network state to flush offline cache queue. Size: $($queue.Count)"

        $remaining = @()
        foreach ($item in $queue) {
            # Convert PSCustomObject back to hashtable for editing
            $ht = @{}
            $item.PSObject.Properties | ForEach-Object { $ht[$_.Name] = $_.Value }

            # Attempt to upload local screenshot first if it is still cached locally
            $localPic = $ht["local_screenshot_path"]
            if ([string]::IsNullOrWhiteSpace($ht["screenshot_url"]) -and -not [string]::IsNullOrWhiteSpace($localPic) -and (Test-Path $localPic)) {
                Write-PulseLog -Level "INFO" -Message "Uploading cached screenshot offline file: $localPic"
                $pubUrl = Upload-ScreenshotToSupabase -LocalFilePath $localPic -IntervalMark $ht["interval_mark"]
                if ($null -ne $pubUrl) {
                    $ht["screenshot_url"] = $pubUrl
                    $ht["local_screenshot_path"] = $null
                    Remove-Item $localPic -Force -ErrorAction SilentlyContinue
                }
            }

            # Extract schema properties only (removes local path parameters)
            $sendHt = @{}
            foreach ($key in $ht.Keys) {
                if ($key -ne "local_screenshot_path") {
                    $sendHt[$key] = $ht[$key]
                }
            }

            # Submit record
            $sent = Send-ResponseToSupabase -Payload $sendHt
            if (-not $sent) {
                $remaining += $item
            }
        }

        if ($remaining.Count -eq 0) {
            Remove-Item -Path $script:OFFLINE_CACHE_FILE -Force -ErrorAction SilentlyContinue
            Write-PulseLog -Level "INFO" -Message "Offline cache fully flushed and cleaned."
        } else {
            $remaining | ConvertTo-Json -Depth 10 | Set-Content -Path $script:OFFLINE_CACHE_FILE -Encoding UTF8 -Force
            Write-PulseLog -Level "WARN" -Message "Offline cache partially flushed. Remaining: $($remaining.Count)"
        }
    } catch {
        Write-PulseLog -Level "ERROR" -Message "Failed to execute cache flushing cycle: $_"
    }
}

# =============================================================================
# WPF INTERFACES (KID-FRIENDLY MULTI-MODAL POPUPS)
# =============================================================================

function Show-WpfLogin {
    $xaml = @"
    <Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
            xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
            Title="Pulselab - Iniciar Oficina" Width="430" Height="460"
            WindowStartupLocation="CenterScreen" WindowStyle="None" AllowsTransparency="True" Background="Transparent" Topmost="True">
        <Border CornerRadius="20" Background="#1D152B" BorderBrush="#4A90E2" BorderThickness="3">
            <Grid Margin="20">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                
                <!-- Title Header -->
                <StackPanel Grid.Row="0" Margin="0,10,0,15" HorizontalAlignment="Center">
                    <TextBlock Text="🚀 PULSELAB" FontSize="26" FontWeight="ExtraBold" Foreground="#4A90E2" HorizontalAlignment="Center"/>
                    <TextBlock Text="Oficina de Robótica LEGO SPIKE" FontSize="14" Foreground="#A0A0C0" HorizontalAlignment="Center" Margin="0,5,0,0"/>
                </StackPanel>
                
                <!-- Text inputs -->
                <StackPanel Grid.Row="1" VerticalAlignment="Center">
                    <TextBlock Text="Quem está no COMPUTADOR? 💻" FontSize="15" FontWeight="Bold" Foreground="White" Margin="0,0,0,8"/>
                    <TextBox Name="TxtPC" FontSize="16" Height="40" Background="#2E2648" Foreground="White" BorderBrush="#4A90E2" BorderThickness="1.5" Padding="8,4" VerticalContentAlignment="Center" Margin="0,0,0,20"/>
                    
                    <TextBlock Text="Quem está na MESA/PISTA? 🏗️" FontSize="15" FontWeight="Bold" Foreground="White" Margin="0,0,0,8"/>
                    <TextBox Name="TxtDesk" FontSize="16" Height="40" Background="#2E2648" Foreground="White" BorderBrush="#4A90E2" BorderThickness="1.5" Padding="8,4" VerticalContentAlignment="Center" Margin="0,0,0,10"/>
                </StackPanel>
                
                <!-- Launch button -->
                <Button Name="BtnStart" Grid.Row="2" Content="Iniciar Oficina de Robótica ✨" FontSize="16" FontWeight="Bold" Height="50" Background="#4A90E2" Foreground="White" Cursor="Hand" IsEnabled="False" Margin="0,10,0,10"/>
            </Grid>
        </Border>
    </Window>
"@

    $reader = New-Object System.Xml.XmlNodeReader([xml]$xaml)
    $window = [Windows.Markup.XamlReader]::Load($reader)

    $txtPC = $window.FindName("TxtPC")
    $txtDesk = $window.FindName("TxtDesk")
    $btnStart = $window.FindName("BtnStart")

    $checkFields = {
        $btnStart.IsEnabled = ($txtPC.Text.Trim() -ne "" -and $txtDesk.Text.Trim() -ne "")
    }

    $txtPC.add_TextChanged($checkFields)
    $txtDesk.add_TextChanged($checkFields)

    $btnStart.add_Click({
        $script:StudentPC = $txtPC.Text.Trim()
        $script:StudentDesk = $txtDesk.Text.Trim()
        $window.DialogResult = $true
        $window.Close()
    })

    $window.ShowDialog() | Out-Null
}

function Show-WpfSampling {
    param(
        [string]$Question,
        [string]$StudentPCName,
        [string]$StudentDeskName
    )

    $xaml = @"
    <Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
            xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
            Title="Expedição Pulselab" Width="680" Height="480"
            WindowStartupLocation="CenterScreen" WindowStyle="None" AllowsTransparency="True" Background="Transparent" Topmost="True">
        <Border CornerRadius="24" Background="#120D24" BorderBrush="#FF5E62" BorderThickness="3">
            <Grid Margin="20">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                
                <!-- Upper Title -->
                <TextBlock Grid.Row="0" Text="🧠 EXPEDIÇÃO DE APRENDIZADO" FontSize="24" FontWeight="ExtraBold" Foreground="#FF5E62" HorizontalAlignment="Center" Margin="0,5,0,10"/>
                
                <!-- Main Question -->
                <TextBlock Grid.Row="1" Text="$Question" FontSize="16" FontWeight="Bold" Foreground="White" TextWrapping="Wrap" HorizontalAlignment="Center" TextAlignment="Center" Margin="0,5,0,20"/>
                
                <!-- Kid Columns -->
                <Grid Grid.Row="2" Margin="0,0,0,15">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="20"/>
                        <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>
                    
                    <!-- Computer kid panel -->
                    <Border Grid.Column="0" CornerRadius="16" Background="#221A3D" Padding="15" BorderBrush="#4A90E2" BorderThickness="2">
                        <StackPanel>
                            <TextBlock Name="LblPCName" FontSize="18" FontWeight="Bold" Foreground="#4A90E2" HorizontalAlignment="Center" Margin="0,0,0,15"/>
                            <RadioButton Name="RadPC1" GroupName="PCGroup" Content="🚀 Muito fácil! (Estou voando)" FontSize="13" Foreground="White" Margin="0,6,0,8" Height="26" VerticalContentAlignment="Center" Cursor="Hand"/>
                            <RadioButton Name="RadPC2" GroupName="PCGroup" Content="💡 Tranquilo (Dá para fazer)" FontSize="13" Foreground="White" Margin="0,6,0,8" Height="26" VerticalContentAlignment="Center" Cursor="Hand"/>
                            <RadioButton Name="RadPC3" GroupName="PCGroup" Content="🧠 Difícil (Está dando trabalho)" FontSize="13" Foreground="White" Margin="0,6,0,8" Height="26" VerticalContentAlignment="Center" Cursor="Hand"/>
                            <RadioButton Name="RadPC4" GroupName="PCGroup" Content="🛑 Travado (Preciso de ajuda!)" FontSize="13" Foreground="White" Margin="0,6,0,8" Height="26" VerticalContentAlignment="Center" Cursor="Hand"/>
                        </StackPanel>
                    </Border>
                    
                    <!-- Separator -->
                    <Grid Grid.Column="1"/>
                    
                    <!-- Desk kid panel -->
                    <Border Grid.Column="2" CornerRadius="16" Background="#221A3D" Padding="15" BorderBrush="#00D2C4" BorderThickness="2">
                        <StackPanel>
                            <TextBlock Name="LblDeskName" FontSize="18" FontWeight="Bold" Foreground="#00D2C4" HorizontalAlignment="Center" Margin="0,0,0,15"/>
                            <RadioButton Name="RadDesk1" GroupName="DeskGroup" Content="🚀 Muito fácil! (Estou voando)" FontSize="13" Foreground="White" Margin="0,6,0,8" Height="26" VerticalContentAlignment="Center" Cursor="Hand"/>
                            <RadioButton Name="RadDesk2" GroupName="DeskGroup" Content="💡 Tranquilo (Dá para fazer)" FontSize="13" Foreground="White" Margin="0,6,0,8" Height="26" VerticalContentAlignment="Center" Cursor="Hand"/>
                            <RadioButton Name="RadDesk3" GroupName="DeskGroup" Content="🧠 Difícil (Está dando trabalho)" FontSize="13" Foreground="White" Margin="0,6,0,8" Height="26" VerticalContentAlignment="Center" Cursor="Hand"/>
                            <RadioButton Name="RadDesk4" GroupName="DeskGroup" Content="🛑 Travado (Preciso de ajuda!)" FontSize="13" Foreground="White" Margin="0,6,0,8" Height="26" VerticalContentAlignment="Center" Cursor="Hand"/>
                        </StackPanel>
                    </Border>
                </Grid>
                
                <!-- Save Button -->
                <Button Name="BtnSave" Grid.Row="3" Content="Salvar Expedição 💾" FontSize="16" FontWeight="Bold" Height="48" Background="#FF5E62" Foreground="White" Cursor="Hand" IsEnabled="False"/>
            </Grid>
        </Border>
    </Window>
"@

    $reader = New-Object System.Xml.XmlNodeReader([xml]$xaml)
    $window = [Windows.Markup.XamlReader]::Load($reader)

    $lblPCName = $window.FindName("LblPCName")
    $lblDeskName = $window.FindName("LblDeskName")
    $btnSave = $window.FindName("BtnSave")

    $radPC1 = $window.FindName("RadPC1")
    $radPC2 = $window.FindName("RadPC2")
    $radPC3 = $window.FindName("RadPC3")
    $radPC4 = $window.FindName("RadPC4")

    $radDesk1 = $window.FindName("RadDesk1")
    $radDesk2 = $window.FindName("RadDesk2")
    $radDesk3 = $window.FindName("RadDesk3")
    $radDesk4 = $window.FindName("RadDesk4")

    $lblPCName.Text = "$StudentPCName (no Computador)"
    $lblDeskName.Text = "$StudentDeskName (na Mesa)"

    $checkSelection = {
        $pcVal = ($radPC1.IsChecked -eq $true -or $radPC2.IsChecked -eq $true -or $radPC3.IsChecked -eq $true -or $radPC4.IsChecked -eq $true)
        $deskVal = ($radDesk1.IsChecked -eq $true -or $radDesk2.IsChecked -eq $true -or $radDesk3.IsChecked -eq $true -or $radDesk4.IsChecked -eq $true)
        $btnSave.IsEnabled = ($pcVal -and $deskVal)
    }

    # Listeners
    $radios = @($radPC1, $radPC2, $radPC3, $radPC4, $radDesk1, $radDesk2, $radDesk3, $radDesk4)
    foreach ($rad in $radios) {
        $rad.add_Checked($checkSelection)
    }

    # Result hashtable
    $results = @{
        PC_Load = 0
        Desk_Load = 0
        Status = $false
    }

    $btnSave.add_Click({
        if ($radPC1.IsChecked) { $results.PC_Load = 1 }
        elseif ($radPC2.IsChecked) { $results.PC_Load = 2 }
        elseif ($radPC3.IsChecked) { $results.PC_Load = 3 }
        elseif ($radPC4.IsChecked) { $results.PC_Load = 4 }

        if ($radDesk1.IsChecked) { $results.Desk_Load = 1 }
        elseif ($radDesk2.IsChecked) { $results.Desk_Load = 2 }
        elseif ($radDesk3.IsChecked) { $results.Desk_Load = 3 }
        elseif ($radDesk4.IsChecked) { $results.Desk_Load = 4 }

        $results.Status = $true
        $window.Close()
    })

    # Close Dialog on timeout parameter
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromSeconds($script:Config.timeout_seconds)
    $timer.add_Tick({
        $timer.Stop()
        $window.Close()
    })
    $timer.Start()

    $window.ShowDialog() | Out-Null
    $timer.Stop()

    return $results
}

function Show-WpfEnding {
    param(
        [string]$StudentPCName,
        [string]$StudentDeskName
    )

    $xaml = @"
    <Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
            xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
            Title="Finalizar Oficina Pulselab" Width="720" Height="500"
            WindowStartupLocation="CenterScreen" WindowStyle="None" AllowsTransparency="True" Background="Transparent" Topmost="True">
        <Border CornerRadius="24" Background="#170F24" BorderBrush="#8E2DE2" BorderThickness="3">
            <Grid Margin="20">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                
                <!-- Header -->
                <TextBlock Grid.Row="0" Text="🏁 CONCLUIR OFICINA DE ROBÓTICA" FontSize="24" FontWeight="ExtraBold" Foreground="#8E2DE2" HorizontalAlignment="Center" Margin="0,5,0,15"/>
                
                <!-- Student Panels -->
                <Grid Grid.Row="1" Margin="0,0,0,10">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="15"/>
                        <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>
                    
                    <!-- PC kid ending panel -->
                    <Border Grid.Column="0" CornerRadius="16" Background="#281A3A" Padding="15" BorderBrush="#4A90E2" BorderThickness="2">
                        <StackPanel>
                            <TextBlock Name="LblPCName" FontSize="18" FontWeight="Bold" Foreground="#4A90E2" HorizontalAlignment="Center" Margin="0,0,0,15"/>
                            
                            <!-- Question 1 -->
                            <TextBlock Text="O que você mais sentiu na oficina?" FontSize="13" FontWeight="Bold" Foreground="White" Margin="0,5,0,5"/>
                            <ComboBox Name="CboPCAfet" FontSize="14" Height="30" Background="#3D295C" Foreground="White" VerticalContentAlignment="Center" Margin="0,0,0,15">
                                <ComboBoxItem Content="😃 Orgulho"/>
                                <ComboBoxItem Content="😐 Concentração"/>
                                <ComboBoxItem Content="🙁 Frustração"/>
                            </ComboBox>
                            
                            <!-- Question 2 -->
                            <TextBlock Text="Gostaria de participar de mais aulas?" FontSize="13" FontWeight="Bold" Foreground="White" Margin="0,5,0,5"/>
                            <RadioButton Name="RadPCAttYes" Content="😍 Sim, com certeza!" FontSize="13" Foreground="White" Margin="0,5,0,6" Cursor="Hand"/>
                            <RadioButton Name="RadPCAttNo" Content="🙁 Não, achei chato" FontSize="13" Foreground="White" Margin="0,5,0,6" Cursor="Hand"/>
                        </StackPanel>
                    </Border>
                    
                    <!-- Spacer -->
                    <Grid Grid.Column="1"/>
                    
                    <!-- Desk kid ending panel -->
                    <Border Grid.Column="2" CornerRadius="16" Background="#281A3A" Padding="15" BorderBrush="#00D2C4" BorderThickness="2">
                        <StackPanel>
                            <TextBlock Name="LblDeskName" FontSize="18" FontWeight="Bold" Foreground="#00D2C4" HorizontalAlignment="Center" Margin="0,0,0,15"/>
                            
                            <!-- Question 1 -->
                            <TextBlock Text="O que você mais sentiu na oficina?" FontSize="13" FontWeight="Bold" Foreground="White" Margin="0,5,0,5"/>
                            <ComboBox Name="CboDeskAfet" FontSize="14" Height="30" Background="#3D295C" Foreground="White" VerticalContentAlignment="Center" Margin="0,0,0,15">
                                <ComboBoxItem Content="😃 Orgulho"/>
                                <ComboBoxItem Content="😐 Concentração"/>
                                <ComboBoxItem Content="🙁 Frustração"/>
                            </ComboBox>
                            
                            <!-- Question 2 -->
                            <TextBlock Text="Gostaria de participar de mais aulas?" FontSize="13" FontWeight="Bold" Foreground="White" Margin="0,5,0,5"/>
                            <RadioButton Name="RadDeskAttYes" Content="😍 Sim, com certeza!" FontSize="13" Foreground="White" Margin="0,5,0,6" Cursor="Hand"/>
                            <RadioButton Name="RadDeskAttNo" Content="🙁 Não, achei chato" FontSize="13" Foreground="White" Margin="0,5,0,6" Cursor="Hand"/>
                        </StackPanel>
                    </Border>
                </Grid>
                
                <!-- Complete Button -->
                <Button Name="BtnFinish" Grid.Row="2" Content="Finalizar Oficina de Robótica 🏁" FontSize="16" FontWeight="Bold" Height="48" Background="#8E2DE2" Foreground="White" Cursor="Hand" IsEnabled="False"/>
            </Grid>
        </Border>
    </Window>
"@

    $reader = New-Object System.Xml.XmlNodeReader([xml]$xaml)
    $window = [Windows.Markup.XamlReader]::Load($reader)

    $lblPCName = $window.FindName("LblPCName")
    $lblDeskName = $window.FindName("LblDeskName")
    $btnFinish = $window.FindName("BtnFinish")

    $cboPCAfet = $window.FindName("CboPCAfet")
    $radPCAttYes = $window.FindName("RadPCAttYes")
    $radPCAttNo = $window.FindName("RadPCAttNo")

    $cboDeskAfet = $window.FindName("CboDeskAfet")
    $radDeskAttYes = $window.FindName("RadDeskAttYes")
    $radDeskAttNo = $window.FindName("RadDeskAttNo")

    $lblPCName.Text = $StudentPCName
    $lblDeskName.Text = $StudentDeskName

    $checkCompletion = {
        $pcA = ($cboPCAfet.SelectedIndex -ne -1)
        $deskA = ($cboDeskAfet.SelectedIndex -ne -1)
        $pcAtt = ($radPCAttYes.IsChecked -eq $true -or $radPCAttNo.IsChecked -eq $true)
        $deskAtt = ($radDeskAttYes.IsChecked -eq $true -or $radDeskAttNo.IsChecked -eq $true)
        $btnFinish.IsEnabled = ($pcA -and $deskA -and $pcAtt -and $deskAtt)
    }

    # Listeners
    $cboPCAfet.add_SelectionChanged($checkCompletion)
    $cboDeskAfet.add_SelectionChanged($checkCompletion)
    $radPCAttYes.add_Checked($checkCompletion)
    $radPCAttNo.add_Checked($checkCompletion)
    $radDeskAttYes.add_Checked($checkCompletion)
    $radDeskAttNo.add_Checked($checkCompletion)

    $results = @{
        PC_Afet = ""
        PC_Att = $false
        Desk_Afet = ""
        Desk_Att = $false
        Status = $false
    }

    $btnFinish.add_Click({
        # Map values cleanly
        # Extract emoji and space to get clean text e.g., 'Orgulho', 'Concentração', 'Frustração'
        $selPC = $cboPCAfet.SelectedItem.Content
        $results.PC_Afet = $selPC.Substring(2)
        $results.PC_Att = ($radPCAttYes.IsChecked -eq $true)

        $selDesk = $cboDeskAfet.SelectedItem.Content
        $results.Desk_Afet = $selDesk.Substring(2)
        $results.Desk_Att = ($radDeskAttYes.IsChecked -eq $true)

        $results.Status = $true
        $window.Close()
    })

    $window.ShowDialog() | Out-Null
    return $results
}

# =============================================================================
# TRAY NOTIFICATION ARCHITECTURE
# =============================================================================

function Initialize-TrayIcon {
    try {
        $script:NotifyIcon = New-Object System.Windows.Forms.NotifyIcon
        $script:NotifyIcon.Icon = [System.Drawing.SystemIcons]::Application
        $script:NotifyIcon.Text = "Pulselab - Oficina de Robótica"
        $script:NotifyIcon.Visible = $true

        $contextMenu = New-Object System.Windows.Forms.ContextMenu
        $menuItemExit = New-Object System.Windows.Forms.MenuItem
        $menuItemExit.Text = "Concluir Oficina"
        $contextMenu.MenuItems.Add($menuItemExit) | Out-Null
        $script:NotifyIcon.ContextMenu = $contextMenu

        $menuItemExit.Add_Click({
            Write-PulseLog -Level "INFO" -Message "Manual session termination triggered from Tray Icon."
            $script:TriggerEnding = $true
        })

        Write-PulseLog -Level "INFO" -Message "System Tray Icon successfully registered in notification area."
    } catch {
        Write-PulseLog -Level "WARN" -Message "Failed to initialize Notification Tray Icon: $_"
    }
}

function Dispose-TrayIcon {
    if ($null -ne $script:NotifyIcon) {
        $script:NotifyIcon.Visible = $false
        $script:NotifyIcon.Dispose()
        $script:NotifyIcon = $null
        Write-PulseLog -Level "INFO" -Message "Notification Tray Icon successfully disposed."
    }
}

# =============================================================================
# MAIN EVENT ORCHESTRATION LOOP
# =============================================================================

function Start-DaemonLoop {
    $marks = [int[]]$script:Config.interval_marks_minutes
    $markCount = $marks.Count

    Write-PulseLog -Level "INFO" -Message "Daemon background collector loop started. Marks=$($marks -join ',')"

    $script:SpikeHandle = Get-SpikeWindowHandle
    $cycleIndex = 0

    while ($cycleIndex -lt $markCount -and -not $script:TriggerEnding) {
        $currentMark = $marks[$cycleIndex]
        $lastMark = if ($cycleIndex -gt 0) { $marks[$cycleIndex - 1] } else { 0 }
        $gapMinutes = $currentMark - $lastMark

        # Determine interval target
        $targetSeconds = if ($script:Config.debug_mode -or $script:ProductionTest) { $gapMinutes } else { $gapMinutes * 60 }
        Write-PulseLog -Level "INFO" -Message "Timer counting down until next evaluation mark. Mark=$currentMark GapSeconds=$targetSeconds"

        # Responsive sleep loop to keep System Tray Icon active
        $sleptMs = 0
        $totalSleepMs = $targetSeconds * 1000
        while ($sleptMs -lt $totalSleepMs -and -not $script:TriggerEnding) {
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 100
            $sleptMs += 100
        }

        # If manual conclusion was triggered during sleep, break loop
        if ($script:TriggerEnding) {
            break
        }

        # Sync active window handle
        $script:SpikeHandle = Get-SpikeWindowHandle

        # Reload remote config for runtime changes
        Get-RemoteConfig

        # Flush cache offline queue if online
        Invoke-FlushCache

        # ----------------------------------------------------
        # Telemetry collection (BEFORE displaying WPF pop-up)
        # ----------------------------------------------------
        Write-PulseLog -Level "INFO" -Message "Collecting workspace state telemetries for Mark=$currentMark..."
        $osTelemetry = Get-ActiveTelemetry
        $spikeFileSize = Get-LastSpikeFileSize
        
        # Local compressed screenshot capture
        $localPicPath = Join-Path $script:OFFLINE_CACHE_DIR "screenshot_$($script:SessionId)_$($currentMark).jpg"
        Get-ScreenCapture -FilePath $localPicPath

        # Display kid-friendly popup
        $results = Show-WpfSampling `
            -Question $script:Config.question_text `
            -StudentPCName $script:StudentPC `
            -StudentDeskName $script:StudentDesk

        # Return focus to SPIKE
        Restore-SpikeFocus -Handle $script:SpikeHandle

        if ($results.Status) {
            # Build payload hash
            $payload = @{
                session_id                 = $script:SessionId
                regional_hub               = $script:Config.regional_hub
                computer_id                = $script:ComputerId
                interval_mark              = $currentMark
                student_pc_name            = $script:StudentPC
                student_pc_load            = $results.PC_Load
                student_desk_name          = $script:StudentDesk
                student_desk_load          = $results.Desk_Load
                telemetry_window_title     = $osTelemetry.WindowTitle
                telemetry_foreground_app   = $osTelemetry.ForegroundApp
                telemetry_idle_seconds     = $osTelemetry.IdleSeconds
                telemetry_file_size_kb     = $spikeFileSize
                screenshot_url             = $null
                local_screenshot_path      = $localPicPath
            }

            # Attempt upload and submission
            Write-PulseLog -Level "INFO" -Message "Uploading and submitting Mark=$currentMark data..."
            $pubUrl = Upload-ScreenshotToSupabase -LocalFilePath $localPicPath -IntervalMark $currentMark
            if ($null -ne $pubUrl) {
                $payload["screenshot_url"] = $pubUrl
                $payload["local_screenshot_path"] = $null
                Remove-Item $localPicPath -Force -ErrorAction SilentlyContinue
                
                $sent = Send-ResponseToSupabase -Payload $payload
                if (-not $sent) {
                    $payload["local_screenshot_path"] = $localPicPath # restore path for cached uploads
                    Add-ToLocalQueue -Payload $payload
                }
            } else {
                # Offline/Failure cache save
                Add-ToLocalQueue -Payload $payload
            }
        } else {
            Write-PulseLog -Level "WARN" -Message "Evaluation mark pop-up timed out without child responses."
            # Delete unused screen capture file
            Remove-Item $localPicPath -Force -ErrorAction SilentlyContinue
        }

        $cycleIndex++
    }

    # ----------------------------------------------------
    # JANELA 3: POST-TEST ENDING (Mark 99)
    # ----------------------------------------------------
    Write-PulseLog -Level "INFO" -Message "Triggering final post-test and office exit evaluation (Mark 99)..."
    
    $script:SpikeHandle = Get-SpikeWindowHandle
    
    $endingResults = Show-WpfEnding -StudentPCName $script:StudentPC -StudentDeskName $script:StudentDesk
    
    # Return focus to SPIKE
    Restore-SpikeFocus -Handle $script:SpikeHandle

    if ($endingResults.Status) {
        # Final telemetries
        $osTelemetry = Get-ActiveTelemetry
        $spikeFileSize = Get-LastSpikeFileSize
        
        $localPicPath = Join-Path $script:OFFLINE_CACHE_DIR "screenshot_$($script:SessionId)_99.jpg"
        Get-ScreenCapture -FilePath $localPicPath

        $payload99 = @{
            session_id                 = $script:SessionId
            regional_hub               = $script:Config.regional_hub
            computer_id                = $script:ComputerId
            interval_mark              = 99
            student_pc_name            = $script:StudentPC
            student_pc_load            = 1 # baseline cognitive load defaults
            student_pc_post_afet       = $endingResults.PC_Afet
            student_pc_post_att        = $endingResults.PC_Att
            student_desk_name          = $script:StudentDesk
            student_desk_load          = 1
            student_desk_post_afet     = $endingResults.Desk_Afet
            student_desk_post_att      = $endingResults.Desk_Att
            telemetry_window_title     = $osTelemetry.WindowTitle
            telemetry_foreground_app   = $osTelemetry.ForegroundApp
            telemetry_idle_seconds     = $osTelemetry.IdleSeconds
            telemetry_file_size_kb     = $spikeFileSize
            screenshot_url             = $null
            local_screenshot_path      = $localPicPath
        }

        # Upload and post
        $pubUrl = Upload-ScreenshotToSupabase -LocalFilePath $localPicPath -IntervalMark "99"
        if ($null -ne $pubUrl) {
            $payload99["screenshot_url"] = $pubUrl
            $payload99["local_screenshot_path"] = $null
            Remove-Item $localPicPath -Force -ErrorAction SilentlyContinue

            $sent = Send-ResponseToSupabase -Payload $payload99
            if (-not $sent) {
                $payload99["local_screenshot_path"] = $localPicPath
                Add-ToLocalQueue -Payload $payload99
            }
        } else {
            Add-ToLocalQueue -Payload $payload99
        }
    } else {
        Write-PulseLog -Level "WARN" -Message "Post-test ending evaluations skipped by child termination."
    }

    # Final attempt to flush offline queue
    Invoke-FlushCache
}

# =============================================================================
# ENTRY POINT
# =============================================================================

try {
    Initialize-Session
    Get-RemoteConfig
    Get-EnvCredentials

    # Display Login
    Show-WpfLogin

    if ([string]::IsNullOrWhiteSpace($script:StudentPC) -or [string]::IsNullOrWhiteSpace($script:StudentDesk)) {
        Write-PulseLog -Level "WARN" -Message "Login window canceled or empty. Terminating daemon."
        exit 0
    }

    # Setup interactive Tray Icon in background
    Initialize-TrayIcon

    # Attempt cache sync on boot
    Invoke-FlushCache

    # Enter core loops
    Start-DaemonLoop

} catch {
    Write-PulseLog -Level "ERROR" -Message "Fatal daemon execution crash: $($_.Exception.Message)"
} finally {
    Dispose-TrayIcon
    Write-PulseLog -Level "INFO" -Message "Pulselab session terminated gracefully. Goodbye."
}
