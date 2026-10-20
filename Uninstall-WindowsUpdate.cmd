@echo off
REM Uninstall-WindowsUpdate - CMD Launcher
REM Autor: David Nemecek | Rijen 2026
REM
REM Pouziti:
REM   Uninstall-WindowsUpdate.cmd -List [-Since 2026-10-01]
REM   Uninstall-WindowsUpdate.cmd -Filter "*Cumulative*"          (interaktivni vyber)
REM   Uninstall-WindowsUpdate.cmd -KB 5127648 -Force [-DryRun] [-Since 2026-10-01]
REM
REM Vyzaduje: elevated (Administrator) pristup pro odinstalaci a mapovani KB -> CBS balicek

set "scriptPath=%~dp0"
set "scriptName=%~n0"

set "hasVerbose=0"
for %%a in (%*) do (
    if /i "%%~a"=="-Verbose" set "hasVerbose=1"
)

if "%hasVerbose%"=="1" (
    powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%scriptPath%%scriptName%.ps1" %*
) else (
    powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%scriptPath%%scriptName%.ps1" %* 2>nul
)
set "exitCode=%ERRORLEVEL%"
exit /b %exitCode%
