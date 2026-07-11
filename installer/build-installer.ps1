[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$SupabaseUrl = $null,

    [Parameter(Mandatory = $false)]
    [string]$SupabaseKey = $null,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = $null
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Resolver caminhos do projeto
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptDir "..")

$agentPath = Join-Path $repoRoot "agent\pulselab-agent.ps1"
$configPath = Join-Path $repoRoot "config\config.json"
$envPath = Join-Path $repoRoot ".env"

# Dicionario para variaveis do .env
$dotenv = @{}

# Carregar arquivo .env se existir
if (Test-Path $envPath) {
    Write-Host "Lendo variaveis do arquivo .env em: $envPath"
    Get-Content $envPath | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith("#") -and $line.Contains("=")) {
            $parts = $line.Split("=", 2)
            $key = $parts[0].Trim()
            $val = $parts[1].Trim().Trim("'").Trim('"')
            $dotenv[$key] = $val
        }
    }
}

# Resolver URL (Parametro > .env > OS env)
if ([string]::IsNullOrWhiteSpace($SupabaseUrl)) {
    $SupabaseUrl = $dotenv["PULSELAB_URL"]
    if ([string]::IsNullOrWhiteSpace($SupabaseUrl)) {
        $SupabaseUrl = $dotenv["SUPABASE_URL"]
    }
    if ([string]::IsNullOrWhiteSpace($SupabaseUrl)) {
        $SupabaseUrl = $env:PULSELAB_URL
    }
}

# Resolver Key (Parametro > .env > OS env)
if ([string]::IsNullOrWhiteSpace($SupabaseKey)) {
    $SupabaseKey = $dotenv["PULSELAB_KEY"]
    if ([string]::IsNullOrWhiteSpace($SupabaseKey)) {
        $SupabaseKey = $dotenv["SUPABASE_KEY"]
    }
    if ([string]::IsNullOrWhiteSpace($SupabaseKey)) {
        $SupabaseKey = $dotenv["SUPABASE_ANON_KEY"]
    }
    if ([string]::IsNullOrWhiteSpace($SupabaseKey)) {
        $SupabaseKey = $env:PULSELAB_KEY
    }
}

# Solicitar interativamente se ainda nao resolvido
if ([string]::IsNullOrWhiteSpace($SupabaseUrl) -or [string]::IsNullOrWhiteSpace($SupabaseKey)) {
    Write-Host "--- Gerador de Instalador Standalone Pulselab ---"
    if ([string]::IsNullOrWhiteSpace($SupabaseUrl)) {
        $SupabaseUrl = (Read-Host "Digite a URL do Supabase (ex: https://xxx.supabase.co)").Trim()
    }
    if ([string]::IsNullOrWhiteSpace($SupabaseKey)) {
        $SupabaseKey = (Read-Host "Digite a Anon Key (Key publica) do Supabase").Trim()
    }
}

if ([string]::IsNullOrWhiteSpace($SupabaseUrl) -or [string]::IsNullOrWhiteSpace($SupabaseKey)) {
    Write-Error "Erro: A URL e a Anon Key sao obrigatorias."
    exit 1
}

if (-not $SupabaseUrl.StartsWith("http")) {
    Write-Error "Erro: A URL do Supabase deve comecar com http:// ou https://"
    exit 1
}

if (-not (Test-Path $agentPath)) {
    Write-Error "Erro: Arquivo do agente nao encontrado em: $agentPath"
    exit 1
}

if (-not (Test-Path $configPath)) {
    Write-Error "Erro: Arquivo de configuracao nao encontrado em: $configPath"
    exit 1
}

Write-Host "Lendo arquivos do projeto..."
$agentBytes = [System.IO.File]::ReadAllBytes($agentPath)
$agentB64 = [System.Convert]::ToBase64String($agentBytes)

$configBytes = [System.IO.File]::ReadAllBytes($configPath)
$configB64 = [System.Convert]::ToBase64String($configBytes)

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $repoRoot "Install-Pulselab.bat"
}

