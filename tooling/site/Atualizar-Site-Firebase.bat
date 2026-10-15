@echo off
chcp 65001 >nul
cd /d "%~dp0..\.."
title PulseLab - Atualizar Página no Firebase Hosting
echo ====================================================================
echo             PULSELAB - DEPLOY NO FIREBASE HOSTING
echo ====================================================================
echo.
echo [1/3] Compilando PWA dos alunos (Vite)...
cd apps\student-pwa
call npm run build
cd ..\..
echo.
python tooling\release\build-installer.py --output dist\PulseLab-3.0.8-Windows.zip

echo [3/3] Montando pasta publica (somente arquivos permitidos)...
python tooling\site\build-hosting.py
if errorlevel 1 (
    echo [ERRO] Falha ao montar hosting-dist. Deploy cancelado.
    pause
    exit /b 1
)
echo Publicando site e PWA no Firebase Hosting...
call npx firebase-tools deploy --only hosting
echo.
echo ====================================================================
echo Processo concluido! Acesse: https://pulselab-robotica-edu.web.app
echo ====================================================================
pause
