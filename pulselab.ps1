#Requires -Version 5.1
# Test-only launcher; never updates from main or reuses production's port/profile.
[CmdletBinding()]
param([switch]$DebugMode)
$ErrorActionPreference = "Stop"
$bridge = Join-Path $PSScriptRoot "bridge\pulselab-bridge.ps1"
$app = Join-Path $PSScriptRoot "app\alunos"
if (-not (Test-Path -LiteralPath $app)) { $app = Join-Path $PSScriptRoot "alunos" }
if (-not (Test-Path -LiteralPath $bridge) -or -not (Test-Path -LiteralPath (Join-Path $app "index.html"))) {
    throw "Pacote de teste incompleto. Extraia todo o ZIP antes de iniciar."
}
$running = $null
try { $running = Invoke-RestMethod -Uri "http://127.0.0.1:43128/health" -TimeoutSec 1 } catch {}
if ($running -and ($running.environment -ne "test" -or $running.version -ne "2.0.0-test.1")) { throw "A porta de teste esta ocupada por outro aplicativo ou outra versao. Feche o servidor anterior antes de testar." }
if (-not $running) {
    Start-Process powershell.exe -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", ('"' + $bridge + '"'), "-AppRoot", ('"' + $app + '"'))
    $ready = $false
    for ($i = 0; $i -lt 20; $i++) {
        try {
            $health = Invoke-RestMethod -Uri "http://127.0.0.1:43128/health" -TimeoutSec 1
            if ($health.environment -eq "test") { $ready = $true; break }
        } catch {}
        Start-Sleep -Milliseconds 250
    }
    if (-not $ready) { throw "Servidor local de teste nao iniciou. Confira a janela do PowerShell." }
}
Start-Process "http://127.0.0.1:43128/alunos/"