$batchTemplate = @"
@echo off
set "BATCH_PATH=%~f0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "iex ((Get-Content -LiteralPath `$env:BATCH_PATH -Raw) -split '(?ms)^#PS_START#')[1]"
exit /b %errorlevel%
#PS_START#
`$ErrorActionPreference = "Stop"

function Write-InstallerLog {
    param([string]`$Level, [string]`$Message)
    `$timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Write-Host "[`$timestamp] [`$Level] `$Message"
}

Write-InstallerLog "INFO" "Pulselab Standalone Installer"
Write-InstallerLog "INFO" "----------------------------------------"

# 1. Verificar assemblies WPF
try {
    Write-InstallerLog "INFO" "Verificando dependencias do WPF/XAML..."
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase -ErrorAction Stop
    Write-InstallerLog "INFO" "WPF verificado com sucesso."
} catch {
    Write-InstallerLog "ERROR" "WPF/PresentationFramework nao disponivel nesta maquina."
    Write-InstallerLog "ERROR" "Este aplicativo requer Windows 10/11 com ambiente desktop."
    Read-Host "Pressione Enter para sair..."
    exit 1
}

# 2. Configurar credenciais
`$supabaseUrl = "$SupabaseUrl"
`$supabaseKey = "$SupabaseKey"

Write-InstallerLog "INFO" "Configurando credenciais do Supabase..."
[System.Environment]::SetEnvironmentVariable("PULSELAB_URL", `$supabaseUrl, "User")
[System.Environment]::SetEnvironmentVariable("PULSELAB_KEY", `$supabaseKey, "User")

# 3. Criar pastas de instalacao
`$targetDir = "C:\Users\Public\Pulselab"
`$agentDir = `$targetDir
`$configDir = Join-Path `$targetDir "config"
`$cacheDir = Join-Path `$targetDir "cache"

Write-InstallerLog "INFO" "Criando pastas em `$targetDir..."
`$null = New-Item -ItemType Directory -Path `$agentDir -Force
`$null = New-Item -ItemType Directory -Path `$configDir -Force
`$null = New-Item -ItemType Directory -Path `$cacheDir -Force

# 4. Extrair script do agente
`$agentB64 = "$agentB64"
`$agentPath = Join-Path `$agentDir "pulselab-agent.ps1"
Write-InstallerLog "INFO" "Extraindo script do agente..."
`$agentBytes = [System.Convert]::FromBase64String(`$agentB64)
[System.IO.File]::WriteAllBytes(`$agentPath, `$agentBytes)

# 5. Extrair arquivo de configuracao
`$configB64 = "$configB64"
`$configPath = Join-Path `$configDir "config.json"
Write-InstallerLog "INFO" "Extraindo arquivo de configuracao..."
`$configBytes = [System.Convert]::FromBase64String(`$configB64)
[System.IO.File]::WriteAllBytes(`$configPath, `$configBytes)

# 6. Criar atalho na Area de Trabalho
`$desktopDir = [System.Environment]::GetFolderPath("Desktop")
`$shortcutPath = Join-Path `$desktopDir "Iniciar Pulselab - Oficina de Robotica.lnk"

# Remover atalho legado de inicializacao automatica se existir
`$startupDir = [System.Environment]::GetFolderPath("Startup")
`$legacyShortcut = Join-Path `$startupDir "Pulselab.lnk"
if (Test-Path `$legacyShortcut) {
    Write-InstallerLog "INFO" "Removendo atalho de inicializacao automatica antigo..."
    Remove-Item `$legacyShortcut -Force -ErrorAction SilentlyContinue
}

Write-InstallerLog "INFO" "Criando atalho na Area de Trabalho..."
try {
    `$wshell = New-Object -ComObject WScript.Shell
    `$shortcut = `$wshell.CreateShortcut(`$shortcutPath)
    `$shortcut.TargetPath = "powershell.exe"
    `$shortcut.Arguments = "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"`$agentPath`""
    `$shortcut.WorkingDirectory = `$agentDir
    `$shortcut.WindowStyle = 7 # Minimized/Hidden
    `$shortcut.Description = "Iniciar Pulselab - Oficina de Robotica"
    `$shortcut.IconLocation = "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe,0"
    `$shortcut.Save()
    Write-InstallerLog "INFO" "Atalho criado com sucesso: `$shortcutPath"
} catch {
    Write-InstallerLog "ERROR" "Erro ao criar o atalho: `$_"
}

Write-InstallerLog "INFO" "----------------------------------------"
Write-InstallerLog "INFO" "Instalacao concluida com sucesso!"
Write-InstallerLog "INFO" "O instrutor pode iniciar a oficina clicando no atalho da Area de Trabalho."
Write-InstallerLog "INFO" "----------------------------------------"
Read-Host "Pressione Enter para finalizar..."
"@

Write-Host "Escrevendo instalador standalone em: $OutputPath"
# Escrever como UTF-8 com BOM para garantir compatibilidade com Windows/CMD
$utf8NoBOM = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllText($OutputPath, $batchTemplate, $utf8NoBOM)

Write-Host "Instalador gerado com sucesso!"
