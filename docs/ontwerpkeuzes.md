# NexusFleet — Ontwerpkeuzes

Per keuze: de vraag, de opties die bekeken of uitgetest zijn, het resultaat, wat weerhouden werd en waarom.
De experimenten E1–E4 (fase 1) bepalen keuzes waar de code van afhangt; hun resultaten vult Tom in.

Format per keuze:

- **Vraag** — wat er beslist moest worden
- **Opties** — wat bekeken of uitgetest werd
- **Resultaat** — metingen of observaties
- **Keuze** — wat weerhouden werd, en waarom
- **Gevolg** — wat dit betekent voor de code

---

## Experimenten (fase 1)

### E1 — Transport: `ssh`, PowerShell-remoting over SSH of Posh-SSH

_Nog uit te voeren._

### E2 — Parallel werken: `ForEach-Object -Parallel`, `Start-ThreadJob` of `Start-Job`

- **Vraag:** welke manier van parallel werken gebruikt NexusFleet om veel hosts tegelijk te behandelen?
- **Opzet:** `lab/E2-concurrency/Measure-Concurrency.ps1`. Per host gesimuleerd werk: 0,5 s wachten (staat voor
  SSH) en een kleine rekenlus. Elke meting draait in een nieuw `pwsh`-proces; mediaan van 3 rondes;
  `ThrottleLimit` 10. Machine: 16 logische CPU's, PowerShell 7.6.9, Windows 10.
- **Resultaat:**

  | Methode | 10 hosts | 50 hosts | Geheugen bij 50 hosts |
  |---|---|---|---|
  | Na elkaar (referentie) | 5,25 s | 26,02 s | 99 MB |
  | `ForEach-Object -Parallel` | **0,71 s** | **2,89 s** | **124 MB** |
  | `Start-ThreadJob` | 0,89 s | 3,36 s | 173 MB |
  | `Start-Job` | 2,69 s | 9,57 s | 464 MB* |

  Het theoretische minimum voor 50 hosts is 50 / 10 × 0,5 s = 2,5 s. `-Parallel` zit daar dicht bij.
  `Start-Job` start voor elke job een volledig nieuw `pwsh`-proces: dat opstarten domineert de tijd, en er
  is geen `-ThrottleLimit`.

  \* Gemeten door elke 100 ms de werkgeheugens van de kindprocessen op te tellen. Omdat de jobs na elkaar
  opstarten en snel klaar zijn, leven er maar een paar tegelijk; bij langer werk per host loopt dit verder op
  (ongeveer 60–70 MB per proces).
- **Voorstel (Claude Code, door Tom te bevestigen):** `ForEach-Object -Parallel` met `-ThrottleLimit` uit een
  parameter. Het snelst, het minst geheugen, ingebouwd, en de uitvoer komt gewoon door de pijplijn.
  `Start-ThreadJob` is een redelijk alternatief (job-objecten, dus later opvragen), maar trager en zwaarder
  zonder dat NexusFleet de jobfuncties nodig heeft. `Start-Job` valt af.
- **Gevolg:** de patronen uit CLAUDE.md sectie 8 gelden: variabelen via `$using:`, de module per runspace
  importeren, en `ShouldProcess` beslissen vóór de parallelle lus. Het werk per host zit in een eigen functie
  (E3).

### E3 — Pester-mocks en `-Parallel`-runspaces

- **Vraag:** werkt een Pester-`Mock` ook voor code die in `ForEach-Object -Parallel` draait? En lost het
  patroon "het werk voor één host in een eigen functie" dat op?
- **Opzet:** `lab/E3-mocks-parallel/`. Een mini-module `FleetDemo.psm1` met dezelfde opbouw als NexusFleet:
  `Get-DemoAnswer` (staat voor SSH of de API, wordt gemockt), `Invoke-DemoHostWork` (het werk voor één host),
  en twee dunne wrappers: een gewone lus en een `ForEach-Object -Parallel` die de module per runspace
  importeert. Uitvoeren: `Invoke-Pester -Path ./lab/E3-mocks-parallel -Output Detailed`.
- **Resultaat** (3 van 3 tests slagen, Pester 5.7.1, PowerShell 7.6):

  | Hoe aangeroepen | Uitkomst | Mock-oproepen geteld |
  |---|---|---|
  | `Invoke-DemoHostWork` rechtstreeks | `mock:host1` | 1 |
  | Gewone lus (`ForEach-Object`) | `mock:host1`, `mock:host2` | 2 |
  | `ForEach-Object -Parallel` | `real:host1`, `real:host2`, `real:host3` | **0** |

  In `-Parallel` draait de **echte** functie. Elke runspace is een nieuwe, lege omgeving die de module opnieuw
  importeert; de mock bestaat alleen in de runspace van de test.
