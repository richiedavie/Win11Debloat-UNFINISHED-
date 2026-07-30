# ServiceManager.ps1 - Disables Background Telemetry Services and Scheduled Tasks (24H2/25H2 Hardened)

$RegistryDisableMap = @{
    "DiagTrack" = @{
        "HKLM\SYSTEM\CurrentControlSet\Services\DiagTrack" = @{ "Start" = 4 }
    }
    "SysMain" = @{
        "HKLM\SYSTEM\CurrentControlSet\Services\SysMain" = @{ "Start" = 4 }
    }
    "WSearch" = @{
        "HKLM\SYSTEM\CurrentControlSet\Services\WSearch" = @{ "Start" = 4 }
    }
    "dosvc" = @{
        "HKLM\SYSTEM\CurrentControlSet\Services\dosvc" = @{ "Start" = 4 }
    }
    "TabletInputService" = @{
        "HKLM\SYSTEM\CurrentControlSet\Services\TabletInputService" = @{ "Start" = 4 }
    }
    "Spooler" = @{
        "HKLM\SYSTEM\CurrentControlSet\Services\Spooler" = @{ "Start" = 4 }
    }
    "dmwappushservice" = @{
        "HKLM\SYSTEM\CurrentControlSet\Services\dmwappushservice" = @{ "Start" = 4 }
    }
    "WerSvc" = @{
        "HKLM\SYSTEM\CurrentControlSet\Services\WerSvc" = @{ "Start" = 4 }
    }
    "EdgeUpdate" = @{
        "HKLM\SYSTEM\CurrentControlSet\Services\EdgeUpdate" = @{ "Start" = 4 }
        "HKLM\SOFTWARE\Policies\Microsoft\EdgeUpdate" = @{ "AutoUpdateCheckPeriodMinutes" = 0; "UpdateDefault" = 0 }
    }
    "WSAIFabricSvc" = @{
        "HKLM\SYSTEM\CurrentControlSet\Services\WSAIFabricSvc" = @{ "Start" = 4 }
    }
    "WpnService" = @{
        "HKLM\SYSTEM\CurrentControlSet\Services\WpnService" = @{ "Start" = 4 }
        "HKLM\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\PushNotifications" = @{ "NoCloudApplicationNotification" = 1; "NoToastApplicationNotification" = 1 }
    }
    "OneDriveSvr" = @{
        "HKLM\SYSTEM\CurrentControlSet\Services\OneDriveSvr" = @{ "Start" = 4 }
    }
    "MapsBroker" = @{
        "HKLM\SYSTEM\CurrentControlSet\Services\MapsBroker" = @{ "Start" = 4 }
    }
    "PhoneSvc" = @{
        "HKLM\SYSTEM\CurrentControlSet\Services\PhoneSvc" = @{ "Start" = 4 }
    }
    "wisvc" = @{
        "HKLM\SYSTEM\CurrentControlSet\Services\wisvc" = @{ "Start" = 4 }
    }
    "WMPNetworkSvc" = @{
        "HKLM\SYSTEM\CurrentControlSet\Services\WMPNetworkSvc" = @{ "Start" = 4 }
    }
    "DPS" = @{
        "HKLM\SYSTEM\CurrentControlSet\Services\DPS" = @{ "Start" = 4 }
    }
    "RemoteRegistry" = @{
        "HKLM\SYSTEM\CurrentControlSet\Services\RemoteRegistry" = @{ "Start" = 4 }
    }
    "FrameServer" = @{
        "HKLM\SYSTEM\CurrentControlSet\Services\FrameServer" = @{ "Start" = 4 }
    }
    "WbioSrvc" = @{
        "HKLM\SYSTEM\CurrentControlSet\Services\WbioSrvc" = @{ "Start" = 4 }
    }
}

function Get-ServiceSafe {
    param([string]$ServiceName)
    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if (-not $svc) {
        $svc = Get-CimInstance -ClassName Win32_Service -Filter "Name='$ServiceName'" -ErrorAction SilentlyContinue
    }
    return $svc
}

