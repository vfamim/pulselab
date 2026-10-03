#Requires -Version 5.1
# ==============================================================================
# PulseLab - Exportador de Dados Locais para Pendrive USB (Modo Offline)
# ==============================================================================

[CmdletBinding()]
param(
    [string]$TargetDrive = "",
    [switch]$SaveToDesktop
)

$ErrorActionPreference = "Continue"

try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch {}

Write-Host ""
Write-Host "====================================================================" -ForegroundColor Cyan
Write-Host "       PULSELAB - EXPORTADOR DE DADOS DA OFICINA (OFFLINE)" -ForegroundColor Cyan
Write-Host "====================================================================" -ForegroundColor Cyan
Write-Host ""

# 1. Localizar pasta dados_locais
$appRoot = Split-Path $PSScriptRoot -Parent
$candidateDataDirs = @(
    (Join-Path $appRoot "dados_locais"),
    (Join-Path $PSScriptRoot "..\dados_locais"),
    (Join-Path $env:LOCALAPPDATA "PulseLab\dados_locais")
)

$dataDir = $null
foreach ($cand in $candidateDataDirs) {
    if (Test-Path -LiteralPath $cand) {
        $dataDir = (Resolve-Path $cand).Path
        break
    }
}

if (-not $dataDir -or -not (Test-Path -LiteralPath $dataDir)) {
    Write-Host "[ERRO] Pasta de dados locais nao encontrada." -ForegroundColor Red
    Write-Host "Nenhuma oficina parece ter sido realizada neste computador ainda." -ForegroundColor Yellow
    Write-Host ""
    if (-not $SaveToDesktop) {
        Write-Host "Pressione Enter para sair..."
        [void][Console]::ReadLine()
    }
    exit 1
}

Write-Host "[1/4] Base local localizada em: $dataDir" -ForegroundColor Green

# 2. Contabilizar sessoes e eventos
$sessoesDir = Join-Path $dataDir "sessoes"
$sessaoFiles = @()
if (Test-Path -LiteralPath $sessoesDir) {
    $sessaoFiles = @(Get-ChildItem -LiteralPath $sessoesDir -Filter "*.json" -File -ErrorAction SilentlyContinue)
}

$eventsFile = Join-Path $dataDir "events.jsonl"
$totalEvents = 0
if (Test-Path -LiteralPath $eventsFile) {
    $totalEvents = (Get-Content -LiteralPath $eventsFile -ErrorAction SilentlyContinue | Measure-Object).Count
}

Write-Host "      - Sessoes completas: $($sessaoFiles.Count)" -ForegroundColor White
Write-Host "      - Eventos de processo: $totalEvents" -ForegroundColor White

if ($sessaoFiles.Count -eq 0 -and $totalEvents -eq 0) {
    Write-Host ""
    Write-Host "[AVISO] Nao ha dados de oficina gravados nesta maquina ainda." -ForegroundColor Yellow
    if (-not $SaveToDesktop) {
        Write-Host "Pressione Enter para sair..."
        [void][Console]::ReadLine()
    }
    exit 0
}

# 3. Detectar pendrive USB
$destDrive = $TargetDrive

if (-not $destDrive -and -not $SaveToDesktop) {
    Write-Host ""
    Write-Host "[2/4] Detectando pendrives USB conectados..." -ForegroundColor Cyan

    $removableDrives = @()
    try {
        $removableDrives = @(Get-CimInstance Win32_LogicalDisk -Filter "DriveType = 2" -ErrorAction SilentlyContinue)
    } catch {
        try {
            $removableDrives = @(Get-WmiObject Win32_LogicalDisk -Filter "DriveType = 2" -ErrorAction SilentlyContinue)
        } catch {}
    }

    if ($removableDrives.Count -eq 0) {
        Write-Host ""
        Write-Host "--------------------------------------------------------------------" -ForegroundColor Yellow
        Write-Host " [!] Nenhum pendrive USB foi detectado automaticamente." -ForegroundColor Yellow
        Write-Host "--------------------------------------------------------------------" -ForegroundColor Yellow
        Write-Host " 1. Conecte o pendrive na porta USB do computador agora."
        Write-Host " 2. Aguarde 3 segundos."
        Write-Host ""
        Write-Host "Deseja tentar detectar novamente? (S/N) ou (D) para salvar na Area de Trabalho:" -ForegroundColor Yellow
        $resp = Read-Host "Opcao [S/N/D]"
        if ($resp -match "^[dD]") {
            $SaveToDesktop = $true
        } else {
            Start-Sleep -Seconds 2
            try {
                $removableDrives = @(Get-CimInstance Win32_LogicalDisk -Filter "DriveType = 2" -ErrorAction SilentlyContinue)
            } catch {
                try {
                    $removableDrives = @(Get-WmiObject Win32_LogicalDisk -Filter "DriveType = 2" -ErrorAction SilentlyContinue)
                } catch {}
            }
        }
    }

    if (-not $SaveToDesktop) {
        if ($removableDrives.Count -gt 0) {
            $selectedDrive = $removableDrives[0]
            $destDrive = $selectedDrive.DeviceID
            Write-Host "      [OK] Pendrive selecionado: $destDrive" -ForegroundColor Green
        } else {
            Write-Host "[AVISO] Salvando na Area de Trabalho como alternativa segura..." -ForegroundColor Yellow
            $SaveToDesktop = $true
        }
    }
}

# 4. Definir pasta destino
$machineName = if ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { "PC-LAB" }
$timeTag = Get-Date -Format "yyyyMMdd_HHmmss"
$exportFolderName = "Coleta_${machineName}_${timeTag}"

