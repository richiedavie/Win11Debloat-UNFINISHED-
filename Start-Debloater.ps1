# Start-Debloater.ps1 - Main entry script

# Ensure Administrator privileges
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[!] Error: Administrator privileges are required to run Windows 11 Debloater." -ForegroundColor Red
    Write-Host "[!] Please run 'Run.bat' as Administrator." -ForegroundColor Red
    Exit
}

# Resolve script root directory path
$RootDir = $PSScriptRoot
if (-not $RootDir) { $RootDir = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $RootDir) { $RootDir = (Get-Location).Path }
$global:RootDir = $RootDir

$ConfigDir = Join-Path $RootDir "config"
$ModulesDir = Join-Path $RootDir "modules"
$UiDir = Join-Path $RootDir "ui"
$BackupDir = Join-Path $RootDir "logs\registry_backups"

# Module files list
$ModuleFiles = @(
    (Join-Path $UiDir "Rendering.ps1"),
    (Join-Path $UiDir "Menu.ps1"),
    (Join-Path $ModulesDir "SafetyManager.ps1"),
    (Join-Path $ModulesDir "AppxManager.ps1"),
    (Join-Path $ModulesDir "RegistryManager.ps1"),
    (Join-Path $ModulesDir "ServiceManager.ps1")
)

# Dot-source all modules directly in script scope
foreach ($ModulePath in $ModuleFiles) {
    if (Test-Path -Path $ModulePath) {
        . $ModulePath
    } else {
        Write-Host "[!] ERROR: Required module file missing at: $ModulePath" -ForegroundColor Red
    }
}

# Main Menu Execution Loop
do {
    $Choice = Show-DebloatMenu

    switch ($Choice) {
        "1" {
            Show-HeaderBanner
            Write-RenderStatus "Starting Full System Debloat Sequence..." "Header"
            $null = Create-Win11RestorePoint -Description "Win11Debloat Full System Cleanup"
            Remove-DebloatAppxPackages -ConfigPath (Join-Path $ConfigDir "bloatware_apps.json")
            Apply-RegistryTweaks -ConfigPath (Join-Path $ConfigDir "registry_tweaks.json") -BackupDir $BackupDir
            Apply-ServiceAndTaskTweaks -ConfigPath (Join-Path $ConfigDir "services_list.json")
            Write-RenderStatus "Full Debloat Sequence Finished successfully!" "Success"
            Read-Host "`nPress Enter to return to menu..."
        }
        "2" {
            Show-HeaderBanner
            $null = Create-Win11RestorePoint -Description "Win11Debloat AppX Purge Backup"
            Remove-DebloatAppxPackages -ConfigPath (Join-Path $ConfigDir "bloatware_apps.json")
            Read-Host "`nPress Enter to return to menu..."
        }
        "3" {
            Show-HeaderBanner
            $null = Create-Win11RestorePoint -Description "Win11Debloat Registry Tweaks Backup"
            Apply-RegistryTweaks -ConfigPath (Join-Path $ConfigDir "registry_tweaks.json") -BackupDir $BackupDir
            Read-Host "`nPress Enter to return to menu..."
        }
        "4" {
            Show-HeaderBanner
            $null = Create-Win11RestorePoint -Description "Win11Debloat Services Tweak Backup"
            Apply-ServiceAndTaskTweaks -ConfigPath (Join-Path $ConfigDir "services_list.json")
            Read-Host "`nPress Enter to return to menu..."
        }
        "5" {
            Show-HeaderBanner
            $null = Create-Win11RestorePoint -Description "Win11Debloat Manual System Restore Point"
            Read-Host "`nPress Enter to return to menu..."
        }
        "Q" {
            Write-Host "`nExiting Windows 11 Debloater. Have a great day!" -ForegroundColor Green
            Break
        }
        Default {
            Write-Host "Invalid selection. Please try again." -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
} while ($Choice -ne "Q")
