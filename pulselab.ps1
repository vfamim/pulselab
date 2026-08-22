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

$params = @{}
if ($DebugMode) { $params["DebugMode"] = $true }
if ($ProductionTest) { $params["ProductionTest"] = $true }
& $agentPath @params
exit $LASTEXITCODE
