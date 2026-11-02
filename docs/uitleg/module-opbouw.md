# Module-opbouw

> Uitleg gegenereerd met Claude Code als studiemateriaal. Niet mijn leerlogboek.

_Stand: unit 1 (mappenstructuur, #1) en unit 2 (manifest en loader, #2)._

## 1. Wat het doet

De repository is verdeeld in mappen die elk één taak hebben: contracten, installatiestappen, contact met
servers, contact met de API, de cmdlets zelf en hulpfuncties. Twee bestanden in de root maken er een
PowerShell-module van: de **manifest** (`NexusFleet.psd1`) beschrijft de module, en de **loader**
(`NexusFleet.psm1`) leest alle scripts uit `src/` in, map per map, in een vaste volgorde.

## 2. Waar het staat

| Pad | Taak |
|---|---|
| `NexusFleet.psd1` | Manifest: naam, versie, vereiste PowerShell-versie, welke functies de gebruiker ziet |
| `NexusFleet.psm1` | Loader: dot-sourcet `src/core` → `utils` → `transports` → `api` → `steps` → `public` |
| `src/core/` | De contracten: wat een *stap* is (`Test` / `Apply` / `Rollback`) en wat een *transport* is (een commando op een host uitvoeren) |
| `src/steps/` | Eén bestand per installatiestap: Docker, agent-container, node registreren, *healthy* controleren |
| `src/transports/` | Hoe de module commando's op een host uitvoert (SSH; de methode kiest experiment E1) |
| `src/api/` | `Invoke-NexusApi`: de enige plek die de REST-API van NexusInfra aanroept |
| `src/public/` | De cmdlets die de gebruiker ziet (`Connect-NexusInfra`, `Import-NexusInventory`, …) |
| `src/utils/` | Gedeelde hulp: `Write-NexusLog` en het inlezen van configuratie |
| `tests/` + submappen | Pester-tests, zelfde indeling als `src/`; `tests/NexusFleet.Tests.ps1` test de manifest en de loader |
| `config/` | Alle NexusInfra-specifieke waarden en een voorbeeldinventaris, zonder geheimen |
| `lab/` | Scripts en notities van de experimenten (fase 1), geen deel van de module |

De mappen in `src/` bevatten voorlopig alleen een `README.md` van één regel met hun taak.

## 3. Hoe het werkt

**`Import-Module ./NexusFleet.psd1`** gebeurt in deze volgorde:

1. PowerShell leest de manifest. Is de PowerShell-versie lager dan `7.6` (de LTS-versie, keuze K4 in `docs/ontwerpkeuzes.md`), of is het Windows PowerShell 5.1
   (`CompatiblePSEditions = @('Core')`), dan stopt het hier met een foutmelding.
2. PowerShell voert het bestand uit dat in `RootModule` staat: de loader.
3. De loader overloopt de mappen in vaste volgorde:

   ```powershell
   $sourceFolders = 'core', 'utils', 'transports', 'api', 'steps', 'public'
   ```

4. Ontbreekt een map, dan stopt hij met een duidelijke fout in plaats van stil verder te gaan:

   ```powershell
   if (-not (Test-Path -Path $folderPath -PathType Container)) {
       throw "NexusFleet cannot load: source folder '$folderPath' is missing."
   }
   ```

5. Per map zoekt hij alle `*.ps1`-bestanden, gesorteerd op naam, en **dot-sourcet** ze (`. $file.FullName`).
   Alles wat in dat script gedefinieerd wordt (functies, variabelen, klassen) komt daardoor in de scope van de
   module terecht. Faalt een script, dan vangt `catch` de fout op en gooit hij een nieuwe fout die het
   bestand noemt:

   ```powershell
   catch {
       throw "NexusFleet cannot load '$($file.FullName)': $_"
   }
   ```

6. Daarna kijkt PowerShell opnieuw naar de manifest: alleen de functies in `FunctionsToExport` worden
   zichtbaar voor de gebruiker. Die lijst is nu nog leeg (`@()`); elke cmdlet komt erbij als hij af is.

**De tests** (`tests/NexusFleet.Tests.ps1`) werken zo:

- *Manifest:* `Test-ModuleManifest` controleert of de manifest geldig is, en de tests kijken naar de
  PowerShell-versie, de editie en of `FunctionsToExport` geen `'*'` bevat.
- *Loader:* de test bouwt een wegwerpkopie van de module in `TestDrive` (een tijdelijke map die Pester na
  de test opruimt). In elke `src`-map komt een `Probe.ps1` die bij het inladen zijn mapnaam naar een bestand
  schrijft. Na `Import-Module` moet dat bestand de mappen in de juiste volgorde bevatten. Twee andere tests
  halen een map weg of voegen een kapot script toe, en controleren de foutmelding.

## 4. Waarom zo

- **Eén taak per map, en `steps/` als map van losse bestanden.** Een stap toevoegen, vervangen of weglaten
  wordt dan een bestand toevoegen, vervangen of verwijderen (criterium *uitbreidbaarheid* in het voorstel).
  Het alternatief was één groot `NexusFleet.psm1`-bestand met alle functies. Dat is in het begin sneller,
  maar wordt onleesbaar, en een stap kun je er niet los uit halen of los testen.
- **Alleen `api/` praat met NexusInfra.** Als NexusInfra zijn API verandert (bedreiging in de SWOT), moet je
  maar op één plek aanpassen, en in tests hoef je maar één ding te mocken.
- **Een vaste mapvolgorde in plaats van "alles inladen".** Voor gewone functies maakt de volgorde niet uit:
  PowerShell zoekt een functie pas op op het moment dat ze wordt *aangeroepen*. Maar klassen (die in `core/`
  komen voor de contracten) en variabelen op moduleniveau moeten al bestaan wanneer een later bestand ze bij
  het inladen gebruikt. Met een vaste volgorde is dat altijd zo. Het alternatief, `Get-ChildItem src -Recurse`,
  laadt in alfabetische mapvolgorde (`api` vóór `core`), wat zou breken zodra `api` een klasse uit `core` nodig heeft.
- **Sorteren op naam binnen een map.** `Get-ChildItem` belooft geen volgorde; op Linux (de CI) kan die
  anders zijn dan op Windows. Sorteren maakt het gedrag overal gelijk. De volgorde van de installatie*stappen*
  hangt hier niet van af: elke stap verklaart later zelf zijn volgorde.
- **Fouten met de bestandsnaam erin.** Zonder `try/catch` zie je enkel "boom" en moet je zelf zoeken welk van
  de bestanden het was (criterium *robuust*).
- **`FunctionsToExport` als expliciete lijst, nooit `'*'`.** Met `'*'` zou elke interne hulpfunctie zichtbaar
  worden voor de gebruiker, en moet PowerShell bij autoloading de hele module inladen om te weten welke
  commando's er zijn. Een expliciete lijst is sneller en toont precies de publieke cmdlets (best practice
  volgens Microsoft). Ook `CmdletsToExport`, `VariablesToExport` en `AliasesToExport` staan om dezelfde reden op `@()`.
