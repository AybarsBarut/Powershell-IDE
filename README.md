# WinIEX Terminal IDE

A terminal-native Windows IDE prototype. It does **not** open WPF, WinForms, Electron, or a browser window. The UI is drawn directly inside Windows Terminal / PowerShell using ANSI escape sequences and `Console.ReadKey()`.

## Target launch

After replacing `REPLACE_ME` in `install.ps1` with your GitHub username/org:

```powershell
iwr -useb https://raw.githubusercontent.com/USER/winiex-terminal-ide/main/install.ps1 | iex
```

For a specific workspace:

```powershell
& ([scriptblock]::Create((iwr -useb https://raw.githubusercontent.com/USER/winiex-terminal-ide/main/install.ps1))) -Workspace C:\Projects\Demo
```

## UI

```text
┌ WinIEX IDE ─────────────────────────────────────────────────────────────┐
│ EXPLORER                 │ EDITOR                                      │
│ C:\Projects\Demo         │ main.py                                     │
│ ▸ src                    │   1  def hello():                           │
│   README.md              │   2      print("hello")                    │
│   main.py                │   3                                        │
│                          ├─────────────────────────────────────────────┤
│                          │ TERMINAL                                    │
│                          │ > python main.py                            │
│                          │ hello                                       │
│                          │ PS C:\Projects\Demo> _                      │
└────────────────────────────────────────────────────────────────────────┘
```

## Controls

- `Tab` — Explorer → Editor → Terminal focus
- Explorer: `↑/↓`, `Enter`, `Backspace`
- Editor: normal text entry, arrows, Home/End, Enter, Backspace/Delete
- `Ctrl+S` — save
- `F5` — run current file
- `Ctrl+R` — refresh filesystem/runtime detection
- `Ctrl+Q` — quit
- Terminal: type a PowerShell command and press `Enter`

## Runtime detection

The IDE intentionally uses tools already installed on the computer and available in `PATH`.

Supported detection/runners include:

- Python
- Node.js
- Deno / Bun
- PowerShell 5/7
- Go
- Rust
- Java JDK
- .NET / dotnet-script
- PHP
- Ruby
- Perl
- GCC / G++

## Notes

This is an early TUI editor core, not a VS Code replacement yet. The next architectural upgrades should be:

1. Real ConPTY-backed embedded terminal for fully interactive subprocesses.
2. Incremental syntax highlighting/tokenization.
3. LSP client for completion/diagnostics/go-to-definition.
4. Multi-tab buffers and split editors.
5. Git status/diff panel.
6. Command palette and searchable file picker.
7. Async process execution with cancellation.

## Security

`iwr | iex` executes remote code immediately. For real distribution, use signed release manifests and SHA-256 verification, and pin downloads to immutable release assets rather than blindly executing the current branch.
