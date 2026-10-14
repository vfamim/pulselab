@echo off
chcp 65001 >nul
title PulseLab - Instalador Local (v3.0.2)
echo ====================================================================
echo                   PULSELAB - INSTALADOR OFFLINE (v3.0.2)

echo ====================================================================
echo.
echo * Zero dependencia de internet.
echo * Nao requer privilegios de administrador.
echo * Preserva dados locais de sessoes anteriores.
echo.

set "INSTALL_DIR=%LOCALAPPDATA%\PulseLab"
set "SRC_DIR=%~dp0"

echo [1/3] Preparando diretorio de instalacao em:
echo       %INSTALL_DIR%
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"
if not exist "%INSTALL_DIR%\data" mkdir "%INSTALL_DIR%\data"
if not exist "%INSTALL_DIR%\app" mkdir "%INSTALL_DIR%\app"
if not exist "%INSTALL_DIR%\bridge" mkdir "%INSTALL_DIR%\bridge"
if not exist "%INSTALL_DIR%\config" mkdir "%INSTALL_DIR%\config"
if not exist "%INSTALL_DIR%\tools" mkdir "%INSTALL_DIR%\tools"
if not exist "%INSTALL_DIR%\scripts" mkdir "%INSTALL_DIR%\scripts"

echo [2/3] Copiando arquivos locais da aplicacao e bridge...
if exist "%SRC_DIR%app" (
    xcopy "%SRC_DIR%app\*" "%INSTALL_DIR%\app\" /E /I /Y /Q >nul 2>&1
) else if exist "%SRC_DIR%alunos" (
    if not exist "%INSTALL_DIR%\app\alunos" mkdir "%INSTALL_DIR%\app\alunos"
    xcopy "%SRC_DIR%alunos\*" "%INSTALL_DIR%\app\alunos\" /E /I /Y /Q >nul 2>&1
)

if exist "%SRC_DIR%bridge" (
    xcopy "%SRC_DIR%bridge\*" "%INSTALL_DIR%\bridge\" /E /I /Y /Q >nul 2>&1
)

if exist "%SRC_DIR%config" (
    xcopy "%SRC_DIR%config\*" "%INSTALL_DIR%\config\" /E /I /Y /Q >nul 2>&1
)

if exist "%SRC_DIR%tools" (
    xcopy "%SRC_DIR%tools\*" "%INSTALL_DIR%\tools\" /E /I /Y /Q >nul 2>&1
)

if exist "%SRC_DIR%Iniciar-PulseLab.bat" copy "%SRC_DIR%Iniciar-PulseLab.bat" "%INSTALL_DIR%\" /Y >nul 2>&1
if exist "%SRC_DIR%iniciar-silencioso.vbs" copy "%SRC_DIR%iniciar-silencioso.vbs" "%INSTALL_DIR%\" /Y >nul 2>&1
if exist "%SRC_DIR%Desinstalar-PulseLab.bat" copy "%SRC_DIR%Desinstalar-PulseLab.bat" "%INSTALL_DIR%\" /Y >nul 2>&1
if exist "%SRC_DIR%pulselab.ps1" copy "%SRC_DIR%pulselab.ps1" "%INSTALL_DIR%\" /Y >nul 2>&1
if exist "%SRC_DIR%pulselab-update.ps1" copy "%SRC_DIR%pulselab-update.ps1" "%INSTALL_DIR%\" /Y >nul 2>&1
if exist "%SRC_DIR%pulselab-installation.ps1" copy "%SRC_DIR%pulselab-installation.ps1" "%INSTALL_DIR%\" /Y >nul 2>&1
if exist "%SRC_DIR%release-public-key.json" copy "%SRC_DIR%release-public-key.json" "%INSTALL_DIR%\" /Y >nul 2>&1
if exist "%SRC_DIR%provisionamento.json" copy "%SRC_DIR%provisionamento.json" "%INSTALL_DIR%\" /Y >nul 2>&1
if exist "%SRC_DIR%Exportar-Dados-Pendrive.bat" copy "%SRC_DIR%Exportar-Dados-Pendrive.bat" "%INSTALL_DIR%\" /Y >nul 2>&1
if exist "%SRC_DIR%scripts\exportar-pendrive.ps1" copy "%SRC_DIR%scripts\exportar-pendrive.ps1" "%INSTALL_DIR%\scripts\" /Y >nul 2>&1
if exist "%SRC_DIR%Install-PulseLab.ps1" copy "%SRC_DIR%Install-PulseLab.ps1" "%INSTALL_DIR%\" /Y >nul 2>&1
if exist "%SRC_DIR%VERSION" copy "%SRC_DIR%VERSION" "%INSTALL_DIR%\" /Y >nul 2>&1
if exist "%SRC_DIR%pulselab.ico" copy "%SRC_DIR%pulselab*.ico" "%INSTALL_DIR%\" /Y >nul 2>&1

