@echo off
REM Uninstall-WindowsUpdate - CMD Launcher
REM Autor: David Nemecek | Rijen 2026
REM
REM Pouziti:
REM   Uninstall-WindowsUpdate.cmd -List [-Since 2026-10-01] [-Json]
REM   Uninstall-WindowsUpdate.cmd -Filter "*Cumulative*"          (interaktivni vyber)
REM   Uninstall-WindowsUpdate.cmd -KB 5127648 -Force [-DryRun] [-Hide]
REM
REM -NonInteractive se prida jen pri presnem tokenu -Force v argumentech
REM (davkovy/Ansible rezim, kde se Read-Host nikdy nevola). Parsovani pres
REM shift/goto, NE 'for %%A in (%*)' - ten v cmd.exe dela wildcard-expanzi
REM na kazde polozce obsahujici * nebo ?, takze by napr. -Filter "*Cumulative*"
REM mohl matchovat soubory v aktualnim adresari misto doslovneho textu.
REM Bez vetveni a presmerovani kolem volani powershell.exe: Read-Host uvnitr
REM if/else bloku s presmerovanim je v nekterych verzich cmd.exe nespolehlivy.
REM
REM Vyzaduje: elevated (Administrator) pristup pro odinstalaci, mapovani KB a skryti

set "scriptPath=%~dp0"
set "scriptName=%~n0"
set "extraFlag="

:parseArgs
if "%~1"=="" goto argsParsed
if /i "%~1"=="-Force" set "extraFlag=-NonInteractive"
shift
goto parseArgs
:argsParsed

powershell.exe -ExecutionPolicy Bypass -NoProfile %extraFlag% -File "%scriptPath%%scriptName%.ps1" %*
set "exitCode=%ERRORLEVEL%"

exit /b %exitCode%
