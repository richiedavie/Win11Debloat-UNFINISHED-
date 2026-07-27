# ==============================================================================
# Win11Debloat - Edge Removal Bridge (C# Engine + AppX + JS Fallback)
# Location: modules/EdgeOptimizer.ps1
# ==============================================================================

function Invoke-EdgeNeutralizer {
    [CmdletBinding()]
    param()

    Write-RenderStatus "Initiating Microsoft Edge Removal & Permanent Neutralization..." "Header"

    try {
        Write-RenderStatus "Removing Edge AppX packages across all users..." "Info"
        Get-AppxPackage -AllUsers *MicrosoftEdge* -ErrorAction SilentlyContinue | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
        Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*MicrosoftEdge*" } | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
        Write-RenderStatus "Edge AppX removal completed." "Success"
        Log-DebloatAction "Edge-AppX-Remove" "Removed MicrosoftEdge AppX packages"
    } catch {
        Write-RenderStatus "Edge AppX removal encountered errors: $_" "Warning"
        Log-DebloatAction "Edge-AppX-Remove" "WARNING: $_"
    }

    $csFile = Join-Path -Path $PSScriptRoot -ChildPath "..\utils\EdgeBlocker.cs"
    $jsFile = Join-Path -Path $PSScriptRoot -ChildPath "..\utils\EdgeBlocker.js"
    $ranCSharp = $false

    if (Test-Path $csFile) {
        Write-RenderStatus "C# Edge Blocker source found. Attempting dynamic compilation..." "Info"
        try {
            $sourceCode = Get-Content -Path $csFile -Raw
            Add-Type -TypeDefinition $sourceCode -Language CSharp -ErrorAction Stop
            Write-RenderStatus "C# Edge Blocker compiled successfully. Executing deep neutralization..." "Info"
            [Win11Debloat.Utils.EdgeBlocker]::Main(@())
            Write-RenderStatus "C# Edge Blocker execution completed." "Success"
            Log-DebloatAction "Edge-CSharp-Block" "Executed EdgeBlocker.cs via Add-Type"
            $ranCSharp = $true
        } catch {
            Write-RenderStatus "C# Edge Blocker compilation/execution failed: $_" "Warning"
            Log-DebloatAction "Edge-CSharp-Block" "FAILED: $_"
        }
    } else {
        Write-RenderStatus "EdgeBlocker.cs not found. Skipping C# engine." "Muted"
    }

    if (-not $ranCSharp) {
        $nodePath = Get-Command "node" -ErrorAction SilentlyContinue
        if ($nodePath -and (Test-Path $jsFile)) {
            Write-RenderStatus "Node.js runtime detected. Executing JS Edge Blocker fallback..." "Info"
            try {
                $null = node $jsFile 2>&1
                Write-RenderStatus "JS Edge Blocker execution completed." "Success"
                Log-DebloatAction "Edge-JS-Block" "Executed EdgeBlocker.js via Node.js"
            } catch {
                Write-RenderStatus "JS Edge Blocker failed: $_" "Warning"
                Log-DebloatAction "Edge-JS-Block" "FAILED: $_"
                Invoke-EdgeNativeFallback
            }
        } else {
            Write-RenderStatus "Node.js not found. Running native PowerShell containment..." "Info"
            Invoke-EdgeNativeFallback
        }
    }

    Write-RenderStatus "Microsoft Edge Neutralization Completed." "Success"
}

function Invoke-EdgeNativeFallback {
    Write-RenderStatus "Applying native PowerShell registry and IFEO containment..." "Info"

    try {
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
    } catch {
        Write-RenderStatus "Edge setup uninstall encountered errors: $_" "Warning"
    }

    try {
        $edgeUpdateKey = "HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate"
        if (-not (Test-Path $edgeUpdateKey)) {
            New-Item -Path $edgeUpdateKey -Force | Out-Null
        }
        Set-ItemProperty -Path $edgeUpdateKey -Name "DoNotUpdateToEdgeWithChromium" -Value 1 -Type DWord -Force -ErrorAction Stop | Out-Null
        Set-ItemProperty -Path $edgeUpdateKey -Name "InstallDefault" -Value 0 -Type DWord -Force -ErrorAction Stop | Out-Null
        Set-ItemProperty -Path $edgeUpdateKey -Name "UpdateDefault" -Value 0 -Type DWord -Force -ErrorAction Stop | Out-Null
        Set-ItemProperty -Path $edgeUpdateKey -Name "PreventAppDefaultsAutoOptIn" -Value 1 -Type DWord -Force -ErrorAction Stop | Out-Null
        Write-RenderStatus "Applied EdgeUpdate anti-reinstall policies." "Success"
        Log-DebloatAction "Edge-Registry" "Set EdgeUpdate anti-reinstall policies"
    } catch {
        try {
            $null = reg add "HKLM\SOFTWARE\Policies\Microsoft\EdgeUpdate" /v "DoNotUpdateToEdgeWithChromium" /t REG_DWORD /d 1 /f 2>&1
            $null = reg add "HKLM\SOFTWARE\Policies\Microsoft\EdgeUpdate" /v "InstallDefault" /t REG_DWORD /d 0 /f 2>&1
            $null = reg add "HKLM\SOFTWARE\Policies\Microsoft\EdgeUpdate" /v "UpdateDefault" /t REG_DWORD /d 0 /f 2>&1
            $null = reg add "HKLM\SOFTWARE\Policies\Microsoft\EdgeUpdate" /v "PreventAppDefaultsAutoOptIn" /t REG_DWORD /d 1 /f 2>&1
            Write-RenderStatus "Applied EdgeUpdate anti-reinstall policies via REG.EXE." "Success"
            Log-DebloatAction "Edge-Registry" "Set EdgeUpdate anti-reinstall policies via REG.EXE"
        } catch {
            Write-RenderStatus "Failed to apply EdgeUpdate policies: $_" "Warning"
            Log-DebloatAction "Edge-Registry" "FAILED: $_"
        }
    }

    try {
        $uninstallKey = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge"
        if (-not (Test-Path $uninstallKey)) {
            New-Item -Path $uninstallKey -Force | Out-Null
        }
        Set-ItemProperty -Path $uninstallKey -Name "NoRemove" -Value 0 -Type DWord -Force -ErrorAction Stop | Out-Null
        Write-RenderStatus "Set NoRemove=0 on Edge uninstall key." "Success"
        Log-DebloatAction "Edge-Registry" "Set NoRemove=0 on Edge uninstall key"
    } catch {
        try {
            $null = reg add "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge" /v "NoRemove" /t REG_DWORD /d 0 /f 2>&1
            Write-RenderStatus "Set NoRemove=0 on Edge uninstall key via REG.EXE." "Success"
            Log-DebloatAction "Edge-Registry" "Set NoRemove=0 via REG.EXE"
        } catch {
            Write-RenderStatus "Failed to set NoRemove on Edge uninstall key: $_" "Warning"
            Log-DebloatAction "Edge-Registry" "FAILED NoRemove: $_"
        }
    }

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
