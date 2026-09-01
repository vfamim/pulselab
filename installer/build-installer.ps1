#Requires -Version 5.1
# PulseLab 1.6.0 - Windows package builder

[CmdletBinding()]
param(
    [string]$OutputPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$Version = "1.6.0"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptDir "..")
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $repoRoot "PulseLab-$Version-Windows.zip"
}
$OutputPath = [IO.Path]::GetFullPath($OutputPath)

$stageParent = Join-Path $env:TEMP "pulselab-package-$([Guid]::NewGuid().ToString('N'))"
$stage = Join-Path $stageParent "PulseLab-$Version-Windows"
try {
    New-Item -ItemType Directory -Path (Join-Path $stage "agent") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $stage "config") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $stage "supabase\scripts") -Force | Out-Null

    Copy-Item (Join-Path $repoRoot "pulselab.ps1") (Join-Path $stage "pulselab.ps1") -Force
    Copy-Item (Join-Path $repoRoot "agent\pulselab-agent.ps1") (Join-Path $stage "agent\pulselab-agent.ps1") -Force
    Copy-Item (Join-Path $repoRoot "config\config.json") (Join-Path $stage "config\config.json") -Force
    Copy-Item (Join-Path $repoRoot "supabase\scripts\enroll-device.ps1") (Join-Path $stage "supabase\scripts\enroll-device.ps1") -Force
    Copy-Item (Join-Path $repoRoot "installer\install.ps1") (Join-Path $stage "Install-PulseLab.ps1") -Force
    Copy-Item (Join-Path $repoRoot "Iniciar-Oficina-Oficial.bat") (Join-Path $stage "Iniciar-Oficina-Oficial.bat") -Force
    Copy-Item (Join-Path $repoRoot "Iniciar-PulseLab-Dev.bat") (Join-Path $stage "Iniciar-PulseLab-Dev.bat") -Force
    Copy-Item (Join-Path $repoRoot "Testar-Pulselab-Rapido.bat") (Join-Path $stage "Testar-Pulselab-Rapido.bat") -Force

    $batch = @'
@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%Install-PulseLab.ps1"
set "EXIT_CODE=%ERRORLEVEL%"
if not "%EXIT_CODE%"=="0" pause
exit /b %EXIT_CODE%
'@
    [IO.File]::WriteAllText((Join-Path $stage "Instalar-PulseLab.bat"), $batch, (New-Object Text.UTF8Encoding($false)))

    $instructions = @"
PULSELAB $Version - PACOTE WINDOWS (PRE-CONFIGURADO)

REQUISITOS
- Windows 10 ou 11 com Windows PowerShell 5.1.
- Nao e necessario configurar URLs ou chaves: o PulseLab ja vem pre-configurado!

COMO USAR (ESCOLHA UMA OPCAO):

OPCAO 1: EXECUCAO DIRETA (Recomendado - Sem instalacao)
1. Extraia todo o arquivo ZIP em uma pasta (ex: Area de Trabalho ou Documentos).
2. De dois cliques em "Iniciar-Oficina-Oficial.bat".
3. Confira os dados da turma na tela visual e clique em "Confirmar e Iniciar Oficina".

OPCAO 2: INSTALACAO COM ATALHO NA AREA DE TRABALHO
1. Extraia todo o arquivo ZIP.
2. De dois cliques em "Instalar-PulseLab.bat".
3. O atalho "Iniciar PulseLab - Oficina de Robotica" sera criado na Area de Trabalho.
4. Abra o atalho sempre que for realizar uma oficina.

RECURSOS
- Sincronizacao automatica em nuvem (Supabase) pre-configurada.
- Auto-atualizacao transparente via GitHub com verificacao criptografica SHA-256.
- Funcionamento seguro e offline com fallback transparente.
"@
    [IO.File]::WriteAllText((Join-Path $stage "INSTRUCOES.txt"), $instructions, (New-Object Text.UTF8Encoding($true)))
    [IO.File]::WriteAllText((Join-Path $stage "VERSION.txt"), "$Version`n", [Text.Encoding]::ASCII)

    $manifest = Get-ChildItem -Path $stage -File -Recurse | Sort-Object FullName | ForEach-Object {
        $relative = $_.FullName.Substring($stage.Length + 1).Replace('\', '/')
        "$((Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash.ToLowerInvariant())  $relative"
    }
    [IO.File]::WriteAllLines((Join-Path $stage "SHA256SUMS.txt"), $manifest, [Text.Encoding]::ASCII)

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
