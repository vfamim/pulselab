#Requires -Version 5.1
<#
.SYNOPSIS
    Script cliente para enrollment seguro de dispositivo PulseLab.
.DESCRIPTION
    Chama a Edge Function enroll-device usando apenas a chave anon e um token de
    enrollment individual de uso único, obtém tokens de sessão (access_token,
    refresh_token) e salva no armazenamento local protegido por DPAPI.
    Nunca recebe nem utiliza uma chave administrativa privilegiada.
.PARAMETER SupabaseUrl
    URL base do projeto Supabase (ex: https://xxx.supabase.co).
.PARAMETER SupabaseAnonKey
    Chave pública anon do Supabase.
.PARAMETER EnrollmentToken
    Token de uso único como SecureString. Quando omitido, o script solicita o
    valor em prompt mascarado para não gravá-lo no histórico ou na linha de comando.
.PARAMETER SiteId
    Identificador da sede/polo (ex: JUAZEIRO-BA).
.PARAMETER RegionalHub
    Polo regional (ex: Polo-Nordeste-01).
.PARAMETER SchoolCode
    Código da escola (ex: ESCOLA-01).
.PARAMETER ComputerId
    Identificador do computador (ex: LAB-01).
.PARAMETER InstallationId
    UUID fixo da máquina (se omitido, lê de installation.json ou gera novo GUID).
.PARAMETER OutputSessionPath
    Caminho de saída para o arquivo de sessão protegido por DPAPI.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$SupabaseUrl = $env:PULSELAB_URL,

    [Parameter(Mandatory = $false)]
    [string]$SupabaseAnonKey = $env:PULSELAB_ANON_KEY,

    [Parameter(Mandatory = $false)]
    [Security.SecureString]$EnrollmentToken,

    [Parameter(Mandatory = $false)]
    [string]$SiteId = "CONFIGURE_SEDE",

    [Parameter(Mandatory = $false)]
    [string]$RegionalHub = "CONFIGURE_REGIONAL",

    [Parameter(Mandatory = $false)]
    [string]$SchoolCode = "CONFIGURE_ESCOLA",

    [Parameter(Mandatory = $false)]
    [string]$ComputerId = $env:COMPUTERNAME,

    [Parameter(Mandatory = $false)]
    [string]$InstallationId = "",

    [Parameter(Mandatory = $false)]
    [string]$OutputSessionPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Security

if ([string]::IsNullOrWhiteSpace($SupabaseUrl)) {
    throw "SupabaseUrl is required (pass -SupabaseUrl or define env var PULSELAB_URL)."
}
if ([string]::IsNullOrWhiteSpace($SupabaseAnonKey)) {
    throw "SupabaseAnonKey is required (pass -SupabaseAnonKey or define env var PULSELAB_ANON_KEY)."
}
if ($null -eq $EnrollmentToken -and -not [string]::IsNullOrWhiteSpace($env:PULSELAB_ENROLLMENT_TOKEN)) {
    $EnrollmentToken = ConvertTo-SecureString $env:PULSELAB_ENROLLMENT_TOKEN -AsPlainText -Force
    Remove-Item Env:PULSELAB_ENROLLMENT_TOKEN -ErrorAction SilentlyContinue
}
if ($null -eq $EnrollmentToken) {
    $EnrollmentToken = Read-Host "Token de enrollment de uso único" -AsSecureString
}
if ($null -eq $EnrollmentToken -or $EnrollmentToken.Length -lt 32) {
    throw "EnrollmentToken is required and must contain at least 32 characters."
}

$localDataRoot = [Environment]::GetFolderPath("LocalApplicationData")
if ([string]::IsNullOrWhiteSpace($localDataRoot)) { $localDataRoot = $env:TEMP }
$dataDir = Join-Path $localDataRoot "PulseLab"
if (-not (Test-Path $dataDir)) { New-Item -ItemType Directory -Path $dataDir -Force | Out-Null }

$installationFile = Join-Path $dataDir "installation.json"
if ([string]::IsNullOrWhiteSpace($InstallationId)) {
    if (Test-Path $installationFile) {
        try {
            $existing = Get-Content $installationFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($existing.installation_id) { $InstallationId = [string]$existing.installation_id }
        } catch {}
    }
}
if ([string]::IsNullOrWhiteSpace($InstallationId)) {
    $InstallationId = [Guid]::NewGuid().ToString()
}

$sessionFilePath = if (-not [string]::IsNullOrWhiteSpace($OutputSessionPath)) {
    $OutputSessionPath
} else {
    Join-Path $dataDir "device_session.dat"
}

Write-Host "Iniciando enrollment de dispositivo PulseLab..." -ForegroundColor Cyan
Write-Host "  Installation ID : $InstallationId"
Write-Host "  Site ID         : $SiteId"
Write-Host "  Computer ID     : $ComputerId"

# 1. Chamar Edge Function enroll-device com anon key + token de uso único
$edgeEndpoint = "$($SupabaseUrl.TrimEnd('/'))/functions/v1/enroll-device"
$headers = @{
    apikey = $SupabaseAnonKey
    Authorization = "Bearer $SupabaseAnonKey"
    "Content-Type" = "application/json"
}

$tokenBstr = [IntPtr]::Zero
$plainEnrollmentToken = $null
try {
    $tokenBstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($EnrollmentToken)
    $plainEnrollmentToken = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($tokenBstr)
    $enrollPayload = @{
        installation_id = $InstallationId
        site_id = $SiteId
        regional_hub = $RegionalHub
        school_code = $SchoolCode
        computer_id = $ComputerId
        enrollment_token = $plainEnrollmentToken
    } | ConvertTo-Json -Compress
    $response = Invoke-RestMethod -Method Post -Uri $edgeEndpoint -Headers $headers -Body $enrollPayload -ContentType "application/json" -TimeoutSec 20
} catch {
    $statusCode = $null
    $errBody = $null
    if ($_.Exception.Response) {
        $statusCode = [int]$_.Exception.Response.StatusCode
        try {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $errBody = $reader.ReadToEnd()
        } catch {}
    }
    throw "Falha no enrollment do dispositivo (HTTP $statusCode): $($_.Exception.Message) $errBody"
} finally {
    $enrollPayload = $null
    $plainEnrollmentToken = $null
    if ($tokenBstr -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($tokenBstr)
    }
}

if (-not $response -or -not $response.access_token) {
    throw "Resposta invalida da Edge Function: credenciais ausentes."
}

# 2. Salvar sessão em arquivo protegido por DPAPI
$sessionObj = @{
    access_token = [string]$response.access_token
    refresh_token = [string]$response.refresh_token
    expires_at = if ($response.expires_at) { [long]$response.expires_at } else { [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + 3600L }
    user_id = [string]$response.user_id
    installation_id = $InstallationId
    site_id = $SiteId
    updated_at = [DateTimeOffset]::UtcNow.ToString("o")
}

$sessionJson = $sessionObj | ConvertTo-Json -Depth 5 -Compress
$plainBytes = [System.Text.Encoding]::UTF8.GetBytes($sessionJson)
$cipherBytes = [System.Security.Cryptography.ProtectedData]::Protect(
    $plainBytes,
    $null,
    [System.Security.Cryptography.DataProtectionScope]::CurrentUser
)

$targetDir = [System.IO.Path]::GetDirectoryName($sessionFilePath)
if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }

[System.IO.File]::WriteAllBytes($sessionFilePath, $cipherBytes)
Write-Host "Sessao de dispositivo salva com protecao DPAPI em:" -ForegroundColor Green
Write-Host "  $sessionFilePath"

# 3. Atualizar installation.json local
$profile = @{
    installation_id = $InstallationId
    site_id = $SiteId
    regional_hub = $RegionalHub
    school_code = $SchoolCode
    computer_id = $ComputerId
    updated_at = [DateTimeOffset]::UtcNow.ToString("o")
}
$profile | ConvertTo-Json -Depth 4 | Set-Content $installationFile -Encoding UTF8 -Force
Write-Host "Perfil de instalacao salvo em: $installationFile" -ForegroundColor Green
Write-Host "Dispositivo matriculado com sucesso!" -ForegroundColor Cyan
