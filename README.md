# WinIEX Terminal IDE

WinIEX is a lightweight, terminal-native IDE prototype for Windows, written entirely in PowerShell. It renders an Explorer, editor, and terminal directly inside the console with ANSI escape sequences and `Console.ReadKey()`—no WPF, WinForms, Electron, or browser window required.

> [!NOTE]
> WinIEX is an early prototype. It is useful for experimenting with a compact terminal editor, but it is not yet a replacement for a full desktop IDE.

## Features

- Three-panel terminal UI: Explorer, editor, and command output
- Keyboard-driven file navigation and text editing
- Direct panel shortcuts and an in-app keyboard guide
- Save and run the active file without leaving the interface
- Built-in PowerShell command prompt with command history
- Automatic runtime detection from `PATH`
- Support for common scripting, compiled, and managed languages
- No third-party PowerShell modules required

## Requirements

- Windows 10 or Windows 11
- Windows PowerShell 5.1 or PowerShell 7+
- A console with ANSI escape-sequence support; Windows Terminal is recommended
- The runtime or compiler for any language you want to run

## Quick start

### One-line launch in the current terminal

Run this command from the directory you want to open as the workspace:

```powershell
irm 'https://raw.githubusercontent.com/AybarsBarut/Powershell-IDE/main/install.ps1' | iex
```

The installer downloads WinIEX to `%LOCALAPPDATA%\WinIEX` and invokes it directly in the current PowerShell or Windows Terminal session. It does not use `Start-Process` or open a separate application window.

To open a specific workspace with the same bootstrap script:

```powershell
& ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/AybarsBarut/Powershell-IDE/main/install.ps1'))) -Workspace 'C:\Projects\Demo'
```

> [!IMPORTANT]
> Piping a remote script to `iex` executes it immediately. Review [`install.ps1`](install.ps1) and [`src/WinIEX.ps1`](src/WinIEX.ps1) before running the one-line command.

### Run from a clone

Clone the repository and launch WinIEX from PowerShell 7:

```powershell
git clone https://github.com/AybarsBarut/Powershell-IDE.git
Set-Location .\Powershell-IDE
pwsh -NoProfile -File .\src\WinIEX.ps1 -Workspace .
```

Windows PowerShell 5.1 can be used instead:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\src\WinIEX.ps1 -Workspace .
```

To open a different workspace, pass its full path:

```powershell
pwsh -NoProfile -File .\src\WinIEX.ps1 -Workspace 'C:\Projects\Demo'
```

## Interface

```text
┌ WinIEX IDE ─────────────────────────────────────────────────────────────┐
│ EXPLORER                 │ EDITOR                                       │
│ C:\Projects\Demo         │ main.py                                      │
│ ▸ src                    │   1  def hello():                            │
│   README.md              │   2      print("hello")                      │
│   main.py                │   3                                          │
│                          ├──────────────────────────────────────────────┤
│                          │ TERMINAL                                     │
│                          │ > python main.py                             │
│                          │ hello                                        │
│                          │ PS C:\Projects\Demo> _                       │
└─────────────────────────────────────────────────────────────────────────┘
```

## Keyboard controls

| Context | Key | Action |
| --- | --- | --- |
| Global | `F1` | Open or close the keyboard guide |
| Global | `F2` / `F3` / `F4` | Focus Explorer / Editor / Terminal directly |
| Global | `Tab` / `Shift+Tab` | Move to the next / previous panel |
| Global | `Esc` | Return to Explorer or close the keyboard guide |
| Global | `Ctrl+S` | Save the active file |
| Global | `F5` | Save and run the active file |
| Global | `Ctrl+R` | Refresh files and runtime detection |
| Global | `Ctrl+Q` | Quit WinIEX |
| Explorer | `↑` / `↓` | Move through entries |
| Explorer | `→` / `Enter` | Open the selected file or directory |
| Explorer | `←` / `Backspace` | Go to the parent directory and keep the previous folder selected |
| Explorer | `Home` / `End` | Jump to the first / last entry |
| Explorer | `PageUp` / `PageDown` | Move by one visible page |
| Editor | Arrow keys, `Home`, `End` | Move the cursor or jump to a line edge |
| Editor | `Ctrl+Home` / `Ctrl+End` | Jump to the start / end of the file |
| Editor | `PageUp` / `PageDown` | Move by one editor page |
| Editor | `Enter`, `Backspace`, `Delete` | Edit text |
| Terminal | `Enter` | Run the entered PowerShell command |
| Terminal | `↑` / `↓` | Browse command history |
| Terminal | `←` / `→`, `Home`, `End`, `Delete` | Edit the command line at the cursor |
| Terminal | `PageUp` / `PageDown` | Scroll command output |
| Terminal | `Ctrl+L` | Clear command output |

## Supported runners

WinIEX detects tools already installed and available in `PATH`.

| File type | Runtime or compiler |
| --- | --- |
| `.py` | Python |
| `.js` | Node.js, with Bun as a fallback |
| `.ts` | Deno or Bun |
| `.ps1` | PowerShell 7 or Windows PowerShell |
| `.go` | Go |
| `.rs` | Rust (`rustc`) |
| `.java` | Java JDK (`javac` and `java`) |
| `.cs` | `dotnet-script`, or `dotnet run` when a `.csproj` is found |
| `.php` | PHP |
| `.rb` | Ruby |
| `.pl` | Perl |
| `.c` / `.cpp` | GCC / G++ |

Press `Ctrl+R` after installing a new runtime so WinIEX can detect it.

## Project structure

```text
Powershell-IDE/
├── src/
│   └── WinIEX.ps1   # Terminal IDE implementation
├── install.ps1      # Same-terminal download/bootstrap launcher
├── LICENSE
└── README.md
```

## Current limitations

- Process output is captured; fully interactive subprocesses are not yet backed by ConPTY.
- Syntax highlighting, completion, diagnostics, tabs, split editors, and Git integration are not implemented yet.
- The terminal panel executes commands in the current PowerShell process.
- Very large files and directories have not been optimized.

## Security

The terminal panel evaluates the commands you enter, and downloaded PowerShell scripts can execute arbitrary code. Review remote scripts before running them, use trusted workspaces, and prefer pinned release assets with checksum verification for production distribution.

## Contributing

Issues and pull requests are welcome. Keep changes focused, test them in both Windows PowerShell 5.1 and PowerShell 7 when possible, and describe any terminal-specific behavior in the pull request.

## License

This project is available under the [MIT License](LICENSE).
