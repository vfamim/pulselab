# ==============================================================================
# PulseLab — Notificação Toast Nativa e Amigável (Windows Offline)
# ==============================================================================
# - Exibe pop-up moderno e não-bloqueante no canto inferior direito
# - Tema escuro PulseLab (#18122c) com borda violeta (#7c3aed)
# - Mascote robozinho PulseLab
# - Som suave de notificação (Asterisk chime)
# - Auto-dismiss após 25 segundos se não for clicado
# - Foca no navegador padrão em modo aplicativo ao clicar
# ==============================================================================

[CmdletBinding()]
param(
    [int]$Mark = 20,
    [int]$Port = 43127,
    [string]$AppRoot = ""
)

$ErrorActionPreference = "SilentlyContinue"

Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue

if (-not ([System.Management.Automation.PSTypeName]'PulseLabToastWin32').Type) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class PulseLabToastWin32 {
    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, int dwExtraInfo);
}
"@ -ErrorAction SilentlyContinue
}

function Focus-ExistingPulseLabWindow {
    try {
        $candidates = Get-Process | Where-Object {
            $_.MainWindowHandle -ne [IntPtr]::Zero -and (
                $_.MainWindowTitle -match 'PulseLab' -or
                $_.MainWindowTitle -match 'Atividade dos alunos'
            )
        }
        $proc = $candidates | Select-Object -First 1
        if ($proc) {
            # 9 = SW_RESTORE (restaura caso a janela esteja minimizada)
            [PulseLabToastWin32]::ShowWindow($proc.MainWindowHandle, 9)
            # Simular toque em tecla Alt para liberar permissão de SetForegroundWindow
            [PulseLabToastWin32]::keybd_event(0x12, 0, 0, 0)
            [PulseLabToastWin32]::keybd_event(0x12, 0, 2, 0)
            [PulseLabToastWin32]::SetForegroundWindow($proc.MainWindowHandle)
            return $true
        }
    } catch {}
    return $false
}

