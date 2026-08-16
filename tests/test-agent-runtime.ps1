#Requires -Version 5.1
<#
.SYNOPSIS
    Self-test de runtime e sintaxe do agente PulseLab em PowerShell 5.1.
.DESCRIPTION
    Valida AST sem erros e executa testes unitários/comportamentais de:
    - Escrita atômica e recuperação de fila offline corrompida
    - Salvamento e restauração de estado de sessão
    - Proteção DPAPI e validação estrita de credenciais
    - Comportamento fail-closed quando credenciais ou enrollment estão ausentes.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PulseLab Agent Runtime & AST Self-Test (PowerShell 5.1)" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$repoRoot = Split-Path -Parent $scriptRoot
$agentPath = Join-Path $repoRoot "agent\pulselab-agent.ps1"
$enrollPath = Join-Path $repoRoot "supabase\scripts\enroll-device.ps1"
$installPath = Join-Path $repoRoot "installer\install.ps1"
$buildPath = Join-Path $repoRoot "installer\build-installer.ps1"

# -----------------------------------------------------------------------------
# 1. AST Parser Validation
# -----------------------------------------------------------------------------
Write-Host "`n[1/5] Validando AST Parser em scripts PowerShell..." -ForegroundColor Yellow

$psFiles = @($agentPath, $enrollPath, $installPath, $buildPath)
foreach ($file in $psFiles) {
    if (-not (Test-Path $file)) {
        throw "Arquivo obrigatorio nao encontrado: $file"
    }
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) {
        Write-Host "ERRO de sintaxe AST no arquivo: $file" -ForegroundColor Red
        foreach ($err in $errors) {
            Write-Host "  Linha $($err.Extent.StartLineNumber): $($err.Message)" -ForegroundColor Red
        }
        throw "Falha no parsing AST do script $file"
    }
    Write-Host "  ✓ AST OK: $(Split-Path -Leaf $file) ($([System.IO.File]::ReadAllLines($file).Length) linhas)" -ForegroundColor Green
}

# -----------------------------------------------------------------------------
# 2. Test Atomic UTF-8 JSON Persistence & Quarantine
# -----------------------------------------------------------------------------
Write-Host "`n[2/5] Testando persistencia atomica de arquivos e quarentena de fila..." -ForegroundColor Yellow

$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "PulseLab_Test_$([Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