function Test-ServiceHasCriticalDependency {
    param([string]$ServiceName)
    $CriticalDeps = @("RpcSs","DcomLaunch","SamSs","EventLog","WinDefend","WdNisSvc","WSearch")
    try {
        $deps = Get-CimInstance -ClassName Win32_Service -Filter "Name='$ServiceName'" -ErrorAction Stop | Select-Object -ExpandProperty DependsOn -ErrorAction SilentlyContinue
        if ($deps) {
            foreach ($dep in $deps) {
                if ($CriticalDeps -contains $dep) { return $true }
            }
        }
    } catch {}
    return $false
}

function Stop-StubbornService {
    param(
        [string]$ServiceName,
        [int]$MaxRetries = 5
    )
    
    $RetryCount = 0
    while ($RetryCount -lt $MaxRetries) {
        try {
            $procList = Get-CimInstance -ClassName Win32_Service -Filter "Name='$ServiceName'" -ErrorAction Stop
            if ($procList -and $procList.State -ne 'Stopped') {
                $procResults = $procList.StopService()
                if ($procResults.ReturnValue -eq 0) {
                    Start-Sleep -Seconds 3
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
                Start-Sleep -Seconds 3
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
                    try {
                        $null = reg add "$RegPath" /v "$ValueName" /t REG_DWORD /d $ValueData /f 2>&1
                        Write-RenderStatus "Registry-disabled $ServiceName via REG.EXE $RegPath $ValueName" "Success"
                        Log-DebloatAction "Service-Registry-Disable" "Registry-disabled $ServiceName via REG.EXE"
                    } catch {
                        Write-RenderStatus "Failed registry disable $ServiceName at $RegPath : $_" "Warning"
                    }
                }
            }
        }
        return $true
    }
    return $false
}

