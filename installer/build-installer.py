#!/usr/bin/env python3
import os
import sys
import base64
import argparse
import json

def load_env(env_path):
    env_vars = {}
    if os.path.exists(env_path):
        print(f"Lendo variaveis do arquivo .env em: {env_path}")
        with open(env_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if "=" in line:
                    key, val = line.split("=", 1)
                    key = key.strip()
                    val = val.strip().strip("'\"")  # Remove aspas simples/duplas
                    env_vars[key] = val
    return env_vars

def main():
    parser = argparse.ArgumentParser(description="Gera o instalador standalone .bat para o Pulselab")
    parser.add_argument("--url", help="URL do Supabase")
    parser.add_argument("--key", help="Anon Key do Supabase")
    parser.add_argument("--output", help="Caminho do arquivo .bat de saida")
    parser.add_argument("--site-id", help="Sede/cidade que ficara vinculada a instalacao")
    parser.add_argument("--regional-hub", help="Polo ou regional da instalacao")
    parser.add_argument("--school-code", help="Codigo da escola da instalacao")
    parser.add_argument("--zip", action="store_true", help="Gerar pacote .zip pronto para envio com o instalador .bat e instrucoes")
    args = parser.parse_args()

    # Resolver diretorios do projeto
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.abspath(os.path.join(script_dir, ".."))
    
    agent_path = os.path.join(repo_root, "agent", "pulselab-agent.ps1")
    config_path = os.path.join(repo_root, "config", "config.json")

    # Tentar carregar do .env se existir
    env_file = os.path.join(repo_root, ".env")
    dotenv = load_env(env_file)

    # Obter credenciais (Arg > .env > OS env)
    url = args.url or dotenv.get("PULSELAB_URL") or dotenv.get("SUPABASE_URL") or os.environ.get("PULSELAB_URL")
    key = args.key or dotenv.get("PULSELAB_KEY") or dotenv.get("SUPABASE_KEY") or dotenv.get("SUPABASE_ANON_KEY") or os.environ.get("PULSELAB_KEY")

    if not url or not key:
        print("--- Gerador de Instalador Standalone Pulselab ---")
        if not url:
            url = input("Digite a URL do Supabase (ex: https://xxx.supabase.co): ").strip()
        if not key:
            key = input("Digite a Anon Key (Key publica) do Supabase: ").strip()

    if not url or not key:
        print("Erro: A URL e a Anon Key sao obrigatorias.")
        sys.exit(1)

    url = url.strip().strip("'\"")
    key = key.strip().strip("'\"")

    # Validacoes basicas
    if not url.startswith("http"):
        print("Erro: A URL do Supabase deve comecar com http:// ou https://")
        sys.exit(1)

    # Verificar arquivos de entrada
    if not os.path.exists(agent_path):
        print(f"Erro: Arquivo do agente nao encontrado em: {agent_path}")
        sys.exit(1)
    if not os.path.exists(config_path):
        print(f"Erro: Arquivo de configuracao nao encontrado em: {config_path}")
        sys.exit(1)

    print("Lendo arquivos do projeto...")
    with open(agent_path, "rb") as f:
        agent_bytes = f.read()
    agent_b64 = base64.b64encode(agent_bytes).decode("ascii")

    with open(config_path, "rb") as f:
        config_bytes = f.read()

    identity_overrides = {
        "site_id": args.site_id,
        "regional_hub": args.regional_hub,
        "school_code": args.school_code,
        "supabase_url": url,
        "supabase_key": key,
    }
    selected_overrides = {
        field: value.strip()
        for field, value in identity_overrides.items()
        if value and value.strip()
    }
    if selected_overrides:
        invalid_fields = [
            field
            for field, value in selected_overrides.items()
            if value.upper().startswith("CONFIGURE_")
        ]
        if invalid_fields:
            print(
                "Erro: valores pre-configurados nao podem usar CONFIGURE_: "
                + ", ".join(invalid_fields)
            )
            sys.exit(1)

        packaged_config = json.loads(config_bytes.decode("utf-8-sig"))
        packaged_config.update(selected_overrides)
        config_bytes = (
            json.dumps(packaged_config, ensure_ascii=False, indent=2) + "\n"
        ).encode("utf-8")
        print(
            "Identidade pre-configurada no instalador: "
            + ", ".join(f"{field}={value}" for field, value in selected_overrides.items())
        )

    config_b64 = base64.b64encode(config_bytes).decode("ascii")

    # Definir saida padrao
    output_path = args.output or os.path.join(repo_root, "Install-Pulselab.bat")

    # Template do batch
    batch_template = f"""@echo off
set "BATCH_PATH=%~f0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=$env:BATCH_PATH; iex ((Get-Content -LiteralPath $p -Raw) -split '(?ms)^#PS_START#')[1]"
exit /b %errorlevel%
#PS_START#
$ErrorActionPreference = "Stop"

function Write-InstallerLog {{
    param([string]$Level, [string]$Message)
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Write-Host "[$timestamp] [$Level] $Message"
}}

Write-InstallerLog "INFO" "Pulselab Standalone Installer"
Write-InstallerLog "INFO" "----------------------------------------"

# 1. Verificar assemblies WPF
try {{
    Write-InstallerLog "INFO" "Verificando dependencias do WPF/XAML..."
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase -ErrorAction Stop
    Write-InstallerLog "INFO" "WPF verificado com sucesso."
}} catch {{
    Write-InstallerLog "ERROR" "WPF/PresentationFramework nao disponivel nesta maquina."
    Write-InstallerLog "ERROR" "Este aplicativo requer Windows 10/11 com ambiente desktop."
    Read-Host "Pressione Enter para sair..."
    exit 1
}}

# 2. Configurar credenciais
$supabaseUrl = "{url}"
$supabaseKey = "{key}"

Write-InstallerLog "INFO" "Configurando credenciais do Supabase..."
[System.Environment]::SetEnvironmentVariable("PULSELAB_URL", $supabaseUrl, "User")
[System.Environment]::SetEnvironmentVariable("PULSELAB_KEY", $supabaseKey, "User")

# 3. Criar pastas de instalacao
$targetDir = "C:\\Users\\Public\\Pulselab"
$agentDir = $targetDir
$configDir = Join-Path $targetDir "config"
$cacheDir = Join-Path $targetDir "cache"

Write-InstallerLog "INFO" "Criando pastas em $targetDir..."
$null = New-Item -ItemType Directory -Path $agentDir -Force
$null = New-Item -ItemType Directory -Path $configDir -Force
$null = New-Item -ItemType Directory -Path $cacheDir -Force

# 4. Extrair script do agente
$agentB64 = "{agent_b64}"
$agentPath = Join-Path $agentDir "pulselab-agent.ps1"
Write-InstallerLog "INFO" "Extraindo script do agente..."
$agentBytes = [System.Convert]::FromBase64String($agentB64)
[System.IO.File]::WriteAllBytes($agentPath, $agentBytes)

# 5. Extrair arquivo de configuracao
$configB64 = "{config_b64}"
$configPath = Join-Path $configDir "config.json"
Write-InstallerLog "INFO" "Extraindo arquivo de configuracao..."
$configBytes = [System.Convert]::FromBase64String($configB64)
[System.IO.File]::WriteAllBytes($configPath, $configBytes)

# 6. Criar atalhos na Area de Trabalho e no Menu Iniciar
$shortcutName = "Iniciar Pulselab - Oficina de Robotica.lnk"
$desktopDir = [System.Environment]::GetFolderPath("Desktop")
$startMenuDir = [System.Environment]::GetFolderPath("Programs")

# Remover atalho legado de inicializacao automatica se existir
$startupDir = [System.Environment]::GetFolderPath("Startup")
$legacyShortcut = Join-Path $startupDir "Pulselab.lnk"
if (Test-Path $legacyShortcut) {{
    Write-InstallerLog "INFO" "Removendo atalho de inicializacao automatica antigo..."
    Remove-Item $legacyShortcut -Force -ErrorAction SilentlyContinue
}}

Write-InstallerLog "INFO" "Criando atalhos na Area de Trabalho e no Menu Iniciar..."
$locations = @($desktopDir, $startMenuDir) | Where-Object {{ -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path $_) }}
foreach ($locDir in $locations) {{
    $shortcutPath = Join-Path $locDir $shortcutName
    try {{
        $wshell = New-Object -ComObject WScript.Shell
        $shortcut = $wshell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = "powershell.exe"
        $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$agentPath`""
        $shortcut.WorkingDirectory = $agentDir
        $shortcut.WindowStyle = 7 # Minimized/Hidden
        $shortcut.Description = "Iniciar Pulselab - Oficina de Robotica"
        $shortcut.IconLocation = "%SystemRoot%\\System32\\WindowsPowerShell\\v1.0\\powershell.exe,0"
        $shortcut.Save()
        Write-InstallerLog "INFO" "Atalho criado com sucesso: $shortcutPath"
    }} catch {{
        Write-InstallerLog "ERROR" "Erro ao criar o atalho em $shortcutPath: $_"
    }}
}}

Write-InstallerLog "INFO" "----------------------------------------"
Write-InstallerLog "INFO" "Instalacao concluida com sucesso!"
Write-InstallerLog "INFO" "O aplicativo pode ser iniciado pelos atalhos da Area de Trabalho ou Menu Iniciar."
Write-InstallerLog "INFO" "----------------------------------------"
Read-Host "Pressione Enter para finalizar..."
"""

    if args.zip or output_path.lower().endswith(".zip"):
        import zipfile
        if output_path.lower().endswith(".zip"):
            zip_path = output_path
            bat_path = output_path[:-4] + ".bat"
        else:
            bat_path = output_path
            zip_path = os.path.splitext(output_path)[0] + ".zip"

        print(f"Escrevendo instalador standalone em: {bat_path}")
        with open(bat_path, "w", encoding="utf-8", newline="\r\n") as f:
            f.write(batch_template)

        instructions_content = (
            "====================================================================\r\n"
            "               PULSELAB - INSTALADOR DA OFICINA\r\n"
            "====================================================================\r\n\r\n"
            "Este arquivo contem o instalador autonomo do PulseLab para esta sede.\r\n\r\n"
            "COMO INSTALAR NAS MAQUINAS DAS ESCOLAS:\r\n"
            "1. Extraia o conteudo deste arquivo ZIP em uma pasta ou pendrive.\r\n"
            "2. Na maquina do aluno/oficina, de DOIS CLIQUES no arquivo .bat (ex: Install-Pulselab-*.bat).\r\n"
            "3. Aguarde a mensagem de conclusao. Nao sao necessarios privilegios de Administrador.\r\n"
            "4. Um atalho chamado 'Iniciar Pulselab - Oficina de Robotica' sera criado na Area de Trabalho.\r\n\r\n"
            "====================================================================\r\n"
        )

        bat_filename = os.path.basename(bat_path)
        print(f"Criando pacote .zip pronto para envio em: {zip_path}")
        with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
            zf.write(bat_path, arcname=bat_filename)
            zf.writestr("INSTRUCOES.txt", instructions_content)

        # Se o usuario pediu .zip diretamente como output, podemos remover o .bat solto temporario
        if output_path.lower().endswith(".zip") and os.path.exists(bat_path):
            os.remove(bat_path)

        print("Pacote .zip gerado com sucesso!")
    else:
        print(f"Escrevendo instalador standalone em: {output_path}")
        with open(output_path, "w", encoding="utf-8", newline="\r\n") as f:
            f.write(batch_template)
        print("Instalador gerado com sucesso!")

if __name__ == "__main__":
    main()
