# ServiceManager.ps1 - Disables Background Telemetry Services and Scheduled Tasks

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
            $DisplayName = if ($Svc.displayName) { $Svc.displayName } else { $SvcName }

            $ServiceObj = Get-Service -Name $SvcName -ErrorAction SilentlyContinue
            if ($ServiceObj) {
                try {
                    Write-RenderStatus "Stopping and disabling service: $SvcName ($DisplayName)" "Info"
                    Stop-Service -Name $SvcName -Force -ErrorAction SilentlyContinue
                    Set-Service -Name $SvcName -StartupType Disabled -ErrorAction Stop
                    Write-RenderStatus "Disabled service: $SvcName" "Success"
                    Log-DebloatAction "Service-Disable" "Stopped & Disabled service $SvcName"
                }
                catch {
                    # Fallback to sc.exe
                    try {
                        $null = sc.exe stop "$SvcName" 2>&1
                        $null = sc.exe config "$SvcName" start= disabled 2>&1
                        Write-RenderStatus "Disabled service via SC.EXE: $SvcName" "Success"
                        Log-DebloatAction "Service-Disable" "Stopped & Disabled service via SC.EXE $SvcName"
                    }
                    catch {
                        Write-RenderStatus "Failed to disable service $SvcName: $_" "Warning"
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
                    Disable-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction Stop | Out-Null
                    Write-RenderStatus "Disabled task: $TaskName" "Success"
                    Log-DebloatAction "ScheduledTask-Disable" "Disabled task $FullTaskPath"
                } else {
                    Write-RenderStatus "Scheduled task not found: $FullTaskPath" "Muted"
                }
            }
            catch {
                # Fallback to schtasks.exe
                try {
                    $null = schtasks.exe /change /tn "$FullTaskPath" /disable 2>&1
                    Write-RenderStatus "Disabled task via SCHTASKS.EXE: $TaskName" "Success"
                    Log-DebloatAction "ScheduledTask-Disable" "Disabled task via SCHTASKS.EXE $FullTaskPath"
                }
                catch {
                    Write-RenderStatus "Failed to disable task $TaskName: $_" "Warning"
                    Log-DebloatAction "ScheduledTask-Disable" "FAILED task $FullTaskPath - $_"
                }
            }
        }
    }

    Write-RenderStatus "Services and Scheduled Tasks Management Completed." "Success"
}
