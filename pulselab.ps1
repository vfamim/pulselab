#Requires -Version 5.1
# PulseLab 1.5.0 - authenticated agent launcher

[CmdletBinding()]
param(
    [switch]$DebugMode,
    [switch]$ProductionTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$agentPath = Join-Path $PSScriptRoot "agent\pulselab-agent.ps1"
$sessionPath = Join-Path ([Environment]::GetFolderPath("LocalApplicationData")) "PulseLab\device_session.dat"

if (-not (Test-Path -LiteralPath $agentPath -PathType Leaf)) {
    throw "PulseLab agent not found: $agentPath"
}
if (-not (Test-Path -LiteralPath $sessionPath -PathType Leaf)) {
    $enrollPath = Join-Path $PSScriptRoot "supabase\scripts\enroll-device.ps1"
    throw "Device is not enrolled. Run '$enrollPath' with a coordinator-issued one-time token before starting PulseLab."
}

$params = @{}
if ($DebugMode) { $params["DebugMode"] = $true }
if ($ProductionTest) { $params["ProductionTest"] = $true }
& $agentPath @params
exit $LASTEXITCODE
