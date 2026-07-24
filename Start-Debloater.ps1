# 1. Environment & OS Detection (Auto-enable DryRun on Linux/macOS)
if ($IsLinux -or $IsMacOS) {
    Write-Host "`n[!] Non-Windows environment detected ($($PSVersionTable.OS))." -ForegroundColor Yellow
    Write-Host "    Forcing SIMULATION (Dry-Run) Mode...`n" -ForegroundColor Yellow
    $DryRun = $true
}

# 2. Resolve script root directory path
$RootDir = $PSScriptRoot
if (-not $RootDir) { $RootDir = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $RootDir) { $RootDir = (Get-Location).Path }
$global:RootDir = $RootDir

$ConfigDir = Join-Path $RootDir "config"
$ModulesDir = Join-Path $RootDir "modules"
$UiDir = Join-Path $RootDir "ui"
$BackupDir = Join-Path $RootDir "logs\registry_backups"
$ManifestPath = Join-Path $RootDir "logs\state_manifest_latest.json"
$PresetsDir = Join-Path $RootDir "presets"

# 3. Module files list
$ModuleFiles = @(
    (Join-Path $UiDir "Rendering.ps1"),
    (Join-Path $UiDir "Menu.ps1"),
    (Join-Path $ModulesDir "VersionGuard.ps1"),
    (Join-Path $ModulesDir "SafetyManager.ps1"),
    (Join-Path $ModulesDir "AppxManager.ps1"),
    (Join-Path $ModulesDir "RegistryManager.ps1"),
    (Join-Path $ModulesDir "ServiceManager.ps1"),
    (Join-Path $ModulesDir "AiManager.ps1"),
    (Join-Path $ModulesDir "RollbackEngine.ps1")
)

foreach ($ModulePath in $ModuleFiles) {
    if (Test-Path -Path $ModulePath) {
        . $ModulePath
    } else {
        Write-Host "[!] ERROR: Required module file missing at: $ModulePath" -ForegroundColor Red
    }
}

# 4. Ensure Administrator privileges
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[!] Error: Administrator privileges are required to run Windows 11 Debloater." -ForegroundColor Red
    Write-Host "[!] Please run 'Run.bat' as Administrator." -ForegroundColor Red
    Exit
}

# 5. Strict Target Build Enforcement (24H2/25H2 minimum 26100)
$TargetBuild = 26100
if (-not (Test-Win11DebloatTargetBuild -MinBuild $TargetBuild)) {
    Write-Host "[!] Unsupported OS build detected. Exiting." -ForegroundColor Red
    Read-Host "`nPress Enter to exit..."
    Exit 1
}

# 6. Create default restore point at startup
$null = Create-Win11RestorePoint -Description "Win11Debloat Pre-Flight Restore Point"

# 7. Preset resolution helper
function Resolve-PresetConfigs {
    param([string]$PresetFile)

    if (-not $PresetFile) { return @{} }

    if (-not (Test-Path $PresetFile)) {
        Write-RenderStatus "Preset file not found: $PresetFile. Falling back to defaults." "Warning"
        return @{}
    }

    try {
        $Preset = Get-Content -Path $PresetFile -Raw | ConvertFrom-Json
    } catch {
        Write-RenderStatus "Failed to parse preset: $PresetFile" "Error"
        return @{}
    }

    $ConfigMap = @{}

    if ($Preset.ai_components_config) {
        $ConfigMap.ai = Join-Path $ConfigDir $Preset.ai_components_config
    }
    if ($Preset.bloatware_config) {
        $ConfigMap.bloatware = Join-Path $ConfigDir $Preset.bloatware_config
    }
    if ($Preset.registry_config) {
        $ConfigMap.registry = Join-Path $ConfigDir $Preset.registry_config
    }
    if ($Preset.services_config) {
        $ConfigMap.services = Join-Path $ConfigDir $Preset.services_config
    }

    $ConfigMap.flags = @{
        ai = [bool]($Preset.include_ai_neutralization -eq $true)
        appx = [bool]($Preset.include_appx_purge -eq $true)
        registry = [bool]($Preset.include_registry_tweaks -eq $true)
        services = [bool]($Preset.include_services_disable -eq $true)
    }

    return $ConfigMap
}

