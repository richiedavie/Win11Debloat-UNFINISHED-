@echo off
:: ============================================================================
:: Windows 11 Debloater Launcher (UAC Admin & ExecutionPolicy Bypass)
:: ============================================================================
setlocal EnableExtensions

:: Set Working Directory to Script Location
cd /d "%~dp0"

:: Check for Administrative Privileges
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [Win11Debloat] Requesting Administrator Privileges...
    echo [Win11Debloat] Please approve the UAC prompt to continue.
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -WorkingDirectory '%~dp0' -Verb RunAs"
    exit /b
)

:: Launch Main PowerShell Script
echo [Win11Debloat] Administrator privileges verified. Starting Windows 11 Debloater...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-Debloater.ps1"

pause
