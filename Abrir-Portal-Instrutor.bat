@echo off
chcp 65001 >nul
title PulseLab - Portal do Instrutor
echo Abrindo Portal do Instrutor no navegador...
start "" "%~dp0instrutor\index.html"
