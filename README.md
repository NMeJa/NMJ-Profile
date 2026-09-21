# NMJ PowerShell Profile (Modular)

Self-bootstrapping, modular PowerShell profile focused on terminal productivity, silent resiliency, and modern CLI tooling.

## Structure

```
$HOME\Documents\PowerShell\
├── Microsoft.PowerShell_profile.ps1   ← thin loader (auto-detects local or user Modules)
└── Modules\
    ├── NMJ.Core\       Bootstrap, helpers, silent startup checks, help aggregator
    ├── NMJ.Nav\        Fuzzy navigation (zoxide + Everything CLI / fzf)
    ├── NMJ.CLI\        Modern CLI tools (eza, bat, gsudo), uv completions, PSReadLine
    ├── NMJ.AI\         Local Ollama → askai / fixit / aish
    ├── NMJ.History\    Atuin integration
    ├── NMJ.Shortcuts\  JSON-based custom commands & multi-format subcommands
    └── NMJ.Themes\     Oh My Posh + FastFetch

$HOME\.nmj\
└── shortcuts.json      Single source of truth for custom shortcuts
```

## Quick Start

1. Copy the `Modules` folder to `$HOME\Documents\PowerShell\Modules` (or keep in place; the loader automatically finds `$PSScriptRoot\Modules`)
2. Copy `Microsoft.PowerShell_profile.ps1` to your `$PROFILE` location  
   (usually `Documents\PowerShell\Microsoft.PowerShell_profile.ps1`)
3. Restart terminal (or run `. $PROFILE`)
4. First run auto-checks missing tools via winget (oh-my-posh, atuin, fzf, es, eza, bat, gsudo, uv, etc.)

---

## Features & Modules

### 📁 Navigation (`NMJ.Nav`)
- `nf <folder>` / `Find-FuzzyFolder` – Fast folder navigation using zoxide first, then Everything (`es.exe`) + `fzf`
- `z <folder>` / `zi` – Direct zoxide jumping
- `Ctrl+t` – Fuzzy file/directory path insertion via PSFzf

### 🧰 Modern CLI & Shell (`NMJ.CLI`)
- `ls` / `ll` / `lt` – Modern listing with icons and git integration (`eza`)
- `cat` – Syntax highlighted file viewing (`bat`)
- `sudo` – Elevated command execution (`gsudo`)
- `uv` – High-performance Python packaging with pre-initialized shell completion
- PSReadLine Predictive IntelliSense configured with `ListView`

### 🚀 Custom Shortcuts (`NMJ.Shortcuts`)
Supports dots, dashes, and space-separated subcommands with full argument forwarding:

```powershell
# All four invocations work seamlessly:
ollama.logs
ollama logs
ollama.debugs
ollama debugs

# Flags and help are forwarded:
ollama logs -?
ollama.debugs -Tail 100
```

#### Creating & Managing Shortcuts
```powershell
# Create an executable shortcut:
New-Shortcut -Name unity66 `
             -Path 'C:\Program Files\Unity\Hub\Editor\6000.6.0f1\Editor\Unity.exe' `
             -Alias @('u66') `
             -Description 'Launch Unity 6.6'

# List or remove shortcuts:
Get-Shortcut
Remove-Shortcut unity66
myhelp shortcuts
```

Paths support environment tags: `$HOME$`, `$LOCALAPPDATA$`, `$APPDATA$`, `$TEMP$`, `$USERPROFILE$`, `$USERNAME$`.

### 🤖 AI Assistant (`NMJ.AI`)
- `askai "question"` – Ask anything, code block is automatically offered to terminal buffer
- `fixit` – Explain and fix the last failed command/error
- `aish` – Interactive terminal chat session
- Powered locally by Ollama (default model: `qwen2.5-coder:7b`)
- Fails cleanly and silently during startup; warns with concise help when command is executed if Ollama is offline

### 📜 History (`NMJ.History`)
- `Ctrl+R` – Atuin interactive fuzzy history search
- `atuin search <query>`
- `Get-AtuinHistory` – PowerShell wrapper

### 🎨 Themes (`NMJ.Themes`)
- `Set-Theme <1-10 | name> [-Perm]` – Presets: `jandedobbeleer`, `if_tea`, `wholespace`, `catppuccin_mocha`, `tokyonight`, `nord`, `gruvbox`, `paradox`, `agnoster`, `catppuccin_frappe`
- `set-icon [list | number]` – FastFetch icon themes
- `ff` – Run FastFetch with current theme

---

## Silent Resiliency & Debugging

- **Silent Startup**: Optional tools, missing models, or theme folders never pollute the terminal on startup.
- **Graceful Fallback**: If a tool is missing when invoked, a clean single-line notice is shown instead of an unhandled exception stack trace.
- **Debug Mode**: Set `$env:PROFILE_DEBUG = 1` before starting the shell to see detailed load timings and module resolution.

## Dependencies

```powershell
# Force reinstall / update of all dependencies:
Update-ProfileDependencies -Force
```
