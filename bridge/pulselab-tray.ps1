# ==============================================================================
# PulseLab — Ícone na bandeja do Windows (área de notificação)
# ==============================================================================
# Mostra que o PulseLab está ligado sem abrir janelas durante a aula.
# Menu (clique direito), para o instrutor:
#   - Encerrar turma...         abre o formulário final (pergunta da bancada + avaliação)
#   - Não registrar esta turma  apaga os dados da turma atual e pausa até a próxima aula
#   - Ver situação              resumo do registro neste computador
# Também religa o PulseLab se o servidor local parar de responder.
# Uma única instância por usuário (mutex).
# ==============================================================================

[CmdletBinding()]
param(
    [int]$Port = 43128,
    [string]$InstallRoot = ""
)

$ErrorActionPreference = "Continue"

$mutex = New-Object System.Threading.Mutex($false, "Local\PulseLabTray")
if (-not $mutex.WaitOne(0)) { exit 0 }

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if (-not $InstallRoot) { $InstallRoot = Split-Path -Path $PSScriptRoot -Parent }
$script:BaseUrl = "http://127.0.0.1:$Port"
$script:Failures = 0
$script:LastRestart = [DateTime]::MinValue
$script:LastStatus = $null

function Invoke-TrayApi {
    param([string]$Path, [string]$Method = "GET")
    if ($Method -eq "POST") {
        # O bridge exige a origem local nos métodos que alteram dados.
        return Invoke-RestMethod -Uri "$($script:BaseUrl)$Path" -Method Post -Body "{}" -ContentType "application/json" -Headers @{ Origin = $script:BaseUrl } -TimeoutSec 10
    }
    return Invoke-RestMethod -Uri "$($script:BaseUrl)$Path" -TimeoutSec 3
}

