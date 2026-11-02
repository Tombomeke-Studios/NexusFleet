# Leerlogboek

> **Tijdelijk concept, geschreven door Claude Code op vraag van Tom (2 november 2026).**
> Hieronder staan alleen de **feiten** van de bevindingen tot nu toe, als ruwe notities. Tom kiest het format,
> verwoordt alles zelf en verwijdert deze melding daarna. Wat Tom verwachtte, probeerde en leerde, vult hij
> zelf in: die kopjes staan bij elke bevinding klaar.

---

## 1. PSScriptAnalyzer faalt soms zelf (2 november 2026)

### Feiten

- **Wat er gebeurde:** bij het nakijken van unit 3 draaide Tom in één `pwsh`-sessie eerst
  `Import-Module Pester`, dan `Invoke-ScriptAnalyzer ... -Settings ./PSScriptAnalyzerSettings.psd1`, en dan
  `Invoke-Pester`. De analyzer gaf `Object reference not set to an instance of an object.`, terwijl de code in
  orde was. De tests slaagden gewoon.
- **Eerder gezien:** dezelfde dag gaf de analyzer ook één keer `The term 'Get-Command' is not recognized`.
- **Metingen ronde 1** (telkens een nieuw `pwsh`-proces per run, PSScriptAnalyzer op de hele repository):

  | Poging | Mislukte runs |
  |---|---|
  | 1.25.0, alle regels | ongeveer 1 op 10 |
  | 1.24.0 (de oplossing uit het upstream-issue) | 10 op 40 |
  | Bestand per bestand analyseren | 8 op 30 |
  | Tot drie keer opnieuw proberen | 1 op 40, ook na drie pogingen |
  | 1.25.0 zonder `PSUseCorrectCasing` | 0 op 105 |

- **Ronde 2:** na experiment E3 kwam de fout terug (3 op 30). De stack trace wees naar een andere regel,
  `PSReservedCmdletChar`, die `Export-ModuleMember` opzocht in de demomodule. De echte oorzaak is dus de gedeelde
  commando-opzoeking in PSScriptAnalyzer, niet één regel.
