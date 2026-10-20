<#
.SYNOPSIS
    Vypise Windows aktualizace nainstalovane od zadaneho data, necha vybrat a odinstaluje je.

.DESCRIPTION
    Obecny nastroj pro rucni i davkovou odinstalaci Windows aktualizaci.
    - Zdroj 1: historie Windows Update (COM Microsoft.Update.Session), jen uspesne instalace od -Since.
    - Zdroj 2: CBS balicky (Get-WindowsPackage -Online) pro mapovani KB -> PackageName.
      Vyzaduje elevaci; bez ni se mapovani preskoci a vypise se jen historie.
    - Zdroj aktualizaci (WSUS / WUfB / WindowsUpdate) se urcuje z registry politik -> wu_source, wu_policy.
    - Interaktivne: ocislovany seznam (volitelne zuzeny -Filter), vyber cisel, potvrzeni.
    - Davkove: -KB + -Force bez dotazu (Ansible).
    - Odinstalace: DISM /Remove-Package, kdyz je KB namapovany na CBS balicek, jinak wusa /uninstall.
    - -Hide / -HideOnly: skryti aktualizace ve WUA na klientovi, aby se znovu nenainstalovala.
    - Ovladace, definice Defenderu a SSU se jen vypisuji, neodinstaluji se.
    - Idempotentni (2359303 = uz odinstalovano => OK; uz skryta => OK).
    - Vystup: tabulka / citelne shrnuti; s -Json pouze JSON na stdout (Ansible-ready), log do souboru.
      Vyjimka: interaktivni rezim (bez -Force) pise vyber/dotazy na konzoli.

.PARAMETER List
    Pouze vypise aktualizace jako tabulku (s -Json jako JSON). Zadne zmeny.

.PARAMETER Json
    Vystup jako JSON (Ansible) misto tabulky a citelneho shrnuti. Plati pro vsechny rezimy.

.PARAMETER Since
    Pocatecni datum instalace. Vychozi: pred 30 dny. Nesmi byt v budoucnosti.

.PARAMETER Filter
    Wildcard na titul nebo KB (napr. "*Cumulative*", "KB50*"). Vychozi: vse.

.PARAMETER KB
    Cisla KB k odinstalaci / skryti, s prefixem KB i bez (5127648 / KB5127648). Lze vice hodnot.

.PARAMETER Category
    Wildcard na kind polozky (lcu, update, driver, definition, ssu, package, other) nebo na nazev kategorie
    z historie WU (napr. "Security Updates", "Drivers"). Lze vice hodnot. Vychozi: vse.

.PARAMETER Hide
    Po odinstalaci navic skryje vybrane KB ve WUA (online scan, muze trvat minuty).

.PARAMETER HideOnly
    Jen skryje vybrane KB, bez odinstalace (typicky po restartu, ktery dokoncil odinstalaci).

.PARAMETER LogRoot
    Lokalni koren pro logy. Log: <LogRoot>\Logs\Uninstall-WindowsUpdate.log (stderr z .cmd do .err vedle).
    Vychozi: %ProgramData%\Scripts. Lokalni i pri behu z NETLOGONu, kam pocitac zapisovat nesmi.

.PARAMETER DryRun
    Simulace bez provedeni zmen; planovane prikazy jdou do logu a do planned.

.PARAMETER Force
    Bez potvrzeni (Ansible / davka). Vyzaduje -KB.

.PARAMETER Silent
    Pro GPO Startup Script: zadny vystup na konzoli (ani tabulka, ani JSON), jen log; bez dotazu.
    Chova se jako -Force (vyzaduje -KB, jinak exit 2 jen do logu).

.EXAMPLE
    .\Uninstall-WindowsUpdate.ps1 -List -Since 2026-10-01
    # tabulka; s -Json jako JSON

.EXAMPLE
    .\Uninstall-WindowsUpdate.ps1 -Filter "*Cumulative*"
    # interaktivni vyber a odinstalace

.EXAMPLE
    .\Uninstall-WindowsUpdate.ps1 -KB 5127648 -Force -DryRun

.EXAMPLE
    .\Uninstall-WindowsUpdate.ps1 -KB 5127648 -HideOnly -Force
    # po restartu: skryti KB, aby ji Windows Update znovu nenainstaloval

