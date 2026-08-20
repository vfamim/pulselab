#Requires -Version 5.1
<#
.SYNOPSIS
    Inicializa o ambiente local de desenvolvimento e teste para o PulseLab.
.DESCRIPTION
    Cria a sessao local protegida por DPAPI (%LOCALAPPDATA%\PulseLab\device_session.dat),
    configura o perfil de instalacao (installation.json) e define as variaveis de ambiente
    necessarias para executar o agente em modo local/offline ou integrado com Supabase.
#>

[CmdletBinding()]
param(
    [string]$SupabaseUrl = "https://mock.supabase.co",
    [string]$SupabaseAnonKey = "mock-anon-key-pulselab-dev",
    [string]$SiteId = "SEDE-DEV",
    [string]$RegionalHub = "Polo-Nordeste-01",
    [string]$SchoolCode = "ESCOLA-DEV",
    [string]$WorkshopCode = "OFICINA-DEV",
    [string]$ClassCode = "TURMA-DEV",
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Security

$localDataRoot = [Environment]::GetFolderPath("LocalApplicationData")
if ([string]::IsNullOrWhiteSpace($localDataRoot)) { $localDataRoot = $env:TEMP }
$dataDir = Join-Path $localDataRoot "PulseLab"
if (-not (Test-Path $dataDir)) { New-Item -ItemType Directory -Path $dataDir -Force | Out-Null }

$sessionFilePath = Join-Path $dataDir "device_session.dat"
$installationFile = Join-Path $dataDir "installation.json"

$installationId = [Guid]::NewGuid().ToString()

if (Test-Path $installationFile) {
    try {
        $existingProfile = Get-Content $installationFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($existingProfile.installation_id) {
            $installationId = [string]$existingProfile.installation_id
        }
        if (-not $PSBoundParameters.ContainsKey("SiteId") -and $existingProfile.site_id) {
            $SiteId = [string]$existingProfile.site_id
        }
    } catch {}
}

# Salvar perfil de instalacao
$profile = @{
    installation_id = $installationId
    site_id = $SiteId
    regional_hub = $RegionalHub
    school_code = $SchoolCode
    workshop_code = $WorkshopCode
    class_code = $ClassCode
    activity_id = "atividade-01-spike"
    group_size = 2
    updated_at = [DateTimeOffset]::UtcNow.ToString("o")
}
$profile | ConvertTo-Json -Depth 4 | Set-Content $installationFile -Encoding UTF8 -Force
Write-Host " [OK] Perfil de instalacao salvo em: $installationFile" -ForegroundColor Green

# Criar sessao DPAPI de desenvolvimento
$sessionObj = @{
    access_token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.pulselab_dev_session"
    refresh_token = "pulselab_dev_refresh_token"
    expires_at = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + 31536000L # 1 ano
    user_id = "dev-user-local"
    installation_id = $installationId
    site_id = $SiteId
    updated_at = [DateTimeOffset]::UtcNow.ToString("o")
}

$sessionJson = $sessionObj | ConvertTo-Json -Compress
$plainBytes = [System.Text.Encoding]::UTF8.GetBytes($sessionJson)
$cipherBytes = [System.Security.Cryptography.ProtectedData]::Protect(
    $plainBytes,
    $null,
    [System.Security.Cryptography.DataProtectionScope]::CurrentUser
)
[System.IO.File]::WriteAllBytes($sessionFilePath, $cipherBytes)
Write-Host " [OK] Sessao DPAPI de desenvolvimento criada em: $sessionFilePath" -ForegroundColor Green

# Definir variaveis de ambiente no escopo User se ainda nao existirem ou se forcado
if ($Force -or [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable("PULSELAB_URL", "User"))) {
    [Environment]::SetEnvironmentVariable("PULSELAB_URL", $SupabaseUrl, "User")
    $env:PULSELAB_URL = $SupabaseUrl
    Write-Host " [OK] Variavel de ambiente PULSELAB_URL definida para o usuario." -ForegroundColor Green
}
if ($Force -or [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable("PULSELAB_ANON_KEY", "User"))) {
    [Environment]::SetEnvironmentVariable("PULSELAB_ANON_KEY", $SupabaseAnonKey, "User")
    $env:PULSELAB_ANON_KEY = $SupabaseAnonKey
    Write-Host " [OK] Variavel de ambiente PULSELAB_ANON_KEY definida para o usuario." -ForegroundColor Green
}

Write-Host "`nAmbiente de teste e desenvolvimento configurado com sucesso!" -ForegroundColor Cyan
