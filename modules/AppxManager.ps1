# AppxManager.ps1 - UWP / AppX Package Purging Engine

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

    Write-RenderStatus "Beginning AppX Package Purging Process..." "Header"

    # Pre-fetch installed and provisioned packages for speed & performance
    $AllUserPackages = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue
    $AllProvisionedPackages = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue

    foreach ($AppName in $Targets) {
        $FoundAny = $false

        # 1. Match Installed AppX Packages
        $MatchingUserPkgs = $AllUserPackages | Where-Object { 
            $_.Name -like "*$AppName*" -or $_.PackageFullName -like "*$AppName*"
        }

        if ($MatchingUserPkgs) {
            foreach ($Pkg in $MatchingUserPkgs) {
                $FoundAny = $true
                try {
                    Write-RenderStatus "Removing installed package: $($Pkg.PackageFullName)" "Info"
                    Remove-AppxPackage -Package $Pkg.PackageFullName -AllUsers -ErrorAction Stop
                    Log-DebloatAction "AppX-User-Remove" "Removed $($Pkg.PackageFullName)"
                }
                catch {
                    try {
                        # Fallback for current user only if -AllUsers fails
                        Remove-AppxPackage -Package $Pkg.PackageFullName -ErrorAction Stop
                        Log-DebloatAction "AppX-User-Remove" "Removed (CurrentUser) $($Pkg.PackageFullName)"
                    } catch {
                        Write-RenderStatus "Failed to remove user package $($Pkg.PackageFullName): $_" "Warning"
                        Log-DebloatAction "AppX-User-Remove" "FAILED: $($Pkg.PackageFullName) - $_"
                    }
                }
            }
        }

        # 2. Match Provisioned AppX Blueprint Packages
        $MatchingProvPkgs = $AllProvisionedPackages | Where-Object { 
            $_.DisplayName -like "*$AppName*" -or $_.PackageName -like "*$AppName*"
        }

        if ($MatchingProvPkgs) {
            foreach ($ProvPkg in $MatchingProvPkgs) {
                $FoundAny = $true
                try {
                    Write-RenderStatus "Purging provisioned package blueprint: $($ProvPkg.PackageName)" "Info"
                    Remove-AppxProvisionedPackage -Online -PackageName $ProvPkg.PackageName -ErrorAction Stop | Out-Null
                    Log-DebloatAction "AppX-Provisioned-Purge" "Purged $($ProvPkg.PackageName)"
                }
                catch {
                    try {
                        # Fallback to DISM command line tool
                        $null = dism.exe /Online /Remove-ProvisionedAppxPackage /PackageName:"$($ProvPkg.PackageName)" 2>&1
                        Write-RenderStatus "Purged provisioned package via DISM.EXE: $($ProvPkg.PackageName)" "Success"
                        Log-DebloatAction "AppX-Provisioned-Purge" "Purged via DISM.EXE $($ProvPkg.PackageName)"
                    } catch {
                        Write-RenderStatus "Failed to purge provisioned package $($ProvPkg.PackageName): $_" "Warning"
                        Log-DebloatAction "AppX-Provisioned-Purge" "FAILED: $($ProvPkg.PackageName) - $_"
                    }
                }
            }
        }

        if (-not $FoundAny) {
            Write-RenderStatus "No installed or provisioned package found matching target pattern: *$AppName*" "Muted"
        }
    }

    Write-RenderStatus "AppX Package Purging Completed." "Success"
}
