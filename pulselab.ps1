#Requires -Version 5.1
# =============================================================================
# pulselab.ps1
# Version    : 1.2.0
# Description: Unified self-configuring entrypoint for Pulselab.
#              Loads credentials from config.json (or environment), prompts
#              graphically in WPF space theme if missing, saves them locally
#              for portable execution, runs WPF shortcut setups, and starts the daemon.
#
# Execution  : powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File pulselab.ps1
# Permissions: Runs as standard user. No admin privileges required.
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

$script:ROOT_DIR    = $PSScriptRoot
$script:CONFIG_PATH = Join-Path $script:ROOT_DIR "config\config.json"
$script:AGENT_PATH  = Join-Path $script:ROOT_DIR "agent\pulselab-agent.ps1"
$script:ROBOT_PATH  = Join-Path $script:ROOT_DIR "agent\robot.png"

# =============================================================================
# LOGGING FUNCTION
# =============================================================================
function Write-SetupLog {
    param([string]$Level, [string]$Message)
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Write-Host "[$timestamp] [SETUP-$Level] $Message"
}

# =============================================================================
# STEP 1: Load and parse config
# =============================================================================
if (-not (Test-Path $script:CONFIG_PATH)) {
    Write-SetupLog "ERROR" "Configuration file not found at $script:CONFIG_PATH. Re-clone repository."
    exit 1
}

$configJson = Get-Content -Path $script:CONFIG_PATH -Raw -Encoding UTF8
$configObj  = $configJson | ConvertFrom-Json

# =============================================================================
# STEP 2: WPF Dialog to prompt for credentials if not found
# =============================================================================
function Show-WpfSetup {
    $robotPath = $script:ROBOT_PATH
    $xaml = @'
    <Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
            xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
            Title="Pulselab - Configuração" Width="430" Height="550"
            WindowStartupLocation="CenterScreen" WindowStyle="None" AllowsTransparency="True" Background="Transparent" Topmost="True">
        <Border CornerRadius="20" BorderBrush="#4A90E2" BorderThickness="3">
            <Border.Background>
                <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                    <GradientStop Color="#2C124D" Offset="0.0"/>
                    <GradientStop Color="#110A24" Offset="1.0"/>
                </LinearGradientBrush>
            </Border.Background>
            <Grid Margin="20">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                
                <!-- Header with Robot -->
                <StackPanel Grid.Row="0" Margin="0,5,0,15" HorizontalAlignment="Center">
                    <Image Name="ImgRobot" Width="85" Height="85" HorizontalAlignment="Center" Margin="0,0,0,10"/>
                    <TextBlock Text="⚙️ CONFIGURAÇÃO" FontSize="24" FontWeight="ExtraBold" Foreground="#4A90E2" HorizontalAlignment="Center"/>
                    <TextBlock Text="Servidor de Dados do Supabase" FontSize="14" Foreground="#A0A0C0" HorizontalAlignment="Center" Margin="0,5,0,0"/>
                </StackPanel>
                
                <!-- Inputs -->
                <StackPanel Grid.Row="1" VerticalAlignment="Center">
                    <TextBlock Text="SUPABASE URL 🌐" FontSize="15" FontWeight="Bold" Foreground="White" Margin="0,0,0,8"/>
                    <TextBox Name="TxtUrl" FontSize="15" Height="40" Background="#1C0F35" Foreground="White" BorderBrush="#4A90E2" BorderThickness="1.5" Padding="8,4" VerticalContentAlignment="Center" Margin="0,0,0,20"/>
                    
                    <TextBlock Text="SUPABASE ANON KEY 🔑" FontSize="15" FontWeight="Bold" Foreground="White" Margin="0,0,0,8"/>
                    <TextBox Name="TxtKey" FontSize="15" Height="40" Background="#1C0F35" Foreground="White" BorderBrush="#4A90E2" BorderThickness="1.5" Padding="8,4" VerticalContentAlignment="Center" Margin="0,0,0,10"/>
                </StackPanel>
                
                <!-- Save Button -->
                <Button Name="BtnSave" Grid.Row="2" Content="Salvar e Iniciar Oficina ✨" FontSize="16" FontWeight="Bold" Height="50" Background="#4A90E2" Foreground="White" Cursor="Hand" IsEnabled="False" Margin="0,10,0,10"/>
            </Grid>
        </Border>
    </Window>
'@

    $reader = New-Object System.Xml.XmlNodeReader([xml]$xaml)
    $window = [Windows.Markup.XamlReader]::Load($reader)

    if (Test-Path $robotPath) {
        $window.FindName("ImgRobot").Source = New-Object System.Windows.Media.Imaging.BitmapImage([Uri]$robotPath)
    }

    $txtUrl = $window.FindName("TxtUrl")
    $txtKey = $window.FindName("TxtKey")
    $btnSave = $window.FindName("BtnSave")

    $checkFields = {
        $btnSave.IsEnabled = ($txtUrl.Text.Trim() -ne "" -and $txtKey.Text.Trim() -ne "")
    }

    $txtUrl.add_TextChanged($checkFields)
    $txtKey.add_TextChanged($checkFields)

    $results = @{
        Url = ""
        Key = ""
        Status = $false
    }

    $btnSave.add_Click({
        $results.Url = $txtUrl.Text.Trim()
        $results.Key = $txtKey.Text.Trim()
        $results.Status = $true
        $window.Close()
    })

    $window.ShowDialog() | Out-Null
    return $results
}

