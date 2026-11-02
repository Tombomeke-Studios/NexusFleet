# Leerlogboek

> **Tijdelijk concept, geschreven door Claude Code op vraag van Tom (2 november 2026).**
> Hieronder staan alleen de feiten van één bevinding, als ruwe notitie. Tom kiest het format, verwoordt dit
> zelf en verwijdert deze melding daarna. Wat Tom verwachtte en leerde, vult hij zelf in.

## PSScriptAnalyzer faalt soms zelf (2 november 2026)

### Feiten

- **Wat er gebeurde:** bij het nakijken van unit 3 draaide Tom in één `pwsh`-sessie eerst
  `Import-Module Pester`, dan `Invoke-ScriptAnalyzer ... -Settings ./PSScriptAnalyzerSettings.psd1`, en dan
  `Invoke-Pester`. De analyzer gaf `Object reference not set to an instance of an object.`, terwijl de code in
  orde was. De tests slaagden gewoon.
- **Eerder gezien:** dezelfde dag gaf de analyzer ook één keer `The term 'Get-Command' is not recognized`,
  maar dat kon toen niet opnieuw worden opgewekt.
- **Metingen** (telkens een nieuw `pwsh`-proces per run, PSScriptAnalyzer op de hele repository):

  | Poging | Mislukte runs |
  |---|---|
  | 1.25.0, alle regels | ongeveer 1 op 10 |
  | 1.24.0 (de oplossing uit het upstream-issue) | 10 op 40 |
  | Bestand per bestand analyseren | 8 op 30 |
  | Tot drie keer opnieuw proberen | 1 op 40, ook na drie pogingen |
  | 1.25.0 zonder `PSUseCorrectCasing` | 0 op 105 |

- **Oorzaak:** een bekende, nog open bug in PSScriptAnalyzer
  ([PowerShell/PSScriptAnalyzer#2205](https://github.com/PowerShell/PSScriptAnalyzer/issues/2205)): de interne
  `Get-Command`-opzoeking draait in runspaces die tegelijk werken, en af en toe loopt dat mis. De regel
  `PSUseCorrectCasing` lokt het uit.
- **Oplossing:** `PSUseCorrectCasing` uit; de CI draait de analyzer met `-ErrorAction Stop`, zodat een falende
  analyzer de job rood maakt in plaats van "geen meldingen" te tonen.
- **Waar het vastligt:** issue #11 (bug), #12 (regel later terug aanzetten), `docs/ontwerpkeuzes.md` (K2),
  `docs/uitleg/kwaliteitscontrole.md`.

### Verwachting

_In te vullen door Tom._

### Wat ik probeerde

_In te vullen door Tom._

### Wat ik leerde

_In te vullen door Tom._
