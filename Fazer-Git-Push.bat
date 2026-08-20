@echo off
chcp 65001 >nul
title PulseLab - Enviar alterações para o GitHub
echo ====================================================================
echo                 PULSELAB - GIT PUSH PARA O GITHUB
echo ====================================================================
echo.
echo Enviando commits da branch main para o repositorio remoto...
echo.
"%LOCALAPPDATA%\MinGit\cmd\git.exe" push origin main
echo.
if %ERRORLEVEL% equ 0 (
    echo ====================================================================
    echo SUCESSO: Todas as alteracoes foram enviadas para o GitHub!
    echo ====================================================================
) else (
    echo ====================================================================
    echo Ocorreu um erro ou sao necessarias credenciais do GitHub.
    echo ====================================================================
)
pause
