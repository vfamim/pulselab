@echo off
chcp 65001 >nul
title PulseLab - Dashboard
echo Abrindo Dashboard de Pesquisa no navegador...
start "" "%~dp0dashboard\index.html"
