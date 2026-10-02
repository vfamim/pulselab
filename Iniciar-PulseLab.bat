@echo off
title PulseLab - Oficina de Robotica
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0pulselab.ps1"
if errorlevel 1 pause
