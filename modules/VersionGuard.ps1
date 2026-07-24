# VersionGuard.ps1 - Build 26100+ (24H2/25H2) Target Validation + 64-bit Enforcement

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

function Test-Is64BitProcess {
    return [Environment]::Is64BitProcess
}

function Test-IsRunningAsSystem {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Invoke-SysNativeReLaunch {
    if (-not [Environment]::Is64BitProcess) {
        $sysNative = "$env:SystemRoot\SysNative\WindowsPowerShell\v1.0\powershell.exe"
        if (Test-Path $sysNative) {
            Write-RenderStatus "Relaunching from 64-bit PowerShell host (SysNative)..." "Info"
            $args = $MyInvocation.UnboundArguments
            Start-Process -FilePath $sysNative -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $MyInvocation.MyCommand.Path, $args) -Verb RunAs
            exit
        }
    }
}