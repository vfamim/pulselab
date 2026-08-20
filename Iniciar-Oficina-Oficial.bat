@echo off
chcp 65001 >nul
title PulseLab - Execução Oficial da Oficina
echo ====================================================================
echo                 PULSELAB - EXECUÇÃO OFICIAL DA OFICINA
echo ====================================================================
echo.
echo * Modo Oficial: Temporizadores reais (Checkpoints em 20 min e 40 min).
echo * Acompanhamento em segundo plano na bandeja do sistema.
echo * Registro completo de telemetria e respostas dos estudantes.
echo.
echo Iniciando agente PulseLab...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0pulselab.ps1"
echo.
echo ====================================================================
echo Oficina finalizada com sucesso.
echo ====================================================================
pause
