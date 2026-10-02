#Requires -Version 5.1
# Smoke-test only the isolated local server, with synthetic requests.
$ErrorActionPreference = "Stop"
$repo = Split-Path $PSScriptRoot -Parent
foreach ($relative in @("pulselab.ps1", "bridge\pulselab-bridge.ps1", "installer\install.ps1")) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $repo $relative), [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw ($errors | Out-String) }
}
$bridge = Join-Path $repo "bridge\pulselab-bridge.ps1"
$app = Join-Path $repo "alunos"
$engine = (Get-Process -Id $PID).Path
$process = Start-Process $engine -PassThru -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", ('"' + $bridge + '"'), "-AppRoot", ('"' + $app + '"'))
try {
    $health = $null
    for ($i = 0; $i -lt 40; $i++) {
        try { $health = Invoke-RestMethod "http://127.0.0.1:43128/health" -TimeoutSec 1; break } catch {}
        Start-Sleep -Milliseconds 250
    }
    if ($health.environment -ne "test" -or $health.cloud_enabled -ne $false) { throw "Test environment health check failed." }
    $page = Invoke-WebRequest "http://127.0.0.1:43128/alunos/" -UseBasicParsing
    if ($page.StatusCode -ne 200 -or $page.Content -notmatch "Teste do protocolo v2") { throw "Test UI not served." }
    if ($page.Headers["Content-Security-Policy"] -notmatch "connect-src 'self'") { throw "Missing network isolation policy." }
    foreach ($case in @(
        @{Path="/health"; Method="POST"; Expected=405},
        @{Path="/collect"; Method="POST"; Expected=405},
        @{Path="/config/config.json"; Method="GET"; Expected=404},
        @{Path="/alunos/%2e%2e%5cVERSION"; Method="GET"; Expected=404}
    )) {
        $status = 0
        try { $status = (Invoke-WebRequest ("http://127.0.0.1:43128" + $case.Path) -Method $case.Method -UseBasicParsing).StatusCode }
        catch { if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode } else { throw } }
        if ($status -ne $case.Expected) { throw ("Unexpected status " + $status + " for " + $case.Path) }
    }
    Write-Host "Portable server checks passed: UI, isolation, no ingestion, no traversal."
} finally {
    if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force }
}
