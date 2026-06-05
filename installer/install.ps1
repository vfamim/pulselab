#Requires -Version 5.1
# =============================================================================
# install.ps1
# Version    : 1.2.0
# Description: Automated bootstrap installer for Pulselab on Windows machines.
#              Downloads the latest repository zip from GitHub, extracts it to
#              C:\Users\Public\pulselab-main, configures local config.json and
#              user environment variables, and creates a Desktop shortcut.
#
# Usage      : $u="https://xxx.supabase.co"; $k="anon_key"; iex (irm "https://raw.githubusercontent.com/vfamim/pulselab/main/installer/install.ps1")
#              OR
#              .\install.ps1 -SupabaseUrl "https://..." -SupabaseKey "..."
# =============================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$SupabaseUrl = "",

    [Parameter(Mandatory = $false)]
    [string]$SupabaseKey = "",

    [Parameter(Mandatory = $false)]
    [string]$DestinationDir = "C:\Users\Public\pulselab-main",

    [Parameter(Mandatory = $false)]
    [string]$GitHubRepo = "vfamim/pulselab",

    [Parameter(Mandatory = $false)]
    [string]$Branch = "main"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Helper for colored output
function Write-InstallLog {
    param(
        [ValidateSet("INFO", "SUCCESS", "WARN", "ERROR")]
        [string]$Level,
        [string]$Message
    )
    $color = "White"
    $prefix = "[PULSELAB]"
    switch ($Level) {
        "INFO"    { $color = "Cyan";    $prefix = "[⚙️ INFO]" }
        "SUCCESS" { $color = "Green";   $prefix = "[✨ OK  ]" }
        "WARN"    { $color = "Yellow";  $prefix = "[⚠️ WARN]" }
        "ERROR"   { $color = "Red";     $prefix = "[🛑 ERRO]" }
    }
    Write-Host "$prefix $Message" -ForegroundColor $color
}

Write-InstallLog "INFO" "Iniciando instalador automatizado do Pulselab..."

# =============================================================================
# STEP 1: Resolve Supabase Credentials from caller scope, env or interactive prompt
# =============================================================================

# Read from caller scope variables ($u / $k) if running via iex
if ([string]::IsNullOrWhiteSpace($SupabaseUrl)) {
    if ($null -ne (Get-Variable -Name "u" -ErrorAction SilentlyContinue)) {
        $SupabaseUrl = (Get-Variable -Name "u").Value
    } elseif ($null -ne (Get-Variable -Name "SupabaseUrl" -Scope Global -ErrorAction SilentlyContinue)) {
        $SupabaseUrl = (Get-Variable -Name "SupabaseUrl" -Scope Global).Value
    } elseif (-not [string]::IsNullOrWhiteSpace([System.Environment]::GetEnvironmentVariable("PULSELAB_URL", "User"))) {
        $SupabaseUrl = [System.Environment]::GetEnvironmentVariable("PULSELAB_URL", "User")
    }
}

if ([string]::IsNullOrWhiteSpace($SupabaseKey)) {
    if ($null -ne (Get-Variable -Name "k" -ErrorAction SilentlyContinue)) {
        $SupabaseKey = (Get-Variable -Name "k").Value
    } elseif ($null -ne (Get-Variable -Name "SupabaseKey" -Scope Global -ErrorAction SilentlyContinue)) {
        $SupabaseKey = (Get-Variable -Name "SupabaseKey" -Scope Global).Value
    } elseif (-not [string]::IsNullOrWhiteSpace([System.Environment]::GetEnvironmentVariable("PULSELAB_KEY", "User"))) {
        $SupabaseKey = [System.Environment]::GetEnvironmentVariable("PULSELAB_KEY", "User")
    }
}

# If still missing, fallback to interactive input
if ([string]::IsNullOrWhiteSpace($SupabaseUrl)) {
    Write-InstallLog "WARN" "A URL do Supabase não foi fornecida."
    $SupabaseUrl = (Read-Host "🌐 Digite a URL do Supabase (ex: https://ref.supabase.co)").Trim()
}
if ([string]::IsNullOrWhiteSpace($SupabaseKey)) {
    Write-InstallLog "WARN" "A Anon Key do Supabase não foi fornecida."
    $SupabaseKey = (Read-Host "🔑 Digite a ANON KEY do Supabase").Trim()
}

if ([string]::IsNullOrWhiteSpace($SupabaseUrl) -or [string]::IsNullOrWhiteSpace($SupabaseKey)) {
    Write-InstallLog "ERROR" "Configuração inválida! A URL e a Anon Key são obrigatórias para prosseguir."
    exit 1
}

# =============================================================================
# STEP 2: Pre-check environment
# =============================================================================
try {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase -ErrorAction Stop
    Write-InstallLog "SUCCESS" "Suporte para interface WPF/XAML detectado com sucesso."
} catch {
    Write-InstallLog "WARN" "Montagens WPF não localizadas. A interface visual pode falhar nesta máquina."
}

# =============================================================================
# STEP 3: Download ZIP from GitHub (No Git required)
# =============================================================================
$zipUrl = "https://github.com/$GitHubRepo/archive/refs/heads/$Branch.zip"
$tempZipPath = Join-Path $env:TEMP "pulselab-setup-$([Guid]::NewGuid().ToString().Substring(0,8)).zip"
$tempExtractDir = Join-Path $env:TEMP "pulselab-extract-$([Guid]::NewGuid().ToString().Substring(0,8))"

