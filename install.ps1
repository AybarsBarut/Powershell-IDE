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

# Invoke directly so WinIEX stays in the current terminal session.
& $main -Workspace $Workspace
