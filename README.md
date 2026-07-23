# Windows 11 Debloater (24H2 / 25H2 Build 26100+)

A modular, safety-first PowerShell debloating tool specifically targeting Windows 11 24H2 / 25H2 (Build 26100+).

## Features

- **Purge "AI Slop" & Pre-installed Apps**: Removes Windows Copilot, Recall indexing, Click to Do, WSAIFabricSvc, AI typing insights, Paint/Photos AI packages, Edge AI extensions, plus stock bloatware (Xbox, Weather, Clipchamp, Spotify, News, etc.) for current user and provisioned packages.
- **Stop Telemetry & Background Bloat**: Hard-disables DiagTrack, dmwappushservice, Bing web search in Start Menu, Widgets, and related scheduled tasks.
- **Safety First**: Automatically creates System Restore Points and backs up modified registry keys prior to applying changes. Includes a full Undo/Rollback engine using state delta manifests.
- **Preset Profiles**: Choose between Default Balanced, Minimal Privacy, or Aggressive Gaming profiles.
- **Build Enforcement**: Strict validation ensuring execution only on Windows 11 24H2/25H2 (Build 26100+).
- **Interactive UI**: Clean PowerShell terminal menu interface for custom module execution or full debloat.

## File Structure

```text
Win11Debloat/
├── Run.bat                                 <-- UAC Elevation & PowerShell Execution Policy Bypass Launcher
├── Start-Debloater.ps1                     <-- Master orchestrator script & CLI entry point
├── config/
│   ├── bloatware_apps.json                 <-- Target AppX & DISM provisioned package list
│   ├── registry_tweaks.json                <-- Policies for Telemetry, Recall, Copilot, Bing
│   ├── services_list.json                  <-- Services & scheduled tasks to disable/stop
│   └── ai_components.json                  <-- 24H2/25H2 specific AI feature flag targets
├── presets/
│   ├── default_debloat.json                <-- Safe, balanced debloat profile
│   ├── minimal_privacy.json                <-- Conservative tweaks (telemetry & basic bloat)
│   └── aggressive_gaming.json              <-- Strips all non-essential services, apps & AI
├── modules/
│   ├── VersionGuard.ps1                    <-- Build 26100+ (24H2/25H2) target validation
│   ├── SafetyManager.ps1                   <-- System Restore Point & Registry backup exporter
│   ├── AiManager.ps1                       <-- Specific handler for Recall, Copilot & WSAI
│   ├── AppxManager.ps1                     <-- Dual-layer AppX & DISM provisioned purging engine
│   ├── RegistryManager.ps1                 <-- HKLM / HKCU policy applier & key manager
│   ├── ServiceManager.ps1                  <-- Service startup-type modifier & Task Scheduler manager
│   └── RollbackEngine.ps1                  <-- Undo engine utilizing state delta manifests
├── ui/
│   ├── Rendering.ps1                       <-- ANSI terminal colors, banners & status formatting
│   └── Menu.ps1                            <-- Interactive CLI menu & option parser
├── utils/
│   └── Invoke-BuildCheck.ps1               <-- Standalone build check diagnostic tool
├── logs/
│   ├── debloat_history.log                 <-- Detailed execution timestamp log
│   └── state_manifest_latest.json          <-- System state snapshot prior to tweak application
├── .gitignore                              <-- Git ignore rule definitions for logs & temp files
└── README.md                               <-- Usage instructions & build compatibility matrix
```

## How to Run

1. Download or clone this repository to your Windows 11 PC.
2. Right-click `Run.bat` and select **Run as Administrator** (or simply double-click it; `Run.bat` will prompt for UAC Elevation automatically).
3. Select a preset on first run, or choose individual operations from the interactive terminal menu.

## Requirements

- Windows 11 (Build 26100+ / 24H2 / 25H2)
- Administrator privileges
- System Restore enabled on `C:` (for automatic restore points)

## Modules

| Module | Purpose |
|--------|---------|
| `VersionGuard.ps1` | Validates OS build >= 26100 before proceeding |
| `SafetyManager.ps1` | Creates restore points and exports registry backups |
| `AiManager.ps1` | Neutralizes Recall, Copilot, ClickToDo, WSAIFabricSvc, Edge AI extensions |
| `AppxManager.ps1` | Removes installed and provisioned AppX packages |
| `RegistryManager.ps1` | Applies HKLM/HKCU registry policies from JSON config |
| `ServiceManager.ps1` | Stops/disables services and scheduled tasks |
| `RollbackEngine.ps1` | Reverts changes using pre-execution state manifests |
| `Invoke-BuildCheck.ps1` | Standalone compatibility diagnostic (can be run from utils/) |

## License

MIT
