# SafetyManager.ps1 - Manages System Restore Points and Registry Backups

function Create-Win11RestorePoint {
    param (
        [string]$Description = "Win11Debloat Auto-Restore Point"
    )
    Write-RenderStatus "Initiating System Restore Point creation..." "Info"
    try {
        # Checkpoint-Computer will auto-enable restore if needed on client SKUs
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
