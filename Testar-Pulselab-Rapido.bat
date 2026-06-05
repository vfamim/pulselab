@echo off
title Pulselab - Modo de Demonstracao Rapida
echo ====================================================================
echo                 PULSELAB - MODO DE TESTE RAPIDO
echo ====================================================================
echo.
echo * Este modo trata os minutos da configuracao como SEGUNDOS.
echo * Os pop-ups de Carga Cognitiva abriraom aos 20s e 40s de teste.
echo * Ao fechar ou concluir, as respostas serao enviadas ao Supabase.
echo.
echo [!] Pressione qualquer tecla para iniciar a simulacao...
pause > nul
echo.
echo Iniciando daemon do Pulselab...
powershell.exe -ExecutionPolicy Bypass -File "%~dp0pulselab.ps1" -ProductionTest
echo.
echo ====================================================================
echo Simulacao do Pulselab concluida.
echo ====================================================================
pause
