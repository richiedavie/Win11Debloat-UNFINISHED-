# RollbackEngine.ps1 - Undo Engine Using State Delta Manifests

function New-SystemStateManifest {
    param (
        [string]$OutputPath = "",
        [string[]]$RegistryPaths = @(),
        [string[]]$ServiceNames = @(),
        [string[]]$AppxPackages = @()
    )

    if (-not $OutputPath) {
        $OutputPath = Join-Path $global:RootDir "logs\state_manifest_latest.json"
    }

    $Manifest = @{
        timestamp = Get-Date -Format "o"
        build_number = $null
        registry_snapshot = @()
        service_snapshot = @()
        appx_snapshot = @()
    }

    try {
        $Manifest.build_number = [int](Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "CurrentBuildNumber" -ErrorAction Stop).CurrentBuildNumber
    } catch {
        $Manifest.build_number = [int]([Environment]::OSVersion.Version.Build)
    }

    foreach ($RegPath in $RegistryPaths) {
        $Hive = $RegPath.Split('\')[0]
        $Path = $RegPath.Substring($Hive.Length + 1)
        $PsDrivePath = "${Hive}:\$Path"

        $Snapshot = @{
            hive = $Hive
            path = $Path
            values_original = @{}
        }

        if (Test-Path $PsDrivePath) {
            $ExistingProps = Get-ItemProperty -Path $PsDrivePath -ErrorAction SilentlyContinue
            if ($ExistingProps) {
                $Props = $ExistingProps.PSObject.Properties | Where-Object { 
                    $_.Name -notmatch '^PS' -and $_.Value -ne $null 
                }
                foreach ($Prop in $Props) {
                    $Snapshot.values_original[$Prop.Name] = @{
                        value = $Prop.Value
                        type = "Unknown"
                    }
                    try {
                        $Item = Get-ItemProperty -Path $PsDrivePath -Name $Prop.Name -ErrorAction Stop
                        $PropType = (Get-ItemProperty -Path $PsDrivePath -Name $Prop.Name).PSObject.Properties[$Prop.Name].TypeNameOfValue
                        if ($PropType -match "Int32|DWord") { $Snapshot.values_original[$Prop.Name].type = "DWord" }
                        elseif ($PropType -match "String|Char") { $Snapshot.values_original[$Prop.Name].type = "String" }
                        elseif ($PropType -match "Byte|Bool") { $Snapshot.values_original[$Prop.Name].type = "Binary" }
                        else { $Snapshot.values_original[$Prop.Name].type = "String" }
                    } catch {
                        $Snapshot.values_original[$Prop.Name].type = "String"
                    }
                }
            }
        }

        $Manifest.registry_snapshot += $Snapshot
    }

    foreach ($SvcName in $ServiceNames) {
        $SvcObj = Get-Service -Name $SvcName -ErrorAction SilentlyContinue
        $SvcSnapshot = @{
            name = $SvcName
            original_start_type = "Unknown"
        }

        if ($SvcObj) {
            $SvcSnapshot.original_start_type = $SvcObj.StartType.ToString()
        }

        $Manifest.service_snapshot += $SvcSnapshot
    }

    foreach ($PkgName in $AppxPackages) {
        $PkgObj = Get-AppxPackage -Name "*$PkgName*" -AllUsers -ErrorAction SilentlyContinue | Select-Object -First 1
        $PkgSnapshot = @{
            name = $PkgName
            was_installed = $false
        }

        if ($PkgObj) {
            $PkgSnapshot.was_installed = $true
        }

        $Manifest.appx_snapshot += $PkgSnapshot
    }

    $Dir = Split-Path -Parent $OutputPath
    if (-not (Test-Path $Dir)) {
        New-Item -ItemType Directory -Path $Dir -Force | Out-Null
    }

    $Manifest | ConvertTo-Json -Depth 10 | Set-Content -Path $OutputPath -Encoding UTF8
    Write-RenderStatus "System state manifest saved to: $OutputPath" "Success"
    Log-DebloatAction "State-Manifest" "Saved state snapshot to $OutputPath"
}

function Invoke-Rollback {
    param (
        [string]$ManifestPath = ""
    )

    if (-not $ManifestPath) {
        $ManifestPath = Join-Path $global:RootDir "logs\state_manifest_latest.json"
    }

    if (-not (Test-Path $ManifestPath)) {
        Write-RenderStatus "Rollback manifest not found at: $ManifestPath" "Error"
        return
    }

    try {
        $Manifest = Get-Content -Path $ManifestPath -Raw | ConvertFrom-Json
    } catch {
        Write-RenderStatus "Failed to parse rollback manifest: $ManifestPath" "Error"
        return
    }

    Write-RenderStatus "Starting Rollback from manifest dated: $($Manifest.timestamp)" "Header"

    $ConfirmRollback = Read-Host -Prompt "This will revert changes recorded in the manifest. Continue? (Y/N)"
    if ($ConfirmRollback -notmatch "^[Yy]$") {
        Write-RenderStatus "Rollback cancelled by user." "Info"
        return
    }

    if ($Manifest.registry_snapshot) {
        foreach ($Snapshot in $Manifest.registry_snapshot) {
            $Hive = $Snapshot.hive
            $Path = $Snapshot.path
            $PsDrivePath = "${Hive}:\$Path"

            Write-RenderStatus "Reverting registry key: ${Hive}\$Path" "Info"

            try {
                if (-not (Test-Path $PsDrivePath)) {
                    if ($Snapshot.values_original.Count -gt 0) {
                        New-Item -Path $PsDrivePath -Force | Out-Null
                    } else {
                        continue
                    }
                }

                foreach ($ValName in ($Snapshot.values_original.Keys)) {
                    $ValData = $Snapshot.values_original[$ValName].value
                    $ValType = $Snapshot.values_original[$ValName].type

                    if ($ValData -eq $null) {
                        Remove-ItemProperty -Path $PsDrivePath -Name $ValName -Force -ErrorAction SilentlyContinue | Out-Null
                    } else {
                        $PsType = "String"
                        if ($ValType -eq "DWord") { $PsType = "DWord" }
                        elseif ($ValType -eq "Binary") { $PsType = "Binary" }

                        Set-ItemProperty -Path $PsDrivePath -Name $ValName -Value $ValData -Type $PsType -Force -ErrorAction Stop | Out-Null
                    }
                }

                Write-RenderStatus "Reverted: ${Hive}\$Path" "Success"
                Log-DebloatAction "Rollback-Registry" "Reverted ${Hive}\$Path"
            } catch {
                Write-RenderStatus "Failed to revert ${Hive}\$Path : $_" "Warning"
            }
        }
    }

    if ($Manifest.service_snapshot) {
        foreach ($SvcSnap in $Manifest.service_snapshot) {
            $SvcName = $SvcSnap.name
            $OriginalStart = $SvcSnap.original_start_type

            if ($OriginalStart -eq "Unknown") { continue }

            Write-RenderStatus "Restoring service startup type: $SvcName -> $OriginalStart" "Info"

            try {
                $SetType = $OriginalStart
                if ($OriginalStart -eq "Automatic") { $SetType = "Automatic" }
                elseif ($OriginalStart -eq "Disabled") { $SetType = "Disabled" }
                elseif ($OriginalStart -eq "Manual") { $SetType = "Manual" }

                Set-Service -Name $SvcName -StartupType $SetType -ErrorAction Stop | Out-Null
                Write-RenderStatus "Restored service: $SvcName ($OriginalStart)" "Success"
                Log-DebloatAction "Rollback-Service" "Restored $SvcName to $OriginalStart"
            } catch {
                try {
                    $scArg = $SetType.ToLower()
                    $null = sc.exe config "$SvcName" start= $scArg 2>&1
                    Write-RenderStatus "Restored service via SC.EXE: $SvcName ($OriginalStart)" "Success"
                    Log-DebloatAction "Rollback-Service" "Restored $SvcName to $OriginalStart via SC.EXE"
                } catch {
                    Write-RenderStatus "Failed to restore service $SvcName : $_" "Warning"
                }
            }
        }
    }

    if ($Manifest.appx_snapshot) {
        foreach ($PkgSnap in $Manifest.appx_snapshot) {
            if ($PkgSnap.was_installed -eq $true) {
                Write-RenderStatus "Note: $($PkgSnap.name) was removed during debloat and cannot be auto-restored via manifest." "Muted"
                Write-RenderStatus "      Use Microsoft Store or 'Add-AppxPackage' to reinstall." "Muted"
            }
        }
    }

    Write-RenderStatus "Rollback sequence completed." "Success"
}
