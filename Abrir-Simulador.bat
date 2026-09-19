@echo off
chcp 65001 >nul
title PulseLab - Simulador e Modo Laboratório
echo ====================================================================
echo             PULSELAB - SIMULADOR & MODO LABORATÓRIO
echo ====================================================================
echo.
echo Iniciando servidor local do PulseLab e abrindo simulador...
echo.

set "BASE_DIR=%~dp0"
if not exist "%BASE_DIR%bridge\pulselab-bridge.ps1" (
    if exist "%LOCALAPPDATA%\PulseLab\bridge\pulselab-bridge.ps1" (
        set "BASE_DIR=%LOCALAPPDATA%\PulseLab\"
    )
)

set "APP_PATH=%BASE_DIR%app\alunos"
if not exist "%APP_PATH%" (
    if exist "%BASE_DIR%alunos" (
        set "APP_PATH=%BASE_DIR%alunos"
    )
)

start "" /B powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%BASE_DIR%bridge\pulselab-bridge.ps1" -Port 43127 -AppRoot "%APP_PATH%" -DataDir "%LOCALAPPDATA%\PulseLab\data"

:: Aguardar o servidor local inicializar com confirmacao ativa
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "for ($i=0; $i -lt 15; $i++) { try { $r = [System.Net.WebRequest]::Create('http://127.0.0.1:43127/health'); $r.Timeout = 400; $res = $r.GetResponse(); if ($res) { $res.Close(); break } } catch { Start-Sleep -Milliseconds 250 } }" >nul 2>&1

:: Abrir interface Web em modo Laboratorio diretamente no navegador padrao
start http://127.0.0.1:43127/alunos/?lab=1

echo.
echo [OK] Simulador ativo em http://127.0.0.1:43127/alunos/?lab=1
echo Controles rapidos e simulacao de checkpoints disponiveis.
echo.
timeout /t 3 >nul
