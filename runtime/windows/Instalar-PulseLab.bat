@echo off
chcp 65001 >nul
title PulseLab - Instalador Local (v3.3.1)
echo ====================================================================
echo                   PULSELAB - INSTALADOR OFFLINE (v3.3.1)

echo ====================================================================
echo.
echo * Zero dependencia de internet.
echo * Nao requer privilegios de administrador.
echo * Preserva dados locais de sessoes anteriores.
echo.

set "INSTALL_DIR=%LOCALAPPDATA%\PulseLab"
set "SRC_DIR=%~dp0arquivos\"

:: Aberto direto de dentro do ZIP, o Windows roda so este arquivo, sem a pasta arquivos.
if not exist "%SRC_DIR%pulselab.ps1" goto :NAO_EXTRAIDO

echo [1/3] Preparando a pasta de instalacao:
echo       %INSTALL_DIR%
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"

echo [2/3] Copiando o PulseLab...
xcopy "%SRC_DIR%*" "%INSTALL_DIR%\" /E /I /Y /Q >nul
if errorlevel 1 (
    echo.
    echo [ERRO] Nao foi possivel copiar os arquivos para %INSTALL_DIR%.
    echo        Feche o PulseLab ^(icone perto do relogio ^> Fechar PulseLab^) e rode o instalador de novo.
    echo.
    pause
    exit /b 1
)

echo.
echo Identificacao desta maquina:
set "PL_LABEL="
set /p "PL_LABEL=Nome da bancada (ex.: PC-01 ou PET-LAB1-PC03) [Enter para padrao]: "

echo.
:: A coleta de pesquisa so liga pelo pacote do polo (provisionamento.json); nada digitado aqui a liga.
echo Polo desta maquina (so identificacao; ignorado se o pacote do polo ja define):
set "PL_POLO="
set /p "PL_POLO=Codigo do polo ou local (ex.: JUA, PET) [Enter para pular]: "

set "PL_REGIONAL="
set /p "PL_REGIONAL=Cidade ou regional (ex.: Juazeiro) [Enter para pular]: "

powershell -NoProfile -ExecutionPolicy Bypass -Command "& { . (Join-Path $env:LOCALAPPDATA 'PulseLab\pulselab-installation.ps1'); $i = Initialize-PulseLabInstallation -InstallRoot (Join-Path $env:LOCALAPPDATA 'PulseLab') -MachineLabel $env:PL_LABEL -Polo $env:PL_POLO -Regional $env:PL_REGIONAL; Write-Host ('      Maquina: ' + $i.machine_label); if ($i.research_collection_enabled -eq $true) { Write-Host ('      Coleta de pesquisa ATIVA - polo ' + $i.site_id + ', CAAE ' + $i.research_authorization_version) } else { Write-Host '      Coleta de pesquisa DESLIGADA neste computador.' } }"
echo.

