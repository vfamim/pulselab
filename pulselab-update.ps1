#Requires -Version 5.1
# PulseLab - Atualizacao automatica assinada (carregado por pulselab.ps1)
#
# Fluxo:
#   1. Baixa o manifesto da ultima release publicada no GitHub e sua assinatura.
#   2. Confere a assinatura RSA-SHA256 com a chave publica distribuida no pacote
#      (release-public-key.json). Sem chave ou assinatura valida, nao atualiza.
#   3. Baixa o ZIP indicado no manifesto e confere o SHA-256 assinado.
#   4. Extrai em pasta temporaria, valida a sintaxe dos scripts e troca as pastas
#      da instalacao guardando a versao anterior em _update_backup.
#   5. pulselab.ps1 confirma a atualizacao depois que o servidor local responde.
#      Se nao responder, restaura a versao anterior e bloqueia a versao com falha.
#
# dados_locais nunca e movido, apagado ou sobrescrito.

$script:PulseLabUpdateManifestUrl = "https://github.com/vfamim/pulselab/releases/latest/download/pulselab-update.json"
$script:PulseLabUpdateAllowedPrefix = "https://github.com/vfamim/pulselab/releases/download/"
$script:PulseLabUpdateMaxBytes = 64MB
$script:PulseLabProtectedItems = @("dados_locais", "_update_stage", "_update_backup", "provisionamento.json")

function Write-PulseLabUpdateLog {
    param([string]$DataDir, [string]$Message)
    Write-Host "[ATUALIZACAO] $Message"
    if (-not $DataDir) { return }
    try {
        if (-not (Test-Path -LiteralPath $DataDir)) { New-Item -ItemType Directory -Path $DataDir -Force | Out-Null }
        $line = "{0} {1}" -f ([DateTime]::UtcNow.ToString("o")), $Message
        Add-Content -LiteralPath (Join-Path $DataDir "update.log") -Value $line -Encoding UTF8
    } catch {}
}

function Get-PulseLabRemoteBytes {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [int]$TimeoutMs = 2000,
        [long]$MaxBytes = 1MB
    )
    if ($Url.StartsWith("file://")) {
        $localPath = ([Uri]$Url).LocalPath
        return [System.IO.File]::ReadAllBytes($localPath)
    }
    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
    } catch {}
    $req = [System.Net.HttpWebRequest]::Create($Url)
    $req.Timeout = $TimeoutMs
    $req.ReadWriteTimeout = $TimeoutMs
    $req.AllowAutoRedirect = $true
    $req.UserAgent = "PulseLab-Updater"
    $resp = $req.GetResponse()
    try {
        $stream = $resp.GetResponseStream()
        $buffer = New-Object byte[] 65536
        $ms = New-Object System.IO.MemoryStream
        while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $ms.Write($buffer, 0, $read)
            if ($ms.Length -gt $MaxBytes) { throw "Download excede o limite de $MaxBytes bytes." }
        }
        return $ms.ToArray()
    } finally {
        $resp.Close()
    }
}

function Get-PulseLabUpdateKey {
    param([Parameter(Mandatory = $true)][string]$InstallRoot)
    $keyFile = Join-Path $InstallRoot "release-public-key.json"
    if (-not (Test-Path -LiteralPath $keyFile)) { return $null }
    try {
        $key = Get-Content -LiteralPath $keyFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($key.kty -ne "RSA" -or -not $key.n -or -not $key.e) { return $null }
        return $key
    } catch {
        return $null
    }
}

function Test-PulseLabSignature {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Data,
        [Parameter(Mandatory = $true)][byte[]]$Signature,
        [Parameter(Mandatory = $true)]$Key
    )
    $rsa = [System.Security.Cryptography.RSA]::Create()
    try {
        $params = New-Object System.Security.Cryptography.RSAParameters
        $params.Modulus = [Convert]::FromBase64String([string]$Key.n)
        $params.Exponent = [Convert]::FromBase64String([string]$Key.e)
        $rsa.ImportParameters($params)
        return $rsa.VerifyData(
            $Data,
            $Signature,
            [System.Security.Cryptography.HashAlgorithmName]::SHA256,
            [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
        )
    } catch {
        return $false
    } finally {
        $rsa.Dispose()
    }
}

