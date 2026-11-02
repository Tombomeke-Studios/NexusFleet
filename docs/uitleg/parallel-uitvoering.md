# Parallel uitvoering

> Uitleg gegenereerd met Claude Code als studiemateriaal. Niet mijn leerlogboek.

_Stand: experimenten E2 (#17) en E3 (#18). Het patroon in de praktijk: zie `preflight.md` (`Test-NexusHost`)._

## 1. Wat het doet

NexusFleet moet tientallen tot honderden hosts behandelen. Na elkaar duurt dat te lang, dus het werk gebeurt
parallel. Experiment E2 meet drie manieren om dat in PowerShell te doen. Experiment E3 bewijst dat je zulke
parallelle code niet zomaar kunt testen met Pester-mocks, en hoe je dat oplost.

## 2. Waar het staat

| Pad | Inhoud |
|---|---|
| `lab/E2-concurrency/Measure-Concurrency.ps1` | Meet na elkaar, `ForEach-Object -Parallel`, `Start-ThreadJob` en `Start-Job` |
| `lab/E3-mocks-parallel/FleetDemo.psm1` | Mini-module met het NexusFleet-patroon: werk per host in een eigen functie |
| `lab/E3-mocks-parallel/MocksAndParallel.Tests.ps1` | Pester-tests die tonen waar een mock wel en niet werkt |
| `docs/ontwerpkeuzes.md`, E2 en E3 | De meetresultaten en het voorstel |

## 3. Hoe het werkt

**E2.** Het script roept zichzelf op, één keer per meting, in een nieuw `pwsh`-proces:

```powershell
$json = pwsh -NoProfile -File $PSCommandPath -Method $name -TargetCount $count `
    -WorkMilliseconds $WorkMilliseconds -ThrottleLimit $ThrottleLimit
```

Zo begint elke meting met een "leeg" proces, en lekt het geheugen van de ene meting niet in de volgende. In
die meting doet elke "host" hetzelfde: even wachten (staat voor SSH) en een kleine rekenlus. Bijvoorbeeld met
`ForEach-Object -Parallel`:

```powershell
$null = 1..$count | ForEach-Object -Parallel {
    Start-Sleep -Milliseconds $using:WorkMilliseconds
    $sum = 0; foreach ($i in 1..20000) { $sum += $i }
    $sum
} -ThrottleLimit $ThrottleLimit
```

- Het blok tussen `{ }` draait in een **runspace**: een aparte, lege PowerShell-omgeving in hetzelfde proces.
- Variabelen van buiten zie je daar niet; je haalt ze binnen met `$using:`.
- `-ThrottleLimit 10` betekent: hoogstens 10 tegelijk.

`Start-ThreadJob` werkt ook met runspaces, maar geeft een job-object terug dat je met `Wait-Job` en
`Receive-Job` ophaalt. `Start-Job` start voor elke job een **volledig nieuw `pwsh`-proces**. Het script stopt
de tijd met een `Stopwatch` en leest het piekgeheugen van het proces (`PeakWorkingSet64`). Bij `Start-Job` telt
het ook het geheugen van de kindprocessen op, die het elke 100 ms bekijkt.

**E3.** De mini-module heeft vier functies. `Get-DemoAnswer` staat voor "de buitenwereld" (SSH, de API) en
wordt in de test vervangen door een mock. `Invoke-DemoHostWork` is het werk voor één host. Twee dunne wrappers
roepen dat werk aan voor meerdere hosts: één in een gewone lus, één parallel:

```powershell
$modulePath = $PSCommandPath
$Name | ForEach-Object -Parallel {
    Import-Module -Name $using:modulePath
    Invoke-DemoHostWork -Name $_
} -ThrottleLimit $ThrottleLimit
```

Elke runspace is leeg, dus de module moet er opnieuw worden ingeladen, via het pad (`$PSCommandPath` is het
pad van het `.psm1`-bestand zelf). De test zet een mock op `Get-DemoAnswer` en controleert drie gevallen:

| Aanroep | Uitkomst | `Should -Invoke` telt |
|---|---|---|
| `Invoke-DemoHostWork` rechtstreeks | `mock:host1` | 1 |
| Gewone lus | `mock:host1`, `mock:host2` | 2 |
| `-Parallel` | `real:host1`, `real:host2`, `real:host3` | **0** |

In de parallelle versie draait de echte functie: de nieuw ingeladen module in de runspace weet niets van de
mock, die alleen in de runspace van de test bestaat.

## 4. Waarom zo

- **`ForEach-Object -Parallel` als voorstel.** Voor 50 hosts: 2,89 s en 124 MB, tegenover 3,36 s en 173 MB voor
  `Start-ThreadJob` en 9,57 s en 464 MB voor `Start-Job`. Het theoretische minimum is 2,5 s (50 hosts / 10
  tegelijk × 0,5 s). `Start-Job` valt af: elk nieuw proces kost opstarttijd en geheugen, en er is geen
  `-ThrottleLimit`.
- **Elke meting in een nieuw proces.** Anders meet je bij de derde methode ook het geheugen dat de eerste twee
  hebben laten liggen.
- **De mediaan van drie rondes**, niet het gemiddelde: één trage uitschieter (bijvoorbeeld een virusscanner die
  net een bestand bekijkt) verschuift een gemiddelde, maar nauwelijks de mediaan.
- **Het werk per host in een eigen functie.** E3 toont dat je parallelle code niet met mocks kunt testen. Door
  alle logica in de functie voor één host te zetten, test je die volledig met mocks, en blijft de parallelle
  wrapper zo dun dat er bijna niets te testen valt.
- **Waarom de module in elke runspace opnieuw ingeladen wordt.** Functies van de module bestaan niet in een
  nieuwe runspace. Het alternatief, de functietekst als string meegeven en opnieuw aanmaken, is moeilijker te
  lezen en vergeet makkelijk een hulpfunctie.

## 5. PowerShell-concepten

- **`ForEach-Object -Parallel` en `-ThrottleLimit`:**
  https://learn.microsoft.com/powershell/module/microsoft.powershell.core/foreach-object
- **`$using:`:** een variabele van de aanroeper gebruiken in een runspace, job of remote sessie.
  https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_remote_variables
- **`Start-ThreadJob`:** https://learn.microsoft.com/powershell/module/threadjob/start-threadjob
- **`Start-Job`, `Wait-Job`, `Receive-Job`:** https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_jobs
- **`$PSCommandPath`:** het volledige pad van het script of de module die nu draait.
  https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_automatic_variables
- **`System.Diagnostics.Stopwatch`:** nauwkeurig tijd meten.
  https://learn.microsoft.com/dotnet/api/system.diagnostics.stopwatch
- **Pester `Mock -ModuleName` en `Should -Invoke`:** een functie vervangen binnen een module en tellen hoe vaak
  ze werd aangeroepen. https://pester.dev/docs/usage/mocking

## 6. Zelf proberen

```powershell
# E3: de drie gevallen (een paar seconden)
Import-Module Pester -MinimumVersion 5.0 -MaximumVersion 5.99
Invoke-Pester -Path ./lab/E3-mocks-parallel -Output Detailed

# E2: de volledige meting (ongeveer 3 minuten)
./lab/E2-concurrency/Measure-Concurrency.ps1 | Format-Table

# E2: kleiner en sneller, of met meer hosts
./lab/E2-concurrency/Measure-Concurrency.ps1 -TargetCount 20 -Repeat 1 | Format-Table
./lab/E2-concurrency/Measure-Concurrency.ps1 -TargetCount 100 -ThrottleLimit 25 -Repeat 1 | Format-Table
```

Zien hoe het faalt:

```powershell
# Een variabele zonder $using: in -Parallel is daar gewoon leeg
$wacht = 100
1..3 | ForEach-Object -Parallel { "wacht = [$wacht]" }          # wacht = []
1..3 | ForEach-Object -Parallel { "wacht = [$using:wacht]" }    # wacht = [100]

# Een functie van buiten bestaat niet in de runspace
function Get-Hallo { 'hallo' }
1..2 | ForEach-Object -Parallel { Get-Hallo }                     # fout: Get-Hallo is not recognized
```

## 7. Controlevragen

1. Wat is het verschil tussen een runspace (`-Parallel`, `Start-ThreadJob`) en een job met `Start-Job`, en wat
   zie je daarvan terug in de metingen?
2. Waarom draait elke meting van E2 in een nieuw `pwsh`-proces?
3. Waarom ziet de code in `-Parallel` de mock uit de test niet?
4. Hoe zorgt het patroon "werk per host in een eigen functie" ervoor dat je toch alles met mocks kunt testen?
5. Wat doet `-ThrottleLimit`, en wat zou er gebeuren met 500 hosts zonder limiet?
