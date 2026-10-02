#Requires -Version 5.1
# ==============================================================================
# PulseLab - Importador PowerShell de Dados Locais para Supabase (Sem Python)
# ==============================================================================

[CmdletBinding()]
param(
    [string]$SourcePath = "",
    [string]$SupabaseUrl = "",
    [string]$SupabaseKey = ""
)

$ErrorActionPreference = "Continue"

try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch {}

Write-Host ""
Write-Host "====================================================================" -ForegroundColor Cyan
Write-Host "  PULSELAB - IMPORTADOR DE DADOS OFFLINE PARA O BANCO SUPABASE" -ForegroundColor Cyan
Write-Host "====================================================================" -ForegroundColor Cyan
Write-Host ""

$repoRoot = Split-Path $PSScriptRoot -Parent

# 1. Carregar credenciais do Supabase
if (-not $SupabaseUrl -or -not $SupabaseKey) {
    $defaultUrl = "https://cylsqbmtglvdfubbarqe.supabase.co"
    $defaultKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImN5bHNxYm10Z2x2ZGZ1YmJhcnFlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzc5NjE1MzIsImV4cCI6MjA5MzUzNzUzMn0.tscU354WLjnYz6E6NOrDQK16ViWBc-Af5FYhvZikFbU"

    $cfgFile = Join-Path $repoRoot "config\config.json"
    if (Test-Path -LiteralPath $cfgFile) {
        try {
            $cfg = Get-Content -LiteralPath $cfgFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($cfg.supabase_url) { $defaultUrl = $cfg.supabase_url }
            if ($cfg.supabase_anon_key) { $defaultKey = $cfg.supabase_anon_key }
        } catch {}
    }
    if (-not $SupabaseUrl) { $SupabaseUrl = $defaultUrl }
    if (-not $SupabaseKey) { $SupabaseKey = $defaultKey }
}

# 2. Localizar pastas de coleta
$sources = [System.Collections.Generic.List[string]]::new()
if ($SourcePath -and (Test-Path -LiteralPath $SourcePath)) {
    $sources.Add((Resolve-Path $SourcePath).Path)
} else {
    try {
        $drives = @(Get-CimInstance Win32_LogicalDisk -Filter "DriveType = 2" -ErrorAction SilentlyContinue)
        foreach ($d in $drives) {
            $penDir = Join-Path ($d.DeviceID + "\") "Coleta-PulseLab"
            if (Test-Path -LiteralPath $penDir) {
                $sources.Add((Resolve-Path $penDir).Path)
            }
        }
    } catch {}

    $desktopCollect = Join-Path ([Environment]::GetFolderPath("Desktop")) "Coleta-PulseLab"
    if (Test-Path -LiteralPath $desktopCollect) {
        $sources.Add((Resolve-Path $desktopCollect).Path)
    }

    $localData = Join-Path $repoRoot "dados_locais"
    if (Test-Path -LiteralPath $localData) {
        $sources.Add((Resolve-Path $localData).Path)
    }
}

if ($sources.Count -eq 0) {
    Write-Host "[ERRO] Nenhuma pasta de dados de coleta encontrada." -ForegroundColor Red
    Write-Host "Conecte o pendrive com os dados coletados ou forneca o caminho com -SourcePath." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Pressione Enter para sair..."
    [void][Console]::ReadLine()
    exit 1
}

Write-Host "Fontes de dados detectadas:" -ForegroundColor Green
foreach ($s in $sources) {
    Write-Host "  [DIR] $s" -ForegroundColor White
}
Write-Host ""

# 3. Mapear arquivos
$sessionFiles = [System.Collections.Generic.List[string]]::new()
$eventsFiles = [System.Collections.Generic.List[string]]::new()

foreach ($src in $sources) {
    $subDirs = @(Get-ChildItem -LiteralPath $src -Directory -Filter "Coleta_*" -ErrorAction SilentlyContinue)
    $targetDirs = if ($subDirs.Count -gt 0) { $subDirs | ForEach-Object { $_.FullName } } else { @($src) }

    foreach ($td in $targetDirs) {
        $sDir = Join-Path $td "sessoes"
        if (Test-Path -LiteralPath $sDir) {
            Get-ChildItem -LiteralPath $sDir -Filter "*.json" -File -ErrorAction SilentlyContinue | ForEach-Object {
                $sessionFiles.Add($_.FullName)
            }
        } else {
            Get-ChildItem -LiteralPath $td -Filter "sessao_*.json" -File -ErrorAction SilentlyContinue | ForEach-Object {
                $sessionFiles.Add($_.FullName)
            }
        }

        $evF = Join-Path $td "events.jsonl"
        if (Test-Path -LiteralPath $evF) { $eventsFiles.Add($evF) }
        $evArch = Join-Path $td "events_archive.jsonl"
        if (Test-Path -LiteralPath $evArch) { $eventsFiles.Add($evArch) }
    }
}

Write-Host "Arquivos localizados:" -ForegroundColor Cyan
Write-Host "  - Sessoes completas: $($sessionFiles.Count)" -ForegroundColor White
Write-Host "  - Arquivos de eventos: $($eventsFiles.Count)" -ForegroundColor White
Write-Host ""

# 4. Processar sessoes e coletar eventos
$researchEvents = [System.Collections.Generic.Dictionary[string, object]]::new()
$sessionEvents = [System.Collections.Generic.Dictionary[string, object]]::new()

foreach ($ef in $eventsFiles) {
    try {
        $lines = [System.IO.File]::ReadAllLines($ef)
        foreach ($line in $lines) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $ev = $line | ConvertFrom-Json
                $evId = [string]$ev.event_id
                if (-not $evId) { continue }

                if ($ev.event_type -in @("pre", "checkpoint", "post", "rubric")) {
                    $researchEvents[$evId] = $ev
                } else {
                    $sessionEvents[$evId] = $ev
                }
            } catch {}
        }
    } catch {}
}

