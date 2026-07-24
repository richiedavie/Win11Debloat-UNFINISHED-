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
    "Microsoft.Windows.IoTShellOnboarding",
    "Microsoft.Win32WebViewHost",
    "Microsoft.Windows.Notepad",
    "Microsoft.Windows.Search",
    "Microsoft.Windows.Copilot.Host",
    "Microsoft.Windows.AI.Copilot.Host",
    "Microsoft.Xbox.TCUI",
    "Microsoft.Windows.Widgets Platform"
)

$ProtectedPackagePatterns = @(
    "*SystemSettings*",
    "*ShellExperienceHost*",
    "*StartMenuExperienceHost*",
    "*CBS*",
    "*Photon*",
    "*Win32WebViewHost*",
    "*Notepad*",
    "*Search*",
    "*Widgets*",
    "*PeopleExperienceHost*",
    "*PinToAI*",
    "*Ai.Copilot*"
)

$FrameworkPackages = @(
    "Microsoft.UI.Xaml",
    "Microsoft.VCLibs",
    "Microsoft.Windows.NETFX",
    "Microsoft.Windows.SDK.NET"
)

function Is-ProtectedSystemPackage {
    param([string]$PackageName)
    
    foreach ($Protected in $ProtectedSystemPackages) {
        if ($PackageName -like "*$Protected*" -or $Protected -like "*$PackageName*") {
            return $true
        }
    }
    
    foreach ($Pattern in $ProtectedPackagePatterns) {
        if ($PackageName -like $Pattern) {
            return $true
        }
    }
    
    return $false
}

function Get-AppxRemovalCandidates {
    param(
        [string[]]$Targets,
        [array]$AllUserPackages,
        [array]$AllProvisionedPackages
    )
    
    $Candidates = @{
        User = @()
        Prov = @()
    }
    
    foreach ($AppName in $Targets) {
        foreach ($Pkg in $AllUserPackages) {
            if ($Pkg.IsFramework -eq $true) { continue }
            $NameMatch = $Pkg.Name -like "*$AppName*"
            $PkgFullNameMatch = $Pkg.PackageFullName -like "*$AppName*"
            $FamilyMatch = $false
            $PublisherMatch = $false

            try { $FamilyMatch = $Pkg.PackageFamilyName -like "*$AppName*" } catch {}
            try { $PublisherMatch = $Pkg.PublisherId -like "*$AppName*" } catch {}
            
            if ($NameMatch -or $PkgFullNameMatch -or $FamilyMatch -or $PublisherMatch) {
                if ($Candidates.User -notcontains $Pkg) {
                    $Candidates.User += $Pkg
                }
            }
        }
        
        foreach ($ProvPkg in $AllProvisionedPackages) {
            $DisplayMatch = $ProvPkg.DisplayName -like "*$AppName*"
            $PkgNameMatch = $ProvPkg.PackageName -like "*$AppName*"
            $InstallLocMatch = $false
            try { $InstallLocMatch = $ProvPkg.InstallLocation -like "*$AppName*" } catch {}
            
            if ($DisplayMatch -or $PkgNameMatch -or $InstallLocMatch) {
                if ($Candidates.Prov -notcontains $ProvPkg) {
                    $Candidates.Prov += $ProvPkg
                }
            }
        }
    }
    
    return $Candidates
}

