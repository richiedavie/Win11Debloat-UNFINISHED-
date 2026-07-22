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

    $Tweaks = Get-Content -Path $ConfigPath | ConvertFrom-Json
    Write-RenderStatus "Applying Registry Policy Injections..." "Header"

    foreach ($Tweak in $Tweaks) {
        $Hive = $Tweak.hive
        $Path = $Tweak.path
        $Name = $Tweak.name
        $Value = $Tweak.value
        $Type = $Tweak.type
        $Description = $Tweak.description

        # Backup key before modification
        Backup-RegistryKey -Hive $Hive -Path $Path -BackupDir $BackupDir

        $FullRegistryPath = "Registry::$Hive\$Path"

        try {
            if (-not (Test-Path $FullRegistryPath)) {
                New-Item -Path $FullRegistryPath -Force | Out-Null
            }

            Set-ItemProperty -Path $FullRegistryPath -Name $Name -Value $Value -Type $Type -Force -ErrorAction Stop
            Write-RenderStatus "Applied: [$Hive\$Path] $Name = $Value ($Description)" "Success"
            Log-DebloatAction "Registry-Tweak" "Applied [$Hive\$Path] $Name = $Value"
        }
        catch {
            Write-RenderStatus "Failed to apply registry tweak [$Hive\$Path] $Name: $_" "Warning"
            Log-DebloatAction "Registry-Tweak" "FAILED [$Hive\$Path] $Name - $_"
        }
    }

    Write-RenderStatus "Registry Policy Injections Completed." "Success"
}
