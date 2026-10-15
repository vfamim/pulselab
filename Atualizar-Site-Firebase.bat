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
python installer\build-installer.py --output instalador\downloads\PulseLab-3.0.3-Windows.zip

echo [3/3] Montando pasta publica (somente arquivos permitidos)...
python scripts\build-hosting.py
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
