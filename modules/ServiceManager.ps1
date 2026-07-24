# ServiceManager.ps1 - Disables Background Telemetry Services and Scheduled Tasks (24H2/25H2 Hardened)

$RegistryDisableMap = @{
    "DiagTrack" = @{
        "HKLM\SYSTEM\CurrentControlSet\Services\DiagTrack" = @{ "Start" = 4 }
    }
    "dmwappushservice" = @{
        "HKLM\SYSTEM\CurrentControlSet\Services\dmwappushservice" = @{ "Start" = 4 }
    }
    "WSearch" = @{
        "HKLM\SYSTEM\CurrentControlSet\Services\WSearch" = @{ "Start" = 4 }
    }
    "SysMain" = @{
        "HKLM\SYSTEM\CurrentControlSet\Services\SysMain" = @{ "Start" = 4 }
    }
    "WerSvc" = @{
        "HKLM\SYSTEM\CurrentControlSet\Services\WerSvc" = @{ "Start" = 4 }
    }
    "EdgeUpdate" = @{
        "HKLM\SYSTEM\CurrentControlSet\Services\EdgeUpdate" = @{ "Start" = 4 }
        "HKLM\SOFTWARE\Policies\Microsoft\EdgeUpdate" = @{ "AutoUpdateCheckPeriodMinutes" = 0; "UpdateDefault" = 0 }
    }
}

function Stop-StubbornService {
    param(
        [string]$ServiceName,
        [int]$MaxRetries = 3
    )
    
    $RetryCount = 0
    while ($RetryCount -lt $MaxRetries) {
        try {
            $procList = Get-WmiObject Win32_Service -Filter "Name='$ServiceName'" -ErrorAction Stop
            if ($procList -and $procList.State -ne 'Stopped') {
                $procResults = $procList.StopService()
                if ($procResults.ReturnValue -eq 0) {
                    Start-Sleep -Seconds 2
                    $check = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
                    if ($check -and $check.Status -eq 'Stopped') {
                        return $true
                    }
                }
            } elseif ($procList -and $procList.State -eq 'Stopped') {
                return $true
            }
        } catch {
            try {
                $null = sc.exe stop "$ServiceName" 2>&1
                Start-Sleep -Seconds 2
                $check = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
                if ($check -and $check.Status -eq 'Stopped') {
                    return $true
                }
            } catch {}
        }
        $RetryCount++
        Start-Sleep -Seconds 1
    }
    return $false
}

function Disable-ServiceViaRegistry {
    param(
        [string]$ServiceName
    )
    
    if ($RegistryDisableMap.ContainsKey($ServiceName)) {
        $RegEntries = $RegistryDisableMap[$ServiceName]
        foreach ($RegPath in $RegEntries.Keys) {
            foreach ($ValueName in $RegEntries[$RegPath].Keys) {
                $ValueData = $RegEntries[$RegPath][$ValueName]
                try {
                    $Parts = $RegPath -split '\\', 2
                    $Hive = $Parts[0]
                    $SubPath = $Parts[1]
                    $PsDrivePath = "${Hive}:\$SubPath"
                    
                    if (-not (Test-Path $PsDrivePath)) {
                        New-Item -Path $PsDrivePath -Force | Out-Null
                    }
                    
                    if (Get-ItemProperty -Path $PsDrivePath -Name $ValueName -ErrorAction SilentlyContinue) {
                        Set-ItemProperty -Path $PsDrivePath -Name $ValueName -Value $ValueData -Type DWord -Force -ErrorAction Stop | Out-Null
                    } else {
                        New-ItemProperty -Path $PsDrivePath -Name $ValueName -Value $ValueData -PropertyType DWord -Force -ErrorAction Stop | Out-Null
                    }
                    Write-RenderStatus "Registry-disabled $ServiceName via $RegPath $ValueName" "Success"
                    Log-DebloatAction "Service-Registry-Disable" "Registry-disabled $ServiceName"
                } catch {
                    Write-RenderStatus "Failed registry disable $ServiceName at $RegPath : $_" "Warning"
                }
            }
        }
        return $true
    }
    return $false
}

