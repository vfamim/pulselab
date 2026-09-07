@echo off
chcp 65001 >nul
title PulseLab — Desinstalar
echo ====================================================================
echo                   PULSELAB — DESINSTALAÇÃO
echo ====================================================================
echo.

echo Encerrando processos do Bridge...
powershell -NoProfile -Command "Get-Process powershell -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match 'pulselab-bridge' } | Stop-Process -Force" >nul 2>&1

set "DESKTOP_LNK=%USERPROFILE%\Desktop\PulseLab - Iniciar Oficina.lnk"
if exist "%DESKTOP_LNK%" del /f /q "%DESKTOP_LNK%" >nul 2>&1

set "INSTALL_DIR=%LOCALAPPDATA%\PulseLab"
if exist "%INSTALL_DIR%" (
    echo Removendo arquivos de aplicação e bridge...
    rmdir /s /q "%INSTALL_DIR%\app" >nul 2>&1
    rmdir /s /q "%INSTALL_DIR%\bridge" >nul 2>&1
    del /f /q "%INSTALL_DIR%\*.bat" >nul 2>&1
    echo Nota: A pasta de dados "%INSTALL_DIR%\data" foi preservada para segurança das pesquisas.
)

echo.
echo ====================================================================
echo [OK] PulseLab desinstalado com sucesso.
echo ====================================================================
echo.
pause