# 8. Capture initial system state manifest
try {
    $RegistryPaths = @(
        "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot",
        "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsAI",
        "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection",
        "HKLM\SOFTWARE\Policies\Microsoft\MicrosoftEdge\Main",
        "HKLM\SOFTWARE\Policies\Microsoft\Edge",
        "HKLM\SOFTWARE\Policies\Microsoft\EdgeUpdate",
        "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate",
        "HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR",
        "HKLM\SOFTWARE\Policies\Microsoft\Windows\Personalization",
        "HKCU\Software\Policies\Microsoft\Windows\WindowsCopilot",
        "HKCU\Software\Microsoft\Windows\CurrentVersion\Search",
        "HKCU\Software\Policies\Microsoft\Windows\Explorer",
        "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced",
        "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager",
        "HKCU\Software\Microsoft\Input\TIPC",
        "HKCU\Software\Microsoft\GameBar",
        "HKCU\Software\Microsoft\Windows\CurrentVersion\GameDVR"
    )
    $ServiceNames = @("DiagTrack","dmwappushservice","sysmain","WerSvc","WSAIFabricSvc","OneDrive","EdgeUpdate","WSearch","WpnService","MapsBroker","PhoneSvc")
    $AppxTargets = @("Copilot","549981C3F5F10","XboxApp","BingWeather","SpotifyMusic","Clipchamp","MicrosoftTeams","PowerAutomateDesktop","YourPhone","SkypeApp","Print3D","ZuneVideo","ZuneMusic")
    New-SystemStateManifest -OutputPath $ManifestPath -RegistryPaths $RegistryPaths -ServiceNames $ServiceNames -AppxPackages $AppxTargets
} catch {
    Write-RenderStatus "Could not generate initial state manifest: $_" "Warning"
}

# 9. Initial Preset Selection
$SelectedPreset = Join-Path $PresetsDir "default_debloat.json"
$PresetLoaded = $false

Write-Host "`nAvailable Presets:" -ForegroundColor Cyan
$PresetIndex = 1
$PresetList = @()

if (Test-Path $PresetsDir) {
    $PresetFiles = Get-ChildItem -Path $PresetsDir -Filter "*.json" | Sort-Object Name
    foreach ($Pf in $PresetFiles) {
        try {
            $P = Get-Content -Path $Pf.FullName -Raw | ConvertFrom-Json
            Write-Host "  [$PresetIndex] $($P.name) - $($P.description)" -ForegroundColor White
            $PresetList += $Pf.FullName
            $PresetIndex++
        } catch {
            Write-Host "  [$PresetIndex] $($Pf.Name) (invalid JSON)" -ForegroundColor DarkGray
            $PresetList += $Pf.FullName
            $PresetIndex++
        }
    }
}

Write-Host "  [$PresetIndex] Deep Debloat (all modules aggressive)" -ForegroundColor Yellow
$PresetList += "deep"
$PresetIndex++

Write-Host "  [$PresetIndex] Skip preset (manual selection)" -ForegroundColor DarkGray
$PresetList += "manual"

do {
    $PresetChoice = Read-Host -Prompt "`nSelect preset [1-$PresetIndex] (default: 1)"
    if (-not $PresetChoice) { $PresetChoice = "1" }

    $Idx = [int]$PresetChoice
    if ($Idx -ge 1 -and $Idx -le $PresetList.Count) {
        $SelectedPreset = $PresetList[$Idx - 1]
        $PresetLoaded = $true
        break
    }

    Write-Host "Invalid preset selection." -ForegroundColor Red
} while ($true)

if ($SelectedPreset -eq "manual") {
    Write-Host "`nManual mode selected. You will choose individual operations from the menu." -ForegroundColor Yellow
} elseif ($SelectedPreset -eq "deep") {
    Write-Host "`nDeep Debloat selected. All modules will run aggressively." -ForegroundColor Yellow
    $PresetLoaded = $true
} else {
    Write-RenderStatus "Preset loaded: $SelectedPreset" "Success"
}

$PresetConfigs = @{}
if ($SelectedPreset -ne "deep" -and $SelectedPreset -ne "manual") {
    $PresetConfigs = Resolve-PresetConfigs -PresetFile $SelectedPreset
}

