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
python installer\build-installer.py --output instalador\downloads\PulseLab-2.2.4-Windows.zip
copy /Y instalador\downloads\PulseLab-2.2.4-Windows.zip instalador\downloads\PulseLab-Alunos-Offline-v2.2.4.zip >nul 2>&1
copy /Y instalador\downloads\PulseLab-2.2.4-Windows.zip.sha256 instalador\downloads\PulseLab-Alunos-Offline-v2.2.4.zip.sha256 >nul 2>&1

echo [3/3] Publicando site e PWA no Firebase Hosting...
call npx firebase-tools deploy --only hosting
echo.
echo ====================================================================
echo Processo concluido! Acesse: https://pulselab-robotica-edu.web.app
echo ====================================================================
pause
