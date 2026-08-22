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

# Sincronizacao automatica do agente via GitHub (GitOps) se houver conexao
try {
    $remoteAgentUrl = "https://raw.githubusercontent.com/vfamim/pulselab/main/agent/pulselab-agent.ps1"
    $remoteResp = Invoke-WebRequest -Uri $remoteAgentUrl -UseBasicParsing -TimeoutSec 6 -ErrorAction Stop
    if ($remoteResp -and $remoteResp.RawContentStream) {
        $remoteBytes = $remoteResp.RawContentStream.ToArray()
        if ($remoteBytes.Length -gt 10000) {
            [System.IO.File]::WriteAllBytes($agentPath, $remoteBytes)
        }
    }
} catch {
    # Em caso de instabilidade ou offline, continua com a versao local
}

$params = @{}
if ($DebugMode) { $params["DebugMode"] = $true }
if ($ProductionTest) { $params["ProductionTest"] = $true }
& $agentPath @params
exit $LASTEXITCODE
