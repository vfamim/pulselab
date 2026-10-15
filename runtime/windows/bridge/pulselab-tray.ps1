# ==============================================================================
# PulseLab — Ícone na bandeja do Windows (área de notificação)
# ==============================================================================
# Mostra que o PulseLab está ligado sem abrir janelas durante a aula.
# Menu (clique direito), para o instrutor:
#   - Encerrar turma...         encerra a turma atual silenciosamente (sem abrir janelas)
#   - Não registrar esta turma  mostra a aula, marca como não autorizada e pausa até a próxima aula
#   - Ver situação              resumo do registro neste computador
#   - Fechar PulseLab           desliga o servidor local e a bandeja até o próximo início
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
[System.Windows.Forms.Application]::EnableVisualStyles()

function Show-ModernDialog {
    param(
        [string]$Message,
        [string]$Title = "PulseLab",
        [System.Windows.Forms.MessageBoxButtons]$Buttons = [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]$Icon = [System.Windows.Forms.MessageBoxIcon]::Information
    )

    $form = New-Object System.Windows.Forms.Form
    $form.Text = $Title
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.ShowInTaskbar = $true
    $form.TopMost = $true
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Regular)
    $form.BackColor = [System.Drawing.Color]::FromArgb(250, 250, 252)

    if ($script:IconYellow) {
        try { $form.Icon = $script:IconYellow } catch {}
    }

    $iconBox = New-Object System.Windows.Forms.PictureBox
    $iconBox.Location = New-Object System.Drawing.Point(22, 22)
    $iconBox.Size = New-Object System.Drawing.Size(38, 38)
    $iconBox.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::StretchImage

    $systemIcon = switch ($Icon) {
        ([System.Windows.Forms.MessageBoxIcon]::Warning)     { [System.Drawing.SystemIcons]::Warning }
        ([System.Windows.Forms.MessageBoxIcon]::Question)    { [System.Drawing.SystemIcons]::Question }
        ([System.Windows.Forms.MessageBoxIcon]::Error)       { [System.Drawing.SystemIcons]::Error }
        default                                              { [System.Drawing.SystemIcons]::Information }
    }
    try { $iconBox.Image = $systemIcon.ToBitmap() } catch {}
    $form.Controls.Add($iconBox)

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Location = New-Object System.Drawing.Point(74, 20)
    $lbl.Text = $Message
    $lbl.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Regular)
    $lbl.ForeColor = [System.Drawing.Color]::FromArgb(30, 41, 59)
    $lbl.AutoSize = $false

    $calcSize = [System.Windows.Forms.TextRenderer]::MeasureText($Message, $lbl.Font, (New-Object System.Drawing.Size(390, 2000)), [System.Windows.Forms.TextFormatFlags]::WordBreak)
    $lbl.Width = 390
    $lbl.Height = [Math]::Max(50, $calcSize.Height + 10)
    $form.Controls.Add($lbl)

    $pnlHeight = 52
    $formWidth = 490
    $formHeight = [Math]::Max(165, $lbl.Location.Y + $lbl.Height + $pnlHeight + 45)
    $form.ClientSize = New-Object System.Drawing.Size($formWidth, $formHeight)

    $pnl = New-Object System.Windows.Forms.Panel
    $pnl.Dock = [System.Windows.Forms.DockStyle]::Bottom
    $pnl.Height = $pnlHeight
    $pnl.BackColor = [System.Drawing.Color]::FromArgb(241, 245, 249)
    $form.Controls.Add($pnl)

    if ($Buttons -eq [System.Windows.Forms.MessageBoxButtons]::YesNo) {
        $btnYes = New-Object System.Windows.Forms.Button
        $btnYes.Text = "Sim"
        $btnYes.DialogResult = [System.Windows.Forms.DialogResult]::Yes
        $btnYes.Location = New-Object System.Drawing.Point(($formWidth - 195), 11)
        $btnYes.Size = New-Object System.Drawing.Size(85, 30)
        $btnYes.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Regular)
        $btnYes.BackColor = [System.Drawing.Color]::FromArgb(239, 68, 68)
        $btnYes.ForeColor = [System.Drawing.Color]::White
        $btnYes.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
        $btnYes.FlatAppearance.BorderSize = 0

        $btnNo = New-Object System.Windows.Forms.Button
        $btnNo.Text = "Não"
        $btnNo.DialogResult = [System.Windows.Forms.DialogResult]::No
        $btnNo.Location = New-Object System.Drawing.Point(($formWidth - 100), 11)
        $btnNo.Size = New-Object System.Drawing.Size(85, 30)
        $btnNo.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
        $btnNo.BackColor = [System.Drawing.Color]::FromArgb(226, 232, 240)
        $btnNo.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
        $btnNo.FlatAppearance.BorderSize = 0

        $pnl.Controls.Add($btnYes)
        $pnl.Controls.Add($btnNo)
        $form.AcceptButton = $btnNo
        $form.CancelButton = $btnNo
    } else {
        $btnOk = New-Object System.Windows.Forms.Button
        $btnOk.Text = "OK"
        $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $btnOk.Location = New-Object System.Drawing.Point(($formWidth - 105), 11)
        $btnOk.Size = New-Object System.Drawing.Size(85, 30)
        $btnOk.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
        $btnOk.BackColor = [System.Drawing.Color]::FromArgb(14, 165, 233)
        $btnOk.ForeColor = [System.Drawing.Color]::White
        $btnOk.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
        $btnOk.FlatAppearance.BorderSize = 0

        $pnl.Controls.Add($btnOk)
        $form.AcceptButton = $btnOk
    }

    $res = $form.ShowDialog()
    $form.Dispose()
    return $res
}