function Stop-LockedAppProcesses {
    param(
        [string]$PackageFamilyName
    )
    
    try {
        $procName = $PackageFamilyName -split "_" | Select-Object -First 1
        $procs = Get-Process -Name $procName -ErrorAction SilentlyContinue
        foreach ($proc in $procs) {
            try {
                Stop-Process -Id $proc.Id -Force -ErrorAction Stop
                Write-RenderStatus "Stopped locked process: $procName (PID $($proc.Id))" "Info"
            } catch {}
        }
    } catch {}
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

    $Candidates = Get-AppxRemovalCandidates -Targets $Targets -AllUserPackages $AllUserPackages -AllProvisionedPackages $AllProvisionedPackages

    $RemovedCount = 0
    $SkippedCount = 0
    $FailedCount = 0

    $UserPkgQueue = New-Object System.Collections.Generic.List[string]
    $ProvPkgQueue = New-Object System.Collections.Generic.List[string]

    foreach ($Pkg in $Candidates.User) {
        if (Is-ProtectedSystemPackage -PackageName $Pkg.PackageFullName) {
            Write-RenderStatus "Protected system app (skipped): $($Pkg.PackageFullName)" "Muted"
            Log-DebloatAction "AppX-User-Remove" "SKIPPED (protected system app): $($Pkg.PackageFullName)"
            $SkippedCount++
            continue
        }
        if ($Pkg.IsFramework -eq $true) {
            Write-RenderStatus "Framework package (skipped): $($Pkg.PackageFullName)" "Muted"
            Log-DebloatAction "AppX-User-Remove" "SKIPPED (framework): $($Pkg.PackageFullName)"
            $SkippedCount++
            continue
        }
        $UserPkgQueue.Add($Pkg.PackageFullName) | Out-Null
    }

    foreach ($ProvPkg in $Candidates.Prov) {
        if (Is-ProtectedSystemPackage -PackageName $ProvPkg.PackageName) {
            Write-RenderStatus "Protected provisioned app (skipped): $($ProvPkg.PackageName)" "Muted"
            Log-DebloatAction "AppX-Provisioned-Purge" "SKIPPED (protected): $($ProvPkg.PackageName)"
            $SkippedCount++
            continue
        }
        $ProvPkgQueue.Add($ProvPkg.PackageName) | Out-Null
    }

    Write-RenderStatus "Processing $($UserPkgQueue.Count) user packages and $($ProvPkgQueue.Count) provisioned packages..." "Info"

    $PurgedProvNames = @()

    foreach ($PkgFullName in $UserPkgQueue) {
        $Removed = $false
        $ErrorMsg = $null
        $PkgObj = $null
        try {
            $PkgObj = Get-AppxPackage -Package $PkgFullName -ErrorAction SilentlyContinue
        } catch {}
        
        if ($PkgObj) {
            try { Stop-LockedAppProcesses -PackageFamilyName $PkgObj.PackageFamilyName } catch {}
        }

        try {
            Remove-AppxPackage -Package $PkgFullName -AllUsers -ErrorAction Stop
            $Removed = $true
        } catch {
            $ErrorMsg = $_.Exception.Message
            try {
                Remove-AppxPackage -Package $PkgFullName -ErrorAction Stop
                $Removed = $true
            } catch {
                try {
                    $pkgObj2 = Get-AppxPackage -Package $PkgFullName -ErrorAction SilentlyContinue
                    if ($pkgObj2) {
                        $pkgObj2 | Remove-AppxPackage -ErrorAction SilentlyContinue
                        $Removed = $true
                    }
                } catch {}
            }
        }
        
        if ($Removed) {
            Write-RenderStatus "Removed installed package: $PkgFullName" "Success"
            Log-DebloatAction "AppX-User-Remove" "Removed $PkgFullName"
            $RemovedCount++
        } else {
            if ($ErrorMsg -match "0x80073CFA|0x80073CF6|part of Windows|cannot be uninstalled|Turn Windows Functions|Is a framework package|dependency") {
                Write-RenderStatus "Protected, framework, or dependency-locked system app (skipped): $PkgFullName" "Muted"
                Log-DebloatAction "AppX-User-Remove" "SKIPPED (protected/framework/dependency): $PkgFullName"
                $SkippedCount++
            } else {
                Write-RenderStatus "Failed to remove user package $PkgFullName : $ErrorMsg" "Warning"
                Log-DebloatAction "AppX-User-Remove" "FAILED: $PkgFullName - $ErrorMsg"
                $FailedCount++
            }
        }
    }

    foreach ($ProvPkgName in $ProvPkgQueue) {
        $Purged = $false
        try {
            Remove-AppxProvisionedPackage -Online -PackageName $ProvPkgName -ErrorAction Stop | Out-Null
            $Purged = $true
            $PurgedProvNames += $ProvPkgName
        } catch {
            try {
                $dismOutput = dism.exe /Online /Remove-ProvisionedAppxPackage /PackageName:"$ProvPkgName" 2>&1 | Out-String
                if ($dismOutput -match "successfully|success") {
                    $Purged = $true
                    $PurgedProvNames += $ProvPkgName
                }
            } catch {}
        }
        
        if ($Purged) {
            Write-RenderStatus "Purged provisioned package: $ProvPkgName" "Success"
            Log-DebloatAction "AppX-Provisioned-Purge" "Purged $ProvPkgName"
            $RemovedCount++
        } else {
            Write-RenderStatus "Failed to purge provisioned package $ProvPkgName" "Warning"
            Log-DebloatAction "AppX-Provisioned-Purge" "FAILED: $ProvPkgName"
            $FailedCount++
        }
    }

    # Clean up provisioned package references for new-user scenario
    if ($PurgedProvNames.Count -gt 0) {
        try {
            $appxAllUserStore = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore"
            if (Test-Path $appxAllUserStore) {
                Get-ChildItem $appxAllUserStore -ErrorAction SilentlyContinue | ForEach-Object {
                    $_.GetValueNames() | ForEach-Object {
                        try {
                            $val = $_.GetValue($_)
                            if ($val) {
                                foreach ($ProvName in $PurgedProvNames) {
                                    if ($val -like "*$ProvName*") {
                                        Remove-ItemProperty -Path $_.PSPath -Name $_ -ErrorAction SilentlyContinue
                                    }
                                }
                            }
                        } catch {}
                    }
                }
                Write-RenderStatus "Cleaned AppxAllUserStore references for newly created users." "Success"
            }
        } catch {}
    }

    Write-RenderStatus "Running final sweep for remaining provisioned packages..." "Info"
    try {
        $RemainingProv = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
        $SweepRemoved = 0
        foreach ($ProvPkg in $RemainingProv) {
            foreach ($AppName in $Targets) {
                if ($ProvPkg.PackageName -like "*$AppName*" -or $ProvPkg.DisplayName -like "*$AppName*") {
                    if (Is-ProtectedSystemPackage -PackageName $ProvPkg.PackageName) { continue }
                    try {
                        $dismResult = dism.exe /Online /Remove-ProvisionedAppxPackage /PackageName:"$($ProvPkg.PackageName)" 2>&1 | Out-String
                        if ($dismResult -match "success|successfully") {
                            Write-RenderStatus "Final sweep purged: $($ProvPkg.PackageName)" "Success"
                            Log-DebloatAction "AppX-Provisioned-FinalSweep" "Purged $($ProvPkg.PackageName)"
                            $SweepRemoved++
                        }
                    } catch {}
                }
            }
        }
        
        if ($SweepRemoved -gt 0) {
            Write-RenderStatus "Final sweep removed $SweepRemoved additional provisioned packages." "Success"
        }
    } catch {}

    Write-RenderStatus "AppX Package Purging Completed. Removed: $RemovedCount, Skipped: $SkippedCount, Failed: $FailedCount" "Success"
}