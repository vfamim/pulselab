#Requires -Version 5.1
# ==============================================================================
# PulseLab - Importador Administrativo (Aviso de Redirecionamento de Segurança)
# ==============================================================================

[CmdletBinding()]
param(
    [string]$SourcePath = "",
    [string]$SupabaseUrl = "",
    [string]$SupabaseKey = ""
)

Write-Host ""
Write-Host "====================================================================" -ForegroundColor Red
Write-Host "  PULSELAB - IMPORTADOR POWERSHELL DESABILITADO POR SEGURANCA" -ForegroundColor Red
Write-Host "====================================================================" -ForegroundColor Red
Write-Host ""
Write-Host "A importacao administrativa remota exige garantias criptograficas completas:" -ForegroundColor Yellow
Write-Host "  1. Autenticacao com credencial operacional (service_role ou JWT de pesquisador)." -ForegroundColor Yellow
Write-Host "     O envio com chave anonima (anon) foi revogado pelo RLS no banco de dados." -ForegroundColor Yellow
Write-Host "  2. Validacao criptografica estrita de manifesto SHA-256 da coleta de campo." -ForegroundColor Yellow
Write-Host "  3. Consolidacao transacional segura em SQLite local com gestao de quarentena." -ForegroundColor Yellow
Write-Host "  4. Resolucao deterministica de idempotencia sem falsos positivos em lotes." -ForegroundColor Yellow
Write-Host ""
Write-Host "Para importar e consolidar os dados com seguranca, utilize o importador oficial:" -ForegroundColor Cyan
Write-Host "  python scripts/importar-para-supabase.py --source <pasta> [--no-cloud]" -ForegroundColor White
Write-Host ""
Write-Host "Para ajuda ou parametros:" -ForegroundColor Gray
Write-Host "  python scripts/importar-para-supabase.py --help" -ForegroundColor Gray
Write-Host "====================================================================" -ForegroundColor Red
Write-Host ""
exit 1
