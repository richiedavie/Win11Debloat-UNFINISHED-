# Menu.ps1 - Interactive Console Menu Navigation

function Show-DebloatMenu {
    param(
        [bool]$PresetLoaded = $false
    )

    Show-HeaderBanner

    if ($PresetLoaded) {
        Write-Host "  Preset mode: ACTIVE" -ForegroundColor Green
        Write-Host ""
    }

    Write-Host "Select an option to proceed:" -ForegroundColor White
    Write-Host ""
    Write-Host "  [1] Perform Full Debloat (Restore Point + AppX + Registry + Services)" -ForegroundColor Green
    Write-Host "  [2] Purge AppX / Provisioned Packages (Apps + DISM)" -ForegroundColor Yellow
    Write-Host "  [3] Inject Registry Policies (Copilot, Recall, Bing, Widgets, Telemetry)" -ForegroundColor Yellow
    Write-Host "  [4] Disable Telemetry Services & Scheduled Tasks" -ForegroundColor Yellow
    Write-Host "  [5] Neutralize AI Components (Recall, Copilot, ClickToDo, WSAI, Edge AI)" -ForegroundColor Magenta
    Write-Host "  [6] Create Manual System Restore Point" -ForegroundColor Cyan
    Write-Host "  [7] Rollback Last Debloat (Undo Engine)" -ForegroundColor Red
    Write-Host "  [8] Run Build Compatibility Check" -ForegroundColor Gray
    Write-Host "  [Q] Exit" -ForegroundColor Red
    Write-Host ""

    $Choice = Read-Host -Prompt "Enter selection [1-8, Q]"
    return $Choice.Trim().ToUpper()
}
