# VersionGuard.ps1 - Build 26100+ (24H2/25H2) Target Validation

function Test-Win11DebloatTargetBuild {
    param (
        [int]$MinBuild = 26100
    )

    $CurrentBuild = $null

    try {
        $CurrentBuild = [int](Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "CurrentBuildNumber" -ErrorAction Stop).CurrentBuildNumber
    } catch {
        try {
            $CurrentBuild = [int]([Environment]::OSVersion.Version.Build)
        } catch {
            Write-RenderStatus "Unable to determine Windows build number." "Error"
            return $false
        }
    }

    Write-RenderStatus "Detected Windows Build: $CurrentBuild (Minimum required: $MinBuild)" "Info"

    if ($CurrentBuild -lt $MinBuild) {
        Write-RenderStatus "ABORT: This tool targets Windows 11 24H2 / 25H2 (Build $MinBuild+) only." "Error"
        Write-RenderStatus "Current build ($CurrentBuild) is not supported. Exiting." "Error"
        return $false
    }

    Write-RenderStatus "Build validation passed. Target environment confirmed." "Success"
    return $true
}

function Test-IsWindows11 {
    $CurrentBuild = $null
    try {
        $CurrentBuild = [int](Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "CurrentBuildNumber" -ErrorAction Stop).CurrentBuildNumber
    } catch {
        $CurrentBuild = [int]([Environment]::OSVersion.Version.Build)
    }

    return ($CurrentBuild -ge 22000)
}