echo.
echo Identificacao desta maquina (opcional): use o mesmo nome da etiqueta no gabinete.
set "PL_LABEL="
set /p "PL_LABEL=Nome da maquina (ex.: PET-LAB1-PC03) ou Enter para manter: "
powershell -NoProfile -ExecutionPolicy Bypass -Command "& { . (Join-Path $env:LOCALAPPDATA 'PulseLab\pulselab-installation.ps1'); $i = Initialize-PulseLabInstallation -InstallRoot (Join-Path $env:LOCALAPPDATA 'PulseLab') -MachineLabel $env:PL_LABEL; Write-Host ('      Maquina: ' + $i.machine_label); if ($i.research_collection_enabled -eq $true) { Write-Host ('      Coleta de pesquisa ATIVA - polo ' + $i.site_id + ', CAAE ' + $i.research_authorization_version) } else { Write-Host '      Coleta de pesquisa DESLIGADA neste computador (use o pacote do seu polo para ativar).' } }"
echo.

echo [3/3] Criando atalho silencioso na Area de Trabalho com icone oficial...
:: Limpar atalhos ou pastas de versoes legadas (v3.0.2)
if exist "%INSTALL_DIR%\app\agent" rd /s /q "%INSTALL_DIR%\app\agent" >nul 2>&1
if exist "%INSTALL_DIR%\app\pulselab-agent.ps1" del /f /q "%INSTALL_DIR%\app\pulselab-agent.ps1" >nul 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -Command "$desktop = [Environment]::GetFolderPath('Desktop'); $startup = [Environment]::GetFolderPath('Startup'); Remove-Item -LiteralPath (Join-Path $desktop 'Iniciar Pulselab - Oficina de Robotica.lnk') -Force -ErrorAction SilentlyContinue; Remove-Item -LiteralPath (Join-Path $startup 'PulseLab.lnk') -Force -ErrorAction SilentlyContinue" >nul 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ws = New-Object -ComObject WScript.Shell; $s = $ws.CreateShortcut([System.IO.Path]::Combine([Environment]::GetFolderPath('Desktop'), 'PulseLab - Iniciar Oficina.lnk')); $s.TargetPath = [System.IO.Path]::Combine($env:SystemRoot, 'System32\wscript.exe'); $s.Arguments = '\"' + [System.IO.Path]::Combine($env:LOCALAPPDATA, 'PulseLab\iniciar-silencioso.vbs') + '\"'; $s.WorkingDirectory = [System.IO.Path]::Combine($env:LOCALAPPDATA, 'PulseLab'); $s.IconLocation = [System.IO.Path]::Combine($env:LOCALAPPDATA, 'PulseLab\pulselab.ico') + ',0'; $s.Description = 'Iniciar oficina de robotica do PulseLab'; $s.Save()" >nul 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ws = New-Object -ComObject WScript.Shell; $s = $ws.CreateShortcut([System.IO.Path]::Combine([Environment]::GetFolderPath('Desktop'), 'PulseLab - Exportar Dados.lnk')); $s.TargetPath = [System.IO.Path]::Combine($env:LOCALAPPDATA, 'PulseLab\Exportar-Dados-Pendrive.bat'); $s.WorkingDirectory = [System.IO.Path]::Combine($env:LOCALAPPDATA, 'PulseLab'); $s.IconLocation = [System.IO.Path]::Combine($env:LOCALAPPDATA, 'PulseLab\pulselab.ico') + ',0'; $s.Description = 'Copiar os registros da oficina para o pendrive'; $s.Save()" >nul 2>&1

:: Inicia com o Windows: a sessao da turma abre quando o computador liga e o icone fica na bandeja.
:: Os computadores sao dedicados as oficinas; use --sem-inicializacao para nao criar o atalho.
if /i not "%1"=="--sem-inicializacao" (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$ws = New-Object -ComObject WScript.Shell; $s = $ws.CreateShortcut([System.IO.Path]::Combine([Environment]::GetFolderPath('Startup'), 'PulseLab.lnk')); $s.TargetPath = [System.IO.Path]::Combine($env:SystemRoot, 'System32\wscript.exe'); $s.Arguments = '\"' + [System.IO.Path]::Combine($env:LOCALAPPDATA, 'PulseLab\iniciar-silencioso.vbs') + '\"'; $s.WorkingDirectory = [System.IO.Path]::Combine($env:LOCALAPPDATA, 'PulseLab'); $s.IconLocation = [System.IO.Path]::Combine($env:LOCALAPPDATA, 'PulseLab\pulselab.ico') + ',0'; $s.Description = 'PulseLab - Inicializacao Automatica'; $s.Save()" >nul 2>&1
    echo [OK] O PulseLab vai iniciar sozinho com o Windows ^(icone na bandeja^).
)

echo.
echo ====================================================================
echo [OK] Instalacao concluida com sucesso!
echo      O PulseLab inicia com o Windows e fica como icone na bandeja.
echo      Para iniciar agora, use o atalho 'PulseLab - Iniciar Oficina'.
echo      Ao fim da aula: clique direito no icone ^> Encerrar turma.
echo ====================================================================
echo.
pause
