#Requires -Version 5.1
# PulseLab 1.8.0 - Web-First Bridge & Student WebApp Launcher

[CmdletBinding()]
param(
    [int]$Port = 43127,
    [string]$AppRoot = "",
    [string]$DataDir = "",
    [switch]$NoBrowser,
    [switch]$Hidden,
    [switch]$LabMode,
    [switch]$DebugMode,
    [switch]$ProductionTest,
    [switch]$QuickTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = $PSScriptRoot
$bridgeScript = Join-Path $scriptRoot "bridge\pulselab-bridge.ps1"
if (-not (Test-Path -LiteralPath $bridgeScript -PathType Leaf)) {
    $altBridge = Join-Path $env:LOCALAPPDATA "PulseLab\bridge\pulselab-bridge.ps1"
    if (Test-Path -LiteralPath $altBridge -PathType Leaf) {
        $bridgeScript = $altBridge
        $scriptRoot = Join-Path $env:LOCALAPPDATA "PulseLab"
    } else {
        throw "PulseLab bridge script not found: $bridgeScript"
    }
}

if ([string]::IsNullOrWhiteSpace($AppRoot)) {
    $candidates = @(
        (Join-Path $scriptRoot "app\alunos"),
        (Join-Path $scriptRoot "alunos"),
        (Join-Path $env:LOCALAPPDATA "PulseLab\app\alunos")
    )
    foreach ($cand in $candidates) {
        if (Test-Path -LiteralPath (Join-Path $cand "index.html") -PathType Leaf) {
            $AppRoot = $cand
            break
        }
    }
}

if ([string]::IsNullOrWhiteSpace($DataDir)) {
    $DataDir = Join-Path $env:LOCALAPPDATA "PulseLab\data"
}

function Check-PulseLabUpdate {
    param(
        [string]$CurrentVersion = "1.8.0",
        [string]$InstallDir = (Join-Path $env:LOCALAPPDATA "PulseLab")
    )
    
    $versionEndpoint = "https://pulselab-robotica-edu.web.app/VERSION"
    
    try {
        $req = [System.Net.WebRequest]::Create($versionEndpoint)
        $req.Timeout = 2000
        $req.Method = "GET"
        $resp = $req.GetResponse()
        $stream = $resp.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($stream)
        $remoteVer = ($reader.ReadToEnd()).Trim()
        $reader.Close()
        $resp.Close()
        
        if (-not $remoteVer) { return }
        
        $isNewer = $false
        try {
            $vRemote = [System.Version]::Parse($remoteVer)
            $vLocal = [System.Version]::Parse($CurrentVersion)
            if ($vRemote -gt $vLocal) { $isNewer = $true }
        } catch {
            if ($remoteVer -ne $CurrentVersion) { $isNewer = $true }
        }
        
        if ($isNewer) {
            Write-Host "[UPDATE] Nova versao v$remoteVer detectada na nuvem! Atualizando..." -ForegroundColor Magenta
            
            $zipUrl = "https://pulselab-robotica-edu.web.app/instalador/downloads/PulseLab-Alunos-Offline-v$remoteVer.zip"
            $tempZip = Join-Path $env:TEMP "PulseLab-Update-$remoteVer.zip"
            $tempExtract = Join-Path $env:TEMP "PulseLab-Update-$remoteVer"
            
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
            $wc = New-Object System.Net.WebClient
            $wc.DownloadFile($zipUrl, $tempZip)
            
            if (Test-Path $tempZip) {
                if (Test-Path $tempExtract) { Remove-Item -Recurse -Force $tempExtract -ErrorAction SilentlyContinue }
                Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
                [System.IO.Compression.ZipFile]::ExtractToDirectory($tempZip, $tempExtract)
                
                $sourceRoot = $tempExtract
                $inner = Join-Path $tempExtract "PulseLab-$remoteVer-Windows"
                if (Test-Path $inner) { $sourceRoot = $inner }
                
                $itemsToUpdate = @("app", "bridge", "config", "tools", "VERSION", "VERSION.txt", "pulselab.ps1", "Iniciar-PulseLab.bat")
                foreach ($item in $itemsToUpdate) {
                    $srcItem = Join-Path $sourceRoot $item
                    $dstItem = Join-Path $InstallDir $item
                    if (Test-Path $srcItem) {
                        if (Test-Path $dstItem -PathType Container) {
                            Copy-Item -Path "$srcItem\*" -Destination $dstItem -Recurse -Force -ErrorAction SilentlyContinue
                        } else {
                            Copy-Item -Path $srcItem -Destination $dstItem -Force -ErrorAction SilentlyContinue
                        }
                    }
                }
                
                Remove-Item -Force $tempZip -ErrorAction SilentlyContinue
                Remove-Item -Recurse -Force $tempExtract -ErrorAction SilentlyContinue
                
                Write-Host "[UPDATE] PulseLab atualizado com sucesso para v$remoteVer!" -ForegroundColor Green
            }
        }
    } catch {
        # Modo silencioso se offline
    }
}

$localVersion = "1.8.0"
$verFile = Join-Path $scriptRoot "VERSION"
if (Test-Path $verFile) {
    try { $localVersion = (Get-Content $verFile -Raw).Trim() } catch {}
}
Check-PulseLabUpdate -CurrentVersion $localVersion -InstallDir $scriptRoot

Write-Host "===================================================================="
Write-Host "               PULSELAB $localVersion - OFICINA DE ROBOTICA"
Write-Host "===================================================================="
Write-Host "Iniciando servidor local do PulseLab na porta $Port..."

# Verificar se o Bridge ja esta rodando
$alreadyRunning = $false
try {
    $resp = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/health" -UseBasicParsing -TimeoutSec 1 -ErrorAction SilentlyContinue
    if ($resp -and $resp.StatusCode -eq 200) { $alreadyRunning = $true }
} catch {}

if (-not $alreadyRunning) {
    $argList = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-WindowStyle", "Hidden",
        "-File", $bridgeScript,
        "-Port", [string]$Port,
        "-AppRoot", $AppRoot,
        "-DataDir", $DataDir
    )
    Start-Process -FilePath "powershell.exe" -ArgumentList $argList
    
    # Aguardar brevemente ate o servidor responder
    for ($i = 0; $i -lt 10; $i++) {
        Start-Sleep -Milliseconds 300
        try {
            $resp = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/health" -UseBasicParsing -TimeoutSec 1 -ErrorAction SilentlyContinue
            if ($resp -and $resp.StatusCode -eq 200) { break }
        } catch {}
    }
}

if (-not $NoBrowser) {
    $targetUrl = "http://127.0.0.1:$Port/alunos/"
    if ($LabMode -or $DebugMode -or $ProductionTest -or $QuickTest) {
        $targetUrl = "http://127.0.0.1:$Port/alunos/?lab=1"
    }
    Write-Host "Abrindo interface dos alunos no navegador padrao ($targetUrl)..."
    Start-Process $targetUrl
}

Write-Host "[OK] PulseLab ativo em http://127.0.0.1:$Port/alunos/"
Write-Host "Alertas nativos aos 20 e 40 minutos de oficina."