.EXAMPLE
    \\<domena>\netlogon\scripts\Uninstall-WindowsUpdate.cmd -KB 5127648 -Hide -Force -Silent
    # GPO Startup Script: 1. start odinstaluje, 2. start skryje, dalsi starty = uz skryta (OK)

.NOTES
    Nazev:     Uninstall-WindowsUpdate.ps1
    Autor:     David Nemecek
    Vytvoreno: 2026-10-20
    Verze:     1.0.0
    Vyzaduje:  Windows 10/11, PowerShell 5.1, elevated (Administrator) pro odinstalaci, mapovani a skryti

    SECURITY WARNING:
    - Odinstalace LCU vraci bezpecnostni opravy. Vzdy nejdriv -List / -DryRun.
    - Po odinstalaci aktualizaci pozastavit/skryt (-Hide / -HideOnly), jinak ji Windows Update nainstaluje znovu.
    - Skryti plati jen pro tuto KB; nasledujici kumulativni aktualizace ji nahradi a nainstaluje se.
    - WSUS s nastavenym deadlinem nebo politiky WUfB mohou skryti na klientovi prebit (NEOVERENO);
      blokaci v takovem prostredi resit na serveru (WSUS decline / WUfB pause).
#>

[CmdletBinding()]
param (
    [switch]$List,
    [switch]$Json,
    [datetime]$Since = (Get-Date).AddDays(-30),
    [string]$Filter = '*',
    [string[]]$KB = @(),
    [string[]]$Category = '*',
    [switch]$Hide,
    [switch]$HideOnly,
    [string]$LogRoot = "$env:ProgramData\Scripts",
    [switch]$DryRun,
    [switch]$Force,
    [switch]$Silent
)

$ErrorActionPreference = 'Stop'; $startTime = Get-Date; $scriptVersion = '1.0.0'
# Konvence GPO skriptu: <LogRoot>\Logs\<scriptName>.log, .err plni launcher; vzdy lokalne, i z NETLOGONu.
$LogPath = Join-Path $LogRoot 'Logs\Uninstall-WindowsUpdate.log'
# NETLOGON ma sdilene moduly v scripts\modules\, git repozitar v submodulu common\; hledame per soubor.
function Find-Lib {
    param([string]$Name)
    $p = Join-Path $PSScriptRoot "modules\$Name"
    if (Test-Path $p) { $p } else { Join-Path $PSScriptRoot "common\$Name" } }
. (Find-Lib 'Add-Log.ps1'); Import-Module (Find-Lib 'Lock-Script.psm1') -Force
# -Silent (GPO) je davkovy rezim bez konzole: bez dotazu jako -Force; -Json vypne tabulku, Write-Result pak nic.
if ($Silent) { $Force = [switch]$true; $Json = [switch]$true }
function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    Add-Log -Message $Message -Level $Level -LogFile $LogPath -StartTime $startTime }
function Add-Warning { param([string]$Msg, [string]$Level = 'WARNING') $result.warnings += $Msg; Write-Log $Msg $Level }

$result = [ordered]@{
    changed = $false; dry_run = [bool]$DryRun; elevated = $false; since = $Since.ToString('s'); mapped = $false
    selected = @(); planned = @(); removed = @(); failed = @(); skipped = @(); hidden = @(); not_found = @()
    reboot_required = $false; warnings = @(); msg = ''; log = $LogPath; wu_source = ''; wu_policy = @{}
}

function Test-Elevated {
    # RID 544 = BUILTIN\Administrators; nazev skupiny je lokalizovany (cs: Administratori), RID ne.
    $id = [Security.Principal.WindowsIdentity]::GetCurrent(); ([Security.Principal.WindowsPrincipal]$id).IsInRole(544) }

function Write-Result {
    # Vysledek na stdout: s -Json JSON pro Ansible, jinak citelne shrnuti pro cloveka (jako vypis -List).
    if ($Silent) { return }
    if ($Json) { $result | ConvertTo-Json -Depth 5; return }
    foreach ($k in 'planned', 'removed', 'failed', 'skipped', 'hidden', 'not_found', 'warnings') {
        $result[$k] | ForEach-Object { Write-Host ("{0,-9} {1}" -f $k, $_) } }
    Write-Host "$($result.msg) | wu: $($result.wu_source) | reboot: $($result.reboot_required) | log: $($result.log)"
}

