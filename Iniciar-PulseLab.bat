@echo off
chcp 65001 >nul
title PulseLab — Atividade dos Alunos
echo ====================================================================
echo                   PULSELAB — INICIAR OFICINA
echo ====================================================================
echo.
echo Iniciando servidor local do PulseLab e abrindo navegador...
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

:: Aguardar brevemente para o HttpListener inicializar
powershell -NoProfile -Command "Start-Sleep -Milliseconds 800" >nul 2>&1

echo Abrindo interface dos alunos no navegador padrão...
start http://127.0.0.1:43127/alunos/

echo.
echo [OK] O PulseLab está ativo em http://127.0.0.1:43127/alunos/
echo Os alertas de 20 min e 40 min tocarão automaticamente no computador.
echo.
timeout /t 5 >nul
