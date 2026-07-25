# ==============================================================================
# Win11Debloat - Edge Optimizer & Removal Module
# Location: modules/EdgeOptimizer.ps1
# ==============================================================================

function Invoke-EdgeNeutralizer {
    [CmdletBinding()]
    param()

    Write-RenderStatus "Initiating Microsoft Edge Removal & Permanent Neutralization..." "Header"

    $edgeSetupPath = Get-ChildItem -Path "${env:ProgramFiles(x86)}\Microsoft\Edge\Application" -Filter "setup.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1

    if ($edgeSetupPath) {
        Write-RenderStatus "Found Edge Installer at: $($edgeSetupPath.FullName)" "Info"
        try {
            Start-Process -FilePath $edgeSetupPath.FullName -ArgumentList "--uninstall", "--system-level", "--verbose-logging", "--force-uninstall" -Wait -WindowStyle Hidden -ErrorAction Stop
            Write-RenderStatus "Edge setup uninstall command executed." "Success"
            Log-DebloatAction "Edge-Uninstall" "Executed setup.exe force-uninstall"
        } catch {
            Write-RenderStatus "Edge setup uninstall failed: $_" "Warning"
            Log-DebloatAction "Edge-Uninstall" "FAILED: $_"
        }
    } else {
        Write-RenderStatus "Edge setup.exe not found. Proceeding to registry/IFEO containment." "Warning"
    }

    $nodePath = Get-Command "node" -ErrorAction SilentlyContinue
    $jsScript = Join-Path -Path $PSScriptRoot -ChildPath "..\utils\EdgeBlocker.js"

    if ($nodePath -and (Test-Path $jsScript)) {
        Write-RenderStatus "Node.js runtime detected. Executing JS Edge Blocker engine..." "Info"
        try {
            $null = node $jsScript 2>&1
            Write-RenderStatus "JS Edge Blocker execution completed." "Success"
            Log-DebloatAction "Edge-IFEO-Block" "Executed EdgeBlocker.js via Node.js"
        } catch {
            Write-RenderStatus "JS Edge Blocker failed: $_" "Warning"
            Log-DebloatAction "Edge-IFEO-Block" "FAILED: $_"
            Invoke-EdgeIfeoFallback
        }
    } else {
        Write-RenderStatus "Node.js not found. Running native PowerShell IFEO Registry containment..." "Info"
        Invoke-EdgeIfeoFallback
    }

    Write-RenderStatus "Microsoft Edge Neutralization Completed." "Success"
}

function Invoke-EdgeIfeoFallback {
    $ifeoKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\msedge.exe"
    try {
        if (-not (Test-Path $ifeoKey)) {
            New-Item -Path $ifeoKey -Force | Out-Null
        }
        Set-ItemProperty -Path $ifeoKey -Name "Debugger" -Value "cmd.exe /c exit" -Type String -Force -ErrorAction Stop
        Write-RenderStatus "IFEO execution block placed on msedge.exe." "Success"
        Log-DebloatAction "Edge-IFEO-Block" "Native IFEO redirect set via PowerShell"
    } catch {
        try {
            $null = reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\msedge.exe" /v "Debugger" /t REG_SZ /d "cmd.exe /c exit" /f 2>&1
            Write-RenderStatus "IFEO execution block placed via REG.EXE." "Success"
            Log-DebloatAction "Edge-IFEO-Block" "Native IFEO redirect set via REG.EXE"
        } catch {
            Write-RenderStatus "Failed to place IFEO block on msedge.exe: $_" "Warning"
            Log-DebloatAction "Edge-IFEO-Block" "FAILED: $_"
        }
    }
}