function Exit-WithResult {
    # Spolecny konec pro predcasne vystupy: warning do JSON i logu, JSON na stdout, exit kod.
    param([string]$Message, [int]$Code, [string]$Level = 'WARNING')
    Add-Warning $Message $Level; $result.msg = $Message; Write-Result; exit $Code
}

function Get-WuSource {
    <#
    .SYNOPSIS
        Cil: urcit zdroj aktualizaci klienta (WSUS / WUfB / WindowsUpdate) a vyplnit wu_policy.
    .NOTES
        Mantinely: cte jen registry politik (HKLM:\SOFTWARE\Policies\...\WindowsUpdate a \AU), nic nemeni.
        Lokalni nastaveni mimo politiky (napr. rucni pauza v Nastaveni) se nevyhodnocuje.
        Kontrola: vraci vzdy jednu z hodnot 'WSUS <url>', 'WUfB', 'WindowsUpdate'.
    #>
    $wu = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -ErrorAction SilentlyContinue
    $au = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' -ErrorAction SilentlyContinue
    $policy = @{ DisableDualScan = $wu.DisableDualScan; NoAutoUpdate = $au.NoAutoUpdate }
    $policy.Keys | Where-Object { $null -ne $policy[$_] } | ForEach-Object { $result.wu_policy[$_] = $policy[$_] }
    if ($au.UseWUServer -eq 1 -and $wu.WUServer) { return "WSUS $($wu.WUServer)" }
    $wufb = 'DeferQualityUpdates', 'DeferFeatureUpdates', 'PauseQualityUpdatesStartTime', 'TargetReleaseVersion'
    if ($wufb | Where-Object { $null -ne $wu.$_ }) { 'WUfB' } else { 'WindowsUpdate' }
}

function Get-UpdateHistory {
    <#
    .SYNOPSIS
        Cil: uspesne instalace z historie Windows Update od -Since, klasifikovane a deduplikovane podle KB.
    .NOTES
        Mantinely: jen Operation=1 (installation), ResultCode 2/3; Date je UTC, proto ToLocalTime.
        Ovladace, definice a SSU dostanou uninstallable=$false - wusa/DISM na ne nepatri.
        Kontrola: kazdy zaznam ma kind; zadna KB se ve vystupu neopakuje.
    #>
    param([datetime]$From)
    $searcher = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher()
    if (($count = $searcher.GetTotalHistoryCount()) -eq 0) { return }
    $entries = $searcher.QueryHistory(0, $count) |
        Where-Object { $_.Title -and $_.Operation -eq 1 -and $_.ResultCode -in 2, 3 }
    $items = foreach ($e in $entries) {
        $date = [datetime]::SpecifyKind($e.Date, 'Utc').ToLocalTime(); if ($date -lt $From) { continue }
        $cats = @($e.Categories | ForEach-Object { $_.Name })
        $kbNum = if ($e.Title -match 'KB(\d+)') { $Matches[1] } else { $null }
        $kind, $method = if ($e.Title -match 'Defender|Security Intelligence|KB2267602') { 'definition', 'none' }
            elseif ($cats -match 'Drivers') { 'driver', 'rollback via Device Manager / pnputil' }
            elseif (-not $kbNum) { 'other', 'none' }
            elseif ($e.Title -match 'Servicing Stack') { 'ssu', 'none (SSU cannot be removed)' }
            elseif ($e.Title -match 'Cumulative Update for Windows') { 'lcu', 'wusa' }
            else { 'update', 'wusa' }
        [pscustomobject]@{
            date = $date.ToString('yyyy-MM-dd HH:mm'); kb = $kbNum; kind = $kind; categories = $cats
            uninstallable = ($kind -in 'update', 'lcu'); method = $method; package = $null; title = $e.Title
        }
    }
    # Posledni instalace vyhrava; ovladace bez KB deduplikujeme podle titulu.
    $items | Sort-Object date -Descending | Group-Object { if ($_.kb) { $_.kb } else { $_.title } } |
        ForEach-Object { $_.Group[0] }
}

