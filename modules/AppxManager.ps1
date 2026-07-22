# AppxManager.ps1 - UWP / AppX Package Purging Engine

function Remove-DebloatAppxPackages {
    param (
        [string]$ConfigPath
    )

    if (-not (Test-Path $ConfigPath)) {
        Write-RenderStatus "Configuration file not found: $ConfigPath" "Error"
        return
    }

    $Config = Get-Content -Path $ConfigPath | ConvertFrom-Json
    $Targets = @()
    if ($Config.ai_copilot_apps) { $Targets += $Config.ai_copilot_apps }
    if ($Config.stock_bloatware_apps) { $Targets += $Config.stock_bloatware_apps }

    Write-RenderStatus "Beginning AppX Package Purging Process..." "Header"

    foreach ($AppName in $Targets) {
        $FoundAny = $false

        # 1. Installed AppX Packages Removal (Current & All Users)
        $UserPackages = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*$AppName*" -or $_.PackageFullName -like "*$AppName*" }
        if ($UserPackages) {
            foreach ($Pkg in $UserPackages) {
                $FoundAny = $true
                try {
                    Write-RenderStatus "Removing installed package: $($Pkg.PackageFullName)" "Info"
                    Remove-AppxPackage -Package $Pkg.PackageFullName -AllUsers -ErrorAction Stop
                    Log-DebloatAction "AppX-User-Remove" "Removed $($Pkg.PackageFullName)"
                }
                catch {
                    Write-RenderStatus "Failed to remove user package $($Pkg.PackageFullName): $_" "Warning"
                    Log-DebloatAction "AppX-User-Remove" "FAILED: $($Pkg.PackageFullName) - $_"
                }
            }
        }

        # 2. Provisioned Package Removal (DISM / Blueprint)
        $ProvisionedPackages = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*$AppName*" -or $_.PackageName -like "*$AppName*" }
        if ($ProvisionedPackages) {
            foreach ($ProvPkg in $ProvisionedPackages) {
                $FoundAny = $true
                try {
                    Write-RenderStatus "Purging provisioned package blueprint: $($ProvPkg.PackageName)" "Info"
                    Remove-AppxProvisionedPackage -Online -PackageName $ProvPkg.PackageName -ErrorAction Stop | Out-Null
                    Log-DebloatAction "AppX-Provisioned-Purge" "Purged $($ProvPkg.PackageName)"
                }
                catch {
                    Write-RenderStatus "Failed to purge provisioned package $($ProvPkg.PackageName): $_" "Warning"
                    Log-DebloatAction "AppX-Provisioned-Purge" "FAILED: $($ProvPkg.PackageName) - $_"
                }
            }
        }

        if (-not $FoundAny) {
            Write-RenderStatus "No installed or provisioned package found for target: $AppName" "Muted"
        }
    }

    Write-RenderStatus "AppX Package Purging Completed." "Success"
}
