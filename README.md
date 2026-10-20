# Uninstall-WindowsUpdate

Vypíše Windows aktualizace nainstalované od zadaného data, nechá vybrat a odinstaluje je.
LCU a další CBS balíčky odebírá přes `DISM /Remove-Package`, ostatní KB přes `wusa /uninstall`.
Ovladače, definice Defenderu a SSU jen vypíše, neodinstaluje.

## Použití

```
Uninstall-WindowsUpdate.cmd -List -Since 2026-10-01          # výpis (tabulka); -Json pro JSON
Uninstall-WindowsUpdate.cmd -Filter "*Cumulative*"           # interaktivní výběr + odinstalace
Uninstall-WindowsUpdate.cmd -Category lcu -List              # filtr podle kind / kategorie WU (např. Drivers)
Uninstall-WindowsUpdate.cmd -KB 5127648 -Force -DryRun       # dávkově, jen plán příkazů
Uninstall-WindowsUpdate.cmd -KB 5127648 -Hide -Force         # odinstalace + skrytí ve Windows Update
Uninstall-WindowsUpdate.cmd -KB 5127648 -HideOnly -Force     # jen skrytí (typicky po restartu)
```

Vyžaduje: Windows 10/11, PowerShell 5.1, oprávnění správce pro odinstalaci a mapování KB na balíček.
Exit kódy: 0 OK, 1 selhání, 2 `-Force` bez `-KB`, 3 chybí elevace, 4 zrušeno uživatelem.
Log: `logs\Uninstall-WindowsUpdate.log`. JSON obsahuje `wu_source` (WSUS / WUfB / WindowsUpdate podle politik).
Pozor: odinstalace LCU vrací bezpečnostní opravy. KB potom skryjte (`-HideOnly` po restartu), jinak ji
Windows Update nainstaluje znovu. Pod WSUS / WUfB blokujte raději na serveru.

## Instalace

`git clone --recurse-submodules https://github.com/dnemecek/uninstall-windowsupdate.git`

Bez `--recurse-submodules` zůstane `common/` prázdná. Git na Windows: `winget install --id Git.Git -e --source winget`.

## Struktura

```
Uninstall-WindowsUpdate.ps1   hlavní skript
Uninstall-WindowsUpdate.cmd   CMD launcher (ExecutionPolicy Bypass)
common/                       submodul dnemecek/ps-common
logs/                         logy (mimo git)
```

## Autor

David Němeček