echo [3/3] Criando atalho silencioso na Area de Trabalho com icone oficial...
:: Limpar atalhos ou pastas de versoes legadas (v3.3.1)
if exist "%INSTALL_DIR%\app\agent" rd /s /q "%INSTALL_DIR%\app\agent" >nul 2>&1
if exist "%INSTALL_DIR%\app\pulselab-agent.ps1" del /f /q "%INSTALL_DIR%\app\pulselab-agent.ps1" >nul 2>&1
if exist "%INSTALL_DIR%\Install-PulseLab.ps1" del /f /q "%INSTALL_DIR%\Install-PulseLab.ps1" >nul 2>&1
if exist "%INSTALL_DIR%\Desinstalar-PulseLab.bat" del /f /q "%INSTALL_DIR%\Desinstalar-PulseLab.bat" >nul 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -Command "$desktop = [Environment]::GetFolderPath('Desktop'); $startup = [Environment]::GetFolderPath('Startup'); Remove-Item -LiteralPath (Join-Path $desktop 'Iniciar Pulselab - Oficina de Robotica.lnk') -Force -ErrorAction SilentlyContinue; Remove-Item -LiteralPath (Join-Path $startup 'PulseLab.lnk') -Force -ErrorAction SilentlyContinue" >nul 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ws = New-Object -ComObject WScript.Shell; $s = $ws.CreateShortcut([System.IO.Path]::Combine([Environment]::GetFolderPath('Desktop'), 'PulseLab - Iniciar Oficina.lnk')); $s.TargetPath = [System.IO.Path]::Combine($env:SystemRoot, 'System32\wscript.exe'); $s.Arguments = '\"' + [System.IO.Path]::Combine($env:LOCALAPPDATA, 'PulseLab\iniciar-silencioso.vbs') + '\"'; $s.WorkingDirectory = [System.IO.Path]::Combine($env:LOCALAPPDATA, 'PulseLab'); $s.IconLocation = [System.IO.Path]::Combine($env:LOCALAPPDATA, 'PulseLab\pulselab.ico') + ',0'; $s.Description = 'Iniciar oficina de robotica do PulseLab'; $s.Save()" >nul 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ws = New-Object -ComObject WScript.Shell; $s = $ws.CreateShortcut([System.IO.Path]::Combine([Environment]::GetFolderPath('Desktop'), 'PulseLab - Exportar Dados.lnk')); $s.TargetPath = [System.IO.Path]::Combine($env:LOCALAPPDATA, 'PulseLab\Exportar-Dados-Pendrive.bat'); $s.WorkingDirectory = [System.IO.Path]::Combine($env:LOCALAPPDATA, 'PulseLab'); $s.IconLocation = [System.IO.Path]::Combine($env:LOCALAPPDATA, 'PulseLab\pulselab.ico') + ',0'; $s.Description = 'Copiar os registros da oficina para o pendrive'; $s.Save()" >nul 2>&1
:: Atalho "Questionario PulseLab" (.url) para reabrir a aba do questionario do fim da aula; o nome leva acento, montado no PowerShell.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$name = 'Question' + [char]0x00E1 + 'rio PulseLab.url'; $ico = [System.IO.Path]::Combine($env:LOCALAPPDATA, 'PulseLab\pulselab.ico'); $lines = @('[InternetShortcut]', 'URL=http://127.0.0.1:43128/alunos/', ('IconFile=' + $ico), 'IconIndex=0'); [System.IO.File]::WriteAllLines([System.IO.Path]::Combine([Environment]::GetFolderPath('Desktop'), $name), [string[]]$lines, [System.Text.Encoding]::Default)" >nul 2>&1

:: Inicia com o Windows: a sessao da turma abre quando o computador liga e o icone fica na bandeja.
:: Os computadores sao dedicados as oficinas; use --sem-inicializacao para nao criar o atalho.
if /i not "%1"=="--sem-inicializacao" (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$ws = New-Object -ComObject WScript.Shell; $s = $ws.CreateShortcut([System.IO.Path]::Combine([Environment]::GetFolderPath('Startup'), 'PulseLab.lnk')); $s.TargetPath = [System.IO.Path]::Combine($env:SystemRoot, 'System32\wscript.exe'); $s.Arguments = '\"' + [System.IO.Path]::Combine($env:LOCALAPPDATA, 'PulseLab\iniciar-silencioso.vbs') + '\"'; $s.WorkingDirectory = [System.IO.Path]::Combine($env:LOCALAPPDATA, 'PulseLab'); $s.IconLocation = [System.IO.Path]::Combine($env:LOCALAPPDATA, 'PulseLab\pulselab.ico') + ',0'; $s.Description = 'PulseLab - Inicializacao Automatica'; $s.Save()" >nul 2>&1
    echo [OK] O PulseLab vai iniciar sozinho com o Windows ^(icone na bandeja^).
)

echo.
echo ====================================================================
echo [OK] Instalacao concluida com sucesso!
echo      O PulseLab inicia com o Windows e fica como icone na bandeja.
echo      Para iniciar agora, use o atalho 'PulseLab - Iniciar Oficina'.
echo      Questionario do fim da aula: abre sozinho; para reabrir, use o atalho 'Questionario PulseLab'.
echo      Ao fim da aula: clique direito no icone ^> Encerrar turma.
echo ====================================================================
echo.
pause
exit /b 0

:NAO_EXTRAIDO
echo.
echo [ERRO] O instalador foi aberto sem extrair o arquivo ZIP.
echo.
echo        1. Feche esta janela.
echo        2. Clique com o botao direito no arquivo .zip e escolha "Extrair tudo...".
echo        3. Na pasta extraida, de dois cliques em Instalar-PulseLab.bat.
echo.
pause
exit /b 1
