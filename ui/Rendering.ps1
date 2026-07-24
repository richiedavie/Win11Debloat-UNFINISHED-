# Rendering.ps1 - Banners, Status Spinners, and Colored Text Output

function Show-HeaderBanner {
    Clear-Host
    Write-Host "==========================================================================" -ForegroundColor Cyan
    Write-Host "   Windows 11 Debloater (24H2 / 25H2 Build 26100+)                       " -ForegroundColor Green
    Write-Host "   AI Slop Purger, Telemetry Stopper, & System Optimizer                 " -ForegroundColor DarkYellow
    Write-Host "==========================================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Write-RenderStatus {
    param (
        [string]$Message,
        [string]$Type = "Info"
    )

    $Timestamp = Get-Date -Format "HH:mm:ss"

    if ($IsLinux -or $IsMacOS) {
        switch ($Type) {
            "Header" { Write-Host "`n[+] $Message" -ForegroundColor Cyan }
            "Success" { Write-Host " [$Timestamp] [OK] $Message" -ForegroundColor Green }
            "Info" { Write-Host " [$Timestamp] [INFO] $Message" -ForegroundColor Gray }
            "Warning" { Write-Host " [$Timestamp] [WARN] $Message" -ForegroundColor Yellow }
            "Error" { Write-Host " [$Timestamp] [ERROR] $Message" -ForegroundColor Red }
            "Muted" { Write-Host " [$Timestamp] [SKIP] $Message" -ForegroundColor DarkGray }
            Default { Write-Host " [$Timestamp] $Message" }
        }
        return
    }

    try {
        $console = $Host.UI.RawUI
        if ($console -and $console.WindowSize) {
            $codePage = (Get-ConsoleUICodePage)
        }
    } catch {}

    switch ($Type) {
        "Header" {
            Write-Host "`n[+] $Message" -ForegroundColor Cyan
        }
        "Success" {
            Write-Host " [$Timestamp] [SUCCESS] $Message" -ForegroundColor Green
        }
        "Info" {
            Write-Host " [$Timestamp] [INFO] $Message" -ForegroundColor Gray
        }
        "Warning" {
            Write-Host " [$Timestamp] [WARN] $Message" -ForegroundColor Yellow
        }
        "Error" {
            Write-Host " [$Timestamp] [ERROR] $Message" -ForegroundColor Red
        }
        "Muted" {
            Write-Host " [$Timestamp] [SKIP] $Message" -ForegroundColor DarkGray
        }
        Default {
            Write-Host " [$Timestamp] $Message"
        }
    }
}

function Log-DebloatAction {
    param (
        [string]$Category,
        [string]$Details
    )
     
    $LogDir = ""
    if ($global:RootDir) {
        $LogDir = Join-Path $global:RootDir "logs"
    } else {
        $LogDir = Join-Path $PSScriptRoot "..\logs"
    }

    if (-not (Test-Path $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    }
     
    $LogFile = Join-Path $LogDir "debloat_history.log"
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $Entry = "[$Timestamp] [$Category] $Details"
    
    $MutexName = "Win11DebloatLogMutex"
    $Mutex = New-Object System.Threading.Mutex($false, $MutexName)
    try {
        $Mutex.WaitOne() | Out-Null
        try {
            [System.IO.File]::AppendAllText($LogFile, $Entry + [Environment]::NewLine)
        } finally {
            $Mutex.ReleaseMutex()
        }
    } finally {
        $Mutex.Dispose()
    }
}
