# ServiceManager.ps1 - Disables Background Telemetry Services and Scheduled Tasks

function Apply-ServiceAndTaskTweaks {
    param (
        [string]$ConfigPath
    )

    if (-not (Test-Path $ConfigPath)) {
        Write-RenderStatus "Configuration file not found: $ConfigPath" "Error"
        return
    }

    $Config = Get-Content -Path $ConfigPath | ConvertFrom-Json
    Write-RenderStatus "Managing Background Services & Scheduled Tasks..." "Header"

    # 1. Disable Services
    if ($Config.services) {
        foreach ($Svc in $Config.services) {
            $SvcName = $Svc.name
            $DisplayName = $Svc.displayName

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
                    Write-RenderStatus "Failed to disable service $SvcName: $_" "Warning"
                    Log-DebloatAction "Service-Disable" "FAILED service $SvcName - $_"
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

            $TaskObj = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue
            if ($TaskObj) {
                try {
                    Write-RenderStatus "Disabling scheduled task: $TaskPath$TaskName" "Info"
                    Disable-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction Stop | Out-Null
                    Write-RenderStatus "Disabled task: $TaskName" "Success"
                    Log-DebloatAction "ScheduledTask-Disable" "Disabled task $TaskPath$TaskName"
                }
                catch {
                    Write-RenderStatus "Failed to disable task $TaskName: $_" "Warning"
                    Log-DebloatAction "ScheduledTask-Disable" "FAILED task $TaskPath$TaskName - $_"
                }
            } else {
                Write-RenderStatus "Scheduled task not present: $TaskPath$TaskName" "Muted"
            }
        }
    }

    Write-RenderStatus "Services and Scheduled Tasks Management Completed." "Success"
}
