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
echo Iniciando daemon do PulseLab em modo Debug...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0pulselab.ps1" -DebugMode
echo.
echo ====================================================================
echo Sessão do PulseLab finalizada.
echo ====================================================================
pause