# Load from environment variables (backup check)
$envUrl = [System.Environment]::GetEnvironmentVariable($configObj.supabase_url_env_var, "User")
$envKey = [System.Environment]::GetEnvironmentVariable($configObj.supabase_key_env_var, "User")

$hasConfigCreds = ($configObj.supabase_url -and $configObj.supabase_key -and -not [string]::IsNullOrWhiteSpace($configObj.supabase_url) -and -not [string]::IsNullOrWhiteSpace($configObj.supabase_key))
$hasEnvCreds    = (-not [string]::IsNullOrWhiteSpace($envUrl) -and -not [string]::IsNullOrWhiteSpace($envKey))

if (-not $hasConfigCreds -and -not $hasEnvCreds) {
    Write-SetupLog "INFO" "Supabase credentials missing. Displaying setup GUI..."
    
    $setup = Show-WpfSetup
    if (-not $setup.Status) {
        Write-SetupLog "ERROR" "Setup dialog cancelled. Setup incomplete."
        exit 1
    }

    $supabaseUrl = $setup.Url
    $supabaseKey = $setup.Key

    # Save to config.json for portable distribution!
    $configObj.supabase_url = $supabaseUrl
    $configObj.supabase_key = $supabaseKey
    $configObj | ConvertTo-Json -Depth 10 | Set-Content -Path $script:CONFIG_PATH -Encoding UTF8 -Force

    # Save to user env vars as backup compatibility
    [System.Environment]::SetEnvironmentVariable($configObj.supabase_url_env_var, $supabaseUrl, "User")
    [System.Environment]::SetEnvironmentVariable($configObj.supabase_key_env_var, $supabaseKey, "User")

    Write-SetupLog "INFO" "Credentials successfully configured in config.json and Windows user environment."
} else {
    Write-SetupLog "INFO" "Valid Supabase credentials detected."
}

# =============================================================================
# STEP 3: Setup shortcut on the Desktop (runs once)
# =============================================================================
$desktopDir  = [System.Environment]::GetFolderPath("Desktop")
$shortcutPath = Join-Path $desktopDir "Iniciar Pulselab - Oficina de Robótica.lnk"

if (-not (Test-Path $shortcutPath)) {
    try {
        Write-SetupLog "INFO" "Creating Desktop shortcut for manual launch..."
        
        $wshell   = New-Object -ComObject WScript.Shell
        $shortcut = $wshell.CreateShortcut($shortcutPath)
        
        $shortcut.TargetPath       = "powershell.exe"
        $shortcut.Arguments        = "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSScriptRoot\pulselab.ps1`""
        $shortcut.WorkingDirectory = $PSScriptRoot
        $shortcut.WindowStyle      = 7 # Minimized/Hidden
        $shortcut.Description      = "Iniciar Pulselab - Oficina de Robótica"
        $shortcut.IconLocation     = "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe,0"
        $shortcut.Save()
        
        Write-SetupLog "INFO" "Desktop shortcut created successfully at $shortcutPath"
    } catch {
        Write-SetupLog "WARN" "Failed to generate Desktop shortcut: $_"
    }
}

# =============================================================================
# STEP 4: Start the agent daemon
# =============================================================================
if (Test-Path $script:AGENT_PATH) {
    Write-SetupLog "INFO" "Starting Pulselab agent daemon..."
    
    # Forward command switches
    $params = @{}
    if ($DebugMode) { $params["DebugMode"] = $true }
    if ($ProductionTest) { $params["ProductionTest"] = $true }

    # Run the daemon
    & $script:AGENT_PATH @params
} else {
    Write-SetupLog "ERROR" "Agent daemon script not found at $script:AGENT_PATH"
    exit 1
}
