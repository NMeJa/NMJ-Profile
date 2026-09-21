# NMJ PowerShell Profile (Modular)

Self-bootstrapping, modular PowerShell profile focused on terminal productivity.

## Structure

```
$HOME\Documents\PowerShell\
├── Microsoft.PowerShell_profile.ps1   ← thin loader (copy this to $PROFILE)
└── Modules\
    ├── NMJ.Core\       Bootstrap, helpers, Ollama soft-warnings, help aggregator
    ├── NMJ.AI\         Local Ollama → askai / fixit / aish
    ├── NMJ.History\    Atuin integration
    ├── NMJ.Shortcuts\  JSON-based custom commands
    └── NMJ.Themes\     Oh My Posh + FastFetch

$HOME\.nmj\
└── shortcuts.json      Single source of truth for custom shortcuts
```

## Quick Start

1. Copy the whole `Modules` folder to `$HOME\Documents\PowerShell\Modules`
2. Copy `Microsoft.PowerShell_profile.ps1` to your `$PROFILE` location  
   (usually `Documents\PowerShell\Microsoft.PowerShell_profile.ps1`)
3. Restart the terminal (or `. $PROFILE`)
4. First run will auto-install missing tools via winget (oh-my-posh, atuin, fzf, eza, bat, etc.)

## New / Changed Features

### AI (replaces archived AIShell)
- `askai "question"` – ask anything, code often inserted into buffer
- `fixit` – explain + fix last error
- `aish` – interactive chat
- Fully offline via Ollama (default model: `qwen2.5-coder:7b`)
- Soft warning system: first 3 profile loads warn if Ollama is missing, then silence. Commands always warn if missing.

### History → Atuin
- Auto-installed by bootstrap
- `Ctrl+R` opens Atuin TUI
- Predictive IntelliSense (PSReadLine History) still works

### Shortcuts (JSON)
```powershell
# Create
New-Shortcut -Name ollama.log `
             -Command 'Get-Content $env:LOCALAPPDATA\Ollama\server.log -Tail 50 -Wait' `
             -Description 'Tail Ollama server log' `
             -Alias @('olog')

New-Shortcut -Name unity66 `
             -Path 'C:\Program Files\Unity\Hub\Editor\6000.6.0f1\Editor\Unity.exe' `
             -Alias @('u66')

# Use
ollama.log
Invoke-NMJShortcut ollama.log
olog -?

# List / remove
Get-Shortcut
Remove-Shortcut ollama.log
myhelp shortcuts
```

Paths support `$HOME$`, `$LOCALAPPDATA$`, `$APPDATA$`, `$TEMP$`, `$USERPROFILE$`.

### Themes
Presets 1-10 (original 4 + tokyonight, nord, gruvbox, paradox, agnoster, catppuccin_frappe).

```powershell
Set-Theme 5
Set-Theme tokyonight -Perm
set-icon list
ff
```

## Export / Backup
- Entire `Modules` folder + `$HOME\.nmj` is all you need.
- `shortcuts.json` is plain JSON → easy to edit or sync with git.

## Force re-install of tools
```powershell
Update-ProfileDependencies -Force
```
