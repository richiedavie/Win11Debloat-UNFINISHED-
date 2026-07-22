# RegistryManager.ps1 - Writes Registry Policies to HKLM / HKCU

function Apply-RegistryTweaks {
    param (
        [string]$ConfigPath,
        [string]$BackupDir
    )

    if (-not (Test-Path $ConfigPath)) {
        Write-RenderStatus "Configuration file not found: $ConfigPath" "Error"
        return
    }

    try {
        $Tweaks = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
    } catch {
        Write-RenderStatus "Failed to parse JSON configuration file: $ConfigPath" "Error"
        return
    }

    Write-RenderStatus "Applying Registry Policy Injections..." "Header"

    foreach ($Tweak in $Tweaks) {
        $Hive = $Tweak.hive
        $Path = $Tweak.path
        $Name = $Tweak.name
        $Value = $Tweak.value
        
        $Type = "DWord"
        if ($Tweak.type) { $Type = $Tweak.type }
        
        $Description = $Tweak.description

        # Backup key before modification
        Backup-RegistryKey -Hive $Hive -Path $Path -BackupDir $BackupDir

        $PsDrivePath = "$Hive:\$Path"

        try {
            if (-not (Test-Path -Path $PsDrivePath)) {
                New-Item -Path $PsDrivePath -Force | Out-Null
            }

            if (Get-ItemProperty -Path $PsDrivePath -Name $Name -ErrorAction SilentlyContinue) {
                Set-ItemProperty -Path $PsDrivePath -Name $Name -Value $Value -Force -ErrorAction Stop | Out-Null
            } else {
                New-ItemProperty -Path $PsDrivePath -Name $Name -Value $Value -PropertyType $Type -Force -ErrorAction Stop | Out-Null
            }

            Write-RenderStatus "Applied: [$Hive\$Path] $Name = $Value ($Description)" "Success"
            Log-DebloatAction "Registry-Tweak" "Applied [$Hive\$Path] $Name = $Value"
        }
        catch {
            # Fallback to reg.exe add if PowerShell provider encounters permission/type issues
            try {
                $RegHive = "HKCU"
                if ($Hive -eq "HKLM") { $RegHive = "HKLM" }
                
                $RegType = "REG_SZ"
                if ($Type -eq "DWord") { $RegType = "REG_DWORD" }
                
                $null = reg add "$RegHive\$Path" /v "$Name" /t $RegType /d "$Value" /f 2>&1
                Write-RenderStatus "Applied via REG.EXE: [$Hive\$Path] $Name = $Value ($Description)" "Success"
                Log-DebloatAction "Registry-Tweak" "Applied via REG.EXE [$Hive\$Path] $Name = $Value"
            }
            catch {
                Write-RenderStatus "Failed to apply registry tweak [$Hive\$Path] $Name: $_" "Warning"
                Log-DebloatAction "Registry-Tweak" "FAILED [$Hive\$Path] $Name - $_"
            }
        }
    }

    Write-RenderStatus "Registry Policy Injections Completed." "Success"
}