# 10. Main Menu Execution Loop
do {
    $Choice = Show-DebloatMenu -PresetLoaded ($SelectedPreset -ne "manual")

    switch ($Choice) {
        "1" {
            Show-HeaderBanner
            Write-RenderStatus "Starting Full Debloat Sequence..." "Header"

            $null = Create-Win11RestorePoint -Description "Win11Debloat Full System Cleanup"

            if ($SelectedPreset -eq "deep" -or $PresetConfigs.flags.ai) {
                Write-RenderStatus "Running AI Component Neutralization..." "Info"
                $AiCfg = Join-Path $ConfigDir "ai_components.json"
                if (-not (Test-Path $AiCfg)) { $AiCfg = $PresetConfigs.ai }
                Invoke-AiComponentNeutralization -ConfigPath $AiCfg
            }

            if ($SelectedPreset -eq "deep" -or $PresetConfigs.flags.appx) {
                $AppxCfg = Join-Path $ConfigDir "bloatware_apps.json"
                if (-not $PresetConfigs.bloatware) { $AppxCfg = $PresetConfigs.bloatware }
                Remove-DebloatAppxPackages -ConfigPath $AppxCfg
            }

            if ($SelectedPreset -eq "deep" -or $PresetConfigs.flags.registry) {
                $RegCfg = Join-Path $ConfigDir "registry_tweaks.json"
                if (-not $PresetConfigs.registry) { $RegCfg = $PresetConfigs.registry }
                Apply-RegistryTweaks -ConfigPath $RegCfg -BackupDir $BackupDir
            }

            if ($SelectedPreset -eq "deep" -or $PresetConfigs.flags.services) {
                $SvcCfg = Join-Path $ConfigDir "services_list.json"
                if (-not $PresetConfigs.services) { $SvcCfg = $PresetConfigs.services }
                Apply-ServiceAndTaskTweaks -ConfigPath $SvcCfg
            }

            Write-RenderStatus "Full Debloat Sequence Finished successfully!" "Success"
            Read-Host "`nPress Enter to return to menu..."
        }
        "2" {
            Show-HeaderBanner
            $null = Create-Win11RestorePoint -Description "Win11Debloat AppX Purge Backup"
            $AppxCfg = Join-Path $ConfigDir "bloatware_apps.json"
            if ($PresetConfigs.bloatware) { $AppxCfg = $PresetConfigs.bloatware }
            Remove-DebloatAppxPackages -ConfigPath $AppxCfg
            Read-Host "`nPress Enter to return to menu..."
        }
        "3" {
            Show-HeaderBanner
            $null = Create-Win11RestorePoint -Description "Win11Debloat Registry Tweaks Backup"
            $RegCfg = Join-Path $ConfigDir "registry_tweaks.json"
            if ($PresetConfigs.registry) { $RegCfg = $PresetConfigs.registry }
            Apply-RegistryTweaks -ConfigPath $RegCfg -BackupDir $BackupDir
            Read-Host "`nPress Enter to return to menu..."
        }
        "4" {
            Show-HeaderBanner
            $null = Create-Win11RestorePoint -Description "Win11Debloat Services Tweak Backup"
            $SvcCfg = Join-Path $ConfigDir "services_list.json"
            if ($PresetConfigs.services) { $SvcCfg = $PresetConfigs.services }
            Apply-ServiceAndTaskTweaks -ConfigPath $SvcCfg
            Read-Host "`nPress Enter to return to menu..."
        }
        "5" {
            Show-HeaderBanner
            Write-RenderStatus "Starting AI Component Neutralization..." "Header"
            $AiCfg = Join-Path $ConfigDir "ai_components.json"
            if ($PresetConfigs.ai) { $AiCfg = $PresetConfigs.ai }
            if (-not (Test-Path $AiCfg)) {
                Write-RenderStatus "AI components config missing at: $AiCfg" "Error"
            } else {
                Invoke-AiComponentNeutralization -ConfigPath $AiCfg
            }
            Read-Host "`nPress Enter to return to menu..."
        }
        "6" {
            Show-HeaderBanner
            $null = Create-Win11RestorePoint -Description "Win11Debloat Manual System Restore Point"
            Read-Host "`nPress Enter to return to menu..."
        }
        "7" {
            Show-HeaderBanner
            Write-RenderStatus "Initiating Rollback from latest state manifest..." "Header"
            Invoke-Rollback -ManifestPath $ManifestPath
            Read-Host "`nPress Enter to return to menu..."
        }
        "8" {
            Show-HeaderBanner
            Write-RenderStatus "Running standalone build compatibility check..." "Header"
            & (Join-Path $ModulesDir "..\utils\Invoke-BuildCheck.ps1")
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
