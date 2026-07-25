# SafetyManager.ps1 - Manages System Restore Points and Registry Backups

function Enable-VolumeShadowCopy {
    try {
        $vssSvc = Get-Service -Name "VSS" -ErrorAction SilentlyContinue
        if (-not $vssSvc) { return $true }

        if ($vssSvc.Status -ne 'Running') {
            Write-RenderStatus "Starting Volume Shadow Copy service for restore point support..." "Info"

            if ($vssSvc.StartType -eq 'Disabled') {
                Write-RenderStatus "VSS is disabled. Attempting to re-enable..." "Warning"

                $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\VSS"
                try {
                    if (Test-Path $regPath) {
                        Set-ItemProperty -Path $regPath -Name "Start" -Value 3 -Type DWord -Force -ErrorAction Stop
                        Write-RenderStatus "Set VSS startup type to Manual via registry." "Success"
                    }
                } catch {
                    Write-RenderStatus "Registry VSS re-enable failed: $_" "Warning"
                }

                try {
                    $null = sc.exe config "VSS" start= demand 2>&1
                    Write-RenderStatus "Set VSS startup type to Demand via SC.EXE." "Success"
                } catch {}

                try {
                    Set-Service -Name "VSS" -StartupType Manual -ErrorAction Stop | Out-Null
                    Write-RenderStatus "Set VSS startup type to Manual via Set-Service." "Success"
                } catch {}
            }

            try {
                Start-Service -Name "VSS" -ErrorAction Stop | Out-Null
                Write-RenderStatus "Volume Shadow Copy service started." "Success"
            } catch {
                try {
                    $null = sc.exe start "VSS" 2>&1
                    Start-Sleep -Seconds 2
                    $vssCheck = Get-Service -Name "VSS" -ErrorAction SilentlyContinue
                    if ($vssCheck -and $vssCheck.Status -eq 'Running') {
                        Write-RenderStatus "Volume Shadow Copy service started via SC.EXE." "Success"
                    } else {
                        Write-RenderStatus "VSS could not be started directly. Will attempt VSS workaround." "Warning"
                    }
                } catch {
                    Write-RenderStatus "VSS start failed. Will attempt VSS workaround." "Warning"
                }
            }
        }

        $vssAfter = Get-Service -Name "VSS" -ErrorAction SilentlyContinue
        if ($vssAfter -and $vssAfter.Status -eq 'Running') {
            return $true
        }

        Write-RenderStatus "VSS service is not running, attempting alternative shadow storage..." "Warning"
        return $true
    } catch {
        Write-RenderStatus "Volume Shadow Copy service unavailable: $_" "Warning"
        return $true
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

        $restoreEnabled = $false
        try {
            $srEnabled = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" -Name "DisableSR" -ErrorAction SilentlyContinue).DisableSR
            if ($srEnabled -ne 1) {
                $restoreEnabled = $true
            }
        } catch {}

        if (-not $restoreEnabled) {
            try {
                $regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore"
                if (-not (Test-Path $regPath)) {
                    New-Item -Path $regPath -Force | Out-Null
                }
                Set-ItemProperty -Path $regPath -Name "DisableSR" -Value 0 -Type DWord -Force -ErrorAction Stop | Out-Null
                Write-RenderStatus "Enabled System Restore via registry." "Success"
                $restoreEnabled = $true
            } catch {
                Write-RenderStatus "Could not enable System Restore via registry: $_" "Warning"
            }
        }

        if ($restoreEnabled) {
            try {
                $null = Checkpoint-Computer -Description $Description -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
                Write-RenderStatus "Successfully created System Restore Point: '$Description'" "Success"
                Log-DebloatAction "Create-RestorePoint" "Successfully created System Restore Point: $Description"
                return $true
            } catch {
                if ($_ -like "*1440 minutes*" -or $_ -like "*restore point already created*") {
                    Write-RenderStatus "A restore point was already created within the last 24 hours (system limit). Continuing..." "Info"
                    Log-DebloatAction "Create-RestorePoint" "Skipped (created within last 24h limit)"
                    return $true
                } elseif ($_ -match "0x80042302|VSS|shadow") {
                    Write-RenderStatus "VSS/shadow storage issue. Attempting vssadmin workaround..." "Warning"
                    try {
                        $shadowResult = vssadmin create shadow /for=C: /quiet 2>&1 | Out-String
                        if ($shadowResult -match "successfully") {
                            $null = Checkpoint-Computer -Description $Description -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
                            Write-RenderStatus "Created System Restore Point after VSS workaround." "Success"
                            Log-DebloatAction "Create-RestorePoint" "Created after VSS workaround: $Description"
                            return $true
                        }
                    } catch {}
                    Write-RenderStatus "Could not create restore point after VSS workaround." "Warning"
                } else {
                    Write-RenderStatus "Could not create System Restore Point: $_" "Warning"
                    Log-DebloatAction "Create-RestorePoint" "FAILED: $_"
                }
                return $false
            }
        } else {
            Write-RenderStatus "System Restore is disabled. Continuing without restore point (debloat will proceed)." "Warning"
            Log-DebloatAction "Create-RestorePoint" "Skipped (System Restore disabled)"
            return $false
        }
    } catch {
        Write-RenderStatus "Unexpected error creating restore point: $_" "Warning"
        Log-DebloatAction "Create-RestorePoint" "FAILED: $_"
        return $false
    }
}


function New-AtomicJsonFile {
    param (
        [string]$Path,
        [object]$Data
    )
    $TempPath = "${Path}.tmp"
    $Data | ConvertTo-Json -Depth 10 | Set-Content -Path $TempPath -Encoding UTF8 -ErrorAction Stop
    Move-Item -Path $TempPath -Destination $Path -Force -ErrorAction Stop
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

function Set-TrustedInstallerRegistryAcl {
    param (
        [string]$Path
    )
    try {
        $acl = Get-Acl -Path $Path -ErrorAction Stop
        $rule = New-Object System.Security.AccessControl.RegistryAccess_rule(
            [Security.Principal.SecurityIdentifier]::new("S-1-5-80-956008885-3418522649-1831038044-1853292631-227147846"),
            "FullControl",
            "Allow"
        )
        $acl.SetAccessRule($rule)
        Set-Acl -Path $Path -AclObject $acl -ErrorAction Stop
        return $true
    } catch {
        try {
            $null = icacls $Path /grant "NT SERVICE\TrustedInstaller:(OI)(CI)F" /T 2>&1
            return $true
        } catch {
            return $false
        }
    }
}

function Test-InternetConnectivity {
    param(
        [string]$TestHost = "www.microsoft.com"
    )
    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $tcpClient.Connect($TestHost, 443)
        $tcpClient.Close()
        return $true
    } catch {
        return $false
    }
}