- **Voorstel (Claude Code, door Tom te bevestigen):** het patroon uit CLAUDE.md houden. Het werk voor één host
  staat altijd in een eigen functie die rechtstreeks getest wordt met mocks; de parallelle lus is een dunne
  wrapper zonder logica. Die wrapper test je met een echte, onschuldige uitvoering (zoals hier) of in een
  integratietest.
- **Gevolg:** in `Test-NexusHost`, `Install-NexusNode` en `Get-NexusFleetStatus` komt de logica per host in
  een aparte functie (bijv. `Test-NexusHostSingle`); unit tests mocken nooit iets "door" een `-Parallel` heen.

### E4 — Scopes van het API-token

_Nog uit te voeren._

---

## Keuzes tijdens de opbouw (fase 0)

### K1 — Pester 5.x vastpinnen

- **Vraag:** welke Pester-versie gebruiken lokaal en in de CI?
- **Opties:** de nieuwste (`-MinimumVersion 5.0`), of een vaste 5.x-versie.
- **Resultaat:** `Install-Module Pester -MinimumVersion 5.0` installeerde Pester 6.2.0. Windows levert zelf
  Pester 3.4.0 mee.
- **Keuze:** Pester 5.7.1, vast (`-RequiredVersion`) in de CI, en lokaal geladen met
  `Import-Module Pester -MinimumVersion 5.0 -MaximumVersion 5.99`. Het voorstel en de tests gaan uit van
  Pester 5, en een vaste versie geeft vandaag en later hetzelfde resultaat.
- **Gevolg:** CLAUDE.md (secties 4 en 6), README en CI gebruiken deze versie.

### K2 — PSScriptAnalyzer stabiel krijgen (`PSUseCorrectCasing` uit, lintscript met herkansing)

- **Vraag:** hoe voorkomen dat PSScriptAnalyzer af en toe zelf faalt (`Object reference not set to an
  instance of an object`, of `The term 'Get-Command' is not recognized`)?
- **Opties en resultaat, ronde 1** (telkens een nieuw `pwsh`-proces per run, analyzer op de hele repo):

  | Optie | Mislukte runs |
  |---|---|
  | 1.25.0, alle regels | ongeveer 1 op 10 |
  | 1.24.0 (voorgesteld in het upstream-issue) | 10 op 40 |
  | Bestand per bestand analyseren | 8 op 30 |
  | Tot drie keer opnieuw proberen | 1 op 40 (ook na drie pogingen) |
  | 1.25.0 zonder `PSUseCorrectCasing` | 0 op 105 |

- **Ronde 2:** na het toevoegen van E3 kwam de fout terug (3 op 30). De stack trace toonde
  `PSReservedCmdletChar` → `Helper.GetExportedFunction` → `CommandInfo.ResolveParameter`, uitgelokt door
  `Export-ModuleMember` in `lab/E3-mocks-parallel/FleetDemo.psm1`. De oorzaak is dus de gedeelde
  commando-opzoeking van PSScriptAnalyzer (race condition,
  [PowerShell/PSScriptAnalyzer#2205](https://github.com/PowerShell/PSScriptAnalyzer/issues/2205)), niet één regel.
  Zonder `Export-ModuleMember`: 0 op 60.
- **Keuze:**
  1. `PSUseCorrectCasing` uit (cosmetisch; terug aan zodra de bug opgelost is, issue #12).
  2. Geen `Export-ModuleMember` in de repo; exporteren gebeurt via de manifest.
  3. `tools/Invoke-NexusLint.ps1`, lokaal en in de CI: probeert alleen fouten met `FullyQualifiedErrorId`
     `RULE_ERROR*` opnieuw (max. 3 keer). Meldingen over code en andere fouten worden nooit opnieuw
     geprobeerd; na 3 mislukte pogingen faalt het script.
- **Gevolg:** één lintcommando voor iedereen, getest met een gemockte analyzer (6 tests). Bug: #11.

### K3 — Lint en tests als aparte CI-jobs

- **Vraag:** PSScriptAnalyzer en Pester in één job of in twee?
- **Resultaat:** PSScriptAnalyzer laadt bij het analyseren van de testbestanden de assembly van de nieuwste
  Pester (6.x). Daarna kan Pester 5 niet meer laden in hetzelfde proces ("Assembly with same name is already
  loaded").
- **Keuze:** twee aparte jobs. Ze draaien tegelijk, tonen apart welke controle faalt, en de botsing kan niet
  optreden.
- **Gevolg:** lokaal eerst Pester 5 importeren, of lint en tests in aparte processen draaien (CLAUDE.md, sectie 4).
