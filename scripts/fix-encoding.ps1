$files = Get-ChildItem -Path . -Recurse -Include *.ps1,*.json,*.bat | Where-Object { $_.FullName -notmatch '\\\.git\\' }
$utf8Bom = [System.Text.Encoding]::UTF8

foreach ($file in $files) {
    try {
        $content = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
        [System.IO.File]::WriteAllText($file.FullName, $content, $utf8Bom)
        Write-Host "UTF-8 BOM aplicado em: $($file.FullName)" -ForegroundColor Green
    }
    catch {
        Write-Host "Erro em $($file.FullName): $($_.Exception.Message)" -ForegroundColor Red
    }
}
