@echo off
powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0pulselab.ps1" %*
