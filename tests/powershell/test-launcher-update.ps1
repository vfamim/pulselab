# Testes do atualizador assinado (pulselab-update.ps1). Roda em pwsh (CI) e Windows PowerShell 5.1.
$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repoRoot "pulselab-update.ps1")
. (Join-Path $repoRoot "pulselab-installation.ps1")

$python = if (Get-Command python3 -ErrorAction SilentlyContinue) { "python3" } else { "python" }
$releaseTool = Join-Path $repoRoot "tooling\release\publicar-release.py"
$failures = 0

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if ($Condition) {
        Write-Host "  ok   $Message"
    } else {
        Write-Host "  FAIL $Message"
        $script:failures++
    }
}

function New-TextFile {
    param([string]$Path, [string]$Content)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Set-Content -LiteralPath $Path -Value $Content -Encoding UTF8
}

function New-FakeTree {
    param([string]$Root, [string]$Version, [string]$Marker)
    New-TextFile (Join-Path $Root "pulselab.ps1") "# launcher $Marker"
    Copy-Item -LiteralPath (Join-Path $repoRoot "pulselab-update.ps1") -Destination (Join-Path $Root "pulselab-update.ps1")
    New-TextFile (Join-Path $Root "VERSION") $Version
    New-TextFile (Join-Path $Root "bridge\pulselab-bridge.ps1") "# bridge $Marker"
    New-TextFile (Join-Path $Root "app\alunos\index.html") "<p>$Marker</p>"
    New-TextFile (Join-Path $Root "config\config.json") "{`"marker`": `"$Marker`"}"
}

function Get-FileUrl {
    param([string]$Path)
    $full = ([System.IO.Path]::GetFullPath($Path)) -replace '\\', '/'
    if ($full.StartsWith("/")) { return "file://$full" }
    return "file:///$full"
}

