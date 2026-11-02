# Kwaliteitscontrole

> Uitleg gegenereerd met Claude Code als studiemateriaal. Niet mijn leerlogboek.

_Stand: unit 3 (PSScriptAnalyzer-instellingen en exporttest, #3). De CI-workflow komt erbij in #5._

## 1. Wat het doet

Twee automatische controles bewaken de kwaliteit van de code. **PSScriptAnalyzer** leest de scripts zonder
ze uit te voeren en meldt alles wat tegen de afgesproken regels ingaat: stijl, foutgevoelige constructies,
verboden werkwoorden. Een **Pester-test** controleert dat de module precies de functies aanbiedt die in de
manifest staan, niet meer en niet minder.

## 2. Waar het staat

| Pad | Inhoud |
|---|---|
| `PSScriptAnalyzerSettings.psd1` | De regels voor PSScriptAnalyzer |
| `tests/NexusFleet.Tests.ps1`, blok `Describe 'NexusFleet module'` | De import- en exporttests |

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
   - commando's met hun echte hoofdletters (`PSUseCorrectCasing`),
   - geen syntax die PowerShell 7.2 niet kent (`PSUseCompatibleSyntax`).

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
`pwsh`-processen. De CI (#5) doet het tweede.

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

## 6. Zelf proberen

```powershell
# Vanuit de root van de repo, in een nieuwe pwsh-sessie
Import-Module Pester -MinimumVersion 5.0 -MaximumVersion 5.99    # eerst Pester 5 (zie de valkuil)
Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1   # niets = schoon
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

## 7. Controlevragen

1. Wat is het verschil tussen wat PSScriptAnalyzer controleert en wat een Pester-test controleert?
2. Waarom staat `Severity` ook op `Information`, en wat zou je missen als alleen `Error` telde?
3. Welke twee regels botsten, en waarom heb je de optie gekozen in plaats van een van de regels uit te zetten?
4. Waarom is de exporttest nodig, als `Import-Module` toch zou falen bij een fout in de manifest?
5. Leg uit waarom Pester 5 niet meer kan laden nadat PSScriptAnalyzer de testbestanden heeft geanalyseerd.
