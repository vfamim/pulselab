@echo off
chcp 65001 >nul
title PulseLab — Instalação Local 100% Offline (v1.7.0)
echo ====================================================================
echo                   PULSELAB — INSTALADOR OFFLINE (v1.7.0)
echo ====================================================================
echo.
echo * Zero dependência de internet.
echo * Não requer privilégios de administrador.
echo * Preserva dados locais de sessões anteriores.
echo.

set "INSTALL_DIR=%LOCALAPPDATA%\PulseLab"
set "SRC_DIR=%~dp0"

echo [1/3] Preparando diretório de instalação em:
echo       %INSTALL_DIR%
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"
if not exist "%INSTALL_DIR%\data" mkdir "%INSTALL_DIR%\data"
if not exist "%INSTALL_DIR%\app" mkdir "%INSTALL_DIR%\app"
if not exist "%INSTALL_DIR%\bridge" mkdir "%INSTALL_DIR%\bridge"
if not exist "%INSTALL_DIR%\config" mkdir "%INSTALL_DIR%\config"
if not exist "%INSTALL_DIR%\tools" mkdir "%INSTALL_DIR%\tools"

echo [2/3] Copiando arquivos locais da aplicação e bridge...
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
if exist "%SRC_DIR%Desinstalar-PulseLab.bat" copy "%SRC_DIR%Desinstalar-PulseLab.bat" "%INSTALL_DIR%\" /Y >nul 2>&1
if exist "%SRC_DIR%pulselab.ps1" copy "%SRC_DIR%pulselab.ps1" "%INSTALL_DIR%\" /Y >nul 2>&1
if exist "%SRC_DIR%Install-PulseLab.ps1" copy "%SRC_DIR%Install-PulseLab.ps1" "%INSTALL_DIR%\" /Y >nul 2>&1
if exist "%SRC_DIR%VERSION" copy "%SRC_DIR%VERSION" "%INSTALL_DIR%\" /Y >nul 2>&1

echo [3/3] Criando atalho na Área de Trabalho...
:: Limpar atalhos ou pastas de versões legadas (v1.6.0)
if exist "%INSTALL_DIR%\app\agent" rd /s /q "%INSTALL_DIR%\app\agent" >nul 2>&1
if exist "%INSTALL_DIR%\app\pulselab-agent.ps1" del /f /q "%INSTALL_DIR%\app\pulselab-agent.ps1" >nul 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -Command "$desktop = [Environment]::GetFolderPath('Desktop'); $startup = [Environment]::GetFolderPath('Startup'); Remove-Item -LiteralPath (Join-Path $desktop 'Iniciar Pulselab - Oficina de Robotica.lnk') -Force -ErrorAction SilentlyContinue; Remove-Item -LiteralPath (Join-Path $startup 'PulseLab.lnk') -Force -ErrorAction SilentlyContinue" >nul 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ws = New-Object -ComObject WScript.Shell; $s = $ws.CreateShortcut([System.IO.Path]::Combine([Environment]::GetFolderPath('Desktop'), 'PulseLab - Iniciar Oficina.lnk')); $s.TargetPath = [System.IO.Path]::Combine($env:LOCALAPPDATA, 'PulseLab\Iniciar-PulseLab.bat'); $s.WorkingDirectory = [System.IO.Path]::Combine($env:LOCALAPPDATA, 'PulseLab'); $s.Description = 'Iniciar oficina do PulseLab'; $s.Save()" >nul 2>&1

echo.
echo ====================================================================
echo [OK] Instalação concluída com sucesso!
echo      Você pode iniciar a oficina pelo atalho criado na Área de Trabalho
echo      ("PulseLab - Iniciar Oficina") ou executando Iniciar-PulseLab.bat.
echo ====================================================================
echo.
pause
