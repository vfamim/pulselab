' ==============================================================================
' PulseLab - Inicializador Silencioso (Zero Console)
' ==============================================================================
' Executa o PulseLab de forma totalmente invisivel (sem prompt de comando e
' sem janela preta do PowerShell piscando na tela).
' ==============================================================================

Dim WshShell, fso, scriptDir, psScript, cmd
Set WshShell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
psScript = scriptDir & "\pulselab.ps1"

If Not fso.FileExists(psScript) Then
    ' Fallback para instalacao em %LOCALAPPDATA%\PulseLab
    psScript = WshShell.ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\PulseLab\pulselab.ps1"
End If

cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & psScript & """"
WshShell.Run cmd, 0, False
