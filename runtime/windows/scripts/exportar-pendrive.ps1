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

# Uma copia que falha (pendrive cheio ou removido) nao para o script, mas marca a exportacao como
# incompleta: sem a marca, a retencao do bridge nao apaga nada achando que ja saiu do computador.
$script:ExportFailed = $false
function Copy-ExportFile([string]$Source, [string]$Destination) {
    try {
        Copy-Item -LiteralPath $Source -Destination $Destination -Force -ErrorAction Stop
        return $true
    } catch {
        $script:ExportFailed = $true
        Write-Host "      [ERRO] Nao foi possivel copiar $(Split-Path -Leaf $Source): $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

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
# Inicio da exportacao, antes de listar os arquivos: sessao criada ou regravada depois disso nao conta
# como exportada (a marca e gravada no fim, em dados_locais).
$exportStartedUtc = [DateTime]::UtcNow
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

# Tombstones de retirada: o importador descarta eventos e snapshots dessas sessoes.
$withdrawnFile = Join-Path $dataDir "sessions_withdrawn.txt"
$totalWithdrawn = 0
if (Test-Path -LiteralPath $withdrawnFile) {
    $totalWithdrawn = @(Get-Content -LiteralPath $withdrawnFile -ErrorAction SilentlyContinue | Where-Object { $_.Trim() }).Count
}

# Aulas marcadas como nao autorizadas ("Nao registrar esta turma"): session_id<TAB>marked_at por linha.
# O importador guarda a marca; essas aulas nunca entram em analise e sao apagadas na revisao do pesquisador.
$unauthorizedFile = Join-Path $dataDir "sessions_unauthorized.txt"
$totalUnauthorized = 0
if (Test-Path -LiteralPath $unauthorizedFile) {
    $totalUnauthorized = @(Get-Content -LiteralPath $unauthorizedFile -ErrorAction SilentlyContinue | Where-Object { $_.Trim() }).Count
}

Write-Host "      - Sessoes completas: $($sessaoFiles.Count)" -ForegroundColor White
Write-Host "      - Eventos de processo: $totalEvents" -ForegroundColor White
Write-Host "      - Sessoes retiradas: $totalWithdrawn" -ForegroundColor White
Write-Host "      - Aulas nao autorizadas: $totalUnauthorized" -ForegroundColor White

if ($sessaoFiles.Count -eq 0 -and $totalEvents -eq 0 -and $totalWithdrawn -eq 0 -and $totalUnauthorized -eq 0) {
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
# Identifica a maquina pelo rotulo do PulseLab (dados_locais\installation.json), nunca pelo nome do Windows.
# installation.json nao vai para o pendrive: dele saem so o rotulo, o id da instalacao, o polo e a
# chave que assina o manifesto (a chave fica so na memoria deste processo).
$machineName = "PC-SEM-ID"
$installationId = ""
$siteId = ""
$installationHmacKey = ""
$installationFile = Join-Path $dataDir "installation.json"
if (Test-Path -LiteralPath $installationFile) {
    try {
        $installation = Get-Content -LiteralPath $installationFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($installation.machine_label) {
            $machineName = ([string]$installation.machine_label -replace '[^A-Za-z0-9_-]', '-')
        }
        if ($installation.installation_id) { $installationId = [string]$installation.installation_id }
        if ($installation.site_id) { $siteId = ([string]$installation.site_id -replace '[^A-Za-z0-9_-]', '') }
        if ($installation.manifest_hmac_key) { $installationHmacKey = [string]$installation.manifest_hmac_key }
    } catch {}
}
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
    if (Copy-ExportFile $catSource $catDest) { $copiedFiles.Add($catDest) }
    Write-Host "      [OK] catalogo_sessoes.json" -ForegroundColor Green
}

# Eventos
if (Test-Path -LiteralPath $eventsFile) {
    $eventsDest = Join-Path $targetExportDir "events.jsonl"
    if (Copy-ExportFile $eventsFile $eventsDest) { $copiedFiles.Add($eventsDest) }
    Write-Host "      [OK] events.jsonl ($totalEvents registros)" -ForegroundColor Green
}

# Arquivo historico
$archiveFile = Join-Path $dataDir "events_archive.jsonl"
if (Test-Path -LiteralPath $archiveFile) {
    $archiveDest = Join-Path $targetExportDir "events_archive.jsonl"
    if (Copy-ExportFile $archiveFile $archiveDest) { $copiedFiles.Add($archiveDest) }
    Write-Host "      [OK] events_archive.jsonl" -ForegroundColor Green
}

# Sessoes retiradas (somente session_id)
if (Test-Path -LiteralPath $withdrawnFile) {
    $withdrawnDest = Join-Path $targetExportDir "sessions_withdrawn.txt"
    if (Copy-ExportFile $withdrawnFile $withdrawnDest) { $copiedFiles.Add($withdrawnDest) }
    Write-Host "      [OK] sessions_withdrawn.txt ($totalWithdrawn sessoes retiradas)" -ForegroundColor Green
}

# Aulas nao autorizadas (somente session_id e data da marcacao)
if (Test-Path -LiteralPath $unauthorizedFile) {
    $unauthorizedDest = Join-Path $targetExportDir "sessions_unauthorized.txt"
    if (Copy-ExportFile $unauthorizedFile $unauthorizedDest) { $copiedFiles.Add($unauthorizedDest) }
    Write-Host "      [OK] sessions_unauthorized.txt ($totalUnauthorized aulas nao autorizadas)" -ForegroundColor Green
}

# Sessoes individuais
$sessCount = 0
foreach ($sFile in $sessaoFiles) {
    $sDest = Join-Path $targetSessoesDir $sFile.Name
    if (Copy-ExportFile $sFile.FullName $sDest) { $copiedFiles.Add($sDest) }
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
[void]$manifestContent.AppendLine("Maquina (rotulo)      : $machineName")
[void]$manifestContent.AppendLine("Instalacao            : $installationId")
[void]$manifestContent.AppendLine("Polo (site_id)        : $siteId")
[void]$manifestContent.AppendLine("Total de Sessoes      : $sessCount")
[void]$manifestContent.AppendLine("Total de Eventos      : $totalEvents")
[void]$manifestContent.AppendLine("Sessoes Retiradas     : $totalWithdrawn")
[void]$manifestContent.AppendLine("Aulas Nao Autorizadas : $totalUnauthorized")
[void]$manifestContent.AppendLine("====================================================================")
[void]$manifestContent.AppendLine("INTEGRIDADE DOS ARQUIVOS (SHA-256):")
[void]$manifestContent.AppendLine("")

$sha = [System.Security.Cryptography.SHA256]::Create()
$targetNormalized = (Resolve-Path $targetExportDir).Path.TrimEnd('\', '/')
foreach ($fPath in $copiedFiles) {
    try {
        $bytes = [System.IO.File]::ReadAllBytes($fPath)
        $hashBytes = $sha.ComputeHash($bytes)
        $hashStr = [BitConverter]::ToString($hashBytes) -replace '-'
        $fullNormalized = (Resolve-Path $fPath).Path
        if ($fullNormalized.StartsWith($targetNormalized, [System.StringComparison]::OrdinalIgnoreCase)) {
            $relPath = $fullNormalized.Substring($targetNormalized.Length).TrimStart('\', '/').Replace('\', '/')
        } else {
            $relPath = Split-Path $fPath -Leaf
        }
        [void]$manifestContent.AppendLine("$hashStr  $relPath")
    } catch {}
}
$sha.Dispose()

[System.IO.File]::WriteAllText($manifestFile, $manifestContent.ToString(), [System.Text.Encoding]::UTF8)
Write-Host "      [OK] manifesto_coleta.txt (hashes SHA-256 gerados)" -ForegroundColor Green

# 7. Assinatura HMAC-SHA256 do manifesto: a variavel de ambiente tem prioridade; sem ela, usa a chave
#    do polo gravada pelo pacote do polo em installation.json. A chave nunca e copiada para o pendrive.
$manifestHmacKey = $env:PULSELAB_MANIFEST_HMAC_KEY
if ([string]::IsNullOrWhiteSpace($manifestHmacKey)) { $manifestHmacKey = $installationHmacKey }
if (-not [string]::IsNullOrWhiteSpace($manifestHmacKey)) {
    try {
        $sigFile = Join-Path $targetExportDir "manifesto_coleta.sig"
        $manifestBytes = [System.IO.File]::ReadAllBytes($manifestFile)
        $keyBytes = [System.Text.Encoding]::UTF8.GetBytes($manifestHmacKey)
        $hmac = [System.Security.Cryptography.HMACSHA256]::new($keyBytes)
        $sigBytes = $hmac.ComputeHash($manifestBytes)
        $sigHex = ([BitConverter]::ToString($sigBytes) -replace '-').ToLowerInvariant()
        $hmac.Dispose()
        # Sem BOM: o importador compara os 64 caracteres hexadecimais.
        [System.IO.File]::WriteAllText($sigFile, $sigHex, (New-Object System.Text.UTF8Encoding($false)))
        Write-Host "      [OK] manifesto_coleta.sig (assinatura HMAC-SHA256 institucional gerada)" -ForegroundColor Green
    } catch {
        Write-Host "      [AVISO] Falha ao assinar manifesto com HMAC-SHA256: $($_.Exception.Message)" -ForegroundColor Yellow
    }
} else {
    Write-Host "      [AVISO] Manifesto sem assinatura: este computador nao tem a chave do polo." -ForegroundColor Yellow
    Write-Host "              Reinstale com o pacote do polo para que a coleta possa ir para a nuvem." -ForegroundColor Yellow
}

# A retencao do bridge so apaga, depois de retention_days, aulas que ja sairam do computador (nuvem ou
# pendrive). A copia na Area de Trabalho nao conta: os dados continuam so neste computador.
if ($script:ExportFailed) {
    Write-Host ""
    Write-Host "[ERRO] Exportacao incompleta: confira o espaco do pendrive e exporte de novo." -ForegroundColor Red
    Write-Host "       Os dados continuam guardados neste computador." -ForegroundColor Yellow
    if (-not $SaveToDesktop) {
        Write-Host "Pressione Enter para sair..."
        [void][Console]::ReadLine()
    }
    exit 1
}
if (-not $SaveToDesktop -and $destDrive) {
    try {
        $exportMark = '{"exported_at":"' + $exportStartedUtc.ToString("yyyy-MM-ddTHH:mm:ss.fffZ") + '"}'
        [System.IO.File]::WriteAllText((Join-Path $dataDir "ultima_exportacao_pendrive.json"), $exportMark, (New-Object System.Text.UTF8Encoding($false)))
    } catch {
        Write-Host "      [AVISO] Nao foi possivel registrar a exportacao: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "====================================================================" -ForegroundColor Green
Write-Host "  EXPORTACAO CONCLUIDA COM SUCESSO!" -ForegroundColor Green
Write-Host "====================================================================" -ForegroundColor Green
Write-Host " Pasta: $targetExportDir" -ForegroundColor White
Write-Host " Arquivos exportados com seguranca." -ForegroundColor White
Write-Host " Entregue o pendrive a coordenacao do projeto. O pesquisador envia" -ForegroundColor Cyan
Write-Host " os dados ao banco central pelo computador dele." -ForegroundColor Cyan
Write-Host "====================================================================" -ForegroundColor Green
Write-Host ""
if (-not $SaveToDesktop) {
    Write-Host "Pressione Enter para finalizar..."
    [void][Console]::ReadLine()
}