$targetExportDir = $null
if ($SaveToDesktop -or -not $destDrive) {
    $desktopPath = [Environment]::GetFolderPath("Desktop")
    $targetExportDir = Join-Path (Join-Path $desktopPath "Coleta-PulseLab") $exportFolderName
} else {
    $targetExportDir = Join-Path (Join-Path ($destDrive + "\") "Coleta-PulseLab") $exportFolderName
}

Write-Host ""
Write-Host "[3/4] Criando pasta de destino: $targetExportDir" -ForegroundColor Cyan
New-Item -ItemType Directory -Path $targetExportDir -Force | Out-Null

$targetSessoesDir = Join-Path $targetExportDir "sessoes"
New-Item -ItemType Directory -Path $targetSessoesDir -Force | Out-Null

# 5. Copiar arquivos
Write-Host "[4/4] Copiando arquivos..." -ForegroundColor Cyan

$copiedFiles = [System.Collections.Generic.List[string]]::new()

# Catalogo
$catSource = Join-Path $dataDir "catalogo_sessoes.json"
if (Test-Path -LiteralPath $catSource) {
    $catDest = Join-Path $targetExportDir "catalogo_sessoes.json"
    Copy-Item -LiteralPath $catSource -Destination $catDest -Force
    $copiedFiles.Add($catDest)
    Write-Host "      [OK] catalogo_sessoes.json" -ForegroundColor Green
}

# Eventos
if (Test-Path -LiteralPath $eventsFile) {
    $eventsDest = Join-Path $targetExportDir "events.jsonl"
    Copy-Item -LiteralPath $eventsFile -Destination $eventsDest -Force
    $copiedFiles.Add($eventsDest)
    Write-Host "      [OK] events.jsonl ($totalEvents registros)" -ForegroundColor Green
}

# Arquivo historico
$archiveFile = Join-Path $dataDir "events_archive.jsonl"
if (Test-Path -LiteralPath $archiveFile) {
    $archiveDest = Join-Path $targetExportDir "events_archive.jsonl"
    Copy-Item -LiteralPath $archiveFile -Destination $archiveDest -Force
    $copiedFiles.Add($archiveDest)
    Write-Host "      [OK] events_archive.jsonl" -ForegroundColor Green
}

# Sessoes individuais
$sessCount = 0
foreach ($sFile in $sessaoFiles) {
    $sDest = Join-Path $targetSessoesDir $sFile.Name
    Copy-Item -LiteralPath $sFile.FullName -Destination $sDest -Force
    $copiedFiles.Add($sDest)
    $sessCount++
}
Write-Host "      [OK] $sessCount arquivo(s) de sessao em sessoes/" -ForegroundColor Green

# 6. Gerar manifesto com hash SHA-256 para auditoria de integridade
$manifestFile = Join-Path $targetExportDir "manifesto_coleta.txt"
$manifestContent = [System.Text.StringBuilder]::new()
[void]$manifestContent.AppendLine("====================================================================")
[void]$manifestContent.AppendLine("PULSELAB - MANIFESTO DE COLETA DE DADOS EM CAMPO (OFFLINE)")
[void]$manifestContent.AppendLine("====================================================================")
[void]$manifestContent.AppendLine("Data e Hora da Coleta : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
[void]$manifestContent.AppendLine("Computador Origem     : $machineName")
[void]$manifestContent.AppendLine("Usuario Windows       : $env:USERNAME")
[void]$manifestContent.AppendLine("Origem dos Dados      : $dataDir")
[void]$manifestContent.AppendLine("Total de Sessoes      : $sessCount")
[void]$manifestContent.AppendLine("Total de Eventos      : $totalEvents")
[void]$manifestContent.AppendLine("====================================================================")
[void]$manifestContent.AppendLine("INTEGRIDADE DOS ARQUIVOS (SHA-256):")
[void]$manifestContent.AppendLine("")

$sha = [System.Security.Cryptography.SHA256]::Create()
foreach ($fPath in $copiedFiles) {
    try {
        $bytes = [System.IO.File]::ReadAllBytes($fPath)
        $hashBytes = $sha.ComputeHash($bytes)
        $hashStr = [BitConverter]::ToString($hashBytes) -replace '-'
        $fName = Split-Path $fPath -Leaf
        [void]$manifestContent.AppendLine("$hashStr  $fName")
    } catch {}
}
$sha.Dispose()

[System.IO.File]::WriteAllText($manifestFile, $manifestContent.ToString(), [System.Text.Encoding]::UTF8)
Write-Host "      [OK] manifesto_coleta.txt (hashes SHA-256 gerados)" -ForegroundColor Green

Write-Host ""
Write-Host "====================================================================" -ForegroundColor Green
Write-Host "  EXPORTACAO CONCLUIDA COM SUCESSO!" -ForegroundColor Green
Write-Host "====================================================================" -ForegroundColor Green
Write-Host " Pasta: $targetExportDir" -ForegroundColor White
Write-Host " Arquivos exportados com seguranca." -ForegroundColor White
Write-Host " Quando tiver acesso a internet, execute Importar-Para-Supabase.bat" -ForegroundColor Cyan
Write-Host " no computador do pesquisador para sincronizar com o banco central." -ForegroundColor Cyan
Write-Host "====================================================================" -ForegroundColor Green
Write-Host ""
if (-not $SaveToDesktop) {
    Write-Host "Pressione Enter para finalizar..."
    [void][Console]::ReadLine()
}
