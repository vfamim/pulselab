@echo off
setlocal
title PulseLab - Exportar Dados para Pendrive
chcp 65001 >nul 2>&1

echo ====================================================================
echo   PULSELAB — EXPORTADOR DE DADOS DA OFICINA (OFFLINE)
echo ====================================================================
echo.
echo Conecte seu pendrive USB e aguarde a copia automatica dos dados...
echo.

set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%scripts\exportar-pendrive.ps1"

if not exist "%PS_SCRIPT%" (
    echo [ERRO] Script scripts\exportar-pendrive.ps1 nao encontrado!
    pause
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%"
exit /b %ERRORLEVEL%
