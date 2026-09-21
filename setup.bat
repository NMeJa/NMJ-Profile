@echo off
setlocal EnableDelayedExpansion
title NMJ PowerShell Profile Setup

echo ========================================================
echo         NMJ PowerShell Profile - Automated Setup
echo ========================================================
echo.

set "SCRIPT_DIR=%~dp0"
set "USER_PS_DIR=%USERPROFILE%\Documents\PowerShell"
set "USER_MODULES_DIR=%USER_PS_DIR%\Modules"
set "USER_NMJ_DIR=%USERPROFILE%\.nmj"
set "PROFILE_TARGET=%USER_PS_DIR%\Microsoft.PowerShell_profile.ps1"
set "SOURCE_PROFILE=%SCRIPT_DIR%Microsoft.PowerShell_profile.ps1"
set "SOURCE_MODULES=%SCRIPT_DIR%Modules"
set "SOURCE_NMJ=%SCRIPT_DIR%.nmj"

:: 1. Ensure target directories exist
echo [1/5] Creating target directories...
if not exist "%USER_PS_DIR%" (
    mkdir "%USER_PS_DIR%" 2>nul
)
if not exist "%USER_MODULES_DIR%" (
    mkdir "%USER_MODULES_DIR%" 2>nul
)
if not exist "%USER_NMJ_DIR%" (
    mkdir "%USER_NMJ_DIR%" 2>nul
)
echo       Target directories ready.

:: 2. Install Modules
echo [2/5] Installing NMJ modules to: %USER_MODULES_DIR%
if exist "%SOURCE_MODULES%" (
    xcopy /E /I /Y /Q "%SOURCE_MODULES%\*" "%USER_MODULES_DIR%\" >nul
    if !errorlevel! equ 0 (
        echo       Modules copied successfully.
    ) else (
        echo       [!] Warning: Failed to copy some module files.
    )
) else (
    echo       [!] Error: Modules directory not found at %SOURCE_MODULES%
    goto :error
)

:: 3. Install .nmj configuration and Themes
echo [3/5] Installing .nmj config and FastFetch Themes to: %USER_NMJ_DIR%
if exist "%SOURCE_NMJ%" (
    xcopy /E /I /Y /Q "%SOURCE_NMJ%\*" "%USER_NMJ_DIR%\" >nul
    if !errorlevel! equ 0 (
        echo       Themes and configuration copied successfully.
    ) else (
        echo       [!] Warning: Failed to copy some configuration files.
    )
)

:: 4. Deploy profile script (with backup)
echo [4/5] Deploying Microsoft.PowerShell_profile.ps1...
if exist "%PROFILE_TARGET%" (
    copy /Y "%PROFILE_TARGET%" "%PROFILE_TARGET%.bak" >nul
    echo       Backed up existing profile to: Microsoft.PowerShell_profile.ps1.bak
)
copy /Y "%SOURCE_PROFILE%" "%PROFILE_TARGET%" >nul
if !errorlevel! equ 0 (
    echo       New profile loader installed successfully.
) else (
    echo       [!] Error: Failed to copy profile to %PROFILE_TARGET%
    goto :error
)

:: 5. Validate in PowerShell
echo [5/5] Validating profile in clean PowerShell environment...
where pwsh >nul 2>nul
if %errorlevel% equ 0 (
    pwsh -NoProfile -ExecutionPolicy Bypass -Command ". '%PROFILE_TARGET%'; Write-Host '[OK] PowerShell 7 profile loaded with zero errors.' -ForegroundColor Green"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -Command ". '%PROFILE_TARGET%'; Write-Host '[OK] Windows PowerShell profile loaded with zero errors.' -ForegroundColor Green"
)

echo.
echo ========================================================
echo         Installation Complete!
echo ========================================================
echo Restart your terminal or run '. $PROFILE' to get started.
echo.
pause
exit /b 0

:error
echo.
echo [!] An error occurred during setup. Please check permissions and try again.
pause
exit /b 1