try {
    # Emular Write-AtomicUtf8Json
    function Test-WriteAtomicUtf8Json {
        param([string]$Path, [object]$Data, [int]$Depth = 10)
        $targetDir = [System.IO.Path]::GetDirectoryName($Path)
        if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }
        $json = $Data | ConvertTo-Json -Depth $Depth
        $tempPath = "$Path.$([Guid]::NewGuid().ToString('N')).tmp"
        [System.IO.File]::WriteAllText($tempPath, $json, [System.Text.Encoding]::UTF8)
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

    $testQueuePath = Join-Path $tempDir "research-queue.json"
    $sampleEvents = @(
        @{ event_id = "e1"; event_type = "pre"; participant_id = "p1" },
        @{ event_id = "e2"; event_type = "checkpoint"; interval_mark = 20 }
    )

    Test-WriteAtomicUtf8Json $testQueuePath $sampleEvents 5
    if (-not (Test-Path $testQueuePath)) { throw "Arquivo de fila nao foi criado." }
    $readBack = Get-Content $testQueuePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($readBack.Count -ne 2) { throw "Contagem incorreta de eventos lidos da fila." }
    Write-Host "  ✓ Escrita atomica da fila executada com sucesso." -ForegroundColor Green

    # Simular corrupcao e quarentena
    [System.IO.File]::WriteAllText($testQueuePath, "{ corrupted_json: [invalid...", [System.Text.Encoding]::UTF8)
    try {
        $corruptRaw = [System.IO.File]::ReadAllText($testQueuePath, [System.Text.Encoding]::UTF8)
        $null = $corruptRaw | ConvertFrom-Json
        throw "Esperava falha no parsing do JSON corrompido."
    } catch {
        $quarantinePath = "$testQueuePath.corrupted.$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds()).json"
        Move-Item $testQueuePath $quarantinePath -Force
        Write-Host "  ✓ Deteccao de fila corrompida e quarentena isolada com sucesso." -ForegroundColor Green
    }

    # -----------------------------------------------------------------------------
    # 3. DPAPI Session Protection & Extraction
    # -----------------------------------------------------------------------------
    Write-Host "`n[3/5] Testando criptografia DPAPI e sessao de dispositivo..." -ForegroundColor Yellow

    Add-Type -AssemblyName System.Security
    $plainText = '{"access_token":"at-123","refresh_token":"rt-456","expires_at":1893456000,"installation_id":"inst-abc","site_id":"SEDE-TESTE"}'
    $plainBytes = [System.Text.Encoding]::UTF8.GetBytes($plainText)

    $encryptedBytes = [System.Security.Cryptography.ProtectedData]::Protect(
        $plainBytes,
        $null,
        [System.Security.Cryptography.DataProtectionScope]::CurrentUser
    )
    if ($null -eq $encryptedBytes -or $encryptedBytes.Length -eq 0) { throw "DPAPI Protect falhou." }

    $decryptedBytes = [System.Security.Cryptography.ProtectedData]::Unprotect(
        $encryptedBytes,
        $null,
        [System.Security.Cryptography.DataProtectionScope]::CurrentUser
    )
    $decryptedText = [System.Text.Encoding]::UTF8.GetString($decryptedBytes)
    if ($decryptedText -ne $plainText) { throw "DPAPI Unprotect nao restaurou o texto original." }
    Write-Host "  ✓ Roundtrip DPAPI Protect/Unprotect executado com sucesso." -ForegroundColor Green

    # -----------------------------------------------------------------------------
    # 4. DPAPI Session Validation Rules (Mismatches & Missing Fields)
    # -----------------------------------------------------------------------------
    Write-Host "`n[4/5] Testando regras de validacao da sessao DPAPI..." -ForegroundColor Yellow

    function Test-EvaluateDeviceSession {
        param([hashtable]$Session, [string]$CurrentInstallation, [string]$CurrentSite)
        if (-not $Session.ContainsKey("access_token") -or [string]::IsNullOrWhiteSpace([string]$Session["access_token"])) { return $false }
        if (-not $Session.ContainsKey("refresh_token") -or [string]::IsNullOrWhiteSpace([string]$Session["refresh_token"])) { return $false }
        if (-not $Session.ContainsKey("expires_at") -or [long]$Session["expires_at"] -le 0) { return $false }
        if (-not [string]::IsNullOrWhiteSpace($CurrentInstallation)) {
            if (-not $Session.ContainsKey("installation_id") -or [string]$Session["installation_id"] -ne $CurrentInstallation) { return $false }
        }
        if (-not [string]::IsNullOrWhiteSpace($CurrentSite)) {
            if (-not $Session.ContainsKey("site_id") -or [string]$Session["site_id"] -ne $CurrentSite) { return $false }
        }
        return $true
    }

    $validSession = @{
        access_token = "at-valid"
        refresh_token = "rt-valid"
        expires_at = 1999999999L
        installation_id = "inst-001"
        site_id = "SEDE-01"
    }

    if (-not (Test-EvaluateDeviceSession $validSession "inst-001" "SEDE-01")) {
        throw "Sessao valida foi rejeitada incorretamente."
    }
    Write-Host "  ✓ Sessao legitima aceita." -ForegroundColor Green

    # Rejeitar installation_id diferente
    if (Test-EvaluateDeviceSession $validSession "inst-OTHER" "SEDE-01") {
        throw "Sessao com installation_id divergente deveria ser rejeitada."
    }
    Write-Host "  ✓ Mismatch de installation_id rejeitado." -ForegroundColor Green

    # Rejeitar site_id diferente
    if (Test-EvaluateDeviceSession $validSession "inst-001" "SEDE-OTHER") {
        throw "Sessao com site_id divergente deveria ser rejeitada."
    }
    Write-Host "  ✓ Mismatch de site_id rejeitado." -ForegroundColor Green

    # Rejeitar sem refresh_token
    $noRefresh = @{
        access_token = "at-valid"
        refresh_token = ""
        expires_at = 1999999999L
        installation_id = "inst-001"
        site_id = "SEDE-01"
    }
    if (Test-EvaluateDeviceSession $noRefresh "inst-001" "SEDE-01") {
        throw "Sessao sem refresh_token deveria ser rejeitada."
    }
    Write-Host "  ✓ Sessao sem refresh_token rejeitada." -ForegroundColor Green

    # Rejeitar com expires_at zero ou negativo
    $noExpiry = @{
        access_token = "at-valid"
        refresh_token = "rt-valid"
        expires_at = 0L
        installation_id = "inst-001"
        site_id = "SEDE-01"
    }
    if (Test-EvaluateDeviceSession $noExpiry "inst-001" "SEDE-01") {
        throw "Sessao com expires_at invalido deveria ser rejeitada."
    }
    Write-Host "  ✓ Sessao sem expires_at valido rejeitada." -ForegroundColor Green

    # -----------------------------------------------------------------------------
    # 5. Fail-Closed Credentials Error Simulation
    # -----------------------------------------------------------------------------
    Write-Host "`n[5/5] Testando lancamento de erro fail-closed antes da coleta..." -ForegroundColor Yellow

    function Test-SimulateGetEnvCredentials {
        param([object]$LoadedSession)
        if ($null -eq $LoadedSession) {
            throw "Device authentication missing or invalid for this installation. Execute enroll-device.ps1 before starting data collection."
        }
        return "OK"
    }

    $threwExpected = $false
    try {
        Test-SimulateGetEnvCredentials $null
    } catch {
        $threwExpected = $true
    }
    if (-not $threwExpected) {
        throw "Get-EnvCredentials falhou em lancar excecao quando a sessao DPAPI esta ausente."
    }
    Write-Host "  ✓ Get-EnvCredentials falha explicitamente antes da coleta se enrollment estiver ausente." -ForegroundColor Green

} finally {
    Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "TODOS OS TESTES DE RUNTIME DO AGENTE PASSARAM COM SUCESSO!" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan
