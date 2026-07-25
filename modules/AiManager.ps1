# AiManager.ps1 - Recall, Copilot, ClickToDo & WSAI Neutralization Engine

function Invoke-AiComponentNeutralization {
    param (
        [string]$ConfigPath,
        [switch]$DryRun
    )

    if (-not (Test-Path $ConfigPath)) {
        Write-RenderStatus "AI components config not found: $ConfigPath" "Error"
        return
    }

    try {
        $Config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
    } catch {
        Write-RenderStatus "Failed to parse AI components JSON: $ConfigPath" "Error"
        return
    }

    Write-RenderStatus "Starting AI Component Neutralization..." "Header"

    $IsOnline = $true
    try {
        $IsOnline = Test-InternetConnectivity
    } catch {}
    if (-not $IsOnline) {
        Write-RenderStatus "No active internet connection detected. Skipping online-dependent AppX provisioning operations." "Warning"
        Write-RenderStatus "Proceeding with offline registry policies and service management only." "Info"
    }

    if ($Config.registry_policies) {
        foreach ($Reg in $Config.registry_policies) {
            $Hive = $Reg.hive
            $Path = $Reg.path
            $Name = $Reg.name
            $Value = $Reg.value
            $Type = $Reg.type
            $Desc = $Reg.description

            $PsDrivePath = "${Hive}:\$Path"

            if ($DryRun) {
                Write-RenderStatus "[DRYRUN] Would set ${Hive}\$Path\$Name = $Value ($Desc)" "Muted"
                continue
            }

            try {
                if (-not (Test-Path -Path $PsDrivePath)) {
                    New-Item -Path $PsDrivePath -Force | Out-Null
                }

                if (Get-ItemProperty -Path $PsDrivePath -Name $Name -ErrorAction SilentlyContinue) {
                    Set-ItemProperty -Path $PsDrivePath -Name $Name -Value $Value -Force -ErrorAction Stop | Out-Null
                } else {
                    New-ItemProperty -Path $PsDrivePath -Name $Name -Value $Value -PropertyType $Type -Force -ErrorAction Stop | Out-Null
                }

                Write-RenderStatus "Applied AI policy: ${Hive}\$Path\$Name = $Value ($Desc)" "Success"
                Log-DebloatAction "AI-Registry-Policy" "Applied ${Hive}\$Path\$Name = $Value"
            } catch {
                Write-RenderStatus "Failed to apply AI policy ${Hive}\$Path\$($Name): $_" "Warning"
                Log-DebloatAction "AI-Registry-Policy" "FAILED ${Hive}\$Path\$Name - $_"
            }
        }
    }

    if ($Config.services) {
        foreach ($Svc in $Config.services) {
            $SvcName = $Svc.name
            $Action = $Svc.action
            $Desc = $Svc.description

            if ($DryRun) {
                Write-RenderStatus "[DRYRUN] Would $Action service: $SvcName ($Desc)" "Muted"
                continue
            }

            $ServiceObj = Get-Service -Name $SvcName -ErrorAction SilentlyContinue
            if ($ServiceObj) {
                try {
                    if ($Action -match "Disable|Stop") {
                        Stop-Service -Name $SvcName -Force -ErrorAction SilentlyContinue
                    }
                    if ($Action -match "Disable") {
                        Set-Service -Name $SvcName -StartupType Disabled -ErrorAction Stop
                        Write-RenderStatus "Disabled AI service: $SvcName ($Desc)" "Success"
                        Log-DebloatAction "AI-Service-Disable" "Disabled $SvcName"
                    } elseif ($Action -match "Start") {
                        Set-Service -Name $SvcName -StartupType Automatic -ErrorAction Stop
                        Write-RenderStatus "Enabled AI service: $SvcName ($Desc)" "Success"
                        Log-DebloatAction "AI-Service-Enable" "Enabled $SvcName"
                    }
                } catch {
                    try {
                        if ($Action -match "Disable") {
                            $null = sc.exe stop "$SvcName" 2>&1
                            $null = sc.exe config "$SvcName" start= disabled 2>&1
                        } elseif ($Action -match "Start") {
                            $null = sc.exe config "$SvcName" start= auto 2>&1
                            $null = sc.exe start "$SvcName" 2>&1
                        }
                        Write-RenderStatus "Managed service via SC.EXE: $SvcName ($Action)" "Success"
                        Log-DebloatAction "AI-Service-Manage" "$Action $SvcName via SC.EXE"
                    } catch {
                        Write-RenderStatus "Failed to manage AI service $($SvcName): $_" "Warning"
                    }
                }
            } else {
                Write-RenderStatus "AI service not present on system: $SvcName" "Muted"
            }
        }
    }

    if ($Config.appx_packages) {
        $Targets = $Config.appx_packages
        $AllUserPackages = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue
        if ($IsOnline) {
            $AllProvisionedPackages = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
        } else {
            $AllProvisionedPackages = @()
        }

        foreach ($AppName in $Targets) {
            $FoundAny = $false

            $MatchingUserPkgs = $AllUserPackages | Where-Object { 
                $_.Name -like "*$AppName*" -or $_.PackageFullName -like "*$AppName*" -or $_.PackageFamilyName -like "*$AppName*"
            }

            if ($MatchingUserPkgs) {
                foreach ($Pkg in $MatchingUserPkgs) {
                    $FoundAny = $true
                    if ($DryRun) {
                        Write-RenderStatus "[DRYRUN] Would remove AppX: $($Pkg.PackageFullName)" "Muted"
                        continue
                    }
                    try {
                        Remove-AppxPackage -Package $Pkg.PackageFullName -AllUsers -ErrorAction Stop
                        Write-RenderStatus "Removed AI AppX: $($Pkg.PackageFullName)" "Success"
                        Log-DebloatAction "AI-AppX-Remove" "Removed $($Pkg.PackageFullName)"
                    } catch {
                        try {
                            Remove-AppxPackage -Package $Pkg.PackageFullName -ErrorAction Stop
                            Write-RenderStatus "Removed AI AppX (CurrentUser): $($Pkg.PackageFullName)" "Success"
                            Log-DebloatAction "AI-AppX-Remove" "Removed (CurrentUser) $($Pkg.PackageFullName)"
                        } catch {
                            Write-RenderStatus "Failed AI AppX removal $($Pkg.PackageFullName): $_" "Warning"
                        }
                    }
                }
            }

            if ($IsOnline) {
                $MatchingProvPkgs = $AllProvisionedPackages | Where-Object { 
                    $_.DisplayName -like "*$AppName*" -or $_.PackageName -like "*$AppName*"
                }

                if ($MatchingProvPkgs) {
                    foreach ($ProvPkg in $MatchingProvPkgs) {
                        $FoundAny = $true
                        if ($DryRun) {
                            Write-RenderStatus "[DRYRUN] Would purge provisioned AI package: $($ProvPkg.PackageName)" "Muted"
                            continue
                        }
                        try {
                            Remove-AppxProvisionedPackage -Online -PackageName $ProvPkg.PackageName -ErrorAction Stop | Out-Null
                            Write-RenderStatus "Purged provisioned AI package: $($ProvPkg.PackageName)" "Success"
                            Log-DebloatAction "AI-Provisioned-Purge" "Purged $($ProvPkg.PackageName)"
                        } catch {
                            try {
                                $null = dism.exe /Online /Remove-ProvisionedAppxPackage /PackageName:"$($ProvPkg.PackageName)" 2>&1
                                Write-RenderStatus "Purged AI package via DISM: $($ProvPkg.PackageName)" "Success"
                                Log-DebloatAction "AI-Provisioned-Purge" "Purged via DISM $($ProvPkg.PackageName)"
                            } catch {
                                Write-RenderStatus "Failed AI provisioned purge $($ProvPkg.PackageName): $_" "Warning"
                            }
                        }
                    }
                }
            } else {
                Write-RenderStatus "Skipping provisioned package purge for $AppName (offline mode)" "Muted"
            }

            if (-not $FoundAny) {
                Write-RenderStatus "No AI package found matching: *$AppName*" "Muted"
            }
        }
    }

    if ($Config.edge_extensions) {
        foreach ($ExtId in $Config.edge_extensions) {
            if ($DryRun) {
                Write-RenderStatus "[DRYRUN] Would purge Edge extension: $ExtId" "Muted"
                continue
            }

            $EdgePolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
            $ExtensionForceInstall = "ExtensionInstallForcelist"
            $ExtensionBlocklist = "ExtensionInstallBlocklist"

            try {
                if (-not (Test-Path $EdgePolicyPath)) {
                    New-Item -Path $EdgePolicyPath -Force | Out-Null
                }

                $ExistingBlocklist = Get-ItemProperty -Path $EdgePolicyPath -Name $ExtensionBlocklist -ErrorAction SilentlyContinue
                [string[]]$Blocklist = @()
                if ($ExistingBlocklist -and $ExistingBlocklist.$ExtensionBlocklist) {
                    $Blocklist = $ExistingBlocklist.$ExtensionBlocklist | ForEach-Object { [string]$_ }
                }
                if ($Blocklist -notcontains $ExtId) {
                    $Blocklist += $ExtId
                }

                Set-ItemProperty -Path $EdgePolicyPath -Name $ExtensionBlocklist -Value ([string[]]$Blocklist) -Force -ErrorAction Stop | Out-Null
                Write-RenderStatus "Blocked Edge AI extension: $ExtId" "Success"
                Log-DebloatAction "AI-Edge-Block" "Blocked extension $ExtId"
            } catch {
                try {
                    $regCmd = "reg add `"HKLM\SOFTWARE\Policies\Microsoft\Edge`" /v `"ExtensionInstallBlocklist`" /t REG_MULTI_SZ /d `"$ExtId`" /f"
                    $null = cmd.exe /c $regCmd 2>&1
                    Write-RenderStatus "Blocked Edge AI extension via REG.EXE: $ExtId" "Success"
                    Log-DebloatAction "AI-Edge-Block" "Blocked extension $ExtId via REG.EXE"
                } catch {
                    try {
                        $escapedExt = $ExtId -replace '\\', '\\\\'
                        $regCmd = "powershell.exe -Command `"Set-ItemProperty -Path 'HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge' -Name 'ExtensionInstallBlocklist' -Value ([string[]]@('$escapedExt')) -Force`""
                        $null = cmd.exe /c $regCmd 2>&1
                        Write-RenderStatus "Blocked Edge AI extension via PowerShell hybrid: $ExtId" "Success"
                        Log-DebloatAction "AI-Edge-Block" "Blocked extension $ExtId via PowerShell hybrid"
                    } catch {
                        Write-RenderStatus "Failed to block Edge extension $ExtId : $_" "Warning"
                    }
                }
            }
        }
    }

if ($Config.post_wu_guard) {
        Write-RenderStatus "Setting up post-Windows Update AI policy re-application guard..." "Info"
        try {
            $guardTaskName = "Win11Debloat_AIPolicyReapply"
            $guardTaskPath = "\Microsoft\Windows\Win11Debloat\"
            $guardAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command `"Invoke-AiComponentNeutralization -ConfigPath '$ConfigPath'`""
            $guardTrigger = New-ScheduledTaskTrigger -AtLogOn
            $guardSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 10)
            $guardPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
            
            try {
                $existingTask = Get-ScheduledTask -TaskPath $guardTaskPath -TaskName $guardTaskName -ErrorAction SilentlyContinue
                if ($existingTask) {
                    Register-ScheduledTask -TaskPath $guardTaskPath -TaskName $guardTaskName -Action $guardAction -Trigger $guardTrigger -Settings $guardSettings -Principal $guardPrincipal -Force -ErrorAction Stop | Out-Null
                } else {
                    Register-ScheduledTask -TaskPath $guardTaskPath -TaskName $guardTaskName -Action $guardAction -Trigger $guardTrigger -Settings $guardSettings -Principal $guardPrincipal -ErrorAction Stop | Out-Null
                }
                Write-RenderStatus "Post-WU AI policy guard task registered successfully." "Success"
            } catch {
                Write-RenderStatus "Could not register post-WU guard task: $_" "Warning"
            }
        } catch {
            Write-RenderStatus "Could not set up post-Windows Update guard: $_" "Warning"
        }
    }

    Write-RenderStatus "AI Component Neutralization Completed." "Success"
}
