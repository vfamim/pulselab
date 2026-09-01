#Requires -Version 5.1
# PulseLab 1.6.0 - authenticated agent launcher and auto-updater

[CmdletBinding()]
param(
    [switch]$DebugMode,
    [switch]$ProductionTest,
    [switch]$DevMode,
    [switch]$NoUpdate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = $PSScriptRoot
$agentPath = Join-Path $scriptRoot "agent\pulselab-agent.ps1"
$configPath = Join-Path $scriptRoot "config\config.json"

if (-not (Test-Path -LiteralPath $agentPath -PathType Leaf)) {
    throw "PulseLab agent script not found: $agentPath"
}

# Rotina de auto-atualizacao segura e atomica com validacao de integridade (SHA-256)
if (-not $NoUpdate -and -not $DevMode) {
    try {
        $remoteAgentUrl = "https://raw.githubusercontent.com/vfamim/pulselab/main/agent/pulselab-agent.ps1"
        if (Test-Path -LiteralPath $configPath -PathType Leaf) {
            try {
                $cfgJson = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($cfgJson.config_remote_url) {
                    if ($cfgJson.config_remote_url -match '^(https://raw\.githubusercontent\.com/[^/]+/[^/]+/[^/]+)/') {
                        $remoteAgentUrl = "$($Matches[1])/agent/pulselab-agent.ps1"
                    }
                }
            } catch {
                # Se falhar o parse da config, usa a URL remota padrao
            }
        }

        # Timeout curto (3 segundos) para nunca atrasar a inicializacao da oficina em caso de lentidao/offline
        $response = Invoke-WebRequest -Uri $remoteAgentUrl -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
        if ($response -and $response.RawContentStream) {
            $remoteBytes = $response.RawContentStream.ToArray()
            # Validacao estrita: tamanho razoavel (> 20KB) e cabecalho esperado do script do agente
            if ($remoteBytes.Length -gt 20000) {
                $contentStart = [System.Text.Encoding]::UTF8.GetString($remoteBytes, 0, [Math]::Min($remoteBytes.Length, 500))
                if ($contentStart -match '#Requires\s+-Version' -or $contentStart -match 'pulselab-agent') {
                    $sha256 = [System.Security.Cryptography.SHA256]::Create()
                    $remoteHash = [BitConverter]::ToString($sha256.ComputeHash($remoteBytes)).Replace("-", "").ToLowerInvariant()
                    $localHash = (Get-FileHash -LiteralPath $agentPath -Algorithm SHA256).Hash.ToLowerInvariant()

                    if ($remoteHash -ne $localHash) {
                        $stagePath = "$agentPath.stage-$([Guid]::NewGuid().ToString('N')).tmp"
                        $backupPath = "$agentPath.backup"
                        try {
                            [System.IO.File]::WriteAllBytes($stagePath, $remoteBytes)
                            if (Test-Path -LiteralPath $backupPath) {
                                Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
                            }
                            if (Test-Path -LiteralPath $agentPath) {
                                Move-Item -LiteralPath $agentPath -Destination $backupPath -Force
                            }
                            Move-Item -LiteralPath $stagePath -Destination $agentPath -Force
                            Write-Host "[PulseLab] Agente atualizado com sucesso (SHA-256: $remoteHash)." -ForegroundColor Green
                        } catch {
                            # Em caso de falha durante a troca, restaura o backup
                            if (-not (Test-Path -LiteralPath $agentPath) -and (Test-Path -LiteralPath $backupPath)) {
                                Move-Item -LiteralPath $backupPath -Destination $agentPath -Force
                            }
                        } finally {
                            if (Test-Path -LiteralPath $stagePath) {
                                Remove-Item -LiteralPath $stagePath -Force -ErrorAction SilentlyContinue
                            }
                        }
                    }
                }
            }
        }
    } catch {
        # Fallback offline transparente: em caso de erro de rede ou timeout, executa a versao local existente
    }
}

$params = @{}
if ($DebugMode) { $params["DebugMode"] = $true }
if ($ProductionTest) { $params["ProductionTest"] = $true }
& $agentPath @params
exit $LASTEXITCODE
