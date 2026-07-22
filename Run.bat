@echo off
setlocal DisableDelayedExpansion

:: Set Working Directory to Script Directory
cd /d "%~dp0"

:: Check for Administrative Privileges
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [Win11Debloat] Requesting Administrator Privileges...
    powershell -Command "Start-Process cmd -ArgumentList '/c \"\"%~f0\"\"' -WorkingDirectory '%~dp0' -Verb RunAs"
    exit /b
)

:: Launch Main PowerShell Script with Bypass Execution Policy
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-Debloater.ps1"

pause