function Open-ClosingForm {
    $url = "$($script:BaseUrl)/alunos/"
    $edgeCandidates = @(
        (Join-Path ${env:ProgramFiles(x86)} "Microsoft\Edge\Application\msedge.exe"),
        (Join-Path $env:ProgramFiles "Microsoft\Edge\Application\msedge.exe"),
        (Join-Path $env:LOCALAPPDATA "Microsoft\Edge\Application\msedge.exe")
    )
    $edgePath = $edgeCandidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
    if ($edgePath) {
        Start-Process -FilePath $edgePath -ArgumentList "--app=`"$url`" --disable-features=Translate,InterestFeedContentSuggestions"
    } else {
        Start-Process $url
    }
}

function Restart-PulseLab {
    # Religa pelo launcher, que trata processo travado e porta ocupada; no máximo uma vez a cada 5 minutos.
    if (([DateTime]::UtcNow - $script:LastRestart).TotalMinutes -lt 5) { return }
    $launcher = Join-Path $InstallRoot "pulselab.ps1"
    if (-not (Test-Path -LiteralPath $launcher)) { return }
    $script:LastRestart = [DateTime]::UtcNow
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$launcher`" -NoUpdate"
}

$greenIconPath = Join-Path $InstallRoot "pulselab-green.ico"
$yellowIconPath = Join-Path $InstallRoot "pulselab-yellow.ico"
$redIconPath = Join-Path $InstallRoot "pulselab-red.ico"
$defaultIconPath = Join-Path $InstallRoot "pulselab.ico"

$script:IconGreen = if (Test-Path -LiteralPath $greenIconPath) { New-Object System.Drawing.Icon($greenIconPath) } else { $null }
$script:IconYellow = if (Test-Path -LiteralPath $yellowIconPath) { New-Object System.Drawing.Icon($yellowIconPath) } else { $null }
$script:IconRed = if (Test-Path -LiteralPath $redIconPath) { New-Object System.Drawing.Icon($redIconPath) } else { $null }

if (-not $script:IconYellow -and (Test-Path -LiteralPath $defaultIconPath)) {
    try { $script:IconYellow = New-Object System.Drawing.Icon($defaultIconPath) } catch {}
}
if (-not $script:IconGreen) { $script:IconGreen = if ($script:IconYellow) { $script:IconYellow } else { [System.Drawing.SystemIcons]::Application } }
if (-not $script:IconYellow) { $script:IconYellow = [System.Drawing.SystemIcons]::Warning }
if (-not $script:IconRed) { $script:IconRed = [System.Drawing.SystemIcons]::Error }

$notify.Icon = $script:IconYellow
$notify.Text = "PulseLab"
$notify.Visible = $true

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$itemClose = $menu.Items.Add("Encerrar turma...")
$itemPause = $menu.Items.Add("Não registrar esta turma")
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
$itemStatus = $menu.Items.Add("Ver situação")
$notify.ContextMenuStrip = $menu

function Set-TrayText([string]$Text) {
    # NotifyIcon.Text aceita no máximo 63 caracteres no .NET Framework.
    if ($Text.Length -gt 63) { $Text = $Text.Substring(0, 63) }
    $notify.Text = $Text
}

function Update-TrayStatus {
    $status = $null
    try { $status = Invoke-TrayApi "/v1/status" } catch { $status = $null }
    if (-not $status) {
        $script:Failures++
        $script:LastStatus = $null
        $notify.Icon = $script:IconRed
        Set-TrayText "PulseLab parado - religando..."
        $itemClose.Enabled = $false
        $itemPause.Enabled = $false
        if ($script:Failures -ge 4) { Restart-PulseLab }
        return
    }
    $script:Failures = 0
    $script:LastStatus = $status
    # Encerrar turma fica sempre habilitado enquanto o PulseLab estiver ativo
    $itemClose.Enabled = $true
    $itemPause.Enabled = [bool]$status.research_active -and -not $status.paused
    $spikeMissing = $status.spike_environment -and $status.spike_environment.status -eq "pasta_nao_encontrada"

    # Selecao do icone por estado:
    # Verde: Bridge ativo, pesquisa ativa, sem erros de pasta SPIKE.
    # Amarelo mostarda: Modo Livre (sem pesquisa), aguardando turma, pausado ou pasta SPIKE nao encontrada.
    # Vermelho: Bridge desligado / parado (tratado acima).
    if ($status.research_active -and -not $status.paused -and -not $spikeMissing) {
        $notify.Icon = $script:IconGreen
    } else {
        $notify.Icon = $script:IconYellow
    }

    if (-not $status.research_active) {
        Set-TrayText "PulseLab ligado - Modo Livre (sem pesquisa)"
    } elseif ($status.paused) {
        Set-TrayText "PulseLab - esta turma não está sendo registrada"
    } elseif ($status.session) {
        $since = ([DateTime]::Parse([string]$status.session.started_at, [System.Globalization.CultureInfo]::InvariantCulture)).ToLocalTime().ToString("HH:mm")
        Set-TrayText "PulseLab - registrando a turma desde $since"
    } else {
        Set-TrayText "PulseLab ligado - aguardando a próxima turma"
    }
}

$itemClose.add_Click({ Open-ClosingForm })

$itemPause.add_Click({
    $answer = [System.Windows.Forms.MessageBox]::Show(
        "Use quando alguém da turma (ou a família) não quiser participar.`n`nOs dados desta turma neste computador serão apagados e o registro fica pausado até a próxima aula. A bancada continua funcionando normalmente.`n`nNão registrar esta turma?",
        "PulseLab",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question,
        [System.Windows.Forms.MessageBoxDefaultButton]::Button2)
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    try {
        $result = Invoke-TrayApi "/v1/session/pause" "POST"
        $message = "Os dados desta turma foram apagados neste computador. O registro volta na próxima aula."
        if ($result.remote_pending) { $message += " A cópia na nuvem será apagada quando houver internet." }
        $notify.ShowBalloonTip(6000, "PulseLab", $message, [System.Windows.Forms.ToolTipIcon]::Info)
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Não foi possível falar com o PulseLab agora. Tente de novo em 1 minuto.", "PulseLab") | Out-Null
    }
    Update-TrayStatus
})

$itemStatus.add_Click({
    Update-TrayStatus
    $s = $script:LastStatus
    if (-not $s) {
        [System.Windows.Forms.MessageBox]::Show("O PulseLab não está respondendo. Ele será religado automaticamente.", "PulseLab") | Out-Null
        return
    }
    $lines = @("Computador: $(if ($s.machine_label) { $s.machine_label } else { 'sem identificação' })")
    if (-not $s.research_active) {
        $lines += "Registro de pesquisa: desligado neste computador."
    } elseif ($s.paused) {
        $lines += "Esta turma não está sendo registrada (pedido do instrutor)."
    } elseif ($s.session) {
        $lines += "Turma registrada há $([Math]::Round([double]$s.session.elapsed_min)) min."
        $lines += "Programas SPIKE detectados: $($s.session.telemetry_events)."
    } else {
        $lines += "Aguardando a próxima turma (começa no primeiro programa salvo)."
    }
    if ($s.spike_environment -and $s.spike_environment.status -eq "pasta_nao_encontrada") {
        $lines += "Atenção: a pasta de projetos do LEGO SPIKE não foi encontrada."
    }
    $lines += "Registros esperando envio: $($s.pending_sync)."
    $lines += if ($s.cloud_enabled) { "Envio para a nuvem: ativo." } else { "Envio para a nuvem: não configurado (use o pendrive)." }
    [System.Windows.Forms.MessageBox]::Show(($lines -join "`n"), "PulseLab $($s.version)") | Out-Null
})

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 15000
$timer.add_Tick({ Update-TrayStatus })
$timer.Start()
Update-TrayStatus

try {
    [System.Windows.Forms.Application]::Run()
} finally {
    $timer.Stop()
    $notify.Visible = $false
    $notify.Dispose()
    $mutex.ReleaseMutex()
}
