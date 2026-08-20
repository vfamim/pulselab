@echo off
chcp 65001 >nul
title PulseLab - Teste Rapido de Producao
echo ====================================================================
echo                 PULSELAB - TESTE RAPIDO DE PRODUCAO
echo ====================================================================
echo.
echo * Trata minutos de checkpoint como SEGUNDOS (20s e 40s).
echo * Abre a tela de contexto, termos, checkpoints e encerramento.
echo.
echo Iniciando PulseLab em modo de teste rápido...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0pulselab.ps1" -ProductionTest
echo.
echo ====================================================================
echo Teste rapido concluido.
echo ====================================================================
pause
