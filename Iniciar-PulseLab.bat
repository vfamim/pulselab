@echo off
title PulseLab TESTE - Protocolo v2
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0pulselab.ps1"
if errorlevel 1 pause
