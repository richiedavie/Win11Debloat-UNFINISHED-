# Menu.ps1 - Interactive Console Menu Navigation

function Show-DebloatMenu {
    Show-HeaderBanner

    Write-Host "Select an option to proceed:" -ForegroundColor White
    Write-Host ""
    Write-Host "  [1] Perform Full Debloat (Restore Point + AppX + Registry + Services)" -ForegroundColor Green
    Write-Host "  [2] Purge AI Slop & Bloatware Apps (AppX / DISM)" -ForegroundColor Yellow
    Write-Host "  [3] Inject Registry Policies (Disable Copilot, Recall, Bing, Widgets)" -ForegroundColor Yellow
    Write-Host "  [4] Disable Telemetry Services & Scheduled Tasks" -ForegroundColor Yellow
    Write-Host "  [5] Create System Restore Point Only" -ForegroundColor Cyan
    Write-Host "  [Q] Exit" -ForegroundColor Red
    Write-Host ""

    $Choice = Read-Host -Prompt "Enter selection [1-5, Q]"
    return $Choice.Trim().ToUpper()
}
