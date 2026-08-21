param(
    [string]$Workspace = (Get-Location).Path
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:ESC = [char]27
$script:Quit = $false
$script:Focus = 'Explorer' # Explorer | Editor | Terminal
$script:ShowHelp = $false
$script:Workspace = [IO.Path]::GetFullPath($Workspace)
$script:CurrentDir = $script:Workspace
$script:Entries = @()
$script:ExplorerIndex = 0
$script:ExplorerScroll = 0
$script:FilePath = $null
$script:Lines = @('')
$script:CursorLine = 0
$script:CursorCol = 0
$script:EditorScrollY = 0
$script:EditorScrollX = 0
$script:Dirty = $false
$script:TerminalInput = ''
$script:TerminalCursor = 0
$script:TerminalHistory = New-Object System.Collections.Generic.List[string]
$script:TerminalHistoryIndex = -1
$script:Output = New-Object System.Collections.Generic.List[string]
$script:OutputScroll = 0
$script:Status = 'Ready'
$script:Runtimes = @{}

function Write-Ansi([string]$Text) { [Console]::Write($Text) }
function Move-To([int]$X, [int]$Y) { Write-Ansi ("$($script:ESC)[$($Y+1);$($X+1)H") }
function Clear-Screen { Write-Ansi ("$($script:ESC)[2J$($script:ESC)[H") }
function Hide-Cursor { Write-Ansi ("$($script:ESC)[?25l") }
function Show-Cursor { Write-Ansi ("$($script:ESC)[?25h") }
function Reset-Style { Write-Ansi ("$($script:ESC)[0m") }

function Fit([string]$Text, [int]$Width) {
    if ($Width -le 0) { return '' }
    if ($null -eq $Text) { $Text = '' }
    $Text = $Text -replace "`t", '    '
    if ($Text.Length -gt $Width) {
        if ($Width -eq 1) { return '…' }
        return $Text.Substring(0, $Width - 1) + '…'
    }
    return $Text.PadRight($Width)
}

function Move-Focus([bool]$Backward) {
    if ($Backward) {
        if ($script:Focus -eq 'Explorer') { $script:Focus = 'Terminal' }
        elseif ($script:Focus -eq 'Terminal') { $script:Focus = 'Editor' }
        else { $script:Focus = 'Explorer' }
    } else {
        if ($script:Focus -eq 'Explorer') { $script:Focus = 'Editor' }
        elseif ($script:Focus -eq 'Editor') { $script:Focus = 'Terminal' }
        else { $script:Focus = 'Explorer' }
    }
    $script:Status = "Focus: $($script:Focus)"
}

function Get-ExplorerPageSize {
    return [Math]::Max(1, [Console]::WindowHeight - 4)
}

function Set-ExplorerIndex([int]$Index) {
    if ($script:Entries.Count -eq 0) {
        $script:ExplorerIndex = 0
        $script:ExplorerScroll = 0
        return
    }

    $script:ExplorerIndex = [Math]::Max(0, [Math]::Min($Index, $script:Entries.Count - 1))
    $visible = Get-ExplorerPageSize
    if ($script:ExplorerIndex -lt $script:ExplorerScroll) {
        $script:ExplorerScroll = $script:ExplorerIndex
    }
    if ($script:ExplorerIndex -ge $script:ExplorerScroll + $visible) {
        $script:ExplorerScroll = $script:ExplorerIndex - $visible + 1
    }
}

function Add-Output([string]$Text) {
    if ($null -eq $Text) { return }
    foreach ($line in ($Text -split "`r?`n")) {
        $script:Output.Add($line)
    }
    while ($script:Output.Count -gt 500) { $script:Output.RemoveAt(0) }
    $script:OutputScroll = 0
}

function Find-CommandPath([string[]]$Names) {
    foreach ($name in $Names) {
        try {
            $cmd = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($cmd) { return $cmd.Source }
        } catch {}
    }
    return $null
}

function Detect-Runtimes {
    $script:Runtimes = @{}
    $defs = @(
        @('python', @('python','py')),
        @('node', @('node')),
        @('deno', @('deno')),
        @('bun', @('bun')),
        @('go', @('go')),
        @('rustc', @('rustc')),
        @('cargo', @('cargo')),
        @('java', @('java')),
        @('javac', @('javac')),
        @('dotnet', @('dotnet')),
        @('dotnet-script', @('dotnet-script')),
        @('php', @('php')),
        @('ruby', @('ruby')),
        @('perl', @('perl')),
        @('gcc', @('gcc')),
        @('g++', @('g++')),
        @('pwsh', @('pwsh')),
        @('powershell', @('powershell'))
    )
    foreach ($d in $defs) {
        $p = Find-CommandPath $d[1]
        if ($p) { $script:Runtimes[$d[0]] = $p }
    }
}

function Refresh-Explorer {
    try {
        $items = @(Get-ChildItem -LiteralPath $script:CurrentDir -Force -ErrorAction Stop |
            Where-Object { $_.Name -notin @('.git') } |
            Sort-Object @{Expression={$_.PSIsContainer};Descending=$true}, Name)
        $entries = New-Object System.Collections.Generic.List[object]
        if ([IO.Path]::GetFullPath($script:CurrentDir).TrimEnd('\\') -ne [IO.Path]::GetPathRoot($script:CurrentDir).TrimEnd('\\')) {
            $entries.Add([pscustomobject]@{ Name='..'; FullName=(Split-Path -Parent $script:CurrentDir); PSIsContainer=$true })
        }
        foreach ($i in $items) { $entries.Add($i) }
        $script:Entries = $entries.ToArray()
        if ($script:ExplorerIndex -ge $script:Entries.Count) { $script:ExplorerIndex = [Math]::Max(0, $script:Entries.Count - 1) }
    } catch {
        $script:Status = "Explorer error: $($_.Exception.Message)"
    }
}

function Open-ExplorerSelection {
    if ($script:Entries.Count -eq 0) { return }

    $entry = $script:Entries[$script:ExplorerIndex]
    if ($entry.PSIsContainer) {
        $script:CurrentDir = $entry.FullName
        $script:ExplorerIndex = 0
        $script:ExplorerScroll = 0
        Refresh-Explorer
        $script:Status = "Directory: $($script:CurrentDir)"
    } else {
        Open-File $entry.FullName
    }
}

function Go-To-ParentDirectory {
    $current = [IO.Path]::GetFullPath($script:CurrentDir).TrimEnd('\')
    $parent = Split-Path -Parent $current
    if (-not $parent -or $parent -eq $current) {
        $script:Status = 'Already at the filesystem root'
        return
    }

    $childName = Split-Path -Leaf $current
    $script:CurrentDir = $parent
    $script:ExplorerIndex = 0
    $script:ExplorerScroll = 0
    Refresh-Explorer

    for ($index = 0; $index -lt $script:Entries.Count; $index++) {
        if ($script:Entries[$index].Name -eq $childName) {
            Set-ExplorerIndex $index
            break
        }
    }
    $script:Status = "Directory: $($script:CurrentDir)"
}

function Open-File([string]$Path) {
    try {
        $raw = [IO.File]::ReadAllText($Path)
        $script:Lines = @($raw -split "`r?`n", -1)
        if ($script:Lines.Count -eq 0) { $script:Lines = @('') }
        $script:FilePath = $Path
        $script:CursorLine = 0
        $script:CursorCol = 0
        $script:EditorScrollY = 0
        $script:EditorScrollX = 0
        $script:Dirty = $false
        $script:Focus = 'Editor'
        $script:Status = "Opened $(Split-Path -Leaf $Path)"
    } catch {
        $script:Status = "Open failed: $($_.Exception.Message)"
    }
}

function Save-File {
    if (-not $script:FilePath) { $script:Status = 'No file open'; return }
    try {
        $enc = New-Object System.Text.UTF8Encoding($false)
        [IO.File]::WriteAllText($script:FilePath, ($script:Lines -join [Environment]::NewLine), $enc)
        $script:Dirty = $false
        $script:Status = "Saved $(Split-Path -Leaf $script:FilePath)"
    } catch {
        $script:Status = "Save failed: $($_.Exception.Message)"
    }
}

function Replace-CurrentLine([string]$Value) {
    $tmp = @($script:Lines)
    $tmp[$script:CursorLine] = $Value
    $script:Lines = $tmp
    $script:Dirty = $true
}

function Insert-Text([string]$Text) {
    $line = $script:Lines[$script:CursorLine]
    if ($script:CursorCol -gt $line.Length) { $script:CursorCol = $line.Length }
    $new = $line.Substring(0, $script:CursorCol) + $Text + $line.Substring($script:CursorCol)
    Replace-CurrentLine $new
    $script:CursorCol += $Text.Length
}

function Editor-Enter {
    $line = $script:Lines[$script:CursorLine]
    $left = $line.Substring(0, [Math]::Min($script:CursorCol, $line.Length))
    $right = $line.Substring([Math]::Min($script:CursorCol, $line.Length))
    $before = @()
    $after = @()
    if ($script:CursorLine -gt 0) { $before = @($script:Lines[0..($script:CursorLine-1)]) }
    if ($script:CursorLine + 1 -lt $script:Lines.Count) { $after = @($script:Lines[($script:CursorLine+1)..($script:Lines.Count-1)]) }
    $script:Lines = @($before + @($left,$right) + $after)
    $script:CursorLine++
    $script:CursorCol = 0
    $script:Dirty = $true
}

function Editor-Backspace {
    if ($script:CursorCol -gt 0) {
        $line = $script:Lines[$script:CursorLine]
        $new = $line.Remove($script:CursorCol - 1, 1)
        Replace-CurrentLine $new
        $script:CursorCol--
    } elseif ($script:CursorLine -gt 0) {
        $prev = $script:Lines[$script:CursorLine - 1]
        $cur = $script:Lines[$script:CursorLine]
        $newCol = $prev.Length
        $newLines = New-Object System.Collections.Generic.List[string]
        for ($i=0; $i -lt $script:Lines.Count; $i++) {
            if ($i -eq $script:CursorLine - 1) { $newLines.Add($prev + $cur) }
            elseif ($i -eq $script:CursorLine) { continue }
            else { $newLines.Add($script:Lines[$i]) }
        }
        $script:Lines = @($newLines)
        $script:CursorLine--
        $script:CursorCol = $newCol
        $script:Dirty = $true
    }
}

function Editor-Delete {
    $line = $script:Lines[$script:CursorLine]
    if ($script:CursorCol -lt $line.Length) {
        Replace-CurrentLine ($line.Remove($script:CursorCol,1))
    } elseif ($script:CursorLine + 1 -lt $script:Lines.Count) {
        $next = $script:Lines[$script:CursorLine + 1]
        $newLines = New-Object System.Collections.Generic.List[string]
        for ($i=0; $i -lt $script:Lines.Count; $i++) {
            if ($i -eq $script:CursorLine) { $newLines.Add($line + $next) }
            elseif ($i -eq $script:CursorLine + 1) { continue }
            else { $newLines.Add($script:Lines[$i]) }
        }
        $script:Lines = @($newLines)
        $script:Dirty = $true
    }
}

function Ensure-EditorVisible([int]$Height, [int]$Width) {
    if ($script:CursorLine -lt $script:EditorScrollY) { $script:EditorScrollY = $script:CursorLine }
    if ($script:CursorLine -ge $script:EditorScrollY + $Height) { $script:EditorScrollY = $script:CursorLine - $Height + 1 }
    if ($script:CursorCol -lt $script:EditorScrollX) { $script:EditorScrollX = $script:CursorCol }
    if ($script:CursorCol -ge $script:EditorScrollX + $Width) { $script:EditorScrollX = $script:CursorCol - $Width + 1 }
    if ($script:EditorScrollX -lt 0) { $script:EditorScrollX = 0 }
}

function Move-EditorPage([int]$Direction) {
    if ($script:Lines.Count -eq 0) { return }
    $terminalHeight = [Math]::Min(12, [Math]::Max(7, [int]([Console]::WindowHeight * 0.28)))
    $pageSize = [Math]::Max(1, [Console]::WindowHeight - $terminalHeight - 3)
    $target = $script:CursorLine + ($Direction * $pageSize)
    $script:CursorLine = [Math]::Max(0, [Math]::Min($target, $script:Lines.Count - 1))
    $script:CursorCol = [Math]::Min($script:CursorCol, $script:Lines[$script:CursorLine].Length)
}

function Insert-TerminalText([string]$Text) {
    $before = $script:TerminalInput.Substring(0, $script:TerminalCursor)
    $after = $script:TerminalInput.Substring($script:TerminalCursor)
    $script:TerminalInput = $before + $Text + $after
    $script:TerminalCursor += $Text.Length
}

function Terminal-Backspace {
    if ($script:TerminalCursor -le 0) { return }
    $script:TerminalInput = $script:TerminalInput.Remove($script:TerminalCursor - 1, 1)
    $script:TerminalCursor--
}

function Terminal-Delete {
    if ($script:TerminalCursor -ge $script:TerminalInput.Length) { return }
    $script:TerminalInput = $script:TerminalInput.Remove($script:TerminalCursor, 1)
}

function Get-NearestProject([string]$Start, [string]$Pattern) {
    $d = if ([IO.File]::Exists($Start)) { Split-Path -Parent $Start } else { $Start }
    while ($d) {
        $m = Get-ChildItem -LiteralPath $d -Filter $Pattern -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($m) { return $m.FullName }
        $parent = Split-Path -Parent $d
        if (-not $parent -or $parent -eq $d) { break }
        $d = $parent
    }
    return $null
}

function Invoke-Captured([string]$Exe, [object[]]$Args, [string]$WorkingDir) {
    Add-Output ("> " + (Split-Path -Leaf $Exe) + ' ' + (($Args | ForEach-Object { if ($_ -match '\s') {'"'+$_+'"'} else {$_} }) -join ' '))
    $old = Get-Location
    try {
        Set-Location -LiteralPath $WorkingDir
        $result = & $Exe @Args 2>&1 | Out-String
        if ($result) { Add-Output $result.TrimEnd() }
        $code = $LASTEXITCODE
        if ($null -eq $code) { $code = 0 }
        Add-Output "[exit $code]"
    } catch {
        Add-Output ("ERROR: " + $_.Exception.Message)
    } finally {
        Set-Location $old
    }
}

function Run-CurrentFile {
    if (-not $script:FilePath) { $script:Status = 'No file open'; return }
    if ($script:Dirty) { Save-File }
    $f = $script:FilePath
    $dir = Split-Path -Parent $f
    $ext = [IO.Path]::GetExtension($f).ToLowerInvariant()
    $script:Focus = 'Terminal'
    try {
        switch ($ext) {
            '.py' { if ($script:Runtimes['python']) { Invoke-Captured $script:Runtimes['python'] @($f) $dir } else { Add-Output 'Python not found in PATH.' } }
            '.js' { if ($script:Runtimes['node']) { Invoke-Captured $script:Runtimes['node'] @($f) $dir } elseif ($script:Runtimes['bun']) { Invoke-Captured $script:Runtimes['bun'] @($f) $dir } else { Add-Output 'Node.js/Bun not found.' } }
            '.ts' { if ($script:Runtimes['deno']) { Invoke-Captured $script:Runtimes['deno'] @('run',$f) $dir } elseif ($script:Runtimes['bun']) { Invoke-Captured $script:Runtimes['bun'] @($f) $dir } else { Add-Output 'Deno/Bun not found for TypeScript.' } }
            '.ps1' { $p = $script:Runtimes['pwsh']; if (-not $p) { $p=$script:Runtimes['powershell'] }; if ($p) { Invoke-Captured $p @('-NoProfile','-ExecutionPolicy','Bypass','-File',$f) $dir } else { Add-Output 'PowerShell runtime not found.' } }
            '.go' { if ($script:Runtimes['go']) { Invoke-Captured $script:Runtimes['go'] @('run',$f) $dir } else { Add-Output 'Go not found.' } }
            '.php' { if ($script:Runtimes['php']) { Invoke-Captured $script:Runtimes['php'] @($f) $dir } else { Add-Output 'PHP not found.' } }
            '.rb' { if ($script:Runtimes['ruby']) { Invoke-Captured $script:Runtimes['ruby'] @($f) $dir } else { Add-Output 'Ruby not found.' } }
            '.pl' { if ($script:Runtimes['perl']) { Invoke-Captured $script:Runtimes['perl'] @($f) $dir } else { Add-Output 'Perl not found.' } }
            '.java' {
                if ($script:Runtimes['javac'] -and $script:Runtimes['java']) {
                    Invoke-Captured $script:Runtimes['javac'] @($f) $dir
                    Invoke-Captured $script:Runtimes['java'] @('-cp',$dir,[IO.Path]::GetFileNameWithoutExtension($f)) $dir
                } else { Add-Output 'Java JDK not found.' }
            }
            '.rs' {
                if ($script:Runtimes['rustc']) {
                    $out = Join-Path $env:TEMP ('winiex-' + [guid]::NewGuid().ToString('N') + '.exe')
                    Invoke-Captured $script:Runtimes['rustc'] @($f,'-o',$out) $dir
                    if (Test-Path $out) { Invoke-Captured $out @() $dir; Remove-Item $out -Force -ErrorAction SilentlyContinue }
                } else { Add-Output 'rustc not found.' }
            }
            '.c' {
                if ($script:Runtimes['gcc']) {
                    $out = Join-Path $env:TEMP ('winiex-' + [guid]::NewGuid().ToString('N') + '.exe')
                    Invoke-Captured $script:Runtimes['gcc'] @($f,'-o',$out) $dir
                    if (Test-Path $out) { Invoke-Captured $out @() $dir; Remove-Item $out -Force -ErrorAction SilentlyContinue }
                } else { Add-Output 'gcc not found.' }
            }
            '.cpp' {
                if ($script:Runtimes['g++']) {
                    $out = Join-Path $env:TEMP ('winiex-' + [guid]::NewGuid().ToString('N') + '.exe')
                    Invoke-Captured $script:Runtimes['g++'] @($f,'-o',$out) $dir
                    if (Test-Path $out) { Invoke-Captured $out @() $dir; Remove-Item $out -Force -ErrorAction SilentlyContinue }
                } else { Add-Output 'g++ not found.' }
            }
            '.cs' {
                if ($script:Runtimes['dotnet-script']) { Invoke-Captured $script:Runtimes['dotnet-script'] @($f) $dir }
                elseif ($script:Runtimes['dotnet']) {
                    $proj = Get-NearestProject $f '*.csproj'
                    if ($proj) { Invoke-Captured $script:Runtimes['dotnet'] @('run','--project',$proj) (Split-Path -Parent $proj) }
                    else { Add-Output 'dotnet found, but no .csproj. Install dotnet-script for single-file .cs execution.' }
                } else { Add-Output '.NET runtime not found.' }
            }
            default { Add-Output "No runner mapped for $ext" }
        }
    } finally { $script:Status = "Run finished: $(Split-Path -Leaf $f)" }
}

function Invoke-TerminalCommand([string]$Command) {
    if ([string]::IsNullOrWhiteSpace($Command)) { return }
    $script:TerminalHistory.Add($Command)
    $script:TerminalHistoryIndex = $script:TerminalHistory.Count
    Add-Output ("PS " + $script:CurrentDir + "> " + $Command)
    $old = Get-Location
    try {
        Set-Location -LiteralPath $script:CurrentDir
        $result = Invoke-Expression $Command 2>&1 | Out-String
        $script:CurrentDir = (Get-Location).Path
        if ($result) { Add-Output $result.TrimEnd() }
        Refresh-Explorer
    } catch {
        Add-Output ("ERROR: " + $_.Exception.Message)
    } finally {
        Set-Location $old
    }
}

function Get-TerminalPromptPrefix([int]$Width) {
    $prefix = 'PS ' + $script:CurrentDir + '> '
    $maxPrefix = [Math]::Max(8, [Math]::Min($Width - 4, [int]($Width * 0.55)))
    if ($prefix.Length -gt $maxPrefix) {
        $leaf = Split-Path -Leaf $script:CurrentDir
        if (-not $leaf) { $leaf = [IO.Path]::GetPathRoot($script:CurrentDir) }
        $prefix = 'PS …\' + $leaf + '> '
    }
    if ($prefix.Length -gt $maxPrefix) {
        $prefix = $prefix.Substring(0, [Math]::Max(1, $maxPrefix - 2)) + '> '
    }
    return $prefix
}

function Draw-Help([int]$Width, [int]$Height) {
    $helpLines = @(
        'PANELS',
        '  F2 Explorer    F3 Editor    F4 Terminal',
        '  Tab next panel    Shift+Tab previous panel    Esc Explorer',
        '',
        'EXPLORER',
        '  ↑/↓ select    ←/Backspace parent    →/Enter open',
        '  Home/End first or last    PageUp/PageDown move one page',
        '',
        'EDITOR',
        '  Arrows move    Home/End line edge    PageUp/PageDown move',
        '  Ctrl+Home/Ctrl+End file edge    Ctrl+S save    F5 run',
        '',
        'TERMINAL',
        '  ←/→/Home/End edit command    ↑/↓ history',
        '  PageUp/PageDown scroll output    Ctrl+L clear output',
        '',
        'GLOBAL',
        '  F1 or Esc close help    Ctrl+R refresh    Ctrl+Q quit'
    )

    $boxWidth = [Math]::Min(76, $Width - 6)
    $boxHeight = [Math]::Min($helpLines.Count + 4, $Height - 4)
    $boxX = [Math]::Max(2, [int](($Width - $boxWidth) / 2))
    $boxY = [Math]::Max(1, [int](($Height - $boxHeight) / 2))

    for ($row = 0; $row -lt $boxHeight; $row++) {
        Move-To $boxX ($boxY + $row)
        if ($row -eq 0) {
            Write-Ansi ("$($script:ESC)[48;5;25m$($script:ESC)[97m" + (Fit ' WinIEX keyboard guide' $boxWidth) + "$($script:ESC)[0m")
        } elseif ($row -eq $boxHeight - 1) {
            Write-Ansi ("$($script:ESC)[48;5;236m$($script:ESC)[38;5;250m" + (Fit ' F1 / Esc: close' $boxWidth) + "$($script:ESC)[0m")
        } else {
            $lineIndex = $row - 2
            $line = if ($lineIndex -ge 0 -and $lineIndex -lt $helpLines.Count) { $helpLines[$lineIndex] } else { '' }
            $color = if ($line -in @('PANELS','EXPLORER','EDITOR','TERMINAL','GLOBAL')) { "$($script:ESC)[38;5;81m" } else { "$($script:ESC)[38;5;252m" }
            Write-Ansi ("$($script:ESC)[48;5;234m" + $color + (Fit (' ' + $line) $boxWidth) + "$($script:ESC)[0m")
        }
    }
}

function Draw-UI {
    $w = [Console]::WindowWidth
    $h = [Console]::WindowHeight
    if ($w -lt 70 -or $h -lt 20) {
        Clear-Screen
        Write-Ansi "WinIEX needs at least 70x20 terminal cells. Current: ${w}x${h}`n"
        return
    }

    $explorerW = [Math]::Min(38, [Math]::Max(24, [int]($w * 0.27)))
    $termH = [Math]::Min(12, [Math]::Max(7, [int]($h * 0.28)))
    $topY = 1
    $statusY = $h - 1
    $termY = $h - $termH - 1
    $editorH = $termY - $topY
    $editorX = $explorerW + 1
    $editorW = $w - $editorX
    $terminalPromptPrefix = ''
    $terminalInputScroll = 0

    Hide-Cursor
    Move-To 0 0
    $title = ' WinIEX  |  F1 Help  F2 Explorer  F3 Editor  F4 Terminal  F5 Run  |  ' + $script:Workspace
    Write-Ansi ("$($script:ESC)[48;5;24m$($script:ESC)[97m" + (Fit $title $w) + "$($script:ESC)[0m")

    # Explorer
    for ($row=0; $row -lt ($h-2); $row++) {
        Move-To 0 ($topY+$row)
        if ($row -eq 0) {
            $position = if ($script:Entries.Count -gt 0) { "$($script:ExplorerIndex + 1)/$($script:Entries.Count)" } else { '0/0' }
            $head = if ($script:Focus -eq 'Explorer') { "▶ F2 EXPLORER  $position" } else { "  F2 EXPLORER  $position" }
            $headBg = if ($script:Focus -eq 'Explorer') { "$($script:ESC)[48;5;25m" } else { "$($script:ESC)[48;5;236m" }
            Write-Ansi ($headBg + "$($script:ESC)[97m" + (Fit $head $explorerW) + "$($script:ESC)[0m")
        } elseif ($row -eq 1) {
            Write-Ansi ("$($script:ESC)[38;5;244m" + (Fit (' ' + $script:CurrentDir) $explorerW) + "$($script:ESC)[0m")
        } else {
            $idx = $script:ExplorerScroll + ($row - 2)
            $text = ''
            if ($idx -lt $script:Entries.Count) {
                $e = $script:Entries[$idx]
                $icon = if ($e.PSIsContainer) { '▸ ' } else { '  ' }
                $marker = if ($idx -eq $script:ExplorerIndex) { '›' } else { ' ' }
                $text = $marker + $icon + $e.Name
                if ($idx -eq $script:ExplorerIndex) {
                    $selectionBg = if ($script:Focus -eq 'Explorer') { "$($script:ESC)[48;5;25m" } else { "$($script:ESC)[48;5;238m" }
                    Write-Ansi ($selectionBg + "$($script:ESC)[97m" + (Fit $text $explorerW) + "$($script:ESC)[0m")
                    continue
                }
            }
            Write-Ansi (Fit $text $explorerW)
        }
        Write-Ansi ("$($script:ESC)[38;5;240m│$($script:ESC)[0m")
    }

    # Editor header
    Move-To $editorX $topY
    $name = if ($script:FilePath) { Split-Path -Leaf $script:FilePath } else { '[no file]' }
    if ($script:Dirty) { $name += ' ●' }
    $eh = if ($script:Focus -eq 'Editor') { '▶ F3 EDITOR  ' + $name } else { '  F3 EDITOR  ' + $name }
    $editorHeadBg = if ($script:Focus -eq 'Editor') { "$($script:ESC)[48;5;25m" } else { "$($script:ESC)[48;5;235m" }
    Write-Ansi ($editorHeadBg + "$($script:ESC)[97m" + (Fit $eh $editorW) + "$($script:ESC)[0m")

    $contentH = $editorH - 1
    $lineNoW = [Math]::Max(4, $script:Lines.Count.ToString().Length + 1)
    $codeW = $editorW - $lineNoW - 1
    Ensure-EditorVisible $contentH $codeW
    for ($r=0; $r -lt $contentH; $r++) {
        $lineIndex = $script:EditorScrollY + $r
        Move-To $editorX ($topY + 1 + $r)
        if ($lineIndex -lt $script:Lines.Count) {
            $ln = ($lineIndex+1).ToString().PadLeft($lineNoW-1) + ' '
            Write-Ansi ("$($script:ESC)[38;5;244m$ln$($script:ESC)[0m")
            $line = $script:Lines[$lineIndex]
            $slice = ''
            if ($script:EditorScrollX -lt $line.Length) { $slice = $line.Substring($script:EditorScrollX) }
            Write-Ansi (Fit $slice ($editorW-$lineNoW))
        } else {
            Write-Ansi (Fit '~' $editorW)
        }
    }

    # Terminal panel
    Move-To $editorX $termY
    $outRows = $termH - 2
    $maxOutputScroll = [Math]::Max(0, $script:Output.Count - $outRows)
    $script:OutputScroll = [Math]::Max(0, [Math]::Min($script:OutputScroll, $maxOutputScroll))
    $scrollLabel = if ($script:OutputScroll -gt 0) { "  scroll +$($script:OutputScroll)" } else { '' }
    $th = if ($script:Focus -eq 'Terminal') { '▶ F4 TERMINAL' + $scrollLabel } else { '  F4 TERMINAL' + $scrollLabel }
    $terminalHeadBg = if ($script:Focus -eq 'Terminal') { "$($script:ESC)[48;5;25m" } else { "$($script:ESC)[48;5;235m" }
    Write-Ansi ($terminalHeadBg + "$($script:ESC)[97m" + (Fit $th $editorW) + "$($script:ESC)[0m")
    $start = [Math]::Max(0, $script:Output.Count - $outRows - $script:OutputScroll)
    for ($r=0; $r -lt $outRows; $r++) {
        Move-To $editorX ($termY + 1 + $r)
        $idx = $start + $r
        $line = if ($idx -lt $script:Output.Count) { $script:Output[$idx] } else { '' }
        Write-Ansi (Fit $line $editorW)
    }
    Move-To $editorX ($termY + $termH - 1)
    $terminalPromptPrefix = Get-TerminalPromptPrefix $editorW
    $inputWidth = [Math]::Max(1, $editorW - $terminalPromptPrefix.Length)
    $terminalInputScroll = [Math]::Max(0, $script:TerminalCursor - $inputWidth + 1)
    $visibleInput = if ($terminalInputScroll -lt $script:TerminalInput.Length) { $script:TerminalInput.Substring($terminalInputScroll) } else { '' }
    $prompt = $terminalPromptPrefix + $visibleInput
    Write-Ansi ("$($script:ESC)[38;5;81m" + (Fit $prompt $editorW) + "$($script:ESC)[0m")

    # Status bar
    Move-To 0 $statusY
    $focusName = $script:Focus.ToUpperInvariant()
    $pos = if ($script:FilePath) { "Ln $($script:CursorLine+1), Col $($script:CursorCol+1)" } else { '' }
    $status = " $focusName | $($script:Status) | $pos | Tab/Shift+Tab:focus  Ctrl+S:save  Ctrl+Q:quit"
    Write-Ansi ("$($script:ESC)[48;5;25m$($script:ESC)[97m" + (Fit $status $w) + "$($script:ESC)[0m")

    if ($script:ShowHelp) {
        Draw-Help $w $h
        Hide-Cursor
        return
    }

    # Cursor
    if ($script:Focus -eq 'Editor' -and $script:FilePath) {
        $cx = $editorX + $lineNoW + ($script:CursorCol - $script:EditorScrollX)
        $cy = $topY + 1 + ($script:CursorLine - $script:EditorScrollY)
        if ($cx -ge $editorX+$lineNoW -and $cx -lt $w -and $cy -gt $topY -and $cy -lt $termY) {
            Move-To $cx $cy; Show-Cursor
        }
    } elseif ($script:Focus -eq 'Terminal') {
        $cx = $editorX + $terminalPromptPrefix.Length + ($script:TerminalCursor - $terminalInputScroll)
        $cx = [Math]::Min($w - 1, $cx)
        $cy = $termY + $termH - 1
        Move-To $cx $cy; Show-Cursor
    }
}

function Handle-Key([ConsoleKeyInfo]$k) {
    $ctrl = (($k.Modifiers -band [ConsoleModifiers]::Control) -ne 0)
    $shift = (($k.Modifiers -band [ConsoleModifiers]::Shift) -ne 0)

    if ($ctrl -and $k.Key -eq [ConsoleKey]::Q) { $script:Quit = $true; return }

    if ($script:ShowHelp) {
        if ($k.Key -in @([ConsoleKey]::F1, [ConsoleKey]::Escape, [ConsoleKey]::Enter)) {
            $script:ShowHelp = $false
            $script:Status = 'Help closed'
        }
        return
    }

    if ($ctrl -and $k.Key -eq [ConsoleKey]::S) { Save-File; return }
    if ($ctrl -and $k.Key -eq [ConsoleKey]::R) { Detect-Runtimes; Refresh-Explorer; $script:Status='Refreshed'; return }
    if ($k.Key -eq [ConsoleKey]::F1) { $script:ShowHelp = $true; $script:Status = 'Keyboard guide'; return }
    if ($k.Key -eq [ConsoleKey]::F2) { $script:Focus = 'Explorer'; $script:Status = 'Focus: Explorer'; return }
    if ($k.Key -eq [ConsoleKey]::F3) { $script:Focus = 'Editor'; $script:Status = 'Focus: Editor'; return }
    if ($k.Key -eq [ConsoleKey]::F4) { $script:Focus = 'Terminal'; $script:Status = 'Focus: Terminal'; return }
    if ($k.Key -eq [ConsoleKey]::F5) { Run-CurrentFile; return }
    if ($k.Key -eq [ConsoleKey]::Escape) { $script:Focus = 'Explorer'; $script:Status = 'Focus: Explorer'; return }
    if ($k.Key -eq [ConsoleKey]::Tab) {
        Move-Focus $shift
        return
    }

    if ($script:Focus -eq 'Explorer') {
        switch ($k.Key) {
            'UpArrow' { Set-ExplorerIndex ($script:ExplorerIndex - 1) }
            'DownArrow' { Set-ExplorerIndex ($script:ExplorerIndex + 1) }
            'Home' { Set-ExplorerIndex 0 }
            'End' { Set-ExplorerIndex ($script:Entries.Count - 1) }
            'PageUp' { Set-ExplorerIndex ($script:ExplorerIndex - (Get-ExplorerPageSize)) }
            'PageDown' { Set-ExplorerIndex ($script:ExplorerIndex + (Get-ExplorerPageSize)) }
            'LeftArrow' { Go-To-ParentDirectory }
            'Backspace' { Go-To-ParentDirectory }
            'RightArrow' { Open-ExplorerSelection }
            'Enter' { Open-ExplorerSelection }
        }
        return
    }

    if ($script:Focus -eq 'Editor') {
        if (-not $script:FilePath) { return }
        switch ($k.Key) {
            'LeftArrow' { if ($script:CursorCol -gt 0) { $script:CursorCol-- } elseif ($script:CursorLine -gt 0) { $script:CursorLine--; $script:CursorCol=$script:Lines[$script:CursorLine].Length } }
            'RightArrow' { if ($script:CursorCol -lt $script:Lines[$script:CursorLine].Length) { $script:CursorCol++ } elseif ($script:CursorLine+1 -lt $script:Lines.Count) { $script:CursorLine++; $script:CursorCol=0 } }
            'UpArrow' { if ($script:CursorLine -gt 0) { $script:CursorLine--; $script:CursorCol=[Math]::Min($script:CursorCol,$script:Lines[$script:CursorLine].Length) } }
            'DownArrow' { if ($script:CursorLine+1 -lt $script:Lines.Count) { $script:CursorLine++; $script:CursorCol=[Math]::Min($script:CursorCol,$script:Lines[$script:CursorLine].Length) } }
            'Home' {
                if ($ctrl) { $script:CursorLine = 0 }
                $script:CursorCol = 0
            }
            'End' {
                if ($ctrl) { $script:CursorLine = $script:Lines.Count - 1 }
                $script:CursorCol = $script:Lines[$script:CursorLine].Length
            }
            'PageUp' { Move-EditorPage -1 }
            'PageDown' { Move-EditorPage 1 }
            'Enter' { Editor-Enter }
            'Backspace' { Editor-Backspace }
            'Delete' { Editor-Delete }
            default {
                if (-not [char]::IsControl($k.KeyChar)) { Insert-Text ([string]$k.KeyChar) }
            }
        }
        return
    }

    if ($script:Focus -eq 'Terminal') {
        if ($ctrl -and $k.Key -eq [ConsoleKey]::L) {
            $script:Output.Clear()
            $script:OutputScroll = 0
            $script:Status = 'Terminal output cleared'
            return
        }

        switch ($k.Key) {
            'Enter' {
                $cmd = $script:TerminalInput
                $script:TerminalInput = ''
                $script:TerminalCursor = 0
                Invoke-TerminalCommand $cmd
            }
            'Backspace' { Terminal-Backspace }
            'Delete' { Terminal-Delete }
            'LeftArrow' { if ($script:TerminalCursor -gt 0) { $script:TerminalCursor-- } }
            'RightArrow' { if ($script:TerminalCursor -lt $script:TerminalInput.Length) { $script:TerminalCursor++ } }
            'Home' { $script:TerminalCursor = 0 }
            'End' { $script:TerminalCursor = $script:TerminalInput.Length }
            'PageUp' {
                $pageSize = [Math]::Max(1, [Math]::Min(10, [Console]::WindowHeight - 5))
                $script:OutputScroll += $pageSize
            }
            'PageDown' {
                $pageSize = [Math]::Max(1, [Math]::Min(10, [Console]::WindowHeight - 5))
                $script:OutputScroll = [Math]::Max(0, $script:OutputScroll - $pageSize)
            }
            'UpArrow' {
                if ($script:TerminalHistory.Count -gt 0) {
                    $script:TerminalHistoryIndex=[Math]::Max(0,$script:TerminalHistoryIndex-1)
                    $script:TerminalInput=$script:TerminalHistory[$script:TerminalHistoryIndex]
                    $script:TerminalCursor=$script:TerminalInput.Length
                }
            }
            'DownArrow' {
                if ($script:TerminalHistory.Count -gt 0) {
                    $script:TerminalHistoryIndex=[Math]::Min($script:TerminalHistory.Count,$script:TerminalHistoryIndex+1)
                    if ($script:TerminalHistoryIndex -eq $script:TerminalHistory.Count) { $script:TerminalInput='' }
                    else { $script:TerminalInput=$script:TerminalHistory[$script:TerminalHistoryIndex] }
                    $script:TerminalCursor=$script:TerminalInput.Length
                }
            }
            default { if (-not [char]::IsControl($k.KeyChar)) { Insert-TerminalText ([string]$k.KeyChar) } }
        }
    }
}

if (-not (Test-Path -LiteralPath $script:Workspace -PathType Container)) {
    throw "Workspace does not exist: $script:Workspace"
}

$oldTitle = [Console]::Title
$oldCursor = [Console]::CursorVisible
try {
    [Console]::Title = 'WinIEX IDE'
    Clear-Screen
    Detect-Runtimes
    Refresh-Explorer
    Add-Output 'WinIEX terminal IDE ready.'
    Add-Output 'Commands run in the current Explorer directory.'
    Add-Output 'Press F1 for the keyboard guide.'
    while (-not $script:Quit) {
        Draw-UI
        $key = [Console]::ReadKey($true)
        Handle-Key $key
    }
} finally {
    Reset-Style
    Show-Cursor
    Clear-Screen
    [Console]::Title = $oldTitle
    [Console]::CursorVisible = $oldCursor
    Write-Host 'WinIEX exited.'
}
