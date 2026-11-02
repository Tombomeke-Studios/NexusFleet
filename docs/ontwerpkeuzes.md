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

_Nog uit te voeren._

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

### K2 — `PSUseCorrectCasing` uit

- **Vraag:** hoe voorkomen dat PSScriptAnalyzer af en toe zelf faalt (`Object reference not set to an
  instance of an object`, of `The term 'Get-Command' is not recognized`)?
- **Opties en resultaat** (telkens een nieuw `pwsh`-proces per run, PSScriptAnalyzer op de hele repo):

  | Optie | Mislukte runs |
  |---|---|
  | 1.25.0, alle regels | ongeveer 1 op 10 |
  | 1.24.0 (voorgesteld in het upstream-issue) | 10 op 40 |
  | Bestand per bestand analyseren | 8 op 30 |
  | Tot drie keer opnieuw proberen | 1 op 40 (ook na drie pogingen) |
  | 1.25.0 zonder `PSUseCorrectCasing` | 0 op 105 |

- **Keuze:** `PSUseCorrectCasing` uit. De oorzaak is een race condition in de interne commando-opzoeking
  van PSScriptAnalyzer ([PowerShell/PSScriptAnalyzer#2205](https://github.com/PowerShell/PSScriptAnalyzer/issues/2205)),
  en die regel lokt ze uit. Hoofdletters zijn cosmetisch; een stabiele controle is belangrijker.
- **Gevolg:** de CI draait de analyzer met `-ErrorAction Stop`, zodat een falende analyzer nooit groen is.
  De regel gaat terug aan zodra de bug opgelost is (issue #12). Bug: #11.

### K3 — Lint en tests als aparte CI-jobs

- **Vraag:** PSScriptAnalyzer en Pester in één job of in twee?
- **Resultaat:** PSScriptAnalyzer laadt bij het analyseren van de testbestanden de assembly van de nieuwste
  Pester (6.x). Daarna kan Pester 5 niet meer laden in hetzelfde proces ("Assembly with same name is already
  loaded").
- **Keuze:** twee aparte jobs. Ze draaien tegelijk, tonen apart welke controle faalt, en de botsing kan niet
  optreden.
- **Gevolg:** lokaal eerst Pester 5 importeren, of lint en tests in aparte processen draaien (CLAUDE.md, sectie 4).
