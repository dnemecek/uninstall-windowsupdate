@echo off
REM Uninstall-WindowsUpdate - CMD Launcher
REM Autor: David Nemecek | Rijen 2026
REM
REM Pouziti:
REM   Uninstall-WindowsUpdate.cmd -List [-Since 2026-10-01] [-Json]
REM   Uninstall-WindowsUpdate.cmd -Filter "*Cumulative*"          (interaktivni vyber)
REM   Uninstall-WindowsUpdate.cmd -KB 5127648 -Force [-DryRun] [-Hide]
REM
REM GPO Startup Script:
REM   Script: \\<domena>\netlogon\scripts\Uninstall-WindowsUpdate.cmd
REM   Parametry: -KB 5127648 -Hide -Force -Silent [-LogRoot C:\<Firma>]
REM
REM Logy: <LogRoot>\Logs\<scriptName>.log (pise .ps1) a .err (stderr, jen davkove).
REM LogRoot vychozi %ProgramData%\Scripts; -LogRoot se cte tady kvuli .err a predava
REM se v %* dal do .ps1 (shift %* nemeni).
REM
REM -NonInteractive a 2>> se pridaji jen pri presnem tokenu -Force nebo -Silent
REM (davkovy/Ansible/GPO rezim, kde se Read-Host nikdy nevola). Parsovani pres
REM shift/goto, NE 'for %%A in (%*)' - ten v cmd.exe dela wildcard-expanzi
REM na kazde polozce obsahujici * nebo ?, takze by napr. -Filter "*Cumulative*"
REM mohl matchovat soubory v aktualnim adresari misto doslovneho textu.
REM Vetveni pres goto navesti, ne if ( ... ) else ( ... ) blok kolem powershell.exe:
REM Read-Host uvnitr bloku s presmerovanim je v nekterych verzich cmd.exe nespolehlivy.
REM Interaktivni volani je proto bez presmerovani.
REM
REM Vyzaduje: elevated (Administrator) pristup pro odinstalaci, mapovani KB a skryti

set "scriptPath=%~dp0"
set "scriptName=%~n0"
set "logRoot=%ProgramData%\Scripts"
set "batch=0"

:parseArgs
if "%~1"=="" goto argsParsed
if /i "%~1"=="-Force" set "batch=1"
if /i "%~1"=="-Silent" set "batch=1"
if /i "%~1"=="-LogRoot" set "logRoot=%~2"
shift
goto parseArgs
:argsParsed

set "logFolder=%logRoot%\Logs"
set "errFile=%logFolder%\%scriptName%.err"
if not exist "%logFolder%" mkdir "%logFolder%"

if "%batch%"=="1" goto runBatch
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%scriptPath%%scriptName%.ps1" %*
exit /b %ERRORLEVEL%

:runBatch
powershell.exe -ExecutionPolicy Bypass -NoProfile -NonInteractive -File "%scriptPath%%scriptName%.ps1" %* 2>>"%errFile%"
exit /b %ERRORLEVEL%
