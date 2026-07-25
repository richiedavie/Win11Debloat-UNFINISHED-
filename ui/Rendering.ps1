# ==============================================================================
# Win11Debloat - Robust CLI Rendering Module
# Location: Win11Debloat/ui/Rendering.ps1
# ==============================================================================

# ------------------------------------------------------------------------------
# Helper: Safely retrieves current window width with fallback default
# ------------------------------------------------------------------------------
function Get-SafeConsoleWidth {
    try {
        if ($Host -and $Host.UI -and $Host.UI.RawUI -and $Host.UI.RawUI.WindowSize) {
            $width = $Host.UI.RawUI.WindowSize.Width
            if ($width -and $width -gt 20) {
                return $width
            }
        }
        return 80
    } catch {
        return 80
    }
}

# ------------------------------------------------------------------------------
# Helper: Safely centers text within a given bounding width
# ------------------------------------------------------------------------------
function Center-CLIText {
    param (
        [string]$Text = "",
        [int]$Width = 76
    )
    if ([string]::IsNullOrEmpty($Text)) { return "" }
    
    if ($Text.Length -ge $Width) {
        return $Text.Substring(0, [Math]::Max(0, $Width - 3)) + "..."
    }

    $totalPadding = $Width - $Text.Length
    $padLeft = [Math]::Max(0, [Math]::Floor($totalPadding / 2))
    $padRight = [Math]::Max(0, [Math]::Ceiling($totalPadding / 2))

    return (" " * $padLeft) + $Text + (" " * $padRight)
}

# ------------------------------------------------------------------------------
# Main UI Renderers
# ------------------------------------------------------------------------------

function Write-CLIHeader {
    param (
        [string]$Title = "WINDOWS 11 DEBLOATER",
        [string]$Subtitle = "System Optimization Utility",
        [ConsoleColor]$BorderColor = [ConsoleColor]::Cyan,
        [ConsoleColor]$TitleColor = [ConsoleColor]::White
    )
    
    $screenWidth = Get-SafeConsoleWidth
    $boxWidth = [Math]::Min([Math]::Max($screenWidth - 4, 40), 80)
    $innerWidth = $boxWidth - 2

    $topBorder    = "╔" + ("═" * $innerWidth) + "╗"
    $bottomBorder = "╚" + ("═" * $innerWidth) + "╝"

    Write-Host $topBorder -ForegroundColor $BorderColor

    $centeredTitle = Center-CLIText -Text $Title -Width $innerWidth
    Write-Host "║" -ForegroundColor $BorderColor -NoNewline
    Write-Host $centeredTitle -ForegroundColor $TitleColor -NoNewline
    Write-Host "║" -ForegroundColor $BorderColor

    if (-not [string]::IsNullOrWhiteSpace($Subtitle)) {
        $centeredSub = Center-CLIText -Text $Subtitle -Width $innerWidth
        Write-Host "║" -ForegroundColor $BorderColor -NoNewline
        Write-Host $centeredSub -ForegroundColor Gray -NoNewline
        Write-Host "║" -ForegroundColor $BorderColor
    }

    Write-Host $bottomBorder -ForegroundColor $BorderColor
}

function Write-CLIMessage {
    param (
        [string]$Message = "",
        [ValidateSet("Info", "Success", "Warning", "Error", "Custom")]
        [string]$Type = "Info",
        [ConsoleColor]$Color = [ConsoleColor]::White
    )
    
    switch ($Type) {
        "Info" {
            Write-Host "[i] " -ForegroundColor Cyan -NoNewline
            Write-Host $Message -ForegroundColor White
        }
        "Success" {
            Write-Host "[+] " -ForegroundColor Green -NoNewline
            Write-Host $Message -ForegroundColor Green
        }
        "Warning" {
            Write-Host "[!] " -ForegroundColor Yellow -NoNewline
            Write-Host $Message -ForegroundColor Yellow
        }
        "Error" {
            Write-Host "[-] " -ForegroundColor Red -NoNewline
            Write-Host $Message -ForegroundColor Red
        }
        "Custom" {
            Write-Host $Message -ForegroundColor $Color
        }
    }
}

function Write-CLIDivider {
    param (
        [string]$Char = "─",
        [ConsoleColor]$Color = [ConsoleColor]::DarkGray
    )
    $width = Get-SafeConsoleWidth
    $lineWidth = [Math]::Min([Math]::Max($width - 2, 20), 80)
    $line = $Char * $lineWidth
    Write-Host $line -ForegroundColor $Color
}

function Clear-CLIScreen {
    try {
        [System.Console]::Clear()
    } catch {
        Write-Host "`n" * 10
    }
}

# ------------------------------------------------------------------------------
# Backward-compatible wrappers used by existing modules
# ------------------------------------------------------------------------------

function Show-HeaderBanner {
    Clear-CLIScreen
    Write-CLIHeader -Title "WINDOWS 11 DEBLOATER" -Subtitle "System Optimization Utility"
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
