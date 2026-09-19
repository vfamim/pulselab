@echo off
chcp 65001 >nul
title PulseLab - Atualizar Página no Firebase Hosting
echo ====================================================================
echo             PULSELAB - DEPLOY NO FIREBASE HOSTING
echo ====================================================================
echo.
echo [1/3] Compilando PWA dos alunos (Vite)...
cd web\agent-simulator
call npm run build
cd ..\..
echo.
echo [2/3] Gerando pacotes ZIP e checksums...
python installer\build-installer.py --output instalador\downloads\PulseLab-1.9.0-Windows.zip
echo.
echo [3/3] Publicando site e PWA no Firebase Hosting...
call npx firebase-tools deploy --only hosting
echo.
echo ====================================================================
echo Processo concluido! Acesse: https://pulselab-robotica-edu.web.app
echo ====================================================================
pause
