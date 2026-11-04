# Kwaliteitscontrole

> Uitleg gegenereerd met Claude Code als studiemateriaal. Niet mijn leerlogboek.

_Stand: unit 3 (PSScriptAnalyzer-instellingen en exporttest, #3), unit 5 (CI-workflow, #5), en de kwaliteitsronde: de
helptest en de tests over de tests (#66, #67). Het testrapport in de CI: zie `ci-cd.md`._

## 1. Wat het doet

Twee automatische controles bewaken de kwaliteit van de code. **PSScriptAnalyzer** leest de scripts zonder
ze uit te voeren en meldt alles wat tegen de afgesproken regels ingaat: stijl, foutgevoelige constructies,
verboden werkwoorden. Een **Pester-test** controleert dat de module precies de functies aanbiedt die in de
manifest staan, niet meer en niet minder. De **CI** (GitHub Actions) draait allebei bij elke push en elke
pull request op een verse Linux-machine, zodat een fout zichtbaar wordt voordat ze in `dev` belandt.

## 2. Waar het staat

| Pad | Inhoud |
|---|---|
| `PSScriptAnalyzerSettings.psd1` | De regels voor PSScriptAnalyzer |
| `tests/NexusFleet.Tests.ps1`, blok `Describe 'NexusFleet module'` | De import- en exporttests |
| `tools/Invoke-NexusLint.ps1` | Het lintscript: lokaal en in de CI hetzelfde |
| `tests/tools/Invoke-NexusLint.Tests.ps1` | Tests voor het lintscript (met een gemockte analyzer) |
| `.github/workflows/ci.yml` | De CI: job `lint` (het lintscript) en job `test` (Pester), elk op `ubuntu-latest` |

## 3. Hoe het werkt

**PSScriptAnalyzer.** Het commando

```powershell
Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
```

overloopt alle `.ps1`-, `.psm1`- en `.psd1`-bestanden en past de regels uit het settings-bestand toe. Geeft
het niets terug, dan is de code schoon. Het settings-bestand doet drie dingen:

1. `Severity = @('Error', 'Warning', 'Information')`: alle meldingen tellen, ook de lichtste. Het doel uit het
   voorstel is "zonder waarschuwingen".
2. `IncludeDefaultRules = $true`: alle standaardregels blijven aan, zoals goedgekeurde werkwoorden
   (`PSUseApprovedVerbs`), geen aliassen (`PSAvoidUsingCmdletAliases`) en `ShouldProcess` voor wijzigende
   functies.
3. `Rules = @{ ... }`: een paar regels die standaard **uit** staan, worden aangezet en ingesteld:
   - inspringen met 4 spaties (`PSUseConsistentIndentation`),
   - `{` op dezelfde regel, `}` op een eigen regel (`PSPlaceOpenBrace`, `PSPlaceCloseBrace`),
   - één spatie rond operatoren, na komma's en rond `|` (`PSUseConsistentWhitespace`),
   - de `=`-tekens in een hashtable onder elkaar (`PSAlignAssignmentStatement`),
   - geen syntax die PowerShell 7.6 niet kent (`PSUseCompatibleSyntax`).

   `PSUseCorrectCasing` (commando's met hun echte hoofdletters) staat bewust **uit**. Zie de tweede valkuil
   onder "Waarom zo".

**De exporttest.** Die importeert de echte module en vergelijkt twee lijsten:

```powershell
$module = Import-Module -Name $script:manifestPath -Force -PassThru
$exported = @($module.ExportedFunctions.Keys | Sort-Object) -join ', '
$listed = @($script:manifestData.FunctionsToExport | Sort-Object) -join ', '

$exported | Should -Be $listed
```

- `-PassThru` laat `Import-Module` het module-object teruggeven. Daarin staat in `ExportedFunctions` wat de
  gebruiker echt kan aanroepen.
- `Import-PowerShellDataFile` (in `BeforeAll`) leest de manifest als een gewone hashtable, zodat je
  `FunctionsToExport` kunt opvragen.
- Beide lijsten worden gesorteerd en tot één tekst samengevoegd. Twee teksten vergelijken is eenvoudiger
  dan twee lijsten, en het werkt ook als beide lijsten leeg zijn, zoals nu.

Een tweede test controleert dat er geen cmdlets, variabelen of aliassen geëxporteerd worden.

**De CI.** Bij elke `git push` en elke pull request leest GitHub `.github/workflows/ci.yml` en start twee
**jobs** tegelijk, elk op een eigen, verse Ubuntu-machine met `pwsh`:

1. `actions/checkout` haalt de code op.
2. De job installeert precies één vaste versie van wat hij nodig heeft: PSScriptAnalyzer `1.25.0` voor `lint`,
   Pester `5.7.1` voor `test`.
3. *Lint* draait hetzelfde lintscript als jij lokaal: `./tools/Invoke-NexusLint.ps1 -GitHubAnnotations`.
   Voor elke melding schrijft het script een speciale regel naar de uitvoer:

   ```powershell
   Write-Output "::error file=$file,line=$($finding.Line)::$($finding.RuleName): $($finding.Message)"
   ```

   GitHub herkent `::error file=...,line=...::` en toont de melding als **annotatie** bij dat bestand en die
   regel, in de run en in een pull request. Is er minstens één melding, dan stopt `throw` de stap en wordt de
   job rood. Hoe het script met fouten van de analyzer zelf omgaat, staat bij de tweede valkuil.
4. *Test* bouwt een Pester-configuratie op en draait de tests zonder de `Integration`-tag:

   ```powershell
   $config = New-PesterConfiguration
   $config.Run.Path = './tests'
   $config.Run.Exit = $true
   $config.Filter.ExcludeTag = 'Integration'
   ```

   `Run.Exit = $true` laat Pester het proces afsluiten met een foutcode als er een test faalt. Aan die
   foutcode ziet GitHub dat de job rood moet worden.

Tijdens deze unit zijn beide kanten uitgeprobeerd. De gewone push gaf een groene run (10 tests geslaagd onder
Pester 5.7.1, geen meldingen). Een commit op een wegwerpbranch met een stijlfout en een bewust falende test gaf
twee rode jobs, met de analyzer-meldingen als annotatie op `src/utils/Stijl.ps1` regel 2. Daarna is die
branch verwijderd.

### De helptest: help die bruikbaar is

`tests/NexusFleet.Tests.ps1` controleert niet alleen dat elke cmdlet help heeft, maar ook dat die help iets zegt:
een beschrijving van meer dan 300 tekens, elke parameter in minstens een korte zin, minstens twee voorbeelden die
geldige PowerShell zijn (`[System.Management.Automation.Language.Parser]::ParseInput`), de cmdlet zelf gebruiken,
alleen parameters gebruiken die bestaan, en een uitleg hebben. Daarbij `.INPUTS`, `.OUTPUTS`, `.NOTES` en `.LINK`
naar de verwante cmdlets en de online documentatie, en dat `about_NexusFleet` meegeleverd wordt. De eerste keer vond
die test in alle zes cmdlets ontbrekende delen, en een voorbeeld dat de cmdlet niet eens gebruikte.

### Tests over de tests

`tests/Quality.Tests.ps1` vindt gaten die anders een mens moet zien:

- **Elke config-waarde heeft een controleregel.** Voor elke sleutel van `config/nexusinfra.psd1` schrijft de test een
  config met een fout type (een hashtable) en een config zonder die sleutel, en verwacht een fout die de sleutel noemt.
  Een nieuwe sleutel zonder regel faalt hier dus vanzelf.
- **Elk fout-id wordt getest.** De test zoekt in `src/` elke tekst `'NexusFleet.X'` of `'NexusApi.X'` die geen
  type-naam is, en eist dat een test hem noemt. Zo kwam `NexusApi.HttpError` (een onverwachte status als 500) boven,
  dat nergens getest werd.

De dekking wees nog zes ongeteste gedragingen aan (de sleutel en `known_hosts` bij installatie en status, een foute
gebruikersnaam of `agentUrl` in de inventaris, een ontbrekend SecretManagement bij `-Save`, een andere fout dan 403 bij
`Connect-NexusInfra`, een antwoord van het paneel dat geen JSON is); die hebben nu elk een test.

## 4. Waarom zo

- **Een settings-bestand in de repo** in plaats van de regels telkens op de commandoregel mee te geven. Zo
  gebruiken jij, de CI en de docent exact dezelfde regels.
- **Formatteringsregels aan.** De standaardregels gaan vooral over fouten, niet over stijl. Met vaste
  stijlregels ziet alle code er hetzelfde uit, ook als ze over maanden geschreven is (criterium *best
  practices*). Het alternatief was enkel de standaardregels, maar dan blijft stijl een kwestie van smaak.
- **Een conflict tussen twee regels opgelost met een optie.** `PSAlignAssignmentStatement` zet de `=`-tekens
  in een hashtable onder elkaar, met dus meerdere spaties. `PSUseConsistentWhitespace` eist net precies één
  spatie rond elke `=`. Bij de eerste run gaf dat 38 meldingen in de twee `.psd1`-bestanden. De optie
  `IgnoreAssignmentOperatorInsideHashTable = $true` laat de spatieregel de `=` in hashtables overslaan, zodat
  het uitlijnen wint. Het alternatief, het uitlijnen afzetten, maakt manifests en configuratiebestanden
  minder leesbaar.
- **De exporttest bestaat omdat PowerShell zelf niets zegt.** Zet je een functie in `FunctionsToExport` die
  niet bestaat (een tikfout of een vergeten bestand), dan laadt `Import-Module` zonder fout en zonder
  waarschuwing. De functie ontbreekt dan gewoon. Dat is tijdens deze unit uitgeprobeerd met een nep-naam
  `Get-NexusFake`: de import slaagde, alleen de exporttest faalde.
- **De test slaagde meteen.** De manifest bestond al sinds unit 2. Daarom werd hij bewust één keer rood
  gemaakt met die nep-naam, om te bewijzen dat hij een fout echt opmerkt.

### Valkuil: Pester 6 en PSScriptAnalyzer in dezelfde sessie

Op deze machine staan Pester 3.4 (ingebouwd in Windows), 5.7.1 en 6.2.0. Als PSScriptAnalyzer de testbestanden
analyseert, zoekt hij de commando's `Describe`, `It` en `Should` op. Daarbij laadt hij de **assembly**
(de gecompileerde DLL) van de nieuwste Pester, versie 6. Een tweede versie van dezelfde assembly kan .NET niet
in hetzelfde proces laden, dus `Import-Module Pester -MaximumVersion 5.99` faalt daarna met *"Assembly with
same name is already loaded"*.

Oplossing: importeer Pester 5 **vóór** je de analyzer draait, of draai lint en tests in aparte
`pwsh`-processen. De CI doet het tweede: lint en test zijn aparte jobs op aparte machines.

### Valkuil: PSScriptAnalyzer faalt soms zelf

Bij het nakijken kwam deze fout boven, zonder dat de code iets mankeerde:

```text
Invoke-ScriptAnalyzer: Object reference not set to an instance of an object.
```

Soms ook *"The term 'Get-Command' is not recognized"*. Dat is een bekende, nog open bug in PSScriptAnalyzer
([PowerShell/PSScriptAnalyzer#2205](https://github.com/PowerShell/PSScriptAnalyzer/issues/2205)). Sommige
regels vragen voor elk commando in je code `Get-Command` op. De analyzer doet dat in een pool van aparte
runspaces die tegelijk draaien, en af en toe loopt dat mis (een *race condition*).

Wat er is uitgeprobeerd, telkens met tientallen runs in een nieuw `pwsh`-proces:

| Poging | Resultaat |
|---|---|
| Versie 1.25.0, alle regels | ongeveer 1 op 10 runs faalt |
| Versie 1.24.0 (de oplossing uit het issue) | slechter: 10 op 40 runs falen |
| Bestand per bestand analyseren | slechter: 8 op 30 runs falen |
| Tot drie keer opnieuw proberen | beter, maar 1 op 40 runs faalt ook na drie pogingen |
| 1.25.0 zonder `PSUseCorrectCasing` | **0 op 105 runs falen**, met en zonder Pester geladen |

Daarom staat `PSUseCorrectCasing` uit. Het is een cosmetische regel, en de VS Code-extensie voor PowerShell
corrigeert hoofdletters ook bij "Format Document". Als de bug opgelost is, kan de regel terug aan.

**Maar dat was niet de hele oplossing.** Bij experiment E3 kwam de fout terug, nu 3 keer op 30 runs. De stack
trace toonde een andere regel: `PSReservedCmdletChar` zocht `Export-ModuleMember` op in de demomodule van E3,
via dezelfde gedeelde opzoeking. De bug zit dus niet in één regel, maar in die gedeelde opzoeking, en
verschillende regels kunnen hem uitlokken. Twee maatregelen:

1. **De trigger weghalen:** de demomodule gebruikt geen `Export-ModuleMember` meer (NexusFleet zelf exporteert
   via de manifest). Daarna 0 fouten in 60 runs.
2. **Het lintscript** `tools/Invoke-NexusLint.ps1` probeert de analyse opnieuw, maar **alleen** bij een interne
   fout van de analyzer. Zo'n fout herken je aan de `FullyQualifiedErrorId`, die begint met `RULE_ERROR`:

   ```powershell
   $ruleErrors = @($analyzerErrors | Where-Object { $_.FullyQualifiedErrorId -like 'RULE_ERROR*' })
   ```

   Meldingen over je code worden nooit opnieuw geprobeerd (die zijn elke keer hetzelfde), en elke andere fout
   (bijvoorbeeld een ontbrekend settings-bestand) stopt meteen. Na `MaxAttempts` (standaard 3) mislukte
   pogingen faalt het script toch. Een falende analyzer wordt dus nooit groen.

Het script heeft zes Pester-tests met een **gemockte** `Invoke-ScriptAnalyzer`: geen meldingen, wel meldingen,
één interne fout en dan een schone run, altijd interne fouten, een andere fout, en de annotaties.

### Valkuil: een mock ziet geen `$script:`-variabelen van de test

Bij het schrijven van die tests faalden er drie. Een mock-body draait op het moment dat het **lintscript**
`Invoke-ScriptAnalyzer` aanroept. Een scriptbestand heeft een eigen *script scope*, dus `$script:x` in de mock
verwijst naar het lintscript, niet naar het testbestand. Een klein experiment toonde wat de mock wel ziet:
gewone variabelen uit `BeforeAll`, `BeforeEach` en `It`. Daarom staan die in de test zonder `$script:`, en is de
teller een hashtable (`$state.Attempt++` wijzigt het gedeelde object; `$teller++` zou een lokale kopie maken).

PSScriptAnalyzer meldt zulke variabelen dan als "assigned but never used", omdat hij niet over scriptblokken
heen kijkt. Dat is de gebruikelijke botsing tussen Pester en de analyzer. Het testbestand onderdrukt die ene
regel met een `SuppressMessageAttribute`, mét verantwoording, en alleen in dat bestand.

### Keuzes in de CI

- **Twee jobs in plaats van één job met twee stappen.** Ze draaien tegelijk (sneller), in GitHub zie je
  meteen *welke* controle faalde, en de Pester-valkuil hierboven kan niet optreden. Het alternatief, één job,
  zou ook werken (elke stap is een eigen proces), maar toont één rood kruis voor twee soorten fouten.
- **Vaste versies** (`-RequiredVersion`) in plaats van "de nieuwste". Op deze laptop installeerde
  `-MinimumVersion 5.0` stilletjes Pester 6. Met een vaste versie draait de CI vandaag en over drie maanden
  exact hetzelfde, en een nieuwe versie kies je bewust.
- **`ubuntu-latest`**: NexusFleet stuurt Linux-hosts aan, en de CI bewijst meteen dat de module ook op Linux
  laadt en slaagt, niet alleen op Windows.
- **`permissions: contents: read`**: de workflow krijgt alleen leesrechten op de repo. Hij hoeft niets te
  schrijven, en zo kan een fout of een kwaadaardige actie ook niets veranderen (minste rechten).
- **Annotaties in plaats van alleen een tabel in het log.** De fout staat dan bij het bestand en de regel,
  ook in een pull request. Dat sluit aan bij het criterium *usability*: duidelijke feedback.
- **Op elke push, ook van feature-branches**, niet alleen op pull requests. Je ziet een fout dan al terwijl
  je aan een branch werkt, niet pas bij het openen van de PR. Het nadeel: bij een open PR draait alles twee
  keer (voor de push en voor de PR). Voor een paar seconden werk is dat geen probleem.

## 5. PowerShell-concepten

- **PSScriptAnalyzer en zijn regels:**
  https://learn.microsoft.com/powershell/utility-modules/psscriptanalyzer/rules/readme
- **Een settings-bestand gebruiken** (`-Settings`, `Severity`, `IncludeDefaultRules`, `Rules`):
  https://learn.microsoft.com/powershell/utility-modules/psscriptanalyzer/using-scriptanalyzer
- **`PSUseConsistentWhitespace`** met de optie `IgnoreAssignmentOperatorInsideHashTable`:
  https://learn.microsoft.com/powershell/utility-modules/psscriptanalyzer/rules/useconsistentwhitespace
- **`PSAlignAssignmentStatement`:**
  https://learn.microsoft.com/powershell/utility-modules/psscriptanalyzer/rules/alignassignmentstatement
- **`PSUseCompatibleSyntax`:**
  https://learn.microsoft.com/powershell/utility-modules/psscriptanalyzer/rules/usecompatiblesyntax
- **`Import-Module -PassThru`:** geeft het module-object terug.
  https://learn.microsoft.com/powershell/module/microsoft.powershell.core/import-module
- **Het module-object (`PSModuleInfo`)** met `ExportedFunctions`, `ExportedCmdlets`, `ExportedVariables` en
  `ExportedAliases`: https://learn.microsoft.com/dotnet/api/system.management.automation.psmoduleinfo
- **`Import-PowerShellDataFile`:** leest een `.psd1` veilig als hashtable, zonder code uit te voeren.
  https://learn.microsoft.com/powershell/module/microsoft.powershell.utility/import-powershelldatafile
- **GitHub Actions workflow-syntax** (`on`, `jobs`, `runs-on`, `steps`, `defaults.run.shell`, `permissions`):
  https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax
- **Workflow commands** (`::error file=...,line=...::`):
  https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-commands
- **Rechten van het workflow-token (`permissions`):**
  https://docs.github.com/en/actions/tutorials/authenticate-with-github_token
- **Pester-configuratie** (`New-PesterConfiguration`, `Run.Exit`, `Filter.ExcludeTag`):
  https://pester.dev/docs/usage/configuration
- **`[System.IO.Path]::GetRelativePath()`:** maakt van een volledig pad een pad relatief aan een map.
  https://learn.microsoft.com/dotnet/api/system.io.path.getrelativepath
- **`-ErrorVariable`** (een common parameter): verzamelt de fouten van één commando in een variabele, zodat je
  ze kunt bekijken in plaats van ze te laten stoppen.
  https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
- **`FullyQualifiedErrorId`:** de vaste code van een fout, handig om op te filteren (in tegenstelling tot de
  boodschap, die kan veranderen). https://learn.microsoft.com/dotnet/api/system.management.automation.errorrecord.fullyqualifiederrorid
- **Scopes** (`$script:`, lokale variabelen, child scopes): waarom een mock geen `$script:`-variabelen van de
  test ziet. https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_scopes
- **`SuppressMessageAttribute`:** één PSScriptAnalyzer-regel onderdrukken voor een bestand of functie, met een
  verantwoording. https://learn.microsoft.com/powershell/utility-modules/psscriptanalyzer/using-scriptanalyzer
- **Pester `Mock` en `Should -Invoke`:** https://pester.dev/docs/usage/mocking

## 6. Zelf proberen

```powershell
# Vanuit de root van de repo, in een nieuwe pwsh-sessie
Import-Module Pester -MinimumVersion 5.0 -MaximumVersion 5.99    # eerst Pester 5 (zie de valkuil)
./tools/Invoke-NexusLint.ps1                                     # niets = schoon
Invoke-Pester -Path ./tests -Output Detailed
```

Zien hoe het faalt:

```powershell
# 1. Een stijlfout: twee spaties inspringen en een alias
Set-Content ./src/utils/Stijl.ps1 "function Get-NexusTest {`n  gci`n}"
Invoke-ScriptAnalyzer -Path ./src/utils/Stijl.ps1 -Settings ./PSScriptAnalyzerSettings.psd1
Remove-Item ./src/utils/Stijl.ps1

# 2. Een functie in de manifest die niet bestaat: de import slaagt, de exporttest faalt
#    Zet in NexusFleet.psd1 tijdelijk: FunctionsToExport = @('Get-NexusFake')
Import-Module ./NexusFleet.psd1 -Force        # geen fout!
Invoke-Pester -Path ./tests -FullNameFilter 'NexusFleet module*' -Output Detailed
#    Zet de manifest daarna terug op @().

# 3. De valkuil: analyzer eerst, dan Pester 5 (in een nieuwe sessie)
Invoke-ScriptAnalyzer -Path ./tests -Settings ./PSScriptAnalyzerSettings.psd1
Import-Module Pester -MinimumVersion 5.0 -MaximumVersion 5.99   # faalt
```

De CI bekijken:

```bash
gh run list --limit 5                 # de laatste runs en hun status
gh run view --log-failed              # alleen het log van wat faalde, van de laatste run
```

Of op GitHub: tabblad **Actions** van de repository.

## 7. Controlevragen

1. Wat is het verschil tussen wat PSScriptAnalyzer controleert en wat een Pester-test controleert?
2. Waarom staat `Severity` ook op `Information`, en wat zou je missen als alleen `Error` telde?
3. Welke twee regels botsten, en waarom heb je de optie gekozen in plaats van een van de regels uit te zetten?
4. Waarom is de exporttest nodig, als `Import-Module` toch zou falen bij een fout in de manifest?
5. Leg uit waarom Pester 5 niet meer kan laden nadat PSScriptAnalyzer de testbestanden heeft geanalyseerd.
6. Hoe weet GitHub dat de Pester-job rood moet worden als er een test faalt?
7. Waarom installeert de CI een vaste versie van Pester en PSScriptAnalyzer, en niet gewoon de nieuwste?
8. Waarom staat `PSUseCorrectCasing` uit, en hoe is bewezen dat dat de oorzaak was?
9. Waarom probeert het lintscript alleen `RULE_ERROR`-fouten opnieuw, en niet de meldingen over je code?
10. Waarom ziet een mock-body geen `$script:`-variabelen van het testbestand, en waarom is de teller een hashtable?
11. Hoe vindt `tests/Quality.Tests.ps1` een config-sleutel waarvoor geen controleregel bestaat?
12. Waarom is "de cmdlet heeft help" niet genoeg, en wat controleert de helptest nog meer?
