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

function Enable-ComputerRestore {
    param (
        [string]$Drive = "C:\"
    )
    
    try {
        Import-Module Microsoft.PowerShell.Management -ErrorAction Stop | Out-Null
    } catch {
        Write-RenderStatus "Could not import Microsoft.PowerShell.Management module. Attempting manual restore enable..." "Warning"
    }
    
    try {
        $null = Enable-ComputerRestore -Drive $Drive -ErrorAction SilentlyContinue
        Write-RenderStatus "Enabled System Restore on $Drive" "Success"
        return $true
    } catch {
        try {
            $vssCmd = "vssadmin create shadow /for=$Drive /quiet 2>&1"
            $null = Invoke-Expression $vssCmd
            if ($LASTEXITCODE -eq 0) {
                Write-RenderStatus "Verified System Restore availability via VSS shadow creation on $Drive" "Success"
                return $true
            }
        } catch {}
        
        try {
            $regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore"
            if (-not (Test-Path $regPath)) {
                New-Item -Path $regPath -Force | Out-Null
            }
            Set-ItemProperty -Path $regPath -Name "DisableSR" -Value 0 -Type DWord -Force -ErrorAction Stop | Out-Null
            Write-RenderStatus "Enabled System Restore via registry on $Drive" "Success"
            return $true
        } catch {
            Write-RenderStatus "Could not enable System Restore on ${Drive}: $_" "Warning"
            return $false
        }
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

        $restoreEnabled = $false
        try {
            $srEnabled = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" -Name "DisableSR" -ErrorAction SilentlyContinue).DisableSR
            if ($srEnabled -ne 1) {
                $restoreEnabled = $true
            }
        } catch {}
        
        if (-not $restoreEnabled) {
            $restoreEnabled = Enable-ComputerRestore -Drive "C:\"
        }
        
        if (-not $restoreEnabled) {
            Write-RenderStatus "Skipping restore point - System Restore not available on C:." "Warning"
            Log-DebloatAction "Create-RestorePoint" "Skipped (System Restore disabled)"
            return $false
        }

        $null = Checkpoint-Computer -Description $Description -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
        Write-RenderStatus "Successfully created System Restore Point: '$Description'" "Success"
        Log-DebloatAction "Create-RestorePoint" "Successfully created System Restore Point: $Description"
        return $true
    }
    catch {
        if ($_ -like "*1440 minutes*" -or $_ -like "*restore point already created*") {
            Write-RenderStatus "A restore point was already created within the last 24 hours (system limit). Continuing..." "Info"
            Log-DebloatAction "Create-RestorePoint" "Skipped (created within last 24h limit)"
            return $true
        } elseif ($_ -match "0x80042302|VSS|shadow") {
            Write-RenderStatus "VSS or shadow storage issue. Attempting shadow creation..." "Warning"
            try {
                $shadowResult = vssadmin create shadow /for=C: /quiet 2>&1 | Out-String
                if ($shadowResult -match "successfully") {
                    $null = Checkpoint-Computer -Description $Description -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
                    Write-RenderStatus "Successfully created System Restore Point after shadow reset: '$Description'" "Success"
                    Log-DebloatAction "Create-RestorePoint" "Successfully created System Restore Point after shadow reset: $Description"
                    return $true
                }
            } catch {
                Write-RenderStatus "Could not create System Restore Point after shadow attempts: $_" "Warning"
                Log-DebloatAction "Create-RestorePoint" "FAILED after shadow attempts: $_"
            }
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
