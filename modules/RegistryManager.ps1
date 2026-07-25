function Get-ActiveUserSid {
    try {
        $userProfile = Get-CimInstance -ClassName Win32_UserProfile -Filter "Special=False AND Loaded=True" -ErrorAction Stop | Select-Object -First 1
        if ($userProfile) {
            $sid = ($userProfile.SID).Value
            return $sid
        }
    } catch {}
    try {
        $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
        return $currentUser.User.Value
    } catch {}
    return $null
}

function Get-UserHiveFromSid {
    param([string]$Sid)
    if (-not $Sid) { return $null }
    $ntuserDat = "C:\Users\$((Get-CimInstance -ClassName Win32_UserAccount -Filter "SID='$Sid'" -ErrorAction SilentlyContinue).Name)\NTUSER.DAT"
    if (Test-Path $ntuserDat) {
        return $ntuserDat
    }
    return $null
}

function Set-TrustedInstallerRegistryAcl {
    param (
        [string]$Path
    )
    try {
        $acl = Get-Acl -Path $Path -ErrorAction Stop
        $sid = [Security.Principal.SecurityIdentifier]::new("S-1-5-80-956008885-3418522649-1831038044-1853292631-227147846")
        $rule = New-Object System.Security.AccessControl.RegistryAccessRule(
            $sid,
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

function Apply-RegistryTweaks {
    param (
        [string]$ConfigPath,
        [string]$BackupDir
    )

    if (-not (Test-Path $ConfigPath)) {
        Write-RenderStatus "Configuration file not found: $ConfigPath" "Error"
        return
    }

    try {
        $Tweaks = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
    } catch {
        Write-RenderStatus "Failed to parse JSON configuration file: $ConfigPath" "Error"
        return
    }

    Write-RenderStatus "Applying Registry Policy Injections..." "Header"

    $RegistryTweakError = $null
    try {
        foreach ($Tweak in $Tweaks) {
            $Hive = $Tweak.hive
            $Path = $Tweak.path
            $Name = $Tweak.name
            $Value = $Tweak.value
            
            $Type = "DWord"
            if ($Tweak.type) { $Type = $Tweak.type }
            
            $Description = $Tweak.description

            Backup-RegistryKey -Hive $Hive -Path $Path -BackupDir $BackupDir

            $PsDrivePath = "${Hive}:\$Path"

            try {
                if (-not (Test-Path -Path $PsDrivePath)) {
                    New-Item -Path $PsDrivePath -Force | Out-Null
                }

                $aclTaken = Set-TrustedInstallerRegistryAcl -Path $PsDrivePath
                if (-not $aclTaken) {
                    Write-RenderStatus "Warning: Could not take ownership of $PsDrivePath" "Warning"
                }

                if (Get-ItemProperty -Path $PsDrivePath -Name $Name -ErrorAction SilentlyContinue) {
                    Set-ItemProperty -Path $PsDrivePath -Name $Name -Value $Value -Force -ErrorAction Stop | Out-Null
                } else {
                    New-ItemProperty -Path $PsDrivePath -Name $Name -Value $Value -PropertyType $Type -Force -ErrorAction Stop | Out-Null
                }

                Write-RenderStatus "Applied: [${Hive}\$Path] $Name = $Value ($Description)" "Success"
                Log-DebloatAction "Registry-Tweak" "Applied [${Hive}\$Path] $Name = $Value"
            }
            catch {
                try {
                    $RegHive = "HKCU"
                    if ($Hive -eq "HKLM") { $RegHive = "HKLM" }
                    
                    $RegType = "REG_SZ"
                    if ($Type -eq "DWord") { $RegType = "REG_DWORD" }
                    
                    $null = reg add "$RegHive\$Path" /v "$Name" /t $RegType /d "$Value" /f 2>&1
                    Write-RenderStatus "Applied via REG.EXE: [${Hive}\$Path] $Name = $Value ($Description)" "Success"
                    Log-DebloatAction "Registry-Tweak" "Applied via REG.EXE [${Hive}\$Path] $Name = $Value"
                }
                catch {
                    Write-RenderStatus "Failed to apply registry tweak [${Hive}\$Path] $($Name): $_" "Warning"
                    Log-DebloatAction "Registry-Tweak" "FAILED [${Hive}\$Path] $Name - $_"
                    $RegistryTweakError = $_
                }
            }
        }
    }
    catch {
        Write-RenderStatus "Critical failure during registry tweak application: $_" "Error"
        Log-DebloatAction "Registry-Tweak" "CRITICAL FAILURE: $_"
        $RegistryTweakError = $_
    }

    if ($RegistryTweakError) {
        Write-RenderStatus "Registry operation encountered errors. Initiating automatic rollback..." "Warning"
        try {
            Invoke-Rollback -ManifestPath $ManifestPath
            Write-RenderStatus "Automatic rollback completed due to registry failures." "Success"
        } catch {
            Write-RenderStatus "Automatic rollback failed: $_" "Error"
        }
    }

    Write-RenderStatus "Registry Policy Injections Completed." "Success"
}