param(
    [switch]$Silent = $false
)

$ErrorActionPreference = "Stop"

function Test-DebloatPrerequisites {
    $Results = @{
        os = $null
        build = 0
        admin = $false
        git = $false
        powershell_version = $PSVersionTable.PSVersion.ToString()
        issues = @()
        warnings = @()
    }

    if ($IsWindows) {
        $Results.os = "Windows"
        try {
            $Results.build = [int](Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "CurrentBuildNumber" -ErrorAction Stop).CurrentBuildNumber
        } catch {
            $Results.build = [int]([Environment]::OSVersion.Version.Build)
        }

        $Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $Principal = New-Object Security.Principal.WindowsPrincipal($Identity)
        $Results.admin = $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } else {
        $Results.os = "$($PSVersionTable.OS) (Non-Windows detected - DryRun simulation active)"
        $Results.build = 0
    }

    try {
        $null = git --version
        $Results.git = $true
    } catch {
        $Results.git = $false
    }

    $Results.cim_available = $false

    if ($Results.os -ne "Windows") {
        $Results.issues += "Not running on Windows. Script will run in Dry-Run simulation mode."
    } elseif ($Results.build -lt 22000) {
        $Results.issues += "Build $($Results.build) detected. This tool requires Build 22000+ (Windows 11)."
    } elseif ($Results.build -lt 26100) {
        $Results.warnings += "Build $($Results.build) detected. This tool is optimized for Build 26100+ (24H2/25H2)."
    }

    if ($IsWindows -and (Get-Command Get-CimInstance -ErrorAction SilentlyContinue)) {
        try {
            $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
            if ($osInfo) { $Results.cim_available = $true }
        } catch { $Results.cim_available = $false }
    }

    if (-not $Results.admin -and $Results.os -eq "Windows") {
        $Results.issues += "Not running as Administrator. Many operations will fail without elevated privileges."
    }

    $DuplicateServices = @(
        "DiagTrack", "dmwappushservice", "WSearch", "WerSvc", "EdgeUpdate"
    )
    $seenServices = @{}
    foreach ($Svc in $DuplicateServices) {
        if ($seenServices.ContainsKey($Svc)) {
            $Results.warnings += "Duplicate service entry detected: $Svc"
        } else {
            $seenServices[$Svc] = $true
        }
    }

    if (-not $Silent) {
        Write-Host "`n=== Win11Debloat Build Check ===" -ForegroundColor Cyan
        Write-Host "OS            : $($Results.os)"
        Write-Host "Build         : $($Results.build)"
        Write-Host "Admin Rights  : $($Results.admin)"
        Write-Host "Git Available : $($Results.git)"
        Write-Host "PowerShell    : $($Results.powershell_version)"
        Write-Host "===============================" -ForegroundColor Cyan

        if ($Results.warnings.Count -gt 0) {
            Write-Host "`nWarnings:" -ForegroundColor DarkYellow
            foreach ($Warning in $Results.warnings) {
                Write-Host "  - $Warning" -ForegroundColor DarkYellow
            }
        }

        if ($Results.issues.Count -gt 0) {
            Write-Host "`nIssues Detected:" -ForegroundColor Yellow
            foreach ($Issue in $Results.issues) {
                Write-Host "  - $Issue" -ForegroundColor Yellow
            }
            Write-Host ""
            return 1
        } else {
            Write-Host "`nAll checks passed. Environment is compatible." -ForegroundColor Green
            return 0
        }
    }

    return 0
}

exit (Test-DebloatPrerequisites)
