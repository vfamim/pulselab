#Requires -Version 5.1
# PulseLab - Launcher com Atualizacao Automatica (GitHub / Nuvem)
[CmdletBinding()]
param([switch]$DebugMode)

$ErrorActionPreference = "Stop"

try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch {}

$scriptRoot = $PSScriptRoot
$bridge = Join-Path $scriptRoot "bridge\pulselab-bridge.ps1"
$app = Join-Path $scriptRoot "app\alunos"
if (-not (Test-Path -LiteralPath $app)) { $app = Join-Path $scriptRoot "alunos" }

if (-not (Test-Path -LiteralPath $bridge) -or -not (Test-Path -LiteralPath (Join-Path $app "index.html"))) {
    throw "Pacote incompleto. Extraia todo o ZIP antes de iniciar."
}

# --- FUNCAO DE COMPARACAO DE VERSAO ---
function Compare-SemVer {
    param([string]$V1, [string]$V2)
    $clean1 = ($V1 -replace '[^0-9\.]', '').Trim('.')
    $clean2 = ($V2 -replace '[^0-9\.]', '').Trim('.')
    try {
        $parsed1 = [System.Version]::Parse($clean1)
        $parsed2 = [System.Version]::Parse($clean2)
        if ($parsed1 -gt $parsed2) { return 1 }
        if ($parsed1 -lt $parsed2) { return -1 }
        return 0
    } catch {
        if ($clean1 -ne $clean2) { return 1 }
        return 0
    }
}

# --- ROTINA DE ATUALIZACAO AUTOMATICA VIA GITHUB ---
function Check-PulseLabUpdate {
    param(
        [string]$CurrentVersion = "2.0.1",
        [string]$InstallDir = $scriptRoot
    )

    $versionEndpoints = @(
        "https://raw.githubusercontent.com/vfamim/pulselab/main/VERSION",
        "https://raw.githubusercontent.com/vfamim/pulselab/test/research-protocol-v2/VERSION",
        "https://pulselab-robotica-edu.web.app/VERSION"
    )

    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    } catch {}

    $remoteVer = $null
    foreach ($endpoint in $versionEndpoints) {
        try {
            $req = [System.Net.WebRequest]::Create($endpoint)
            $req.Timeout = 2500
            $req.Method = "GET"
            $resp = $req.GetResponse()
            $stream = $resp.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($stream)
            $content = ($reader.ReadToEnd()).Trim()
            $reader.Close()
            $resp.Close()
            if ($content -and $content.Length -lt 20) {
                $remoteVer = $content
                break
            }
        } catch {}
    }

    if (-not $remoteVer) { return }

    $cmp = Compare-SemVer -V1 $remoteVer -V2 $CurrentVersion
    if ($cmp -gt 0) {
        Write-Host ""
        Write-Host "====================================================================" -ForegroundColor Magenta
        Write-Host "  [ATUALIZACAO] Nova versao v$remoteVer disponivel! Atualizando..." -ForegroundColor Magenta
        Write-Host "====================================================================" -ForegroundColor Magenta

        $zipCandidates = @(
            "https://raw.githubusercontent.com/vfamim/pulselab/main/instalador/downloads/PulseLab-$remoteVer-Windows.zip",
            "https://github.com/vfamim/pulselab/releases/download/v$remoteVer/PulseLab-$remoteVer-Windows.zip",
            "https://raw.githubusercontent.com/vfamim/pulselab/main/instalador/downloads/PulseLab-Alunos-Offline-v$remoteVer.zip",
            "https://pulselab-robotica-edu.web.app/instalador/downloads/PulseLab-Alunos-Offline-v$remoteVer.zip"
        )

        $tempZip = Join-Path $env:TEMP "PulseLab-Update-$remoteVer.zip"
        $tempExtract = Join-Path $env:TEMP "PulseLab-Update-$remoteVer"

        $downloaded = $false
        $wc = New-Object System.Net.WebClient
        foreach ($zipUrl in $zipCandidates) {
            try {
                if (Test-Path -LiteralPath $tempZip) { Remove-Item -LiteralPath $tempZip -Force -ErrorAction SilentlyContinue }
                $wc.DownloadFile($zipUrl, $tempZip)
                if ((Test-Path -LiteralPath $tempZip) -and ((Get-Item -LiteralPath $tempZip).Length -gt 50000)) {
                    $downloaded = $true
                    break
                }
            } catch {}
        }

        if ($downloaded -and (Test-Path -LiteralPath $tempZip)) {
            try {
                if (Test-Path -LiteralPath $tempExtract) { Remove-Item -Recurse -Force $tempExtract -ErrorAction SilentlyContinue }
                Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
                [System.IO.Compression.ZipFile]::ExtractToDirectory($tempZip, $tempExtract)

                $sourceRoot = $tempExtract
                $subDirs = Get-ChildItem -LiteralPath $tempExtract -Directory
                if ($subDirs.Count -eq 1 -and (Test-Path -LiteralPath (Join-Path $subDirs[0].FullName "pulselab.ps1"))) {
                    $sourceRoot = $subDirs[0].FullName
                }

                $itemsToUpdate = @("alunos", "app", "bridge", "config", "tools", "VERSION", "pulselab.ps1", "Iniciar-PulseLab.bat")
                foreach ($item in $itemsToUpdate) {
                    $srcItem = Join-Path $sourceRoot $item
                    $dstItem = Join-Path $InstallDir $item
                    if (Test-Path -LiteralPath $srcItem) {
                        if (Test-Path -LiteralPath $srcItem -PathType Container) {
                            if (-not (Test-Path -LiteralPath $dstItem)) { New-Item -ItemType Directory -Path $dstItem -Force | Out-Null }
                            Copy-Item -Path "$srcItem\*" -Destination $dstItem -Recurse -Force -ErrorAction SilentlyContinue
                        } else {
                            Copy-Item -LiteralPath $srcItem -Destination $dstItem -Force -ErrorAction SilentlyContinue
                        }
                    }
                }

                Write-Host "  [OK] PulseLab atualizado com sucesso para a versao v$remoteVer!" -ForegroundColor Green
                Write-Host "====================================================================" -ForegroundColor Green
                Write-Host ""
            } catch {
                Write-Host "  [AVISO] Falha ao descompactar atualizacao. Continuando com versao local..." -ForegroundColor Yellow
            } finally {
                Remove-Item -Force -LiteralPath $tempZip -ErrorAction SilentlyContinue
                Remove-Item -Recurse -Force -LiteralPath $tempExtract -ErrorAction SilentlyContinue
            }
        }
    }
}

