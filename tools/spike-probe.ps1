# ==============================================================================
# PulseLab — Spike Probe (Diagnóstico e Mapeamento de UI Automation no Windows)
# ==============================================================================
# Script de diagnóstico 100% somente leitura para verificar quais elementos
# acessíveis o LEGO SPIKE App 3 expõe no Windows sem capturar screenshots.
#
# USO:
# powershell -ExecutionPolicy Bypass -File .\tools\spike-probe.ps1
# ==============================================================================

[CmdletBinding()]
param(
    [string]$OutputFile = "spike-probe-report.json",
    [int]$MaxDepth = 4
)

Add-Type -AssemblyName UIAutomationClient -ErrorAction SilentlyContinue
Add-Type -AssemblyName UIAutomationTypes -ErrorAction SilentlyContinue

function Sanitize-Text([string]$text) {
    if (-not $text) { return "" }
    # Remove eventuais caminhos de arquivos e nomes pessoais
    $sanitized = $text -replace '[a-zA-Z]:\\[^"<>|\r\n]+', '<path>'
    $sanitized = $sanitized -replace '\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b', '<email>'
    return $sanitized.Trim()
}

Write-Host "Procurando janela do LEGO SPIKE..." -ForegroundColor Cyan

$spikeProcesses = Get-Process | Where-Object {
    $_.MainWindowHandle -ne [IntPtr]::Zero -and ($_.MainWindowTitle -match "SPIKE|LEGO Education" -or $_.ProcessName -match "SPIKE|Spike")
}

if (-not $spikeProcesses) {
    Write-Warning "Nenhuma janela ativa do LEGO SPIKE encontrada. Abra o aplicativo e tente novamente."
    $emptyReport = @{
        status = "not_found"
        timestamp = [DateTime]::UtcNow.ToString("o")
        elements = @()
    }
    $emptyReport | ConvertTo-Json -Depth 5 | Set-Content -Path $OutputFile -Force
    exit 0
}

$proc = $spikeProcesses[0]
Write-Host "Encontrado: $($proc.ProcessName) (PID: $($proc.Id), Título: $($proc.MainWindowTitle))" -ForegroundColor Green

$rootElement = [System.Windows.Automation.AutomationElement]::FromHandle($proc.MainWindowHandle)
if (-not $rootElement) {
    Write-Error "Não foi possível obter AutomationElement do identificador de janela."
    exit 1
}

$collectedElements = [System.Collections.Generic.List[PSCustomObject]]::new()

function Walk-Element($element, [int]$depth) {
    if ($depth -gt $MaxDepth -or $null -eq $element) { return }

    try {
        $controlType = $element.Current.ControlType.ProgrammaticName
        $automationId = $element.Current.AutomationId
        $name = Sanitize-Text $element.Current.Name
        $className = $element.Current.ClassName
        $bounds = $element.Current.BoundingRectangle

        $elementInfo = [PSCustomObject]@{
            depth = $depth
            control_type = $controlType
            automation_id = $automationId
            class_name = $className
            name_sample = if ($name.Length -gt 40) { $name.Substring(0, 40) + "..." } else { $name }
            has_bounds = ($bounds.Width -gt 0 -and $bounds.Height -gt 0)
        }

        $collectedElements.Add($elementInfo)

        $children = $element.FindAll([System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition)
        foreach ($child in $children) {
            Walk-Element $child ($depth + 1)
        }
    } catch {
        # Ignora nós inacessíveis
    }
}

Write-Host "Mapeando árvore de acessibilidade (profundidade máx: $MaxDepth)..." -ForegroundColor Cyan
Walk-Element $rootElement 0

$report = [PSCustomObject]@{
    status = "success"
    process_name = $proc.ProcessName
    window_title = Sanitize-Text $proc.MainWindowTitle
    timestamp = [DateTime]::UtcNow.ToString("o")
    total_elements = $collectedElements.Count
    elements = $collectedElements
}

$report | ConvertTo-Json -Depth 6 | Set-Content -Path $OutputFile -Force
Write-Host "Relatório gerado com sucesso em: $OutputFile ($($collectedElements.Count) elementos mapeados)." -ForegroundColor Green
