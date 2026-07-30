# ==============================================================================
# Win11Debloat - Low-Spec Optimization Module
# Location: modules/LowSpecPreset.ps1
# ==============================================================================

function Apply-LowSpecOptimizations {
    [CmdletBinding()]
    param()

    Write-RenderStatus "Applying Low-Spec Hardware Optimizations..." "Header"

    # 1. Disable Global Background App Execution (Frees RAM & CPU cycles)
    $AppBackgroundPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications"
    try {
        if (-not (Test-Path $AppBackgroundPath)) {
            New-Item -Path $AppBackgroundPath -Force | Out-Null
        }
        Set-ItemProperty -Path $AppBackgroundPath -Name "GlobalUserDisabled" -Value 1 -Type DWord -Force -ErrorAction Stop | Out-Null
        Write-RenderStatus "Disabled background execution for UWP apps." "Success"
        Log-DebloatAction "LowSpec-Optimization" "Disabled GlobalUserDisabled"
    } catch {
        try {
            $null = reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" /v "GlobalUserDisabled" /t REG_DWORD /d 1 /f 2>&1
            Write-RenderStatus "Disabled background execution for UWP apps via REG.EXE." "Success"
            Log-DebloatAction "LowSpec-Optimization" "Disabled GlobalUserDisabled via REG.EXE"
        } catch {
            Write-RenderStatus "Failed to disable background apps: $_" "Warning"
        }
    }

    # 2. Disable Visual Transparency Effects (Frees iGPU / Shared Memory)
    $PersonalizePath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
    try {
        Set-ItemProperty -Path $PersonalizePath -Name "EnableTransparency" -Value 0 -Type DWord -Force -ErrorAction Stop | Out-Null
        Write-RenderStatus "Disabled window transparency effects." "Success"
        Log-DebloatAction "LowSpec-Optimization" "Disabled EnableTransparency"
    } catch {
        try {
            $null = reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v "EnableTransparency" /t REG_DWORD /d 0 /f 2>&1
            Write-RenderStatus "Disabled window transparency effects via REG.EXE." "Success"
            Log-DebloatAction "LowSpec-Optimization" "Disabled EnableTransparency via REG.EXE"
        } catch {
            Write-RenderStatus "Failed to disable transparency effects: $_" "Warning"
        }
    }

    # 3. Disable Microsoft Edge Startup Boost & Background Preloading
    $EdgePolicies = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
    try {
        if (-not (Test-Path $EdgePolicies)) {
            New-Item -Path $EdgePolicies -Force | Out-Null
        }
        Set-ItemProperty -Path $EdgePolicies -Name "StartupBoostEnabled" -Value 0 -Type DWord -Force -ErrorAction Stop | Out-Null
        Set-ItemProperty -Path $EdgePolicies -Name "BackgroundModeEnabled" -Value 0 -Type DWord -Force -ErrorAction Stop | Out-Null
        Write-RenderStatus "Blocked Edge background preloading and Startup Boost." "Success"
        Log-DebloatAction "LowSpec-Optimization" "Disabled Edge StartupBoost and BackgroundMode"
    } catch {
        try {
            $null = reg add "HKLM\SOFTWARE\Policies\Microsoft\Edge" /v "StartupBoostEnabled" /t REG_DWORD /d 0 /f 2>&1
            $null = reg add "HKLM\SOFTWARE\Policies\Microsoft\Edge" /v "BackgroundModeEnabled" /t REG_DWORD /d 0 /f 2>&1
            Write-RenderStatus "Blocked Edge background preloading via REG.EXE." "Success"
            Log-DebloatAction "LowSpec-Optimization" "Disabled Edge policies via REG.EXE"
        } catch {
            Write-RenderStatus "Failed to block Edge background preloading: $_" "Warning"
        }
    }

    # 4. Disable Xbox Game DVR Background Polling
    $GameDVRPath = "HKCU:\System\GameConfigStore"
    try {
        Set-ItemProperty -Path $GameDVRPath -Name "GameDVR_Enabled" -Value 0 -Type DWord -Force -ErrorAction Stop | Out-Null
        Write-RenderStatus "Disabled Game DVR background recording." "Success"
        Log-DebloatAction "LowSpec-Optimization" "Disabled GameDVR_Enabled"
    } catch {
        try {
            $null = reg add "HKCU\System\GameConfigStore" /v "GameDVR_Enabled" /t REG_DWORD /d 0 /f 2>&1
            Write-RenderStatus "Disabled Game DVR background recording via REG.EXE." "Success"
            Log-DebloatAction "LowSpec-Optimization" "Disabled GameDVR via REG.EXE"
        } catch {
            Write-RenderStatus "Failed to disable Game DVR: $_" "Warning"
        }
    }

    Write-RenderStatus "Low-Spec Optimizations Applied." "Success"
}
