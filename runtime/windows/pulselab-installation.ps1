#Requires -Version 5.1
# PulseLab - Identidade da maquina e provisionamento por polo (carregado por pulselab.ps1 e pelo instalador)
#
# dados_locais\installation.json guarda:
#   - installation_id: UUID aleatorio gerado uma unica vez nesta maquina;
#   - machine_label: rotulo legivel (ex.: PET-LAB1-PC03), usado em exportacoes e etiquetas;
#   - dados do polo vindos de provisionamento.json (sede, escola, autorizacao de pesquisa).
#   - manifest_hmac_key: chave do polo que assina o pendrive (exportar-pendrive.ps1); nunca e exportada.
#
# O arquivo fica em dados_locais, que atualizacoes e reinstalacoes nunca sobrescrevem.
# Nenhum nome de computador, usuario do Windows ou caminho pessoal e gravado.

$script:PulseLabCaaePattern = '^\d{8}\.\d\.\d{4}\.\d{4}$'
# Numero de exemplo da documentacao: casa com o formato, mas nao e parecer de CEP nenhum.
$script:PulseLabExampleCaae = "12345678.9.0000.1234"
$script:PulseLabProvisioningFields = @(
    "provisioning_id",
    "site_id",
    "regional_hub",
    "school_code",
    "research_collection_enabled",
    "research_authorization_version",
    "research_authorized_purposes",
    "retention_days",
    "calendario_missoes",
    "enrollment_token",
    "manifest_hmac_key"
)

function ConvertTo-PulseLabMachineLabel {
    param([string]$Text)
    if (-not $Text) { return "" }
    $clean = ($Text.Trim().ToUpperInvariant() -replace '[^A-Z0-9_-]', '-') -replace '-{2,}', '-'
    $clean = $clean.Trim('-')
    if ($clean.Length -gt 32) { $clean = $clean.Substring(0, 32) }
    return $clean
}

function Read-PulseLabJsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Save-PulseLabInstallation {
    param([string]$Path, $Data)
    $tmp = "$Path.tmp"
    $json = $Data | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText($tmp, $json, (New-Object System.Text.UTF8Encoding($false)))
    if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force }
    Move-Item -LiteralPath $tmp -Destination $Path
}

function Test-PulseLabResearchAuthorization {
    param($Data)
    if ($Data.research_collection_enabled -ne $true) { return $false }
    $caae = [string]$Data.research_authorization_version
    if ($caae -notmatch $script:PulseLabCaaePattern -or $caae -eq $script:PulseLabExampleCaae) { return $false }
    return (@($Data.research_authorized_purposes) -contains "academic_research")
}

function Initialize-PulseLabInstallation {
    param(
        [Parameter(Mandatory = $true)][string]$InstallRoot,
        [string]$MachineLabel = "",
        [string]$ProvisioningFile = "",
        [string]$Polo = "",
        [string]$Regional = ""
    )
    $dataDir = Join-Path $InstallRoot "dados_locais"
    if (-not (Test-Path -LiteralPath $dataDir)) { New-Item -ItemType Directory -Path $dataDir -Force | Out-Null }
    $path = Join-Path $dataDir "installation.json"

    $current = $null
    try { $current = Read-PulseLabJsonFile -Path $path } catch {}
    $data = [ordered]@{}
    if ($current) {
        foreach ($prop in $current.PSObject.Properties) { $data[$prop.Name] = $prop.Value }
    }
    $changed = $false

    if (-not ([string]$data["installation_id"] -match '^[0-9a-fA-F-]{36}$')) {
        $data["installation_id"] = [Guid]::NewGuid().ToString()
        $data["created_at"] = [DateTime]::UtcNow.ToString("o")
        $changed = $true
    }

    $label = ConvertTo-PulseLabMachineLabel $MachineLabel
    if ($label) {
        if ($data["machine_label"] -ne $label) { $data["machine_label"] = $label; $changed = $true }
    } elseif (-not $data["machine_label"]) {
        $data["machine_label"] = "PC-" + ([string]$data["installation_id"]).Substring(0, 6).ToUpperInvariant()
        $changed = $true
    }

    if (-not $ProvisioningFile) { $ProvisioningFile = Join-Path $InstallRoot "provisionamento.json" }
    $provisioning = $null
    try { $provisioning = Read-PulseLabJsonFile -Path $ProvisioningFile } catch {}
    if ($provisioning -and $provisioning.provisioning_id -and $provisioning.provisioning_id -ne $data["provisioning_id"]) {
        foreach ($field in $script:PulseLabProvisioningFields) {
            $value = $provisioning.$field
            if ($null -ne $value) { $data[$field] = $value }
        }
        $data["provisioned_at"] = [DateTime]::UtcNow.ToString("o")
        $changed = $true
    }

    # A 3.2.1 ligava a coleta pelo CAAE digitado no instalador (provisioning_id "<polo>-installer-<data>").
    # Coleta so vem do pacote do polo: essas maquinas voltam a ficar sem coleta ate receber o pacote.
    if ([string]$data["provisioning_id"] -match '-installer-') {
        $data.Remove("provisioning_id")
        if ($data["research_collection_enabled"] -eq $true) {
            $data["research_collection_enabled"] = $false
            $data["research_blocked_reason"] = "coleta ligada pelo instalador sem pacote do polo"
        }
        $changed = $true
    }

    # Polo e regional digitados so identificam maquinas sem pacote do polo; nunca ligam a coleta.
    if (-not $data["provisioning_id"]) {
        $cleanPolo = if ($Polo) { ([string]$Polo).Trim().ToUpperInvariant() } else { "" }
        $cleanRegional = if ($Regional) { ([string]$Regional).Trim() } else { "" }
        if ($cleanPolo -and $data["site_id"] -ne $cleanPolo) { $data["site_id"] = $cleanPolo; $changed = $true }
        if ($cleanRegional -and $data["regional_hub"] -ne $cleanRegional) { $data["regional_hub"] = $cleanRegional; $changed = $true }
    }

    # Coleta so fica ligada com CAAE no formato oficial e finalidade academica declarada.
    if ($data.Contains("research_collection_enabled") -and $data["research_collection_enabled"] -eq $true) {
        if (-not (Test-PulseLabResearchAuthorization -Data ([pscustomobject]$data))) {
            $data["research_collection_enabled"] = $false
            $data["research_blocked_reason"] = "autorizacao sem CAAE valido"
            $changed = $true
        } elseif ($data.Contains("research_blocked_reason")) {
            $data.Remove("research_blocked_reason")
            $changed = $true
        }
    }

    if ($changed) { Save-PulseLabInstallation -Path $path -Data $data }
    return [pscustomobject]$data
}
