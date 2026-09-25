#Requires -Version 5.1
# Portable loopback-only static server. No http.sys URL reservation/admin needed.
# No ingestion, filesystem scanning, data directories, updates or outbound calls.
[CmdletBinding()]
param([ValidateSet(43128)][int]$Port = 43128, [string]$AppRoot = "", [string]$DataDir = "")
$ErrorActionPreference = "Stop"
if (-not $AppRoot) {
    $AppRoot = Join-Path $PSScriptRoot "..\app\alunos"
    if (-not (Test-Path -LiteralPath $AppRoot)) { $AppRoot = Join-Path $PSScriptRoot "..\alunos" }
}
$root = [IO.Path]::GetFullPath($AppRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
$prefix = $root + [IO.Path]::DirectorySeparatorChar
$crlf = [string][char]13 + [char]10
$headerEnd = $crlf + $crlf
$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $Port)
$listener.ExclusiveAddressUse = $true
$listener.Start()
Write-Host "PulseLab TESTE: http://127.0.0.1:$Port/alunos/ (Ctrl+C para encerrar)"
try {
    while ($true) {
        $client = $listener.AcceptTcpClient()
        try {
            $stream = $client.GetStream()
            $stream.ReadTimeout = 2000
            $stream.WriteTimeout = 2000
            $header = [Text.StringBuilder]::new()
            $tail = ""
            while ($header.Length -lt 8192) {
                $value = $stream.ReadByte()
                if ($value -lt 0) { break }
                [void]$header.Append([char]$value)
                $tail = ($tail + [char]$value)
                if ($tail.Length -gt 4) { $tail = $tail.Substring($tail.Length - 4) }
                if ($tail -eq $headerEnd) { break }
            }
            $request = $header.ToString()
            if (-not $request.EndsWith($headerEnd)) { continue }
            $firstLine = ($request -split "\r\n", 2)[0]
            $status = 200
            $type = "text/plain; charset=utf-8"
            $bytes = [byte[]]@()
            $method = ""
            if ($firstLine -notmatch '^(GET|HEAD|POST|PUT|PATCH|DELETE|OPTIONS) ([^ ]+) HTTP/1\.[01]$') {
                $status = 400
            } else {
                $method = $Matches[1]
                $rawPath = $Matches[2]
                if ($method -notin @("GET", "HEAD")) {
                    $status = 405
                } elseif ($rawPath -notmatch '^/' -or $rawPath.StartsWith("//")) {
                    $status = 400
                } else {
                    $path = [Uri]::UnescapeDataString(($rawPath -split '\?', 2)[0])
                    if ($path -eq "/health") {
                        $bytes = [Text.Encoding]::UTF8.GetBytes('{"environment":"test","version":"2.0.0-test.1","cloud_enabled":false}')
                        $type = "application/json"
                    } elseif (-not $path.StartsWith("/alunos/") -or $path.Contains(":") -or $path.Contains([string][char]0)) {
                        $status = 404
                    } else {
                        $relative = $path.Substring(8)
                        if (-not $relative) { $relative = "index.html" }
                        $target = [IO.Path]::GetFullPath((Join-Path $root $relative))
                        if (-not $target.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $target -PathType Leaf)) {
                            $status = 404
                        } else {
                            $type = switch ([IO.Path]::GetExtension($target).ToLowerInvariant()) {
                                ".html" { "text/html; charset=utf-8" }
                                ".js" { "application/javascript; charset=utf-8" }
                                ".css" { "text/css; charset=utf-8" }
                                ".json" { "application/json" }
                                ".webmanifest" { "application/manifest+json" }
                                ".png" { "image/png" }
                                ".svg" { "image/svg+xml" }
                                ".ico" { "image/x-icon" }
                                default { "application/octet-stream" }
                            }
                            $bytes = [IO.File]::ReadAllBytes($target)
                        }
                    }
                }
            }
            $reason = @{200="OK";400="Bad Request";404="Not Found";405="Method Not Allowed"}[$status]
            $lines = @(
                "HTTP/1.1 $status $reason",
                "Content-Type: $type",
                ("Content-Length: " + $bytes.Length),
                "Connection: close",
                "Cache-Control: no-store",
                "X-Content-Type-Options: nosniff",
                "Content-Security-Policy: default-src 'self'; connect-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; script-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'none'",
                "", ""
            )
            $responseHeader = [Text.Encoding]::ASCII.GetBytes(($lines -join $crlf))
            $stream.Write($responseHeader, 0, $responseHeader.Length)
            if ($method -ne "HEAD") { $stream.Write($bytes, 0, $bytes.Length) }
        } catch {
            # Malformed requests/timeouts are closed without exposing paths or content.
        } finally { $client.Close() }
    }
} finally { $listener.Stop() }