if (-not $InstallRoot) { $InstallRoot = Split-Path -Path $PSScriptRoot -Parent }
$script:BaseUrl = "http://127.0.0.1:$Port"
$script:Failures = 0
$script:LastRestart = [DateTime]::MinValue
$script:LastStatus = $null

function Invoke-TrayApi {
    param([string]$Path, [string]$Method = "GET", [string]$Body = "{}")
    if ($Method -eq "POST") {
        # O bridge exige a origem local nos métodos que alteram dados.
        return Invoke-RestMethod -Uri "$($script:BaseUrl)$Path" -Method Post -Body $Body -ContentType "application/json" -Headers @{ Origin = $script:BaseUrl } -TimeoutSec 10
    }
    return Invoke-RestMethod -Uri "$($script:BaseUrl)$Path" -TimeoutSec 3
}

# Gravado pelo bridge em /v1/shutdown: avisa a bandeja para sair em vez de religar o servidor.
$script:SignalFile = Join-Path $InstallRoot "dados_locais\shutdown.signal"
$script:Exiting = $false

function Stop-Tray {
    $script:Exiting = $true
    if ($timer) { $timer.Stop() }
    $notify.Visible = $false
    # Sem efeito antes de Application::Run; nesse caso o laço nem chega a começar (ver o fim do arquivo).
    [System.Windows.Forms.Application]::Exit()
}

function Exit-PulseLabApp {
    # O bridge desliga e encerra a bandeja; se ele não responder, a bandeja sai sozinha.
    try { [void](Invoke-TrayApi "/v1/shutdown" "POST") } catch {}
    Stop-Tray
}