function Get-PackageMap {
    <#
    .SYNOPSIS
        Cil: CBS balicky nainstalovane od -Since a jejich KB (podklad pro mapovani KB -> PackageName).
    .NOTES
        Mantinely: vyzaduje elevaci. LCU se jmenuje Package_for_RollupFix~... a KB v nazvu nema, proto KB
        hledame regexem napric vsemi vlastnostmi detailu balicku (nazev vlastnosti s KB neni overen).
        Kontrola: kazdy vraceny objekt ma name a ssu; kb muze byt $null (balicek bez nalezene KB).
    #>
    param([datetime]$From)
    # Jen aktualizace (SecurityUpdate, Update, Hotfix, ...): LCU pri instalaci preservisuje i Features on Demand
    # (RSAT, jazyky, ovladace) s novym InstallTime; ty nejsou aktualizace a jejich odebrani by odebralo funkci OS.
    # UninstallPending = DISM odebral balicek (3010), dokonci se az restartem; nesmi skoncit na wusa.
    $packages = Get-WindowsPackage -Online | Where-Object {
        "$($_.PackageState)" -in 'Installed', 'UninstallPending' -and [datetime]$_.InstallTime -ge $From -and
        "$($_.ReleaseType)" -match 'Update|Hotfix|ServicePack' }
    foreach ($p in $packages) {
        $detail = Get-WindowsPackage -Online -PackageName $p.PackageName
        $text = ($detail.PSObject.Properties | ForEach-Object { "$($_.Value)" }) -join ' '
        $kbNum = if ($text -match '(?:KB\s*|kbid=|/help/)(\d+)') { $Matches[1] } else { $null }
        [pscustomobject]@{ name = $p.PackageName; kb = $kbNum; ssu = ($p.PackageName -match 'ServicingStack')
            date = ([datetime]$p.InstallTime).ToString('yyyy-MM-dd HH:mm'); description = $detail.Description
            pending = ("$($p.PackageState)" -eq 'UninstallPending') }
    }
}

function Hide-WindowsUpdate {
    <#
    .SYNOPSIS
        Cil: skryt zadane KB ve WUA na klientovi (IsHidden), aby je Windows Update znovu nenainstaloval.
    .NOTES
        Mantinely: online scan proti nakonfigurovanemu zdroji (minuty). Po DISM /Remove-Package neni
        aktualizace do restartu nabidnuta, proto se -Hide typicky spousti az po restartu (-HideOnly).
        Kriterium vyslovne zahrnuje i skryte aktualizace, aby uz skryta KB byla idempotentni OK.
        Kontrola: kazda KB skoncila v hidden (skryta / uz skryta), planned (DRY-RUN) nebo ve warnings.
    #>
    param([string[]]$KbList)
    $src = $result.wu_source; Write-Log "WU scan for offered updates ($src) start"
    if (-not $DryRun) { $null = New-Item $stateDir -ItemType Directory -Force }
    $searcher = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher()
    $offered = @($searcher.Search('IsInstalled=0 and IsHidden=0 or IsInstalled=0 and IsHidden=1').Updates)
    Write-Log "WU scan done: $($offered.Count) updates offered"
    foreach ($k in $KbList) {
        $hits = @($offered | Where-Object { @($_.KBArticleIDs) -contains $k })
        $msg = "KB$k not offered by $src; if uninstall is pending reboot, run -Hide again after reboot"
        if (-not $hits) { Add-Warning $msg; continue }
        foreach ($u in $hits) {
            if ($u.IsHidden) { Write-Log "Already hidden KB$k" }
            elseif ($DryRun) { $result.planned += "hide KB$k"; Write-Log "DRY-RUN: hide KB$k"; continue }
            else { $u.IsHidden = $true; $result.changed = $true; Write-Log "Hidden KB$k $($u.Title)" }
            $result.hidden += "KB$k"
            # Znacka pro rychly konec dalsich startu (GPO): tam se pak neceka na online scan WU.
            if (-not $DryRun) { Set-Content (Join-Path $stateDir "KB$k.hidden") (Get-Date -Format s) }
        }
    }
}

