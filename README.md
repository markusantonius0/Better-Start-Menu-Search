# CmdPal Start Search

**Replace Windows Start Menu search with [PowerToys Command Palette](https://learn.microsoft.com/windows/powertoys/command-palette)** — seamlessly, with zero system modifications.

![Windows 11](https://img.shields.io/badge/Windows%2011-0078D4?logo=windows11&logoColor=white)
![PowerToys](https://img.shields.io/badge/PowerToys-Required-blue)
![AutoHotkey v2](https://img.shields.io/badge/AutoHotkey-v2-green)
![License](https://img.shields.io/badge/License-MIT-yellow)

## What It Does

Press the **Windows key** to open the Start Menu like normal. The moment you **start typing**, the Start Menu dismisses and **PowerToys Command Palette** takes over with your query already entered — no lost keystrokes.

| Action | Result |
|---|---|
| `Win` → click pinned apps | Normal Start Menu behavior (unchanged) |
| `Win` → type `calc` | Start Menu closes → Command Palette opens with `calc` |
| `Win + S` or `Win + Q` | Command Palette opens directly |
| `Win` → `Ctrl + V` | Command Palette opens with clipboard contents |

> **Zero registry edits. Zero system file patches.** Just a lightweight background script that can be stopped at any time to instantly restore default Windows behavior.

## Quick Start

### Option A: Double-Click (Easiest)
Download or clone the repository, then simply double-click **`Setup.bat`**.

### Option B: PowerShell
```powershell
# Clone the repo
git clone https://github.com/YOUR_USERNAME/cmdpal-start-search.git
cd cmdpal-start-search

# Run the installer (installs prerequisites if needed)
powershell -ExecutionPolicy Bypass -File Setup.ps1
```

The installer will:

1. ✅ Check for **winget** (Windows Package Manager)
2. ✅ Install **PowerToys** if missing (via winget)
3. ✅ Enable **Command Palette** in PowerToys settings
4. ✅ Disable legacy **PowerToys Run** (avoids hotkey conflicts)
5. ✅ Install **AutoHotkey v2** if missing (via winget)
6. ✅ Detect your Command Palette hotkey and sync the script
7. ✅ Register a **startup shortcut** so it runs on every login
8. ✅ Launch immediately

## Uninstall

Double-click **`Uninstall.bat`** or run:

```powershell
powershell -ExecutionPolicy Bypass -File Uninstall.ps1
```

This stops the background script and removes the startup shortcut. PowerToys and AutoHotkey are **not** uninstalled. Run `Setup.ps1` again at any time to re-enable.

## How It Works

A lightweight [AutoHotkey v2](https://www.autohotkey.com/) script runs in the background (~3 MB RAM) and watches for keyboard input while the Windows Start Menu or Search Host has focus:

```
User presses Win          → Start Menu opens normally
User types a character    → AHK intercepts the keystroke
                          → Sends Escape to dismiss Start Menu
                          → Sends Win+Alt+Space to open Command Palette
                          → Buffers any fast-typed characters during the switch
                          → Sends all buffered text into CmdPal's search box
```

The script only activates when `StartMenuExperienceHost.exe` or `SearchHost.exe` has focus. All other applications and keyboard shortcuts (`Win+E`, `Win+L`, `Alt+Tab`, etc.) are completely unaffected.

## System Tray

Look for the green **H** icon in your Windows taskbar system tray:

| Menu Item | Description |
|---|---|
| **Suspend / Resume** | Temporarily disable the interceptor without closing it |
| **Reload Script** | Apply changes made to the `.ahk` file |
| **Exit** | Close the script completely |

## Requirements

- **Windows 11** (Windows 10 may work but is untested)
- **[Microsoft PowerToys](https://github.com/microsoft/PowerToys)** with Command Palette enabled
- **[AutoHotkey v2](https://www.autohotkey.com/)** (v2.0+)

All prerequisites are installed automatically by `Setup.ps1` via [winget](https://learn.microsoft.com/windows/package-manager/winget/).

## Files

| File | Purpose |
|---|---|
| `PowerToys_StartSearch.ahk` | The core background interceptor script |
| `Setup.bat` | Double-click launcher for `Setup.ps1` |
| `Setup.ps1` | One-click installer (prerequisites + startup + launch) |
| `Uninstall.bat` | Double-click launcher for `Uninstall.ps1` |
| `Uninstall.ps1` | Stops the script and removes the startup shortcut |
| `LICENSE` | MIT License |
| `.gitignore` | Ignores temporary and local workspace files |
| `.github/workflows/validate.yml` | GitHub Actions CI for automated script validation |

## FAQ

**Q: Does this modify Windows system files or the registry?**
No. It's a user-space script that intercepts keystrokes only when the Start Menu has focus. Stopping the script instantly restores default behavior.

**Q: Will this conflict with other AutoHotkey scripts?**
No. The hotkeys are context-sensitive — they only activate when the Start Menu or Windows Search is the active window.

**Q: What if I change my Command Palette hotkey?**
Re-run `Setup.ps1` — it reads your CmdPal settings and patches the script automatically.

**Q: Does it work with the Win key held for other shortcuts?**
Yes. Only single keypresses while the Start Menu is open are intercepted. Holding `Win` and pressing `E`, `D`, `L`, etc. works exactly as before.

## License

[MIT](LICENSE)
