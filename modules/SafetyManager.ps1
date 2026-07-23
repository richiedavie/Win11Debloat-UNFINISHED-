# SafetyManager.ps1 - Manages System Restore Points and Registry Backups

function Enable-VolumeShadowCopy {
    try {
        $vssSvc = Get-Service -Name "VSS" -ErrorAction SilentlyContinue
        if (-not $vssSvc) { return $true }

        if ($vssSvc.Status -ne 'Running') {
            Write-RenderStatus "Starting Volume Shadow Copy service for restore point support..." "Info"
            if ($vssSvc.StartType -eq 'Disabled') {
                try {
                    Set-Service -Name "VSS" -StartupType Manual -ErrorAction Stop | Out-Null
                } catch {
                    $null = sc.exe config "VSS" start= demand 2>&1 | Out-Null
                }
            }
            try {
                Start-Service -Name "VSS" -ErrorAction Stop | Out-Null
            } catch {
                $null = sc.exe start "VSS" 2>&1 | Out-Null
            }
            Write-RenderStatus "Volume Shadow Copy service started." "Success"
        }
        return $true
    } catch {
        Write-RenderStatus "Volume Shadow Copy service unavailable: $_" "Warning"
        return $false
    }
}

function Create-Win11RestorePoint {
    param (
        [string]$Description = "Win11Debloat Auto-Restore Point"
    )
    Write-RenderStatus "Initiating System Restore Point creation..." "Info"
    try {
        $vssReady = Enable-VolumeShadowCopy
        if (-not $vssReady) {
            Write-RenderStatus "Skipping restore point - VSS service unavailable." "Warning"
            Log-DebloatAction "Create-RestorePoint" "Skipped (VSS unavailable)"
            return $false
        }

        $null = Checkpoint-Computer -Description $Description -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
        Write-RenderStatus "Successfully created System Restore Point: '$Description'" "Success"
        Log-DebloatAction "Create-RestorePoint" "Successfully created System Restore Point: $Description"
        return $true
    }
    catch {
        if ($_ -like "*1440 minutes*") {
            Write-RenderStatus "A restore point was already created within the last 24 hours (system limit). Continuing..." "Info"
            Log-DebloatAction "Create-RestorePoint" "Skipped (created within last 24h limit)"
        } else {
            Write-RenderStatus "Could not create System Restore Point: $_" "Warning"
            Log-DebloatAction "Create-RestorePoint" "FAILED: $_"
        }
        return $false
    }
}


function Backup-RegistryKey {
    param (
        [string]$Hive,
        [string]$Path,
        [string]$BackupDir
    )
    if (-not (Test-Path $BackupDir)) {
        New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    }
    
    $SanitizedPath = $Path -replace '\\', '_'
    $TargetFile = Join-Path $BackupDir "$Hive`_$SanitizedPath.reg"
    
    Write-RenderStatus "Backing up registry key $Hive\$Path..." "Info"
    try {
        $RegPath = "$Hive\$Path"
        $null = reg export "$RegPath" "$TargetFile" /y 2>&1
        Log-DebloatAction "Backup-RegistryKey" "Exported $RegPath to $TargetFile"
    }
    catch {
        Log-DebloatAction "Backup-RegistryKey" "Key $Hive\$Path did not exist or failed to backup."
    }
}