- **De manifest met de hand geschreven**, niet met `New-ModuleManifest`. Dat commando maakt een bestand van
  ruim honderd regels, vooral commentaar; deze versie bevat alleen wat de module gebruikt, zodat elke regel
  uit te leggen is.
- **Een `README.md` per map in plaats van lege `.ps1`-bestanden.** Git bewaart geen lege mappen, dus er moest
  iets in. Lege scriptbestanden zouden namen vastleggen die nog niet beslist zijn (de transportmethode volgt
  pas uit E1). Een `README.md` toont de taak van de map ook op GitHub en wordt door de loader nooit geladen,
  want die leest alleen `*.ps1`.
- **`logs/` bestaat nog niet.** Die map maakt de module zelf aan tijdens een uitvoering, en hij komt in
  `.gitignore` (#4). Logbestanden horen niet in de repository.

## 5. PowerShell-concepten

- **Scriptmodule:** een `.psm1`-bestand met functies, plus een manifest (`.psd1`) dat de module beschrijft.
  https://learn.microsoft.com/powershell/scripting/developer/module/how-to-write-a-powershell-script-module
- **Modulemanifest** (`RootModule`, `PowerShellVersion`, `CompatiblePSEditions`, `FunctionsToExport`):
  https://learn.microsoft.com/powershell/scripting/developer/module/how-to-write-a-powershell-module-manifest
- **Publieke en interne functies:** alleen wat de manifest exporteert, is zichtbaar voor de gebruiker.
  https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_modules
- **Dot-sourcing** (`. pad\naar\script.ps1`): het script draait in de *huidige* scope, niet in een eigen
  scope, zodat zijn functies en variabelen blijven bestaan. In de loader is die huidige scope de module.
  https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_scripts#script-scope-and-dot-sourcing
- **`$PSScriptRoot`:** de map van het script dat nu draait. Daardoor werkt de loader, waar de module ook staat.
  https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_automatic_variables#psscriptroot
- **`throw` en `try/catch`:** een fout die de uitvoering stopt, en het opvangen ervan. In `catch` is `$_` de
  opgevangen fout. https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_try_catch_finally
- **Pester `TestDrive`:** een tijdelijke map per test die Pester zelf opruimt.
  https://pester.dev/docs/usage/testdrive
- **Pester `Should -Throw -ExpectedMessage`:** controleert dat een scriptblok een fout gooit met een bepaalde
  boodschap (met wildcards `*`). https://pester.dev/docs/commands/Should (zie `-Throw`)
- **Pester-conventie `*.Tests.ps1`:** Pester zoekt standaard naar bestanden met die naam. Het spiegelen van
  `src/` is een afspraak van dit project, geen regel van Pester.
  https://pester.dev/docs/usage/file-placement-and-naming

## 6. Zelf proberen

```powershell
# Vanuit de root van de repo
Test-ModuleManifest ./NexusFleet.psd1
Import-Module ./NexusFleet.psd1 -Force -Verbose     # -Verbose toont wat PowerShell inlaadt
Get-Command -Module NexusFleet                      # nog leeg: er zijn nog geen publieke cmdlets

# De tests (Pester 5, niet 6 of de ingebouwde 3.4)
Import-Module Pester -MinimumVersion 5.0 -MaximumVersion 5.99
Invoke-Pester -Path ./tests -Output Detailed
```

Zien hoe het faalt:

```powershell
# 1. Een ontbrekende map
Rename-Item ./src/api api-weg
Import-Module ./NexusFleet.psd1 -Force       # fout: source folder '...src/api' is missing
Rename-Item ./src/api-weg api

# 2. Een kapot script
Set-Content ./src/utils/Kapot.ps1 'throw "kapot"'
Import-Module ./NexusFleet.psd1 -Force       # fout noemt Kapot.ps1
Remove-Item ./src/utils/Kapot.ps1

# 3. Windows PowerShell 5.1 (powershell.exe in plaats van pwsh)
powershell.exe -NoProfile -Command "Import-Module ./NexusFleet.psd1"   # geweigerd door de manifest
```

## 7. Controlevragen

1. Waarom staat de code om NexusInfra aan te spreken in één aparte map, en wat win je daarmee bij het testen?
2. Wat is het verschil tussen een script gewoon uitvoeren en het dot-sourcen, en waarom heeft de loader dat tweede nodig?
3. Voor gewone functies maakt de laadvolgorde niet uit. Waarvoor dan wel, en waarom staat `core` vooraan?
4. Wat gebeurt er als `FunctionsToExport = '*'` zou staan? Noem een nadeel voor de gebruiker en een voor de snelheid.
5. Hoe controleert de loadertest de volgorde, zonder in de module zelf te kijken?