- **Oorzaak:** een bekende, nog open bug
  ([PowerShell/PSScriptAnalyzer#2205](https://github.com/PowerShell/PSScriptAnalyzer/issues/2205)): een *race
  condition* (twee dingen die tegelijk lopen en elkaar soms in de weg zitten).
- **Oplossing:** `PSUseCorrectCasing` uit; geen `Export-ModuleMember` in de repo; lint altijd via
  `tools/Invoke-NexusLint.ps1`, dat alleen de interne fouten van de analyzer (`RULE_ERROR`) opnieuw probeert.
- **Waar het vastligt:** issues #11 en #12, `docs/ontwerpkeuzes.md` (K2), `docs/uitleg/kwaliteitscontrole.md`.

### Verwachting
_In te vullen door Tom._

### Wat ik probeerde
_In te vullen door Tom._

### Wat ik leerde
_In te vullen door Tom._

---

## 2. Een commando voor bash werkt niet zomaar in PowerShell (2 november 2026)

### Feiten

- **Wat er gebeurde:** Tom plakte `pwsh -NoProfile -Command "... ForEach-Object { Get-Content $_.FullName ... }"`
  in zijn PowerShell-venster. Elke oproep faalde met `Cannot find path '...\.FullName'`.
- **Oorzaak:** het commando was geschreven voor bash. In PowerShell vult de *buitenste* shell `$_` tussen
  dubbele aanhalingstekens al in voordat de binnenste `pwsh` start. `$_` was daar leeg, dus er bleef `.FullName`
  over.
- **Oplossing:** in een PowerShell-prompt het commando rechtstreeks uitvoeren, zonder `pwsh -Command "..."`.

### Verwachting
_In te vullen door Tom._

### Wat ik probeerde
_In te vullen door Tom._

### Wat ik leerde
_In te vullen door Tom._

---

## 3. Drie Pester-versies op één machine (2 november 2026)

### Feiten

- Windows levert zelf Pester **3.4.0** mee.
- `Install-Module Pester -MinimumVersion 5.0` installeerde Pester **6.2.0**, de nieuwste versie, niet 5.
- Pester 5.7.1 is er apart naast gezet; laden met `Import-Module Pester -MinimumVersion 5.0 -MaximumVersion 5.99`.
- **Botsing:** als PSScriptAnalyzer de testbestanden analyseert, laadt hij de assembly (de DLL) van de nieuwste
  Pester (6). Daarna kan Pester 5 in hetzelfde proces niet meer laden ("Assembly with same name is already
  loaded"). Oplossing: eerst Pester 5 importeren, of lint en tests in aparte processen (de CI doet dat).
- **Waar het vastligt:** `docs/ontwerpkeuzes.md` (K1, K3), CLAUDE.md sectie 4.

### Verwachting
_In te vullen door Tom._

### Wat ik probeerde
_In te vullen door Tom._

### Wat ik leerde
_In te vullen door Tom._

---

## 4. Pester-mocks en scopes (2 november 2026)

### Feiten

- **Mocks en `-Parallel` (experiment E3):** een mock werkt als je de functie rechtstreeks aanroept (1 keer
  geteld) en in een gewone lus (2 keer), maar **niet** in `ForEach-Object -Parallel` (0 keer: daar draait de
  echte functie). Elke runspace is een nieuwe, lege omgeving die de module opnieuw inlaadt.
- **Mocks en `$script:`:** bij de tests van het lintscript faalden er drie. Een mock-body draait op het moment dat
  het *lintscript* het gemockte commando aanroept; dat scriptbestand heeft een eigen script scope. `$script:x` in
  de mock verwees dus naar het lintscript, niet naar de test. Een klein experiment toonde dat de mock wel gewone
  variabelen uit `BeforeAll`/`It` ziet. Een teller moet in een hashtable (`$state.Attempt++`).
- **Waar het vastligt:** `lab/E3-mocks-parallel/`, `docs/ontwerpkeuzes.md` (E3),
  `docs/uitleg/kwaliteitscontrole.md`, `docs/uitleg/parallel-uitvoering.md`.

### Verwachting
_In te vullen door Tom._

### Wat ik probeerde
_In te vullen door Tom._

### Wat ik leerde
_In te vullen door Tom._

---

## 5. Interne modulefuncties in een runspace (2 november 2026)

### Feiten

- `Write-NexusLog` is intern (niet geëxporteerd). Een `-Parallel`-runspace die de module importeert, kan de
  functie daarna **niet** aanroepen.
- Wel mogelijk: het werk uitvoeren *in de scope van de module*:
  `$m = Import-Module $using:manifest -PassThru; & $m { param(...) Write-NexusLog ... } $args`.
- Modulevariabelen (`$script:RunId`) bestaan niet in een runspace; daarom is er een run-context-object dat met
  `$using:` meegaat.
- **Waar het vastligt:** test in `tests/utils/Write-NexusLog.Tests.ps1`, `docs/uitleg/logging.md`, CLAUDE.md
  sectie 8.

### Verwachting
_In te vullen door Tom._

### Wat ik probeerde
_In te vullen door Tom._

### Wat ik leerde
_In te vullen door Tom._

---

## 6. `-WhatIf` erft door naar alles eronder (2 november 2026)

### Feiten

- Bij een cmdlet met `-WhatIf` staat `$WhatIfPreference` op `$true`, en dat geldt voor elk commando eronder, ook
  `New-Item` en `Add-Content`. Zonder maatregel zou een dry run dus geen logbestand schrijven.
- Oplossing: `-WhatIf:$false` op de commando's die altijd moeten gebeuren (de logging). Twee tests bewijzen het.
- **Waar het vastligt:** `src/utils/Initialize-NexusRunContext.ps1`, `src/utils/Write-NexusLog.ps1`,
  `docs/uitleg/logging.md`.

### Verwachting
_In te vullen door Tom._

### Wat ik probeerde
_In te vullen door Tom._

### Wat ik leerde
_In te vullen door Tom._

---

## 7. SSH vanuit PowerShell (experiment E1, 2 november 2026)

### Feiten

- Lab: twee Docker-containers als stand-in voor een verse Ubuntu-VM (sshd, gebruiker met alleen een sleutel en
  sudo zonder wachtwoord); één met PowerShell erop voor remoting.
- **`localhost` was traag:** 2,2 s per verbinding. Oorzaak: `localhost` probeert eerst IPv6 (`::1`), de poorten
  luisterden alleen op IPv4. Met `127.0.0.1`: 0,2 s.
- **Geheim via stdin kwam verkeerd aan:** een string die je in PowerShell naar `ssh` pijpt, krijgt op Windows
  `\r\n` erachter. `od -c` op de host toonde `g e h e i m \r \n`. Met een `byte[]` pijpen kwamen exact de bytes
  aan (kan vanaf PowerShell 7.4).
- Resultaten van de drie transporten en het voorstel: `docs/ontwerpkeuzes.md` (E1).

### Verwachting
_In te vullen door Tom._

### Wat ik probeerde
_In te vullen door Tom._

### Wat ik leerde
_In te vullen door Tom._

---

## 8. Parallel werken meten (experiment E2, 2 november 2026)

### Feiten

- Per host 0,5 s gesimuleerd werk, 10 tegelijk, mediaan van 3 rondes, elke meting in een nieuw proces.
- 50 hosts: na elkaar 26,0 s · `ForEach-Object -Parallel` 2,89 s / 124 MB · `Start-ThreadJob` 3,36 s / 173 MB ·
  `Start-Job` 9,57 s / 464 MB. Het minimum is 2,5 s (50 / 10 × 0,5 s).
- `Start-Job` start voor elke job een volledig nieuw `pwsh`-proces; dat opstarten kost de meeste tijd.
- **Waar het vastligt:** `lab/E2-concurrency/`, `docs/ontwerpkeuzes.md` (E2), `docs/uitleg/parallel-uitvoering.md`.

### Verwachting
_In te vullen door Tom._

### Wat ik probeerde
_In te vullen door Tom._

### Wat ik leerde
_In te vullen door Tom._

---

## 9. Minimale PowerShell-versie (2 november 2026)

### Feiten

- Levenscyclus volgens Microsoft: 7.2 niet meer ondersteund sinds 8 november 2024; 7.4 tot 10 november 2026;
  7.6 (LTS) tot 14 november 2028.
- De CI draaide al op PowerShell 7.6.9 (Ubuntu 26.04), zichtbaar in het CI-log.
- Keuze van Tom: **7.6**, voor de langdurige ondersteuning. Doorgevoerd in de manifest (test eerst) en de
  documentatie (#28, `docs/ontwerpkeuzes.md` K4).

### Verwachting
_In te vullen door Tom._

### Wat ik probeerde
_In te vullen door Tom._

### Wat ik leerde
_In te vullen door Tom._
