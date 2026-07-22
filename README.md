# Windows 11 Debloater (24H2 / 25H2 Build 26100+)

A modular, safety-first PowerShell debloating tool specifically targeting Windows 11 24H2 / 25H2 (Build 26100+).

## Features

- **Purge "AI Slop" & Pre-installed Apps**: Removes Windows Copilot app, Recall indexing components, AI typing insights/voice access, Paint/Photos AI feature packages, as well as stock bloatware apps (Xbox, Weather, Clipchamp, Spotify, News, etc.) for current user and provisioned packages.
- **Stop Telemetry & Background Bloat**: Hard-disables DiagTrack (`Connected User Experiences and Telemetry`), `dmwappushservice`, Bing web search in Start Menu, and Widgets.
- **Safety First**: Automatically creates a System Restore Point and backs up modified registry keys prior to executing debloat actions.
- **Interactive UI**: Clean PowerShell terminal menu interface for custom module execution or full debloat.

## File Structure

```text
Win11Debloat/
├── Run.bat                     <-- UAC Elevation & PowerShell Execution Policy Bypass Launcher
├── Start-Debloater.ps1         <-- Entry script & main loop
├── config/
│   ├── bloatware_apps.json     <-- AppX package removal rules & AI bloat targets
│   ├── registry_tweaks.json    <-- Registry policy keys for Telemetry, Recall, Copilot, Bing
│   └── services_list.json      <-- Background services & scheduled tasks to disable
├── modules/
│   ├── SafetyManager.ps1       <-- System Restore Point & Registry backup utilities
│   ├── AppxManager.ps1         <-- UWP AppX & DISM Provisioned Package purging engine
│   ├── RegistryManager.ps1     <-- HKLM / HKCU policy applier engine
│   └── ServiceManager.ps1      <-- Windows Service & Scheduled Task execution engine
├── ui/
│   ├── Rendering.ps1           <-- Terminal banners, status reporting, colored output
│   └── Menu.ps1                <-- Interactive menu interface & input handlers
├── logs/                       <-- Auto-created log directory
│   └── debloat_history.log     <-- Runtime action log
├── .gitignore                  <-- Git ignore rules for logs & temporary files
└── README.md                   <-- Setup & Usage documentation
```

## How to Run

1. Download or clone this repository to your Windows 11 PC.
2. Right-click `Run.bat` and select **Run as Administrator** (or simply double-click it; `Run.bat` will prompt for UAC Elevation automatically).
3. Select your desired option from the interactive terminal menu.

> **Note**: Requires Windows 11 (Build 26100+ / 24H2 / 25H2 recommended). System Restore must be enabled on your system drive (`C:`) to auto-create restore points.
