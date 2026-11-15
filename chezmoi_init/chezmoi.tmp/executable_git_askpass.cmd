@echo off
setlocal

:: The %~1 variable holds the prompt string passed by Git, with surrounding quotes removed.

:: Check if the prompt contains "Username"
echo %~1 | findstr /i "Username" >nul
if %errorlevel% equ 0 (
    echo 51386141
    exit /b 0
)

:: Check if the prompt contains "Password"
echo %~1 | findstr /i "Password" >nul
if %errorlevel% equ 0 (
    echo %GITHUB_PAT%
    exit /b 0
)

:: Failsafe exit if neither matched
exit /b 1
