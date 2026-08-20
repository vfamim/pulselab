@echo off
chcp 65001 >nul
title PulseLab - Simulador de Agente
echo Abrindo Simulador do Agente no navegador...
start "" "%~dp0simulador\index.html"
