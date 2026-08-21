param(
    [string]$Workspace = (Get-Location).Path,
    [string]$Branch = 'main'
)

$ErrorActionPreference = 'Stop'
$repo = 'AybarsBarut/Powershell-IDE'
$base = "https://raw.githubusercontent.com/$repo/$Branch"
$cache = Join-Path $env:LOCALAPPDATA 'WinIEX'
$main = Join-Path $cache 'WinIEX.ps1'

New-Item -ItemType Directory -Force -Path $cache | Out-Null
Invoke-WebRequest -UseBasicParsing "$base/src/WinIEX.ps1" -OutFile $main

# Windows PowerShell 5.1 treats BOM-less scripts as the active ANSI code page.
# Preserve the UTF-8 box-drawing characters by adding a BOM when necessary.
$bytes = [IO.File]::ReadAllBytes($main)
$utf8Bom = [Text.Encoding]::UTF8.GetPreamble()
$hasUtf8Bom = $bytes.Length -ge $utf8Bom.Length
for ($index = 0; $hasUtf8Bom -and $index -lt $utf8Bom.Length; $index++) {
    if ($bytes[$index] -ne $utf8Bom[$index]) { $hasUtf8Bom = $false }
}
if (-not $hasUtf8Bom) {
    [IO.File]::WriteAllBytes($main, [byte[]]($utf8Bom + $bytes))
}

# Invoke directly so WinIEX stays in the current terminal session.
& $main -Workspace $Workspace
