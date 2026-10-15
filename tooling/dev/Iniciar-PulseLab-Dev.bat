@echo off
chcp 65001 >nul
title PulseLab - Modo de Desenvolvimento / Debug
echo ====================================================================
echo                 PULSELAB - MODO DE DESENVOLVIMENTO
echo ====================================================================
echo.
echo * Executa o agente em modo Debug (sem tempos de espera).
echo * Usa a configuração local e registra eventos na fila offline local.
echo.
cd /d "%~dp0..\.."
echo Montando o pacote em dist-dev\ a partir do repositorio...
python tooling\release\build-installer.py --stage dist-dev
if errorlevel 1 (
    echo [ERRO] Nao foi possivel montar o pacote. Rode "npm run build" em apps\student-pwa antes.
    pause
    exit /b 1
)
echo Iniciando daemon do PulseLab em modo Debug...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "dist-dev\pulselab.ps1" -DebugMode
echo.
echo ====================================================================
echo Sessão do PulseLab finalizada.
echo ====================================================================
pause
