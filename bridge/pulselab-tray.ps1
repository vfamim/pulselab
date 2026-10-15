# ==============================================================================
# PulseLab — Ícone na bandeja do Windows (área de notificação)
# ==============================================================================
# Mostra que o PulseLab está ligado sem abrir janelas durante a aula.
# Menu (clique direito), para o instrutor:
#   - Encerrar turma...         encerra a turma atual silenciosamente (sem abrir janelas)
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
    param([string]$Path, [string]$Method = "GET")
    if ($Method -eq "POST") {
        # O bridge exige a origem local nos métodos que alteram dados.
        return Invoke-RestMethod -Uri "$($script:BaseUrl)$Path" -Method Post -Body "{}" -ContentType "application/json" -Headers @{ Origin = $script:BaseUrl } -TimeoutSec 10
    }
    return Invoke-RestMethod -Uri "$($script:BaseUrl)$Path" -TimeoutSec 3
}

function Exit-PulseLabApp {
    $signalFile = Join-Path $InstallRoot "dados_locais\shutdown.signal"
    try { [System.IO.File]::WriteAllText($signalFile, "shutdown") } catch {}
    try {
        [void](Invoke-TrayApi "/v1/shutdown" "POST")
    } catch {}
    try {
        Get-Process -Name "msedge" -ErrorAction SilentlyContinue | Where-Object {
            try {
                $cmd = (Get-CimInstance Win32_Process -Filter "ProcessId = $($_.Id)" -ErrorAction SilentlyContinue).CommandLine
                $cmd -and ($cmd -match "43128" -or $cmd -match "alunos")
            } catch { $false }
        } | Stop-Process -Force -ErrorAction SilentlyContinue
    } catch {}
    $notify.Visible = $false
    [System.Windows.Forms.Application]::Exit()
}

function Close-CurrentTurma {
    Update-TrayStatus
    $s = $script:LastStatus
    if (-not $s -or -not $s.session) {
        $ans = Show-ModernDialog `
            -Message "Nenhuma turma ativa no momento.`n`nDeseja fechar o PulseLab agora?" `
            -Title "PulseLab" `
            -Buttons ([System.Windows.Forms.MessageBoxButtons]::YesNo) `
            -Icon ([System.Windows.Forms.MessageBoxIcon]::Question)
        if ($ans -eq [System.Windows.Forms.DialogResult]::Yes) {
            Exit-PulseLabApp
        }
        return
    }
    $answer = Show-ModernDialog `
        -Message "Deseja encerrar a sessão e fechar o PulseLab agora?`n`nA gravação desta aula será finalizada e o aplicativo será encerrado." `
        -Title "PulseLab — Encerrar Turma" `
        -Buttons ([System.Windows.Forms.MessageBoxButtons]::YesNo) `
        -Icon ([System.Windows.Forms.MessageBoxIcon]::Question)
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    try {
        $result = Invoke-TrayApi "/v1/session/close" "POST"
    } catch {}
    Exit-PulseLabApp
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
    $signalFile = Join-Path $InstallRoot "dados_locais\shutdown.signal"
    if (-not (Test-Path -LiteralPath $signalFile)) {
        $signalFile = Join-Path $InstallRoot "shutdown.signal"
    }
    if (Test-Path -LiteralPath $signalFile) {
        try { Remove-Item -LiteralPath $signalFile -Force -ErrorAction SilentlyContinue } catch {}
        $notify.Visible = $false
        [System.Windows.Forms.Application]::Exit()
        return
    }
    $status = $null
    try { $status = Invoke-TrayApi "/v1/status" } catch { $status = $null }
    if (-not $status) {
        if (Test-Path -LiteralPath $signalFile) {
            try { Remove-Item -LiteralPath $signalFile -Force -ErrorAction SilentlyContinue } catch {}
            $notify.Visible = $false
            [System.Windows.Forms.Application]::Exit()
            return
        }
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

$itemPause.add_Click({
    $answer = Show-ModernDialog `
        -Message "Use quando alguém da turma (ou a família) não quiser participar.`n`nOs dados desta turma neste computador serão apagados e o registro fica pausado até a próxima aula. A bancada continua funcionando normalmente.`n`nNão registrar esta turma?" `
        -Title "PulseLab" `
        -Buttons ([System.Windows.Forms.MessageBoxButtons]::YesNo) `
        -Icon ([System.Windows.Forms.MessageBoxIcon]::Question)
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    try {
        $result = Invoke-TrayApi "/v1/session/pause" "POST"
        $message = "Os dados desta turma foram apagados neste computador. O registro volta na próxima aula."
        if ($result.remote_pending) { $message += " A cópia na nuvem será apagada quando houver internet." }
        $notify.ShowBalloonTip(6000, "PulseLab", $message, [System.Windows.Forms.ToolTipIcon]::Info)
    } catch {
        Show-ModernDialog -Message "Não foi possível falar com o PulseLab agora. Tente de novo em 1 minuto." -Title "PulseLab" -Icon ([System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
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