$sessionCount = 0
foreach ($sf in $sessionFiles) {
    try {
        $raw = Get-Content -LiteralPath $sf -Raw -Encoding UTF8
        $sessObj = $raw | ConvertFrom-Json
        $sessionCount++

        if ($sessObj.events) {
            foreach ($ev in $sessObj.events) {
                $evId = [string]$ev.event_id
                if (-not $evId) { continue }
                if ($ev.event_type -in @("pre", "checkpoint", "post", "rubric")) {
                    $researchEvents[$evId] = $ev
                } else {
                    $sessionEvents[$evId] = $ev
                }
            }
        }
    } catch {}
}

Write-Host "Eventos unicos para sincronizacao:" -ForegroundColor Cyan
Write-Host "  - research_events: $($researchEvents.Count)" -ForegroundColor White
Write-Host "  - research_session_events: $($sessionEvents.Count)" -ForegroundColor White
Write-Host ""

# 5. Enviar ao Supabase
try {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls11 -bor [System.Net.SecurityProtocolType]::Tls
} catch {}

$headers = @{
    apikey = $SupabaseKey
    Authorization = "Bearer $SupabaseKey"
    "Content-Type" = "application/json"
    Prefer = "resolution=ignore-duplicates,return=minimal"
}

function Upload-BatchToSupabase {
    param(
        [string]$Table,
        [System.Collections.Generic.List[object]]$Items,
        [string]$Url,
        [hashtable]$Headers
    )
    if ($Items.Count -eq 0) { return 0 }
    $batchSize = 40
    $totalUploaded = 0
    $endpoint = "$($Url.TrimEnd("/"))/rest/v1/$Table?on_conflict=event_id"

    for ($i = 0; $i -lt $Items.Count; $i += $batchSize) {
        $count = [Math]::Min($batchSize, ($Items.Count - $i))
        $chunk = $Items.GetRange($i, $count)

        $cleanChunk = [System.Collections.Generic.List[object]]::new()
        foreach ($itm in $chunk) {
            $dict = [System.Collections.Specialized.OrderedDictionary]::new()
            foreach ($prop in $itm.PSObject.Properties) {
                if (-not $prop.Name.StartsWith("_") -and $null -ne $prop.Value) {
                    if ($Table -eq "research_events" -and $prop.Name -eq "details") {
                        continue
                    }
                    $dict[$prop.Name] = $prop.Value
                }
            }
            $cleanChunk.Add($dict)
        }

        $jsonBody = $cleanChunk | ConvertTo-Json -Depth 10 -Compress
        try {
            Invoke-RestMethod -Method Post -Uri $endpoint -Headers $Headers -Body $jsonBody -TimeoutSec 15 -ErrorAction Stop | Out-Null
            $totalUploaded += $count
        } catch {
            $statusCode = 0
            try { $statusCode = [int]$_.Exception.Response.StatusCode } catch {}
            if ($statusCode -eq 409) {
                $totalUploaded += $count
            } else {
                Write-Host "      [!] Status $statusCode no envio de $Table" -ForegroundColor Yellow
            }
        }
    }
    return $totalUploaded
}

Write-Host "Enviando registros para o Supabase..." -ForegroundColor Cyan

$rList = [System.Collections.Generic.List[object]]::new()
foreach ($val in $researchEvents.Values) { $rList.Add($val) }
$upResearch = Upload-BatchToSupabase -Table "research_events" -Items $rList -Url $SupabaseUrl -Headers $headers
Write-Host "  [OK] research_events sincronizados: $upResearch / $($researchEvents.Count)" -ForegroundColor Green

$sList = [System.Collections.Generic.List[object]]::new()
foreach ($val in $sessionEvents.Values) { $sList.Add($val) }
$upSession = Upload-BatchToSupabase -Table "research_session_events" -Items $sList -Url $SupabaseUrl -Headers $headers
Write-Host "  [OK] research_session_events sincronizados: $upSession / $($sessionEvents.Count)" -ForegroundColor Green

Write-Host ""
Write-Host "====================================================================" -ForegroundColor Green
Write-Host "  IMPORTACAO PARA O SUPABASE CONCLUIDA!" -ForegroundColor Green
Write-Host "====================================================================" -ForegroundColor Green
Write-Host " Total de sessoes processadas : $sessionCount" -ForegroundColor White
Write-Host " Total de eventos enviados   : $($upResearch + $upSession)" -ForegroundColor White
Write-Host "====================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Pressione Enter para finalizar..."
[void][Console]::ReadLine()