try {
    # Tocar som de checkpoint (Asterisk + Beep audível para máxima compatibilidade)
    try {
        [System.Media.SystemSounds]::Asterisk.Play()
    } catch {}
    try {
        [System.Console]::Beep(1046, 150)
        [System.Console]::Beep(1318, 200)
    } catch {}

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "PulseLab - Check-in"
    $form.Size = New-Object System.Drawing.Size(420, 145)
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
    $form.TopMost = $true
    $form.ShowInTaskbar = $false
    $form.BackColor = [System.Drawing.Color]::FromArgb(24, 18, 44) # #18122c

    # Garantir foco e primeiro plano ao exibir
    $form.Add_Shown({
        try {
            $form.Activate()
            $form.BringToFront()
        } catch {}
    })

    # Posicionar no canto inferior direito da área de trabalho
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $form.Location = New-Object System.Drawing.Point(($screen.Right - 440), ($screen.Bottom - 165))

    # Borda suave roxa PulseLab
    $form.Add_Paint({
        param($sender, $e)
        $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(124, 58, 237), 2)
        $rect = New-Object System.Drawing.Rectangle(0, 0, ($sender.Width - 1), ($sender.Height - 1))
        $e.Graphics.DrawRectangle($pen, $rect)
        $pen.Dispose()
    })

    # Ícone do robozinho mascote
    $robotImg = $null
    $candidates = @()
    if ($PSScriptRoot) {
        $candidates += (Join-Path $PSScriptRoot "..\pulselab.ico")
        $candidates += (Join-Path $PSScriptRoot "..\agent\robot.png")
    }
    if ($AppRoot) {
        $candidates += (Join-Path $AppRoot "..\..\agent\robot.png")
    }
    if ($env:LOCALAPPDATA) {
        $candidates += (Join-Path $env:LOCALAPPDATA "PulseLab\pulselab.ico")
    }
    foreach ($c in $candidates) {
        if (Test-Path $c) {
            try {
                if ($c.EndsWith(".ico")) {
                    $ico = New-Object System.Drawing.Icon($c, 64, 64)
                    $robotImg = $ico.ToBitmap()
                } else {
                    $robotImg = [System.Drawing.Image]::FromFile($c)
                }
                break
            } catch {}
        }
    }

    if ($robotImg) {
        $pb = New-Object System.Windows.Forms.PictureBox
        $pb.Size = New-Object System.Drawing.Size(64, 64)
        $pb.Location = New-Object System.Drawing.Point(18, 24)
        $pb.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
        $pb.Image = $robotImg
        $form.Controls.Add($pb)
    } else {
        $lblEmoji = New-Object System.Windows.Forms.Label
        $lblEmoji.Text = [char]::ConvertFromUtf32(0x1F916) # 🤖
        $lblEmoji.Font = New-Object System.Drawing.Font("Segoe UI Emoji", 30)
        $lblEmoji.ForeColor = [System.Drawing.Color]::White
        $lblEmoji.Location = New-Object System.Drawing.Point(18, 24)
        $lblEmoji.Size = New-Object System.Drawing.Size(64, 64)
        $lblEmoji.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        $form.Controls.Add($lblEmoji)
    }

    # Título amigável com destaque aqua PulseLab
    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = "PulseLab - Check-in de $Mark min"
    $lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    $lblTitle.ForeColor = [System.Drawing.Color]::FromArgb(94, 234, 212) # #5eead4
    $lblTitle.Location = New-Object System.Drawing.Point(96, 16)
    $lblTitle.Size = New-Object System.Drawing.Size(280, 22)
    $form.Controls.Add($lblTitle)

    # Mensagem amigável e acolhedora
    $lblMsg = New-Object System.Windows.Forms.Label
    $lblMsg.Text = "Hora da dupla registrar o progresso da oficina!`nLeva menos de 30 segundos."
    $lblMsg.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $lblMsg.ForeColor = [System.Drawing.Color]::FromArgb(226, 232, 240)
    $lblMsg.Location = New-Object System.Drawing.Point(96, 40)
    $lblMsg.Size = New-Object System.Drawing.Size(295, 36)
    $form.Controls.Add($lblMsg)

    # Botão principal de ação
    $btnOpen = New-Object System.Windows.Forms.Button
    $btnOpen.Text = "Responder agora"
    $btnOpen.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $btnOpen.ForeColor = [System.Drawing.Color]::White
    $btnOpen.BackColor = [System.Drawing.Color]::FromArgb(0, 167, 160) # #00a7a0
    $btnOpen.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnOpen.FlatAppearance.BorderSize = 0
    $btnOpen.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(0, 195, 187)
    $btnOpen.Location = New-Object System.Drawing.Point(96, 86)
    $btnOpen.Size = New-Object System.Drawing.Size(160, 32)
    $btnOpen.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnOpen.Add_Click({
        try {
            # 1. Tentar trazer para o primeiro plano a janela do PulseLab ja aberta
            if (Focus-ExistingPulseLabWindow) {
                $form.Close()
                return
            }

            # 2. Se nenhuma janela aberta for encontrada, abre a URL normalmente no navegador
            $targetUrl = "http://127.0.0.1:$Port/alunos/"
            Start-Process $targetUrl
        } catch {
            try { Start-Process "http://127.0.0.1:$Port/alunos/" } catch {}
        }
        $form.Close()
    })
    $form.Controls.Add($btnOpen)

    # Botão de fechar suave "X"
    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "X"
    $btnClose.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $btnClose.ForeColor = [System.Drawing.Color]::FromArgb(148, 163, 184)
    $btnClose.BackColor = [System.Drawing.Color]::Transparent
    $btnClose.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnClose.FlatAppearance.BorderSize = 0
    $btnClose.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(45, 35, 75)
    $btnClose.Location = New-Object System.Drawing.Point(385, 8)
    $btnClose.Size = New-Object System.Drawing.Size(26, 26)
    $btnClose.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnClose.Add_Click({ $form.Close() })
    $form.Controls.Add($btnClose)

    # Auto-dismiss após 25 segundos se a dupla não interagir
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 25000
    $timer.Add_Tick({
        $timer.Stop()
        $form.Close()
    })
    $form.Add_FormClosing({
        try { $timer.Stop(); $timer.Dispose() } catch {}
    })
    $timer.Start()

    # Executar o loop de eventos na thread do processo independente
    [System.Windows.Forms.Application]::Run($form)
} catch {
    # Falha silenciosa para nunca interromper a máquina
}
