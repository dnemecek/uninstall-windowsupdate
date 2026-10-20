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
Uninstall-WindowsUpdate.cmd -KB 5127648 -Force -Json         # výstup jako JSON (Ansible), platí pro všechny režimy
Uninstall-WindowsUpdate.cmd -KB KB5127648 -Force             # dávkově, bez dotazů
Uninstall-WindowsUpdate.cmd -KB 5127648 -Hide -Force         # odinstalace + skrytí ve Windows Update
Uninstall-WindowsUpdate.cmd -KB 5127648 -HideOnly -Force     # jen skrytí (typicky po restartu)
```

Vyžaduje: Windows 10/11, PowerShell 5.1, oprávnění správce pro odinstalaci a mapování KB na balíček.
Exit kódy: 0 OK, 1 selhání, 2 `-Force` bez `-KB`, 3 chybí elevace, 4 zrušeno uživatelem.
Log: `<LogRoot>\Logs\Uninstall-WindowsUpdate.log` (výchozí `%ProgramData%\Scripts`), stderr dávkově do `.err`. JSON obsahuje `wu_source` (WSUS / WUfB / WindowsUpdate podle politik).
Po odinstalaci DISMem není KB do restartu nabízena, proto `-HideOnly` spusťte až po restartu.

Pozor: odinstalace LCU vrací bezpečnostní opravy. Aktualizaci potom skryjte (`-Hide`) nebo pozastavte,
jinak ji Windows Update nainstaluje znovu. Pod WSUS / WUfB blokujte raději na serveru.

## Parametry

| Parametr | Význam |
|---|---|
| `-List` | Jen výpis (tabulka), žádné změny. |
| `-Since <datum>` | Aktualizace nainstalované od data (výchozí před 30 dny), např. `2026-10-15`. |
| `-Filter <wildcard>` | Filtr na název nebo KB, např. `"*Cumulative*"`, `"KB50*"`. |
| `-Category <wildcard>` | Filtr na druh (`lcu`, `update`, `driver`, `definition`, `ssu`, `package`, `other`) nebo kategorii WU (`Drivers`). |
| `-KB <čísla>` | KB k odinstalaci / skrytí, s prefixem `KB` i bez; lze více (`-KB 5127648,5127690`). |
| `-Hide` | Po odinstalaci navíc skryje KB ve Windows Update. |
| `-HideOnly` | Jen skryje KB, bez odinstalace (po restartu, který odinstalaci dokončil). |
| `-DryRun` | Simulace: jen vypíše plánované příkazy. |
| `-Force` | Bez dotazů (dávka, Ansible); vyžaduje `-KB`. |
| `-Json` | Výstup jako JSON místo tabulky a shrnutí. |
| `-Silent` | GPO Startup Script: žádný výstup na konzoli, jen log; chová se jako `-Force`. |
| `-LogRoot <cesta>` | Kořen logů; log `<LogRoot>\Logs\Uninstall-WindowsUpdate.log` + `.err` (výchozí `%ProgramData%\Scripts`). |

Odinstalace a zákaz opětovné instalace (DISM odinstalaci dokončí až restartem, do té doby KB nejde skrýt):

```
Uninstall-WindowsUpdate.cmd -KB 5127648 -Force              # 1. odinstalace
                                                            # 2. restart
Uninstall-WindowsUpdate.cmd -KB 5127648 -HideOnly -Force    # 3. skrytí ve Windows Update
```

## Nasazení přes GPO

Computer Configuration → Policies → Windows Settings → Scripts (Startup) → Scripts:

- Script: `\\<domena>\netlogon\scripts\Uninstall-WindowsUpdate.cmd`
- Parameters: `-KB 5127648 -Hide -Force -Silent [-LogRoot C:\<Firma>]`

Soubory do `\\<domena>\netlogon\scripts\`:

```
Uninstall-WindowsUpdate.cmd
Uninstall-WindowsUpdate.ps1
modules\Add-Log.ps1          (z common\)
modules\Lock-Script.psm1     (z common\)
```

První start odinstaluje, druhý skryje, další starty skončí OK beze změny (už skrytá).
Další starty bez práce končí hned (Get-HotFix + značka `<LogRoot>\State\KB<n>.hidden`, bez online scanu);
zámek `<LogRoot>\Locks` brání souběžnému běhu.
Log: `<LogRoot>\Logs\Uninstall-WindowsUpdate.log` + `.err` (stderr). KB, která není nainstalovaná,
je v `not_found` (exit 0).

Pozor:
- DISM odebírá LCU i několik minut a synchronní startup skript zdrží boot; limit čekání GPO
  na skripty může běh přerušit (NEOVĚŘENO).
- Hromadná odinstalace LCU vrací bezpečnostní opravy. Nejdřív testovací OU.

Nápověda: `powershell -NoProfile -Command "Get-Help .\Uninstall-WindowsUpdate.ps1 -Full"`.

## Instalace

```
git clone --recurse-submodules https://github.com/dnemecek/uninstall-windowsupdate.git
```

Bez `--recurse-submodules` zůstane `common/` prázdná a skript selže na chybějícím `Add-Log.ps1`.
Git na Windows: `winget install --id Git.Git -e --source winget`.

## Struktura

```
Uninstall-WindowsUpdate.ps1   hlavní skript
Uninstall-WindowsUpdate.cmd   CMD launcher (ExecutionPolicy Bypass)
common/                       submodul dnemecek/ps-common
```

## Autor

David Němeček