try {
    Write-Log "=== Uninstall-WindowsUpdate v$scriptVersion start dry_run=$DryRun list=$List since=$Since cat=$Category"
    if ($Since -gt (Get-Date)) { throw "Since ($($result.since)) is in the future." }
    # Pres .cmd (powershell -File) prijde "-KB 1,2" jako jeden retezec, proto deleni na carkach a mezerach.
    $kbWanted = @($KB -split '[,\s]+' | Where-Object { $_ } | ForEach-Object { $_ -replace '^KB', '' } |
        Select-Object -Unique)
    # Kategorie maji mezery ("Security Updates"), proto deleni jen na carkach.
    $catWanted = @($Category -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if (-not $catWanted) { $catWanted = '*' }
    if ($badKb = @($kbWanted -notmatch '^\d+$')) { throw "Invalid KB value(s): $($badKb -join ', ')" }
    # Exit-ScriptLock netreba: zamek drzi otevreny FileStream a uvolni se s koncem procesu i pri exit z hloubky.
    if (-not (Enter-ScriptLock -LockName 'Uninstall-WindowsUpdate' -LockFolder (Join-Path $LogRoot 'Locks'))) {
        Exit-WithResult 'Another instance is running, exit' 0 'INFO' }
    # Rychly konec (GPO pousti skript pri kazdem startu, inventar a online scan WU trvaji ~minutu): KB je hotova,
    # kdyz neni v Get-HotFix a (bez -Hide nebo uz ma znacku State\KB<n>.hidden). Po reinstalaci ji Get-HotFix
    # vidi a bezi plny beh, znacka se ignoruje. Prazdny Get-HotFix (chyba WMI) rychly konec nepovoli.
    $hotfixes = @(Get-HotFix -ErrorAction SilentlyContinue | ForEach-Object { $_.HotFixID -replace '^KB', '' })
    $stateDir = Join-Path $LogRoot 'State'
    $done = @($kbWanted | Where-Object { $hotfixes -notcontains $_ -and
        (-not ($Hide -or $HideOnly) -or (Test-Path (Join-Path $stateDir "KB$_.hidden"))) })
    if ($kbWanted -and $hotfixes -and -not $List -and $done.Count -eq $kbWanted.Count) {
        $result.not_found = @($done | ForEach-Object { "KB$_" })
        Exit-WithResult "Nothing to do: KB$($done -join ', KB') already removed/hidden" 0 'INFO' }
    $result.elevated = Test-Elevated
    $result.wu_source = Get-WuSource; Write-Log "WU source: $($result.wu_source)"

    # ---------------------------------------------------------------- inventory
    $items = @(Get-UpdateHistory -From $Since)
    if ($result.elevated) {
        $packages = @(Get-PackageMap -From $Since); $result.mapped = $true
        foreach ($i in $items | Where-Object { $_.kb -and $_.uninstallable }) {
            # Pri vice balicich k jedne KB preferujeme LCU (RollupFix) - ten se odebira DISMem.
            $match = @($packages | Where-Object { $_.kb -eq $i.kb -and -not $_.ssu } |
                Sort-Object { $_.name -notmatch 'RollupFix' })
            if (-not $match) { continue }
            $i.package = $match[0].name; $i.method = 'dism'; if ($i.package -match 'RollupFix') { $i.kind = 'lcu' }
            if ($match.Count -gt 1) { $result.warnings += "KB$($i.kb): $($match.Count) packages, using $($i.package)" }
        }
        # Balicky, jejichz KB uz je v historii (napr. SSU cast kombinovaneho SSU+LCU), nevypisujeme znovu.
        foreach ($p in $packages | Where-Object { -not ($_.kb -and $items.kb -contains $_.kb) }) {
            $kind, $method = if ($p.ssu) { 'ssu', 'none (SSU cannot be removed)' }
                elseif ($p.name -match 'RollupFix') { 'lcu', 'dism' } else { 'package', 'dism' }
            $title = if ($p.description) { $p.description } else { $p.name }
            $items += [pscustomobject]@{ date = $p.date; kb = $p.kb; kind = $kind; categories = @()
                uninstallable = -not $p.ssu; method = $method; package = $p.name; title = $title }
        }
        $pendingNames = @($packages | Where-Object { $_.pending } | ForEach-Object { $_.name })
        foreach ($i in $items | Where-Object { $_.package -and $pendingNames -contains $_.package }) {
            $i.uninstallable = $false; $i.method = 'pending reboot'; $result.reboot_required = $true
            Add-Warning "KB$($i.kb) $($i.package): uninstall pending reboot"
        }
    } else { Add-Warning 'Not elevated: CBS package mapping skipped, history only (removal would use wusa).' }
    # Historie WU drzi i uz odinstalovane KB (Operation=1 zustava); bez CBS balicku rozhoduje Get-HotFix
    # (funguje i bez elevace, $hotfixes vyse). MSRT (KB890830) v Get-HotFix neni a odinstalovat nejde, spravne vypadne.
    $unmapped = @($items | Where-Object { $_.kind -in 'update', 'lcu' -and -not $_.package })
    foreach ($i in $unmapped | Where-Object { $hotfixes -notcontains $_.kb }) {
        $i.uninstallable = $false; $i.method = 'not installed'
    }
    $items = @($items | Where-Object { $_.title -like $Filter -or "KB$($_.kb)" -like $Filter } |
        Where-Object { $names = @($_.kind) + $_.categories; $catWanted | Where-Object { $names -like $_ } } |
        Sort-Object date -Descending)

    # ---------------------------------------------------------------- list
    if ($List) {
        $result.updates = $items; $result.msg = "$($items.Count) updates since $($result.since)"; Write-Log $result.msg
        # Tabulka pro cloveka (jako Uninstall-MsiPackage); s -Json jen JSON z Write-Result.
        # Uzka tabulka: sloupec remove = metoda odinstalace nebo '-', titul zkraceny na 80 znaku (cely je v -Json).
        $short = { if ($_.title.Length -gt 80) { $_.title.Substring(0, 77) + '...' } else { $_.title } }
        if (-not $Json) { $items | Format-Table date, @{ n = 'KB'; e = { if ($_.kb) { "KB$($_.kb)" } } }, kind,
            @{ n = 'remove'; e = { if ($_.uninstallable) { $_.method } else { '-' } } },
            @{ n = 'title'; e = $short } -AutoSize |
            Out-String -Width 160 | Write-Host }
        Write-Result; exit 0
    }

    # ---------------------------------------------------------------- selection
    if ($kbWanted) {
        $selected = @($items | Where-Object { $_.kb -and $kbWanted -contains $_.kb })
        # Nenalezena / uz odinstalovana KB neni chyba (exit 0): GPO spousti stejne parametry pri kazdem startu.
        $installed = @($items | Where-Object { $_.method -ne 'not installed' } | ForEach-Object { $_.kb })
        $result.not_found = @($kbWanted | Where-Object { $installed -notcontains $_ } | ForEach-Object { "KB$_" })
        if ($result.not_found) { Write-Log "Not found / not installed: $($result.not_found -join ', ')" 'WARNING' }
    } elseif (-not $Force) {
        if ($items.Count -eq 0) { Write-Host "No updates since $($result.since) match filter '$Filter'."; exit 0 }
        Write-Host "`nUpdates installed since $($result.since) (filter: $Filter)`n------------------------------"
        for ($n = 0; $n -lt $items.Count; $n++) {
            $u = $items[$n]; $yn = if ($u.uninstallable) { 'yes' } else { 'no' }; $k = "KB$($u.kb)"
            Write-Host ("{0,3}. {1} {2,-10} {3,-10} {4,-3} {5}" -f ($n + 1), $u.date, $k, $u.kind, $yn, $u.title)
        }
        $answer = Read-Host "`nNumbers to process (e.g. 1,3,5) or Enter to quit"
        if (-not $answer.Trim()) { Write-Log 'Nothing selected'; exit 0 }
        $idx = @($answer -split '[,\s]+' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ - 1 } |
            Where-Object { $_ -ge 0 -and $_ -lt $items.Count } | Sort-Object -Unique)
        if (-not $idx.Count) { Write-Log 'Nothing selected'; exit 0 }
        $selected = @($items[$idx])
    } else { Exit-WithResult '-Force requires -KB.' 2 'ERROR' }

    # Skryvat jde i KB, ktera uz neni v historii (napr. odinstalovana pred -Since), proto primo z -KB.
    $hideKbs = @(if ($kbWanted) { $kbWanted } else { @($selected.kb) -ne $null }); if ($HideOnly) { $selected = @() }
    foreach ($s in $selected | Where-Object { -not $_.uninstallable }) {
        $result.skipped += "KB$($s.kb) $($s.kind): $($s.method)"; Write-Log "Skipped: $($s.title)" 'WARNING'
    }
    $selected = @($selected | Where-Object { $_.uninstallable })
    $result.selected = @($selected | ForEach-Object { "KB$($_.kb) [$($_.method)] $($_.title)" })
    # S -Hide se skryva i bez odinstalace: po restartu uz KB neni co odebrat, ale skryt ji je potreba (GPO 2. start).
    if ($selected.Count -eq 0 -and -not (($Hide -or $HideOnly) -and $hideKbs)) {
        Exit-WithResult 'Nothing to uninstall or hide.' 0
    }
    if (-not $result.elevated -and -not $DryRun) {
        Exit-WithResult 'Update removal/hiding requires elevation (Administrator).' 3 'ERROR'
    }
    if (-not $Force -and -not $DryRun) {
        Write-Host "`nWill uninstall:"; $result.selected | ForEach-Object { Write-Host "  - $_" }
        if ($Hide -or $HideOnly) { Write-Host "Will hide: KB$($hideKbs -join ', KB')" }
        if ((Read-Host 'Continue? [y/N]') -notmatch '^[yY]') { Write-Log 'Aborted by user' 'WARNING'; exit 4 }
    }

    # ---------------------------------------------------------------- uninstall
    foreach ($u in $selected) {
        # S PackageName vzdy DISM: Microsoft v release notes kumulativnich aktualizaci uvadi, ze wusa /uninstall
        # na kombinovany SSU+LCU balicek nefunguje (obsahuje SSU), a doporucuje DISM /Remove-Package
        # s nazvem LCU balicku. wusa jen pro KB bez namapovaneho balicku.
        $cmdText = if ($u.package) { "dism.exe /Online /Remove-Package /PackageName:$($u.package) /Quiet /NoRestart" }
                   else { "wusa.exe /uninstall /kb:$($u.kb) /quiet /norestart" }
        if ($DryRun) { $result.planned += $cmdText; Write-Log "DRY-RUN: $cmdText"; continue }
        Write-Log "Uninstalling KB$($u.kb): $cmdText"
        $exe, $argList = $cmdText -split ' ', 2
        $p = Start-Process $exe -ArgumentList $argList -Wait -PassThru -WindowStyle Hidden
        $id = if ($u.package) { $u.package } else { "KB$($u.kb)" }
        # 2359303 = 0x240007 WU_S_ALREADY_UNINSTALLED (aktualizace neni nainstalovana) => idempotentni OK.
        switch ($p.ExitCode) {
            { $_ -in 0, 3010 } { $result.removed += $id; $result.changed = $true; Write-Log "OK $id exit=$_" }
            2359303 { $result.removed += $id; Write-Log "Already removed $id" }
            default { $result.failed += "$($id):$($p.ExitCode)"; Write-Log "FAILED $id exit=$($p.ExitCode)" 'ERROR' }
        }
        if ($p.ExitCode -eq 3010) { $result.reboot_required = $true; Write-Log "Reboot required $id" 'WARNING' }
    }

    # ---------------------------------------------------------------- hide
    if ($Hide -and $result.reboot_required) { Add-Warning 'Uninstall pending reboot: run -HideOnly after reboot.' }
    if ($Hide -or $HideOnly) { Hide-WindowsUpdate -KbList $hideKbs }

    $result.msg = "removed=$($result.removed.Count) failed=$($result.failed.Count) hidden=$($result.hidden.Count)" +
        " planned=$($result.planned.Count) not_found=$($result.not_found.Count)"
    Write-Log "=== done changed=$($result.changed) $($result.msg) reboot_required=$($result.reboot_required)"
    Write-Result; exit [int]($result.failed.Count -gt 0)
}
catch {
    Write-Log "FATAL: $($_.Exception.Message)" -Level ERROR; Write-Log "Stack: $($_.ScriptStackTrace)" -Level ERROR
    $result.error = $_.Exception.Message; $result.msg = $result.error
    Write-Result; exit 1
}