function Close-CurrentTurma {
    Update-TrayStatus
    $s = $script:LastStatus
    if (-not $s -or -not $s.session) {
        $notify.ShowBalloonTip(3000, "PulseLab", "Nenhuma turma ativa sendo registrada no momento.", [System.Windows.Forms.ToolTipIcon]::Info)
        return
    }
    $answer = Show-ModernDialog `
        -Message "Deseja encerrar a turma deste computador agora?`n`nA gravação desta aula será finalizada e a próxima começará automaticamente quando o próximo programa for salvo no LEGO SPIKE." `
        -Title "PulseLab — Encerrar Turma" `
        -Buttons ([System.Windows.Forms.MessageBoxButtons]::YesNo) `
        -Icon ([System.Windows.Forms.MessageBoxIcon]::Question)
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    try {
        [void](Invoke-TrayApi "/v1/session/close" "POST")
        $notify.ShowBalloonTip(4000, "PulseLab", "Turma encerrada com sucesso. Pronto para a próxima aula.", [System.Windows.Forms.ToolTipIcon]::Info)
    } catch {
        Show-ModernDialog -Message "Não foi possível encerrar a turma agora. Tente de novo em 1 minuto." -Title "PulseLab" -Icon ([System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
    }
    Update-TrayStatus
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
$notify = New-Object System.Windows.Forms.NotifyIcon
$notify.Icon = $script:IconYellow
$notify.Text = "PulseLab"
$notify.Visible = $true

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$menu.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Regular)
$menu.RenderMode = [System.Windows.Forms.ToolStripRenderMode]::System
$itemClose = $menu.Items.Add("Encerrar turma...")
$itemPause = $menu.Items.Add("Não registrar esta turma")
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
$itemStatus = $menu.Items.Add("Ver situação")
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
$itemExit = $menu.Items.Add("Fechar PulseLab")
$notify.ContextMenuStrip = $menu

function Set-TrayText([string]$Text) {
    # NotifyIcon.Text aceita no máximo 63 caracteres no .NET Framework.
    if ($Text.Length -gt 63) { $Text = $Text.Substring(0, 63) }
    $notify.Text = $Text
}

function Update-TrayStatus {
    if ($script:Exiting) { return }
    if (Test-Path -LiteralPath $script:SignalFile) {
        Remove-Item -LiteralPath $script:SignalFile -Force -ErrorAction SilentlyContinue
        Stop-Tray
        return
    }
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

$itemClose.add_Click({ Close-CurrentTurma })

$itemExit.add_Click({
    $answer = Show-ModernDialog `
        -Message "Deseja fechar o PulseLab agora?`n`nO monitoramento e o servidor local serão desligados." `
        -Title "PulseLab — Fechar Aplicativo" `
        -Buttons ([System.Windows.Forms.MessageBoxButtons]::YesNo) `
        -Icon ([System.Windows.Forms.MessageBoxIcon]::Question)
    if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) {
        Exit-PulseLabApp
    }
})

# Aula alvo como o instrutor a reconhece: "às 14:05 (50 min)", com a data se não for de hoje.
function Format-TrayAula($Target) {
    $when = "às $($Target.started_local)"
    if (-not $Target.started_today) { $when = "em $($Target.started_local_date) $when" }
    return "$when ($($Target.duration_min) min)"
}

$itemPause.add_Click({
    Update-TrayStatus
    $s = $script:LastStatus
    if (-not $s) {
        Show-ModernDialog -Message "Não foi possível falar com o PulseLab agora. Tente de novo em 1 minuto." -Title "PulseLab" -Icon ([System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }
    # A bandeja mostra a aula que será marcada; o bridge recusa se ela mudar antes da confirmação.
    $target = $s.mark_target
    if ($target) {
        $question = "Use quando alguém da bancada (ou a família) não quiser participar.`n`nAula que começou $(Format-TrayAula $target). Marcar esta aula como não autorizada? Os dados não serão usados na pesquisa.`n`nO registro fica pausado até a próxima aula. A bancada continua usando tudo normalmente."
        $shownId = [string]$target.session_id
    } else {
        $question = "Não há aula registrada neste computador agora. O registro fica pausado até a próxima aula.`n`nContinuar?"
        $shownId = ""
    }
    $answer = Show-ModernDialog `
        -Message $question `
        -Title "PulseLab — Não registrar esta turma" `
        -Buttons ([System.Windows.Forms.MessageBoxButtons]::YesNo) `
        -Icon ([System.Windows.Forms.MessageBoxIcon]::Question)
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    try {
        $result = Invoke-TrayApi "/v1/session/pause" "POST" (@{ session_id = $shownId } | ConvertTo-Json -Compress)
        if ($result.marked -and $result.target) {
            $message = "Aula que começou $(Format-TrayAula $result.target) marcada como não autorizada. Os dados não serão usados na pesquisa. O registro volta na próxima aula."
        } else {
            $message = "Nenhuma aula foi marcada. O registro fica pausado até a próxima aula."
        }
        $notify.ShowBalloonTip(6000, "PulseLab", $message, [System.Windows.Forms.ToolTipIcon]::Info)
    } catch {
        $httpStatus = 0
        try { $httpStatus = [int]$_.Exception.Response.StatusCode } catch {}
        $failure = if ($httpStatus -eq 409) {
            "A aula mudou enquanto a janela estava aberta. Nada foi marcado. Abra o menu e escolha Não registrar esta turma de novo."
        } else {
            "Não foi possível falar com o PulseLab agora. Nada foi marcado. Tente de novo em 1 minuto."
        }
        Show-ModernDialog -Message $failure -Title "PulseLab" -Icon ([System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
    }
    Update-TrayStatus
})

$itemStatus.add_Click({
    Update-TrayStatus
    $s = $script:LastStatus
    if (-not $s) {
        Show-ModernDialog -Message "O PulseLab não está respondendo. Ele será religado automaticamente." -Title "PulseLab" -Icon ([System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
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
    Show-ModernDialog -Message ($lines -join "`n") -Title "PulseLab $($s.version)" -Icon ([System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
})

# Um sinal que já existe na partida sobrou de um desligamento anterior (o bridge encerra a
# bandeja antes que ela o leia): apagar, senão a bandeja sairia logo ao iniciar.
Remove-Item -LiteralPath $script:SignalFile -Force -ErrorAction SilentlyContinue

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 15000
$timer.add_Tick({ Update-TrayStatus })
$timer.Start()
Update-TrayStatus

try {
    if (-not $script:Exiting) { [System.Windows.Forms.Application]::Run() }
} finally {
    $timer.Stop()
    $notify.Visible = $false
    $notify.Dispose()
    $mutex.ReleaseMutex()
}
