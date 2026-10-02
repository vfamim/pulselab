@echo off
setlocal
title PulseLab - Importar Dados para o Supabase
chcp 65001 >nul 2>&1

echo ====================================================================
echo   PULSELAB — IMPORTADOR DE DADOS OFFLINE PARA O BANCO DE DADOS
echo ====================================================================
echo.
echo Conecte seu computador a internet e insira o pendrive com os dados...
echo.

set "SCRIPT_DIR=%~dp0"
set "PY_SCRIPT=%SCRIPT_DIR%scripts\importar-para-supabase.py"
set "PS_SCRIPT=%SCRIPT_DIR%scripts\importar-para-supabase.ps1"

:: 1. Tentar executar via Python se disponível (consolida em SQLite + Supabase)
where python >nul 2>&1
if %ERRORLEVEL% equ 0 (
    if exist "%PY_SCRIPT%" (
        echo [OK] Python detectado. Executando consolidador SQLite e importador Supabase...
        echo.
        python "%PY_SCRIPT%" %*
        goto :FINAL
    )
)

where py >nul 2>&1
if %ERRORLEVEL% equ 0 (
    if exist "%PY_SCRIPT%" (
        echo [OK] Python Launcher detectado. Executando consolidador SQLite e importador Supabase...
        echo.
        py "%PY_SCRIPT%" %*
        goto :FINAL
    )
)

:: 2. Fallback para PowerShell nativo (zero dependências)
echo [AVISO] Python nao encontrado. Usando importador nativo do Windows PowerShell...
echo.
if exist "%PS_SCRIPT%" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" %*
    goto :FINAL
) else (
    echo [ERRO] Nem o script Python nem o script PowerShell foram localizados!
    pause
    exit /b 1
)

:FINAL
exit /b %ERRORLEVEL%