$work = Join-Path ([System.IO.Path]::GetTempPath()) ("pulselab-update-test-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work | Out-Null

try {
    $privateKey = Join-Path $work "release-key.pem"
    $publicKey = Join-Path $work "release-public-key.json"
    & $python $releaseTool gerar-chave --private $privateKey --public-out $publicKey | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Falha ao gerar chave de teste." }

    # Pacote novo (9.9.9), com uma pasta dados_locais que nunca deve chegar a instalacao.
    $pkgParent = Join-Path $work "pkg"
    $pkgRoot = Join-Path $pkgParent "PulseLab-9.9.9-Windows"
    New-FakeTree -Root $pkgRoot -Version "9.9.9" -Marker "nova"
    Copy-Item -LiteralPath $publicKey -Destination (Join-Path $pkgRoot "release-public-key.json")
    New-TextFile (Join-Path $pkgRoot "dados_locais\sessoes\intrusa.json") "{}"
    New-TextFile (Join-Path $pkgRoot "scripts\exportar-pendrive.ps1") "# exportador"
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = Join-Path $work "PulseLab-9.9.9-Windows.zip"
    [System.IO.Compression.ZipFile]::CreateFromDirectory($pkgParent, $zip)

    $releaseDir = Join-Path $work "release"
    & $python $releaseTool assinar --zip $zip --version 9.9.9 --out-dir $releaseDir --private $privateKey --package-url (Get-FileUrl $zip) | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Falha ao assinar manifesto de teste." }
    $manifestUrl = Get-FileUrl (Join-Path $releaseDir "pulselab-update.json")

    function New-Install {
        param([string]$Name)
        $root = Join-Path $work $Name
        New-FakeTree -Root $root -Version "2.2.7" -Marker "antiga"
        Copy-Item -LiteralPath $publicKey -Destination (Join-Path $root "release-public-key.json")
        New-TextFile (Join-Path $root "dados_locais\sessoes\sessao-real.json") "{`"real`": true}"
        New-TextFile (Join-Path $root "dados_locais\installation.json") "{`"installation_id`": `"abc`"}"
        return $root
    }

    Write-Host "Assinatura gerada pelo OpenSSL e verificada pelo .NET"
    $key = Get-PulseLabUpdateKey -InstallRoot (New-Install "keycheck")
    $mBytes = [System.IO.File]::ReadAllBytes((Join-Path $releaseDir "pulselab-update.json"))
    $sBytes = [System.IO.File]::ReadAllBytes((Join-Path $releaseDir "pulselab-update.json.sig"))
    Assert-True (Test-PulseLabSignature -Data $mBytes -Signature $sBytes -Key $key) "assinatura valida aceita"
    $tampered = [byte[]]$mBytes.Clone(); $tampered[10] = $tampered[10] -bxor 1
    Assert-True (-not (Test-PulseLabSignature -Data $tampered -Signature $sBytes -Key $key)) "manifesto alterado recusado"

    Write-Host "Atualizacao aplicada e confirmada"
    $inst = New-Install "install-ok"
    $result = Update-PulseLabIfOnline -CurrentVersion "2.2.7" -InstallRoot $inst -ManifestUrl $manifestUrl -AllowedPrefix "file://"
    Assert-True ($result -eq "installed") "resultado installed (obtido: $result)"
    Assert-True ((Get-Content (Join-Path $inst "VERSION") -Raw).Trim() -eq "9.9.9") "VERSION atualizado"
    Assert-True ((Get-Content (Join-Path $inst "app\alunos\index.html") -Raw) -match "nova") "app substituido"
    Assert-True (-not (Test-Path (Join-Path $inst "bridge\bridge"))) "sem pasta aninhada"
    Assert-True (Test-Path (Join-Path $inst "scripts\exportar-pendrive.ps1")) "item novo instalado"
    Assert-True (Test-Path (Join-Path $inst "dados_locais\sessoes\sessao-real.json")) "dados_locais preservado"
    Assert-True (-not (Test-Path (Join-Path $inst "dados_locais\sessoes\intrusa.json"))) "dados_locais do pacote ignorado"
    Assert-True ((Get-Content (Join-Path $inst "dados_locais\installation.json") -Raw) -match "abc") "installation.json preservado"
    Assert-True (Test-Path (Join-Path $inst "dados_locais\update-pending.json")) "marcador pendente criado"
    Assert-True (Complete-PulseLabUpdate -InstallRoot $inst) "confirmacao aceita"
    Assert-True (-not (Test-Path (Join-Path $inst "dados_locais\update-pending.json"))) "marcador removido"
    $again = Update-PulseLabIfOnline -CurrentVersion "9.9.9" -InstallRoot $inst -ManifestUrl $manifestUrl -AllowedPrefix "file://"
    Assert-True ($again -eq "current") "nao reinstala a mesma versao (obtido: $again)"

    Write-Host "Reversao apos falha do servidor local"
    $inst = New-Install "install-rollback"
    [void](Update-PulseLabIfOnline -CurrentVersion "2.2.7" -InstallRoot $inst -ManifestUrl $manifestUrl -AllowedPrefix "file://")
    Assert-True (Restore-PulseLabUpdate -InstallRoot $inst -Reason "teste") "reversao executada"
    Assert-True ((Get-Content (Join-Path $inst "VERSION") -Raw).Trim() -eq "2.2.7") "VERSION anterior restaurado"
    Assert-True ((Get-Content (Join-Path $inst "app\alunos\index.html") -Raw) -match "antiga") "app anterior restaurado"
    Assert-True (-not (Test-Path (Join-Path $inst "scripts"))) "item novo removido na reversao"
    Assert-True (Test-Path (Join-Path $inst "dados_locais\sessoes\sessao-real.json")) "dados_locais preservado na reversao"
    $blocked = Update-PulseLabIfOnline -CurrentVersion "2.2.7" -InstallRoot $inst -ManifestUrl $manifestUrl -AllowedPrefix "file://"
    Assert-True ($blocked -eq "blocked") "versao revertida fica bloqueada (obtido: $blocked)"

    Write-Host "Recusas"
    $inst = New-Install "install-refusals"
    Remove-Item -LiteralPath (Join-Path $inst "release-public-key.json")
    Assert-True ((Update-PulseLabIfOnline -CurrentVersion "2.2.7" -InstallRoot $inst -ManifestUrl $manifestUrl -AllowedPrefix "file://") -eq "no-key") "sem chave publica nao atualiza"
    Copy-Item -LiteralPath $publicKey -Destination (Join-Path $inst "release-public-key.json")
    $wrongPrefix = Update-PulseLabIfOnline -CurrentVersion "2.2.7" -InstallRoot $inst -ManifestUrl $manifestUrl
    Assert-True ($wrongPrefix -eq "rejected") "pacote fora do canal recusado (obtido: $wrongPrefix)"
    $missing = Update-PulseLabIfOnline -CurrentVersion "2.2.7" -InstallRoot $inst -ManifestUrl ((Get-FileUrl $work) + "/inexistente.json") -AllowedPrefix "file://"
    Assert-True ($missing -eq "offline") "manifesto inacessivel tratado como offline (obtido: $missing)"

    $forged = Join-Path $work "forged"
    New-Item -ItemType Directory -Path $forged | Out-Null
    $m = Get-Content (Join-Path $releaseDir "pulselab-update.json") -Raw | ConvertFrom-Json
    $m.package_sha256 = ("0" * 64)
    [System.IO.File]::WriteAllText((Join-Path $forged "pulselab-update.json"), ($m | ConvertTo-Json))
    Copy-Item -LiteralPath (Join-Path $releaseDir "pulselab-update.json.sig") -Destination (Join-Path $forged "pulselab-update.json.sig")
    $forgedResult = Update-PulseLabIfOnline -CurrentVersion "2.2.7" -InstallRoot $inst -ManifestUrl (Get-FileUrl (Join-Path $forged "pulselab-update.json")) -AllowedPrefix "file://"
    Assert-True ($forgedResult -eq "rejected") "manifesto sem assinatura correspondente recusado (obtido: $forgedResult)"
    Assert-True ((Get-Content (Join-Path $inst "VERSION") -Raw).Trim() -eq "2.2.7") "instalacao intacta apos recusas"

    Write-Host "Correcao de pastas aninhadas deixadas pela versao 2.2.7"
    $inst = New-Install "install-nested"
    New-TextFile (Join-Path $inst "bridge\bridge\pulselab-bridge.ps1") "# bridge nova aninhada"
    New-TextFile (Join-Path $inst "app\app\alunos\index.html") "<p>nova aninhada</p>"
    $repaired = Repair-PulseLabNestedFolders -InstallRoot $inst
    Assert-True (($repaired -contains "bridge") -and ($repaired -contains "app")) "pastas aninhadas detectadas"
    Assert-True ((Get-Content (Join-Path $inst "bridge\pulselab-bridge.ps1") -Raw) -match "aninhada") "bridge aninhada promovida"
    Assert-True ((Get-Content (Join-Path $inst "app\alunos\index.html") -Raw) -match "aninhada") "app aninhado promovido"
    Assert-True (-not (Test-Path (Join-Path $inst "bridge\bridge"))) "pasta aninhada removida"

    Write-Host "Identidade da maquina e provisionamento"
    $idRoot = Join-Path $work "identity"
    New-Item -ItemType Directory -Path $idRoot | Out-Null
    $first = Initialize-PulseLabInstallation -InstallRoot $idRoot
    Assert-True ($first.installation_id -match '^[0-9a-f-]{36}$') "installation_id gerado"
    Assert-True ($first.machine_label -eq ("PC-" + $first.installation_id.Substring(0, 6).ToUpperInvariant())) "rotulo padrao derivado do id"
    Assert-True ($first.research_collection_enabled -ne $true) "coleta desligada sem provisionamento"
    $labeled = Initialize-PulseLabInstallation -InstallRoot $idRoot -MachineLabel "pet lab1/pc 03"
    Assert-True ($labeled.installation_id -eq $first.installation_id) "id estavel entre execucoes"
    Assert-True ($labeled.machine_label -eq "PET-LAB1-PC-03") "rotulo saneado (obtido: $($labeled.machine_label))"
    $prov = Join-Path $idRoot "provisionamento.json"
    New-TextFile $prov '{"provisioning_id":"PET-1","site_id":"PET","research_collection_enabled":true,"research_authorization_version":"v2.0-piloto","research_authorized_purposes":["academic_research"]}'
    $badAuth = Initialize-PulseLabInstallation -InstallRoot $idRoot
    Assert-True ($badAuth.research_collection_enabled -eq $false) "autorizacao sem CAAE nao liga a coleta"
    Assert-True ($badAuth.site_id -eq "PET") "sede aplicada pelo provisionamento"
    New-TextFile $prov '{"provisioning_id":"PET-2","site_id":"PET","research_collection_enabled":true,"research_authorization_version":"12345678.9.0000.1234","research_authorized_purposes":["academic_research"]}'
    $goodAuth = Initialize-PulseLabInstallation -InstallRoot $idRoot
    Assert-True ($goodAuth.research_collection_enabled -eq $true) "CAAE valido liga a coleta"
    Assert-True ($goodAuth.installation_id -eq $first.installation_id -and $goodAuth.machine_label -eq "PET-LAB1-PC-03") "provisionamento preserva id e rotulo"
    $raw = Get-Content (Join-Path $idRoot "dados_locais\installation.json") -Raw
    Assert-True (-not ($raw -match [Regex]::Escape([Environment]::MachineName)) -and -not ($raw -match [Regex]::Escape([Environment]::UserName))) "sem nome do computador ou do usuario"
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures -gt 0) {
    Write-Host "$failures falha(s)."
    exit 1
}
Write-Host "Todos os testes do atualizador passaram."
