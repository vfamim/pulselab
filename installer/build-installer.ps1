#Requires -Version 5.1
# PulseLab 1.8.0 - Windows package builder (PWA + Bridge)
# Builds the standalone release ZIP file containing the Web-First offline package.

[CmdletBinding()]
param(
    [string]$OutputPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$Version = "1.8.0"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptDir "..")
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $repoRoot "PulseLab-$Version-Windows.zip"
}
$OutputPath = [IO.Path]::GetFullPath($OutputPath)

$stageParent = Join-Path $env:TEMP "pulselab-package-$([Guid]::NewGuid().ToString('N'))"
$stage = Join-Path $stageParent "PulseLab-$Version-Windows"
try {
    New-Item -ItemType Directory -Path (Join-Path $stage "app\alunos") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $stage "bridge") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $stage "config") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $stage "tools") -Force | Out-Null

    # Copiar PWA
    $alunosDir = Join-Path $repoRoot "alunos"
    if (-not (Test-Path -LiteralPath (Join-Path $alunosDir "index.html") -PathType Leaf)) {
        throw "PWA build missing in alunos/. Run build first."
    }
    Copy-Item -Path (Join-Path $alunosDir "*") -Destination (Join-Path $stage "app\alunos") -Recurse -Force

    # Copiar Bridge
    Copy-Item (Join-Path $repoRoot "bridge\pulselab-bridge.ps1") (Join-Path $stage "bridge\pulselab-bridge.ps1") -Force
    Copy-Item (Join-Path $repoRoot "bridge\spike-parser.ps1") (Join-Path $stage "bridge\spike-parser.ps1") -Force
    Copy-Item (Join-Path $repoRoot "bridge\pulselab-toast.ps1") (Join-Path $stage "bridge\pulselab-toast.ps1") -Force

    # Copiar Tools
    if (Test-Path -LiteralPath (Join-Path $repoRoot "tools\spike-probe.ps1") -PathType Leaf) {
        Copy-Item (Join-Path $repoRoot "tools\spike-probe.ps1") (Join-Path $stage "tools\spike-probe.ps1") -Force
    }

    # Copiar Config
    if (Test-Path -LiteralPath (Join-Path $repoRoot "config\defaults.json") -PathType Leaf) {
        Copy-Item (Join-Path $repoRoot "config\defaults.json") (Join-Path $stage "config\defaults.json") -Force
    }
    if (Test-Path -LiteralPath (Join-Path $repoRoot "config\config.json") -PathType Leaf) {
        Copy-Item (Join-Path $repoRoot "config\config.json") (Join-Path $stage "config\config.json") -Force
    }

    # Copiar Scripts e Launchers
    Copy-Item (Join-Path $repoRoot "Instalar-PulseLab.bat") (Join-Path $stage "Instalar-PulseLab.bat") -Force
    Copy-Item (Join-Path $repoRoot "Iniciar-PulseLab.bat") (Join-Path $stage "Iniciar-PulseLab.bat") -Force
    Copy-Item (Join-Path $repoRoot "Desinstalar-PulseLab.bat") (Join-Path $stage "Desinstalar-PulseLab.bat") -Force
    Copy-Item (Join-Path $repoRoot "pulselab.ps1") (Join-Path $stage "pulselab.ps1") -Force
    Copy-Item (Join-Path $repoRoot "pulselab.ico") (Join-Path $stage "pulselab.ico") -Force
    Copy-Item (Join-Path $repoRoot "installer\install.ps1") (Join-Path $stage "Install-PulseLab.ps1") -Force

    $instructions = @"
====================================================================
PULSELAB $Version — PACOTE PORTÁTIL E OFFLINE PARA WINDOWS
====================================================================

O PulseLab é o ambiente de acompanhamento de oficinas de robótica escolar com LEGO SPIKE.
Totalmente desacoplado: interface executada diretamente no navegador padrão (PWA 100% offline),
servidor Bridge local mínimo em loopback (porta 43127) e leitura automática de projetos (.llsp3).

REQUISITOS:
- Windows 10 ou 11 com Windows PowerShell 5.1 (já nativo no Windows).
- Zero internet necessária durante a oficina.
- Não requer privilégios de administrador.

COMO USAR:

OPÇÃO 1: EXECUÇÃO DIRETA (Recomendado — Sem instalação)
1. Extraia todo o arquivo ZIP em qualquer pasta (ex: Área de Trabalho ou Pendrive).
2. Dê dois cliques em "Iniciar-PulseLab.bat".
3. O navegador padrão abrirá automaticamente em http://127.0.0.1:43127/alunos/.
4. O Bridge emitirá alertas sonoros e visuais aos 20 e 40 minutos de oficina.

OPÇÃO 2: INSTALAÇÃO NO SISTEMA (Com atalho na Área de Trabalho)
1. Extraia todo o arquivo ZIP.
2. Dê dois cliques em "Instalar-PulseLab.bat".
3. O atalho "PulseLab - Iniciar Oficina" será criado na Área de Trabalho.
4. Para abrir nas próximas oficinas, basta dar dois cliques no atalho.

COMO DESINSTALAR:
- Dê dois cliques em "Desinstalar-PulseLab.bat".
"@
    [IO.File]::WriteAllText((Join-Path $stage "INSTRUCOES.txt"), $instructions, (New-Object Text.UTF8Encoding($true)))
    [IO.File]::WriteAllText((Join-Path $stage "VERSION"), "$Version`n", [Text.Encoding]::ASCII)
    [IO.File]::WriteAllText((Join-Path $stage "VERSION.txt"), "$Version`n", [Text.Encoding]::ASCII)

    $manifest = Get-ChildItem -Path $stage -File -Recurse | Sort-Object FullName | ForEach-Object {
        $relative = $_.FullName.Substring($stage.Length + 1).Replace('\', '/')
        "$((Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash.ToLowerInvariant())  $relative"
    }
    [IO.File]::WriteAllLines((Join-Path $stage "SHA256SUMS.txt"), $manifest, [Text.Encoding]::UTF8)

    $outputDir = Split-Path -Parent $OutputPath
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    if (Test-Path $OutputPath) { Remove-Item $OutputPath -Force }
    Compress-Archive -Path $stage -DestinationPath $OutputPath -CompressionLevel Optimal
    $zipHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $OutputPath).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText("$OutputPath.sha256", "$zipHash  $([IO.Path]::GetFileName($OutputPath))`n", [Text.Encoding]::ASCII)
    Write-Host "Package: $OutputPath"
    Write-Host "SHA-256: $zipHash"
} finally {
    Remove-Item $stageParent -Recurse -Force -ErrorAction SilentlyContinue
}
