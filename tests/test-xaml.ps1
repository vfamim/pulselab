Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$code = Get-Content .\agent\pulselab-agent.ps1 -Raw
$xamlMatches = [regex]::Matches($code, '(?s)\$xaml\s*=\s*@"(.*?)"@')

Write-Host "Total de templates XAML encontrados no agente: $($xamlMatches.Count)" -ForegroundColor Cyan

$i = 1
foreach ($m in $xamlMatches) {
    $x = $m.Groups[1].Value
    # Substitui variaveis interpoladas para mock valido
    $x = $x -replace '\$installationSummaryXaml', 'Sede: A | Escola: B'
    $x = $x -replace '\$sessionSummaryXaml', 'Oficina: C | Turma: D'
    $x = $x -replace '\$roleLabelXaml', 'Aluno 1 (Computador)'
    $x = $x -replace '\$subtextXaml', 'Responda individualmente'
    $x = $x -replace '\$priorRoboticsXaml', 'Antes de hoje, montou robo?'
    $x = $x -replace '\$selfEfficacyXaml', 'Consigo programar missao.'
    $x = $x -replace '\$IntervalMark', '20'
    $x = $x -replace '\$mentalEffortXaml', 'Esforco mental?'
    $x = $x -replace '\$progressStateXaml', 'Como a dupla esta avancando?'
    $x = $x -replace '\$collaborationXaml', 'Decidimos juntos?'
    $x = $x -replace '\$collabVisibility', 'Visible'
    $x = $x -replace '\$participantALabelXaml', 'Aluno 1 (Computador)'
    $x = $x -replace '\$participantBLabelXaml', 'Aluno 2 (Montagem)'
    $x = $x -replace '\$postUnderstandingXaml', 'Entendi o programa?'
    $x = $x -replace '\$postAffectXaml', 'Como voce se sentiu?'
    $x = $x -replace '\$postReturnXaml', 'Participaria novamente?'
    $x = $x -replace '\$school', 'Escola'
    $x = $x -replace '\$site', 'Sede'
    $x = $x -replace '\$class', 'Turma'
    $x = $x -replace '\$startedTime', '08:30'
    $x = $x -replace '\$cpTextEsc', 'Checkpoints: 20 min'

    try {
        $reader = New-Object Xml.XmlNodeReader ([xml]$x)
        $win = [Windows.Markup.XamlReader]::Load($reader)
        Write-Host "  [OK] Template $i carregado: $($win.Title) (Dimensões: $($win.Width)x$($win.Height))" -ForegroundColor Green
    }
    catch {
        Write-Host "  [ERRO] Template $i falhou: $($_.Exception.Message)" -ForegroundColor Red
        throw $_
    }
    $i++
}

Write-Host "`nTodos os $($xamlMatches.Count) templates XAML modernos foram validados com 100% de sucesso!" -ForegroundColor Green