function Remove-StubScheduledTask {
    param(
        [string]$TaskPath,
        [string]$TaskName
    )
    
    try {
        $FullTaskPath = "$TaskPath$TaskName"
        $AltPath = $TaskPath.Trim('\')
        $AltTaskPath = "\\$AltPath\\"
        
        $TaskObj = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue
        if (-not $TaskObj) {
            $TaskObj = Get-ScheduledTask -TaskPath $AltTaskPath -TaskName $TaskName -ErrorAction SilentlyContinue
        }
        if (-not $TaskObj) {
            $TaskObj = Get-ScheduledTask -TaskPath "\\" -TaskName $TaskName -ErrorAction SilentlyContinue
        }
        
        if ($TaskObj) {
            $null = Unregister-ScheduledTask -TaskPath $TaskObj.TaskPath -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
            if (-not $?) {
                $null = schtasks.exe /delete /tn "$FullTaskPath" /f 2>&1
            }
            Write-RenderStatus "Removed stub scheduled task: $TaskName" "Success"
            Log-DebloatAction "ScheduledTask-Remove" "Removed stub task $FullTaskPath"
            return $true
        }
    } catch {
        Write-RenderStatus "Could not verify/remove stub task $TaskName : $_" "Muted"
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

    if ($Config.services) {
        foreach ($Svc in $Config.services) {
            $SvcName = $Svc.name
            $DisplayName = $SvcName
            if ($Svc.displayName) { $DisplayName = $Svc.displayName }
            $Action = $Svc.action

            $ServiceObj = Get-ServiceSafe -ServiceName $SvcName
            if (-not $ServiceObj) {
                Write-RenderStatus "Service not present on system: $SvcName" "Muted"
                continue
            }

            try {
                if ($Action -match "Disable" -and (Test-ServiceHasCriticalDependency -ServiceName $SvcName)) {
                    Write-RenderStatus "Skipping $SvcName - has critical OS dependencies" "Warning"
                    Log-DebloatAction "Service-Disable" "SKIPPED (critical dependency): $SvcName"
                    continue
                }
                
                Write-RenderStatus "Managing service: $SvcName ($DisplayName) -> $Action" "Info"
                
                if ($Action -match "Disable|Stop") {
                    $Stopped = Stop-StubbornService -ServiceName $SvcName -MaxRetries 5
                    if ($Stopped) {
                        Write-RenderStatus "Stopped service: $SvcName" "Success"
                    } else {
                        Write-RenderStatus "Service may still be running: $SvcName (continuing...)" "Warning"
                    }
                }
                
                if ($Action -match "Disable") {
                    try {
                        if ($Action -match "Delay") {
                            Set-Service -Name $SvcName -StartupType Automatic -ErrorAction Stop
                            Write-RenderStatus "Set service to Automatic (Delayed): $SvcName" "Success"
                            Log-DebloatAction "Service-Disable" "Set delayed start $SvcName"
                        } else {
                            Set-Service -Name $SvcName -StartupType Disabled -ErrorAction Stop | Out-Null
                            Write-RenderStatus "Disabled service: $SvcName" "Success"
                            Log-DebloatAction "Service-Disable" "Disabled service $SvcName"
                        }
                    } catch {
                        $RegDisabled = Disable-ServiceViaRegistry -ServiceName $SvcName
                        if (-not $RegDisabled) {
                            try {
                                if ($Action -match "Delay") {
                                    $null = sc.exe config "$SvcName" start= delayed-auto 2>&1
                                    Write-RenderStatus "Set service to Delayed-Auto via SC.EXE: $SvcName" "Success"
                                } else {
                                    $null = sc.exe config "$SvcName" start= disabled 2>&1
                                    Write-RenderStatus "Disabled service via SC.EXE: $SvcName" "Success"
                                }
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
        }
    }

    if ($Config.scheduled_tasks) {
        foreach ($Task in $Config.scheduled_tasks) {
            $TaskPath = $Task.path
            $TaskName = $Task.name
            $FullTaskPath = "$TaskPath$TaskName"

            try {
                $TaskObj = $null
                $PathsToTry = @($TaskPath, "\\$($TaskPath.Trim('\'))\", "\\")
                foreach ($Path in $PathsToTry) {
                    $TaskObj = Get-ScheduledTask -TaskPath $Path -TaskName $TaskName -ErrorAction SilentlyContinue
                    if ($TaskObj) { break }
                }
                
                if ($TaskObj) {
                    Write-RenderStatus "Disabling scheduled task: $TaskName ($($TaskObj.State))" "Info"
                    try {
                        Disable-ScheduledTask -TaskPath $TaskObj.TaskPath -TaskName $TaskName -ErrorAction Stop | Out-Null
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
                    
                    try {
                        $null = Unregister-ScheduledTask -TaskPath $TaskObj.TaskPath -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
                        Write-RenderStatus "Unregistered task stub: $TaskName" "Success"
                    } catch {}
                } else {
                    $AltFullPath = "$($TaskPath.Trim('\'))\$TaskName"
                    $AltTaskObj = $null
                    foreach ($Path in $PathsToTry) {
                        $AltTaskObj = Get-ScheduledTask -TaskPath $Path -TaskName $TaskName -ErrorAction SilentlyContinue
                        if ($AltTaskObj) { break }
                    }
                    
                    if ($AltTaskObj) {
                        Write-RenderStatus "Disabling scheduled task (alt path): $AltFullPath" "Info"
                        try {
                            Disable-ScheduledTask -TaskPath $AltTaskObj.TaskPath -TaskName $TaskName -ErrorAction Stop | Out-Null
                            Write-RenderStatus "Disabled task: $TaskName" "Success"
                            Log-DebloatAction "ScheduledTask-Disable" "Disabled task $AltFullPath"
                        } catch {
                            $schResult = schtasks.exe /change /tn "$AltFullPath" /disable 2>&1
                            if ($LASTEXITCODE -eq 0) {
                                Write-RenderStatus "Disabled task via SCHTASKS.EXE: $TaskName" "Success"
                            }
                        }
                    } else {
                        Write-RenderStatus "Scheduled task not found (may already be removed): $FullTaskPath" "Muted"
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
