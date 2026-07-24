# AppxManager.ps1 - UWP / AppX Package Purging Engine (24H2/25H2 Hardened)

$ProtectedSystemPackages = @(
    "MicrosoftWindows.Client.Photon",
    "Microsoft.Windows.PeopleExperienceHost",
    "Microsoft.Windows.PinToAI",
    "Microsoft.Windows.Widgets",
    "Microsoft.Windows.AI.Copilot",
    "Microsoft.Windows.Photos",
    "Microsoft.Paint",
    "Microsoft.PrintExperienceHost",
    "Microsoft.SecureAssessmentPlatform",
    "Microsoft.Windows.SecureAssessmentBrowser",
    "Microsoft.Windows.StartMenuExperienceHost",
    "Microsoft.Windows.ShellExperienceHost",
    "MicrosoftWindows.Client.CBS",
    "Microsoft.Windows.AppRep.ChxApp",
    "Microsoft.Windows.CloudExperienceHost",
    "Microsoft.Windows.IoTShellOnboarding"
)

function Is-ProtectedSystemPackage {
    param([string]$PackageName)
    
    foreach ($Protected in $ProtectedSystemPackages) {
        if ($PackageName -like "*$Protected*" -or $Protected -like "*$PackageName*") {
            return $true
        }
    }
    return $false
}

