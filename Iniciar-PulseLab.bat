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
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%BASE_DIR%pulselab.ps1"
