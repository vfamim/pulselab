@echo off
chcp 65001 >nul
title PulseLab - Suite de Testes
echo ============================================================
echo Executando testes automatizados de runtime e AST...
echo ============================================================
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tests\test-agent-runtime.ps1"
echo.
echo ============================================================
echo Validando todos os 10 templates visuais XAML modernos...
echo ============================================================
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tests\test-xaml.ps1"
echo.
pause
