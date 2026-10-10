@echo off
title PulseLab - Oficina de Robotica
if exist "%~dp0iniciar-silencioso.vbs" (
    start "" wscript.exe "%~dp0iniciar-silencioso.vbs"
    exit /b 0
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0pulselab.ps1"
if errorlevel 1 pause