Write-InstallLog "INFO" "Baixando repositório de '$zipUrl'..."
try {
    # Ensure TLS 1.2 is enabled for secure connection to GitHub
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    
    # Download ZIP file
    Invoke-WebRequest -Uri $zipUrl -OutFile $tempZipPath -UseBasicParsing
    Write-InstallLog "SUCCESS" "Download concluído com sucesso."
} catch {
    Write-InstallLog "ERROR" "Falha ao baixar o arquivo do GitHub: $_"
    exit 1
}

# =============================================================================
# STEP 4: Extract and install to destination
# =============================================================================
Write-InstallLog "INFO" "Extraindo arquivos do projeto..."
try {
    # Create temp extraction folder
    New-Item -ItemType Directory -Path $tempExtractDir -Force | Out-Null
    
    # Extract ZIP
    Expand-Archive -Path $tempZipPath -DestinationPath $tempExtractDir -Force
    Write-InstallLog "SUCCESS" "Extração concluída."

    # Identify extracted subfolder (usually 'pulselab-main' or similar)
    $subfolders = Get-ChildItem -Path $tempExtractDir | Where-Object { $_.PSIsContainer }
    $sourceDir = $subfolders[0].FullName

    # Clean destination if it exists (ensuring we don't have write locks)
    if (Test-Path $DestinationDir) {
        Write-InstallLog "WARN" "Pasta de destino '$DestinationDir' já existe. Atualizando arquivos..."
        # Remove old files but ignore cache/logs locks if any
        Remove-Item -Path "$DestinationDir\*" -Recurse -Force -ErrorAction SilentlyContinue
    } else {
        New-Item -ItemType Directory -Path $DestinationDir -Force | Out-Null
    }

    # Copy files to destination
    Copy-Item -Path "$sourceDir\*" -Destination $DestinationDir -Recurse -Force
    Write-InstallLog "SUCCESS" "Arquivos instalados em '$DestinationDir'."
} catch {
    Write-InstallLog "ERROR" "Falha na extração ou cópia dos arquivos: $_"
    # Cleanup
    Remove-Item -Path $tempZipPath -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $tempExtractDir -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
} finally {
    # Clean up zip and temp folder
    Remove-Item -Path $tempZipPath -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $tempExtractDir -Recurse -Force -ErrorAction SilentlyContinue
}

# =============================================================================
# STEP 5: Pre-configure config.json in destination
# =============================================================================
$configFilePath = Join-Path $DestinationDir "config\config.json"
if (Test-Path $configFilePath) {
    try {
        $configJson = Get-Content -Path $configFilePath -Raw -Encoding UTF8
        $configObj  = $configJson | ConvertFrom-Json
        $configObj.supabase_url = $SupabaseUrl
        $configObj.supabase_key = $SupabaseKey
        $configObj | ConvertTo-Json -Depth 10 | Set-Content -Path $configFilePath -Encoding UTF8 -Force
        Write-InstallLog "SUCCESS" "Credenciais gravadas no arquivo 'config/config.json' portátil."
    } catch {
        Write-InstallLog "WARN" "Não foi possível gravar as credenciais diretamente no config.json: $_"
    }
} else {
    Write-InstallLog "WARN" "config.json não encontrado em '$configFilePath'. Pulando gravação local."
}

# Config User-level environment variables as backup
try {
    [System.Environment]::SetEnvironmentVariable("PULSELAB_URL", $SupabaseUrl, "User")
    [System.Environment]::SetEnvironmentVariable("PULSELAB_KEY", $SupabaseKey, "User")
    Write-InstallLog "SUCCESS" "Variáveis de ambiente do usuário do Windows configuradas com sucesso."
} catch {
    Write-InstallLog "WARN" "Falha ao definir variáveis de ambiente: $_"
}

# =============================================================================
# STEP 6: Create Desktop Shortcut
# =============================================================================
$desktopDir  = [System.Environment]::GetFolderPath("Desktop")
$shortcutPath = Join-Path $desktopDir "Iniciar Pulselab - Oficina de Robótica.lnk"

try {
    # Remove old automatically startup folder link if it was ever configured
    $startupDir  = [System.Environment]::GetFolderPath("Startup")
    $legacyShortcut = Join-Path $startupDir "Pulselab.lnk"
    if (Test-Path $legacyShortcut) {
        Remove-Item $legacyShortcut -Force -ErrorAction SilentlyContinue
    }

    # Create Desktop shortcut pointing to the new install
    $wshell   = New-Object -ComObject WScript.Shell
    $shortcut = $wshell.CreateShortcut($shortcutPath)
    
    $shortcut.TargetPath       = "powershell.exe"
    $shortcut.Arguments        = "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$DestinationDir\pulselab.ps1`""
    $shortcut.WorkingDirectory = $DestinationDir
    $shortcut.WindowStyle      = 7 # Minimized/Hidden
    $shortcut.Description      = "Iniciar Pulselab - Oficina de Robótica"
    $shortcut.IconLocation     = "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe,0"
    $shortcut.Save()

    Write-InstallLog "SUCCESS" "Atalho na Área de Trabalho criado: '$shortcutPath'"
} catch {
    Write-InstallLog "WARN" "Falha ao criar o atalho na Área de Trabalho: $_"
}

# =============================================================================
# STEP 7: Completed
# =============================================================================
Write-InstallLog "SUCCESS" "--------------------------------------------------------"
Write-InstallLog "SUCCESS" "INSTALAÇÃO CONCLUÍDA COM SUCESSO!"
Write-InstallLog "SUCCESS" "Pulselab está pronto para ser utilizado nesta máquina."
Write-InstallLog "SUCCESS" "  Pasta Local : $DestinationDir"
Write-InstallLog "SUCCESS" "  Atalho      : Área de Trabalho -> 'Iniciar Pulselab - Oficina de Robótica'"
Write-InstallLog "SUCCESS" "--------------------------------------------------------"