# --- VERIFICA VERSAO LOCAL E EXECUTA CHECAGEM DE UPDATE ---
$localVersion = "2.0.1"
$verFile = Join-Path $scriptRoot "VERSION"
if (Test-Path -LiteralPath $verFile) {
    try { $localVersion = (Get-Content $verFile -Raw).Trim() } catch {}
}

# Auto-update silencioso e resiliente
try {
    Check-PulseLabUpdate -CurrentVersion $localVersion -InstallDir $scriptRoot
} catch {}

# Recarrega a versao local atualizada
if (Test-Path -LiteralPath $verFile) {
    try { $localVersion = (Get-Content $verFile -Raw).Trim() } catch {}
}

Write-Host "===================================================================="
Write-Host "           PULSELAB $localVersion - OFICINA DE ROBOTICA"
Write-Host "===================================================================="

# --- INICIALIZACAO DO SERVIDOR LOCAL (BRIDGE) ---
$running = $null
try { $running = Invoke-RestMethod -Uri "http://127.0.0.1:43128/health" -TimeoutSec 1 } catch {}

if (-not $running) {
    Start-Process powershell.exe -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", ('"' + $bridge + '"'), "-AppRoot", ('"' + $app + '"'))
    $ready = $false
    for ($i = 0; $i -lt 20; $i++) {
        try {
            $health = Invoke-RestMethod -Uri "http://127.0.0.1:43128/health" -TimeoutSec 1
            if ($health) { $ready = $true; break }
        } catch {}
        Start-Sleep -Milliseconds 250
    }
    if (-not $ready) { throw "Servidor local nao iniciou. Confira a janela do PowerShell." }
}

Write-Host "[OK] Servidor ativo em http://127.0.0.1:43128/alunos/"
Start-Process "http://127.0.0.1:43128/alunos/"
