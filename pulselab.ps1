#Requires -Version 5.1
# PulseLab 1.5.0 - authenticated agent launcher

[CmdletBinding()]
param(
    [switch]$DebugMode,
    [switch]$ProductionTest,
    [switch]$DevMode
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$agentPath = Join-Path $PSScriptRoot "agent\pulselab-agent.ps1"
$localDataRoot = [Environment]::GetFolderPath("LocalApplicationData")
if ([string]::IsNullOrWhiteSpace($localDataRoot)) { $localDataRoot = $env:TEMP }
$sessionPath = Join-Path $localDataRoot "PulseLab\device_session.dat"

if (-not (Test-Path -LiteralPath $agentPath -PathType Leaf)) {
    throw "PulseLab agent not found: $agentPath"
}

if (-not (Test-Path -LiteralPath $sessionPath -PathType Leaf)) {
    if ($DebugMode -or $ProductionTest -or $DevMode) {
        $devSetupScript = Join-Path $PSScriptRoot "scripts\setup-dev-session.ps1"
        if (Test-Path -LiteralPath $devSetupScript -PathType Leaf) {
            Write-Host "Sessao DPAPI nao encontrada. Inicializando ambiente de teste local..." -ForegroundColor Yellow
            & $devSetupScript
        }
    }
}

if (-not (Test-Path -LiteralPath $sessionPath -PathType Leaf)) {
    $enrollPath = Join-Path $PSScriptRoot "supabase\scripts\enroll-device.ps1"
    throw "Device is not enrolled. Run '$enrollPath' with a coordinator-issued one-time token, or run '.\scripts\setup-dev-session.ps1' for local testing."
}

$params = @{}
if ($DebugMode) { $params["DebugMode"] = $true }
if ($ProductionTest) { $params["ProductionTest"] = $true }
& $agentPath @params
exit $LASTEXITCODE
