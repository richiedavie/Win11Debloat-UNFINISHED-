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
        $AllProvisionedPackages = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue

        foreach ($AppName in $Targets) {
            $FoundAny = $false

            $MatchingUserPkgs = $AllUserPackages | Where-Object { 
                $_.Name -like "*$AppName*" -or $_.PackageFullName -like "*$AppName*"
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

                $Blocklist = @()
                if (Get-ItemProperty -Path $EdgePolicyPath -Name $ExtensionBlocklist -ErrorAction SilentlyContinue) {
                    $Blocklist = (Get-ItemProperty -Path $EdgePolicyPath -Name $ExtensionBlocklist).$ExtensionBlocklist
                    if (-not $Blocklist) { $Blocklist = @() }
                }
                if ($Blocklist -notcontains $ExtId) {
                    $Blocklist += $ExtId
                }

                Set-ItemProperty -Path $EdgePolicyPath -Name $ExtensionBlocklist -Value $Blocklist -Force -ErrorAction Stop | Out-Null
                Write-RenderStatus "Blocked Edge AI extension: $ExtId" "Success"
                Log-DebloatAction "AI-Edge-Block" "Blocked extension $ExtId"
            } catch {
                Write-RenderStatus "Failed to block Edge extension $ExtId : $_" "Warning"
            }
        }
    }

    Write-RenderStatus "AI Component Neutralization Completed." "Success"
}