function ConvertTo-PulseLabVersion {
    param([string]$Text)
    $clean = ([string]$Text -replace '[^0-9\.]', '').Trim('.')
    try { return [System.Version]::Parse($clean) } catch { return $null }
}

function Get-PulseLabBlockedVersions {
    param([string]$DataDir)
    $file = Join-Path $DataDir "update-blocked.json"
    if (-not (Test-Path -LiteralPath $file)) { return @() }
    try { return @((Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json).versions) } catch { return @() }
}

function Add-PulseLabBlockedVersion {
    param([string]$DataDir, [string]$Version)
    $versions = @(Get-PulseLabBlockedVersions -DataDir $DataDir) + $Version | Select-Object -Unique
    $payload = @{ versions = @($versions) } | ConvertTo-Json
    Set-Content -LiteralPath (Join-Path $DataDir "update-blocked.json") -Value $payload -Encoding UTF8
}

function Get-PulseLabVerifiedManifest {
    param(
        [Parameter(Mandatory = $true)][string]$ManifestUrl,
        [Parameter(Mandatory = $true)]$Key,
        [string]$AllowedPrefix = $script:PulseLabUpdateAllowedPrefix,
        [int]$TimeoutMs = 2000
    )
    $manifestBytes = Get-PulseLabRemoteBytes -Url $ManifestUrl -TimeoutMs $TimeoutMs -MaxBytes 64KB
    $sigBytes = Get-PulseLabRemoteBytes -Url "$ManifestUrl.sig" -TimeoutMs $TimeoutMs -MaxBytes 4KB
    if (-not (Test-PulseLabSignature -Data $manifestBytes -Signature $sigBytes -Key $Key)) {
        throw "Assinatura do manifesto invalida."
    }
    $manifest = [System.Text.Encoding]::UTF8.GetString($manifestBytes) | ConvertFrom-Json
    if (-not (ConvertTo-PulseLabVersion $manifest.version)) { throw "Manifesto sem versao valida." }
    if ([string]$manifest.package_sha256 -notmatch '^[a-f0-9]{64}$') { throw "Manifesto sem SHA-256 valido." }
    if (-not ([string]$manifest.package_url).StartsWith($AllowedPrefix)) { throw "URL do pacote fora do canal permitido." }
    return $manifest
}

function Get-PulseLabPayloadRoot {
    param([string]$ExtractDir)
    if (Test-Path -LiteralPath (Join-Path $ExtractDir "pulselab.ps1")) { return $ExtractDir }
    $subDirs = @(Get-ChildItem -LiteralPath $ExtractDir -Directory)
    if ($subDirs.Count -eq 1 -and (Test-Path -LiteralPath (Join-Path $subDirs[0].FullName "pulselab.ps1"))) {
        return $subDirs[0].FullName
    }
    return $null
}

function Test-PulseLabPayload {
    param([string]$PayloadRoot)
    $required = @("pulselab.ps1", "pulselab-update.ps1", "VERSION", "bridge\pulselab-bridge.ps1", "app\alunos\index.html")
    foreach ($rel in $required) {
        if (-not (Test-Path -LiteralPath (Join-Path $PayloadRoot $rel))) { throw "Pacote sem $rel." }
    }
    foreach ($script in @("pulselab.ps1", "pulselab-update.ps1", "bridge\pulselab-bridge.ps1", "bridge\spike-parser.ps1")) {
        $path = Join-Path $PayloadRoot $script
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$errors)
        if ($errors -and $errors.Count -gt 0) { throw "Erro de sintaxe em ${script}: $($errors[0].Message)" }
    }
}