function Remove-DebloatAppxPackages {
    param (
        [string]$ConfigPath
    )

    if (-not (Test-Path $ConfigPath)) {
        Write-RenderStatus "Configuration file not found: $ConfigPath" "Error"
        return
    }

    try {
        $Config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
    } catch {
        Write-RenderStatus "Failed to parse JSON configuration file: $ConfigPath" "Error"
        return
    }

    $Targets = @()
    if ($Config.ai_copilot_apps) { $Targets += $Config.ai_copilot_apps }
    if ($Config.stock_bloatware_apps) { $Targets += $Config.stock_bloatware_apps }

    # Deduplicate targets while preserving search patterns
    $UniqueTargets = @()
    $Seen = @{}
    foreach ($Target in $Targets) {
        if (-not $Seen.ContainsKey($Target.ToLower())) {
            $UniqueTargets += $Target
            $Seen[$Target.ToLower()] = $true
        }
    }
    $Targets = $UniqueTargets

    Write-RenderStatus "Beginning AppX Package Purging Process..." "Header"
    Write-RenderStatus "Targeting $($Targets.Count) unique package patterns across installed and provisioned stores." "Info"

    # Pre-fetch ALL installed and provisioned packages aggressively
    $AllUserPackages = @()
    try {
        $AllUserPackages = Get-AppxPackage -AllUsers -ErrorAction Stop
    } catch {
        $AllUserPackages = Get-AppxPackage -ErrorAction SilentlyContinue
    }
    
    $AllProvisionedPackages = @()
    try {
        $AllProvisionedPackages = Get-AppxProvisionedPackage -Online -ErrorAction Stop
    } catch {
        $AllProvisionedPackages = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
    }

    $RemovedCount = 0
    $SkippedCount = 0
    $FailedCount = 0

    foreach ($AppName in $Targets) {
        $FoundAny = $false

        # 1. Match Installed AppX Packages - AGGRESSIVE MULTI-PROPERTY MATCHING
        $MatchingUserPkgs = @()
        foreach ($Pkg in $AllUserPackages) {
            $NameMatch = $Pkg.Name -like "*$AppName*"
            $PkgFullNameMatch = $Pkg.PackageFullName -like "*$AppName*"
            $FamilyMatch = $false
            try { $FamilyMatch = $Pkg.PackageFamilyName -like "*$AppName*" } catch {}
            
            if ($NameMatch -or $PkgFullNameMatch -or $FamilyMatch) {
                $MatchingUserPkgs += $Pkg
            }
        }

        if ($MatchingUserPkgs) {
            foreach ($Pkg in $MatchingUserPkgs) {
                $FoundAny = $true
                
                if (Is-ProtectedSystemPackage -PackageName $Pkg.PackageFullName) {
                    Write-RenderStatus "Protected system app (skipped): $($Pkg.PackageFullName)" "Muted"
                    Log-DebloatAction "AppX-User-Remove" "SKIPPED (protected system app): $($Pkg.PackageFullName)"
                    $SkippedCount++
                    continue
                }

                try {
                    Write-RenderStatus "Removing installed package: $($Pkg.PackageFullName)" "Info"
                    Remove-AppxPackage -Package $Pkg.PackageFullName -AllUsers -ErrorAction Stop
                    Write-RenderStatus "Removed installed package: $($Pkg.PackageFullName)" "Success"
                    Log-DebloatAction "AppX-User-Remove" "Removed $($Pkg.PackageFullName)"
                    $RemovedCount++
                }
                catch {
                    try {
                        Remove-AppxPackage -Package $Pkg.PackageFullName -ErrorAction Stop
                        Write-RenderStatus "Removed installed package (CurrentUser): $($Pkg.PackageFullName)" "Success"
                        Log-DebloatAction "AppX-User-Remove" "Removed (CurrentUser) $($Pkg.PackageFullName)"
                        $RemovedCount++
                    } catch {
                        if ($_ -match "0x80073CFA|part of Windows|cannot be uninstalled|Turn Windows Features") {
                            Write-RenderStatus "Protected system app (skipped): $($Pkg.PackageFullName)" "Muted"
                            Log-DebloatAction "AppX-User-Remove" "SKIPPED (protected system app): $($Pkg.PackageFullName)"
                            $SkippedCount++
                        } else {
                            Write-RenderStatus "Failed to remove user package $($Pkg.PackageFullName): $_" "Warning"
                            Log-DebloatAction "AppX-User-Remove" "FAILED: $($Pkg.PackageFullName) - $_"
                            $FailedCount++
                        }
                    }
                }
            }
        }

        # 2. Match Provisioned AppX Blueprint Packages - AGGRESSIVE MATCHING
        $MatchingProvPkgs = @()
        foreach ($ProvPkg in $AllProvisionedPackages) {
            $DisplayMatch = $ProvPkg.DisplayName -like "*$AppName*"
            $PkgNameMatch = $ProvPkg.PackageName -like "*$AppName*"
            
            if ($DisplayMatch -or $PkgNameMatch) {
                $MatchingProvPkgs += $ProvPkg
            }
        }

        if ($MatchingProvPkgs) {
            foreach ($ProvPkg in $MatchingProvPkgs) {
                $FoundAny = $true
                
                if (Is-ProtectedSystemPackage -PackageName $ProvPkg.PackageName) {
                    Write-RenderStatus "Protected provisioned app (skipped): $($ProvPkg.PackageName)" "Muted"
                    Log-DebloatAction "AppX-Provisioned-Purge" "SKIPPED (protected): $($ProvPkg.PackageName)"
                    $SkippedCount++
                    continue
                }

                try {
                    Write-RenderStatus "Purging provisioned package blueprint: $($ProvPkg.PackageName)" "Info"
                    Remove-AppxProvisionedPackage -Online -PackageName $ProvPkg.PackageName -ErrorAction Stop | Out-Null
                    Write-RenderStatus "Purged provisioned package: $($ProvPkg.PackageName)" "Success"
                    Log-DebloatAction "AppX-Provisioned-Purge" "Purged $($ProvPkg.PackageName)"
                    $RemovedCount++
                }
                catch {
                    try {
                        $dismOutput = dism.exe /Online /Remove-ProvisionedAppxPackage /PackageName:"$($ProvPkg.PackageName)" 2>&1 | Out-String
                        if ($dismOutput -match "successfully|success") {
                            Write-RenderStatus "Purged provisioned package via DISM.EXE: $($ProvPkg.PackageName)" "Success"
                            Log-DebloatAction "AppX-Provisioned-Purge" "Purged via DISM.EXE $($ProvPkg.PackageName)"
                            $RemovedCount++
                        } else {
                            Write-RenderStatus "DISM purged provisioned package: $($ProvPkg.PackageName)" "Success"
                            Log-DebloatAction "AppX-Provisioned-Purge" "Purged via DISM $($ProvPkg.PackageName)"
                            $RemovedCount++
                        }
                    } catch {
                        Write-RenderStatus "Failed to purge provisioned package $($ProvPkg.PackageName): $_" "Warning"
                        Log-DebloatAction "AppX-Provisioned-Purge" "FAILED: $($ProvPkg.PackageName) - $_"
                        $FailedCount++
                    }
                }
            }
        }

        if (-not $FoundAny) {
            Write-RenderStatus "No installed or provisioned package found matching target pattern: *$AppName*" "Muted"
        }
    }

    # 3. Final sweep - remove any remaining provisioned packages from the system that match our target names
    Write-RenderStatus "Running final sweep for remaining provisioned packages..." "Info"
    $RemainingProv = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
    $SweepRemoved = 0
    foreach ($ProvPkg in $RemainingProv) {
        foreach ($AppName in $Targets) {
            if ($ProvPkg.PackageName -like "*$AppName*" -or $ProvPkg.DisplayName -like "*$AppName*") {
                if (Is-ProtectedSystemPackage -PackageName $ProvPkg.PackageName) { continue }
                try {
                    $null = dism.exe /Online /Remove-ProvisionedAppxPackage /PackageName:"$($ProvPkg.PackageName)" 2>&1
                    Write-RenderStatus "Final sweep purged: $($ProvPkg.PackageName)" "Success"
                    Log-DebloatAction "AppX-Provisioned-FinalSweep" "Purged $($ProvPkg.PackageName)"
                    $SweepRemoved++
                } catch {}
            }
        }
    }
    
    if ($SweepRemoved -gt 0) {
        Write-RenderStatus "Final sweep removed $SweepRemoved additional provisioned packages." "Success"
    }

    Write-RenderStatus "AppX Package Purging Completed. Removed: $RemovedCount, Skipped: $SkippedCount, Failed: $FailedCount" "Success"
}