function Apply-ServiceAndTaskTweaks {
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

    Write-RenderStatus "Managing Background Services & Scheduled Tasks..." "Header"

    # 1. Disable Services
    if ($Config.services) {
        foreach ($Svc in $Config.services) {
            $SvcName = $Svc.name
            $DisplayName = $SvcName
            if ($Svc.displayName) { $DisplayName = $Svc.displayName }
            $Action = $Svc.action

            $ServiceObj = Get-Service -Name $SvcName -ErrorAction SilentlyContinue
            if (-not $ServiceObj) {
                $ServiceObj = Get-WmiObject Win32_Service -Filter "Name='$SvcName'" -ErrorAction SilentlyContinue
            }

            if ($ServiceObj) {
                try {
                    Write-RenderStatus "Managing service: $SvcName ($DisplayName) -> $Action" "Info"
                    
                    if ($Action -match "Disable|Stop") {
                        $Stopped = Stop-StubbornService -ServiceName $SvcName -MaxRetries 3
                        if ($Stopped) {
                            Write-RenderStatus "Stopped service: $SvcName" "Success"
                        } else {
                            Write-RenderStatus "Service may still be running: $SvcName (continuing...)" "Warning"
                        }
                    }
                    
                    if ($Action -match "Disable") {
                        try {
                            Set-Service -Name $SvcName -StartupType Disabled -ErrorAction Stop | Out-Null
                            Write-RenderStatus "Disabled service: $SvcName" "Success"
                            Log-DebloatAction "Service-Disable" "Disabled service $SvcName"
                        } catch {
                            $RegDisabled = Disable-ServiceViaRegistry -ServiceName $SvcName
                            if (-not $RegDisabled) {
                                try {
                                    $null = sc.exe config "$SvcName" start= disabled 2>&1
                                    Write-RenderStatus "Disabled service via SC.EXE: $SvcName" "Success"
                                    Log-DebloatAction "Service-Disable" "Disabled service via SC.EXE $SvcName"
                                } catch {
                                    Write-RenderStatus "Failed to disable service $($SvcName): $_" "Warning"
                                    Log-DebloatAction "Service-Disable" "FAILED service $SvcName - $_"
                                }
                            }
                        }
                    }
                }
                catch {
                    try {
                        if ($Action -match "Disable") {
                            $RegDisabled = Disable-ServiceViaRegistry -ServiceName $SvcName
                            if ($RegDisabled) {
                                Write-RenderStatus "Disabled service via registry: $SvcName" "Success"
                            } else {
                                $null = sc.exe config "$SvcName" start= disabled 2>&1
                                $null = sc.exe stop "$SvcName" 2>&1
                                Write-RenderStatus "Disabled service via SC.EXE: $SvcName" "Success"
                                Log-DebloatAction "Service-Disable" "Disabled service via SC.EXE $SvcName"
                            }
                        }
                    } catch {
                        Write-RenderStatus "Failed to manage service $($SvcName): $_" "Warning"
                        Log-DebloatAction "Service-Disable" "FAILED service $SvcName - $_"
                    }
                }
            } else {
                Write-RenderStatus "Service not present on system: $SvcName" "Muted"
            }
        }
    }

    # 2. Disable Telemetry Scheduled Tasks
    if ($Config.scheduled_tasks) {
        foreach ($Task in $Config.scheduled_tasks) {
            $TaskPath = $Task.path
            $TaskName = $Task.name
            $FullTaskPath = "$TaskPath$TaskName"

            try {
                $TaskObj = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue
                if ($TaskObj) {
                    Write-RenderStatus "Disabling scheduled task: $FullTaskPath" "Info"
                    try {
                        Disable-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction Stop | Out-Null
                        Write-RenderStatus "Disabled task: $TaskName" "Success"
                        Log-DebloatAction "ScheduledTask-Disable" "Disabled task $FullTaskPath"
                    } catch {
                        $schResult = schtasks.exe /change /tn "$FullTaskPath" /disable 2>&1
                        if ($LASTEXITCODE -eq 0 -or $schResult -match "success") {
                            Write-RenderStatus "Disabled task via SCHTASKS.EXE: $TaskName" "Success"
                            Log-DebloatAction "ScheduledTask-Disable" "Disabled task via SCHTASKS.EXE $FullTaskPath"
                        } else {
                            Write-RenderStatus "Could not disable task $TaskName (may require interactive prompt)" "Muted"
                        }
                    }
                } else {
                    $FileTask = $TaskName -replace " ", ""
                    $PathNoSlash = $TaskPath.Trim('\')
                    $AltFullPath = "$PathNoSlash\$FileTask"
                    $AltTaskObj = Get-ScheduledTask -TaskPath "\\$PathNoSlash\" -TaskName $TaskName -ErrorAction SilentlyContinue
                    
                    if ($AltTaskObj) {
                        Write-RenderStatus "Disabling scheduled task (alt path): $AltFullPath" "Info"
                        try {
                            Disable-ScheduledTask -TaskPath "\\$PathNoSlash\" -TaskName $TaskName -ErrorAction Stop | Out-Null
                            Write-RenderStatus "Disabled task: $TaskName" "Success"
                            Log-DebloatAction "ScheduledTask-Disable" "Disabled task $AltFullPath"
                        } catch {
                            $schResult = schtasks.exe /change /tn "$AltFullPath" /disable 2>&1
                            if ($LASTEXITCODE -eq 0) {
                                Write-RenderStatus "Disabled task via SCHTASKS.EXE: $TaskName" "Success"
                            }
                        }
                    } else {
                        Write-RenderStatus "Scheduled task not found: $FullTaskPath" "Muted"
                    }
                }
            } catch {
                Write-RenderStatus "Error processing task $($TaskName): $_" "Warning"
                Log-DebloatAction "ScheduledTask-Disable" "FAILED task $FullTaskPath - $_"
            }
        }
    }

    Write-RenderStatus "Services and Scheduled Tasks Management Completed." "Success"
}