function Restore-PulseLabUpdate {
    param(
        [Parameter(Mandatory = $true)][string]$InstallRoot,
        [string]$Reason = "falha na inicializacao"
    )
    $dataDir = Join-Path $InstallRoot "dados_locais"
    $backup = Join-Path $InstallRoot "_update_backup"
    $pendingFile = Join-Path $dataDir "update-pending.json"
    if (-not (Test-Path -LiteralPath $backup)) { return $false }

    $pending = $null
    if (Test-Path -LiteralPath $pendingFile) {
        try { $pending = Get-Content -LiteralPath $pendingFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
    }
    $installed = @()
    $newItems = @()
    if ($pending -and $pending.installed_items) { $installed = @($pending.installed_items) }
    if ($pending -and $pending.new_items) { $newItems = @($pending.new_items) }

    foreach ($name in $installed) {
        if ($script:PulseLabProtectedItems -contains $name) { continue }
        $target = Join-Path $InstallRoot $name
        $saved = Join-Path $backup $name
        if (Test-Path -LiteralPath $saved) {
            if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
            Move-Item -LiteralPath $saved -Destination $target
        } elseif ($newItems -contains $name -and (Test-Path -LiteralPath $target)) {
            Remove-Item -LiteralPath $target -Recurse -Force
        }
    }
    Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction SilentlyContinue

    if ($pending -and $pending.to) { Add-PulseLabBlockedVersion -DataDir $dataDir -Version ([string]$pending.to) }
    Remove-Item -LiteralPath $pendingFile -Force -ErrorAction SilentlyContinue
    $toVersion = if ($pending) { $pending.to } else { "?" }
    $fromVersion = if ($pending) { $pending.from } else { "?" }
    Write-PulseLabUpdateLog -DataDir $dataDir -Message "Versao $toVersion revertida para $fromVersion ($Reason)."
    return $true
}

function Complete-PulseLabUpdate {
    param([Parameter(Mandatory = $true)][string]$InstallRoot)
    $dataDir = Join-Path $InstallRoot "dados_locais"
    $pendingFile = Join-Path $dataDir "update-pending.json"
    if (-not (Test-Path -LiteralPath $pendingFile)) { return $false }
    try {
        $pending = Get-Content -LiteralPath $pendingFile -Raw -Encoding UTF8 | ConvertFrom-Json
        Write-PulseLabUpdateLog -DataDir $dataDir -Message "Versao $($pending.to) confirmada apos inicializacao."
    } catch {}
    Remove-Item -LiteralPath $pendingFile -Force -ErrorAction SilentlyContinue
    return $true
}

function Install-PulseLabPayload {
    param(
        [Parameter(Mandatory = $true)][string]$InstallRoot,
        [Parameter(Mandatory = $true)][string]$PayloadRoot,
        [Parameter(Mandatory = $true)][string]$FromVersion,
        [Parameter(Mandatory = $true)][string]$ToVersion
    )
    $dataDir = Join-Path $InstallRoot "dados_locais"
    $backup = Join-Path $InstallRoot "_update_backup"
    if (Test-Path -LiteralPath $backup) { Remove-Item -LiteralPath $backup -Recurse -Force }
    New-Item -ItemType Directory -Path $backup -Force | Out-Null
    if (-not (Test-Path -LiteralPath $dataDir)) { New-Item -ItemType Directory -Path $dataDir -Force | Out-Null }

    $items = @(Get-ChildItem -LiteralPath $PayloadRoot -Force | Where-Object { $script:PulseLabProtectedItems -notcontains $_.Name })
    $pending = [ordered]@{
        from = $FromVersion
        to = $ToVersion
        started_at = [DateTime]::UtcNow.ToString("o")
        installed_items = @($items | ForEach-Object { $_.Name })
        new_items = @($items | Where-Object { -not (Test-Path -LiteralPath (Join-Path $InstallRoot $_.Name)) } | ForEach-Object { $_.Name })
    }
    Set-Content -LiteralPath (Join-Path $dataDir "update-pending.json") -Value ($pending | ConvertTo-Json) -Encoding UTF8

    try {
        foreach ($item in $items) {
            $target = Join-Path $InstallRoot $item.Name
            if (Test-Path -LiteralPath $target) {
                Move-Item -LiteralPath $target -Destination (Join-Path $backup $item.Name)
            }
            Move-Item -LiteralPath $item.FullName -Destination $target
        }
    } catch {
        $err = $_.Exception.Message
        [void](Restore-PulseLabUpdate -InstallRoot $InstallRoot -Reason "falha ao trocar arquivos: $err")
        throw
    }
}

function Repair-PulseLabNestedFolders {
    # Versoes ate 2.2.7 copiavam pastas com Copy-Item sobre destino existente, o que
    # cria bridge\bridge, app\app etc. Traz o conteudo aninhado (mais novo) para o lugar certo.
    param([Parameter(Mandatory = $true)][string]$InstallRoot)
    $repaired = @()
    foreach ($name in @("app", "alunos", "bridge", "config", "scripts", "tools")) {
        $outer = Join-Path $InstallRoot $name
        $nested = Join-Path $outer $name
        if (-not (Test-Path -LiteralPath $nested -PathType Container)) { continue }
        if ($name -eq "app" -and -not (Test-Path -LiteralPath (Join-Path $nested "alunos"))) { continue }
        foreach ($child in @(Get-ChildItem -LiteralPath $nested -Force)) {
            $dest = Join-Path $outer $child.Name
            if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
            Move-Item -LiteralPath $child.FullName -Destination $dest
        }
        Remove-Item -LiteralPath $nested -Recurse -Force
        $repaired += $name
    }
    if ($repaired.Count -gt 0) {
        Write-PulseLabUpdateLog -DataDir (Join-Path $InstallRoot "dados_locais") -Message "Pastas aninhadas corrigidas: $($repaired -join ', ')."
    }
    return $repaired
}

function Update-PulseLabIfOnline {
    param(
        [Parameter(Mandatory = $true)][string]$CurrentVersion,
        [Parameter(Mandatory = $true)][string]$InstallRoot,
        [string]$ManifestUrl = $script:PulseLabUpdateManifestUrl,
        [string]$AllowedPrefix = $script:PulseLabUpdateAllowedPrefix,
        [int]$ProbeTimeoutMs = 2000,
        [int]$DownloadTimeoutMs = 60000
    )
    $dataDir = Join-Path $InstallRoot "dados_locais"

    $key = Get-PulseLabUpdateKey -InstallRoot $InstallRoot
    if (-not $key) { return "no-key" }

    try {
        $manifest = Get-PulseLabVerifiedManifest -ManifestUrl $ManifestUrl -Key $key -AllowedPrefix $AllowedPrefix -TimeoutMs $ProbeTimeoutMs
    } catch {
        $ex = $_.Exception
        while ($ex) {
            if ($ex -is [System.Net.WebException] -or $ex -is [System.Net.Sockets.SocketException] -or $ex -is [System.IO.IOException]) {
                return "offline"
            }
            $ex = $ex.InnerException
        }
        Write-PulseLabUpdateLog -DataDir $dataDir -Message "Manifesto recusado: $($_.Exception.Message)"
        return "rejected"
    }

    $vLocal = ConvertTo-PulseLabVersion $CurrentVersion
    $vRemote = ConvertTo-PulseLabVersion $manifest.version
    if ($vLocal -and $vRemote -le $vLocal) { return "current" }
    if ((Get-PulseLabBlockedVersions -DataDir $dataDir) -contains [string]$manifest.version) { return "blocked" }

    $stage = Join-Path $InstallRoot "_update_stage"
    try {
        if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
        New-Item -ItemType Directory -Path $stage -Force | Out-Null
        Write-PulseLabUpdateLog -DataDir $dataDir -Message "Baixando versao $($manifest.version)."

        $zipBytes = Get-PulseLabRemoteBytes -Url ([string]$manifest.package_url) -TimeoutMs $DownloadTimeoutMs -MaxBytes $script:PulseLabUpdateMaxBytes
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            $actual = ([BitConverter]::ToString($sha.ComputeHash($zipBytes)) -replace '-', '').ToLower()
        } finally {
            $sha.Dispose()
        }
        if ($actual -ne [string]$manifest.package_sha256) { throw "SHA-256 do pacote nao confere com o manifesto assinado." }

        $zipPath = Join-Path $stage "package.zip"
        [System.IO.File]::WriteAllBytes($zipPath, $zipBytes)
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $extractDir = Join-Path $stage "extracted"
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $extractDir)

        $payloadRoot = Get-PulseLabPayloadRoot -ExtractDir $extractDir
        if (-not $payloadRoot) { throw "Estrutura do pacote nao reconhecida." }
        Test-PulseLabPayload -PayloadRoot $payloadRoot

        Install-PulseLabPayload -InstallRoot $InstallRoot -PayloadRoot $payloadRoot -FromVersion $CurrentVersion -ToVersion ([string]$manifest.version)
        Write-PulseLabUpdateLog -DataDir $dataDir -Message "Versao $($manifest.version) instalada; aguardando confirmacao do servidor local."
        return "installed"
    } catch {
        Write-PulseLabUpdateLog -DataDir $dataDir -Message "Atualizacao nao aplicada: $($_.Exception.Message)"
        return "failed"
    } finally {
        if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
