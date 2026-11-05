# Stappen en rollback

> Uitleg gegenereerd met Claude Code als studiemateriaal. Niet mijn leerlogboek.

_Stand: het stappencontract en de step runner (#27). De vier echte stappen en hoe `Install-NexusNode` ze gebruikt:
zie `installatie.md`._

## 1. Wat het doet

Een server een node maken bestaat uit een paar stappen na elkaar. Elke stap kan drie dingen: **controleren** of
hij al gedaan is, hem **uitvoeren**, en hem **terugdraaien**. De step runner werkt de stappen voor één server
af. Is een stap al in orde, dan slaat hij die over; daardoor verandert een tweede run niets. Mislukt een stap,
dan draait hij terug wat hij zelf gedaan heeft, zodat er geen half geïnstalleerde server achterblijft.

## 2. Waar het staat

| Pad | Inhoud |
|---|---|
| `src/core/Register-NexusStep.ps1` | Het stappencontract en het register (`$script:NexusStepRegistry`) |
| `src/core/Get-NexusStep.ps1` | De geregistreerde stappen, gesorteerd op `Order` |
| `src/core/Invoke-NexusStepSequence.ps1` | De runner: Test → Apply, rollback bij een fout, `-PlanOnly` voor de dry run |
| `src/steps/` | Hier komt per stap één bestand (fase 3) |
| `tests/core/Register-NexusStep.Tests.ps1`, `Invoke-NexusStepSequence.Tests.ps1` | 6 + 11 tests met nep-stappen |

## 3. Hoe het werkt

**1. Een stap registreert zichzelf.** Later staat in `src/steps/` bijvoorbeeld een bestand `Docker.ps1` met:

```powershell
Register-NexusStep -Name 'Docker' -Order 10 -Description 'Install Docker Engine' `
    -Test     { param($Context) <# is Docker er al? $true of $false #> } `
    -Apply    { param($Context) <# installeer Docker #> } `
    -Rollback { param($Context) <# verwijder wat Apply installeerde #> }
```

De loader laadt eerst `src/core` (dus `Register-NexusStep` bestaat al) en daarna `src/steps`. Elke stap komt zo
in het register. `Register-NexusStep` weigert een tweede stap met dezelfde naam of dezelfde `Order`, zodat de
volgorde nooit dubbelzinnig is.

**2. De runner werkt de stappen af** voor één host:

```powershell
$result = Invoke-NexusStepSequence -HostName 'web01' -Step (Get-NexusStep) -Context $stepContext -RunContext $run
```

Per stap, op volgorde van `Order`:

1. `& $current.Test $Context`. Het antwoord moet `$true` of `$false` zijn; iets anders is een fout (zo valt een
   slordige Test meteen op).
2. `$true`: **AlreadyDone**, door naar de volgende stap.
3. `$false` en `-PlanOnly`: **WouldApply** (dry run), door naar de volgende stap.
4. `$false`: `& $current.Apply $Context` → **Applied**.
5. Gooit Test of Apply een fout: **Failed**, en de lus stopt (`break`). De stappen erna blijven **NotRun**.

**3. Terugdraaien.** Na een fout loopt een tweede lus **achteruit** vanaf de mislukte stap:

```powershell
$wasTouched = ($i -eq $failedIndex -and $failedPhase -eq 'Apply') -or $outcomes[$i].Outcome -eq 'Applied'
```

Alleen stappen die deze run zelf aanraakte, worden teruggedraaid: elke **Applied**-stap, en de mislukte stap als
zijn Apply al begonnen was (die kan half gelukt zijn). Een **AlreadyDone**-stap blijft staan. Faalt een rollback,
dan wordt dat genoteerd (`Rollback = 'Failed'`) en gaan de andere rollbacks gewoon door. Faalt de rollback van de
mislukte stap zelf, dan komt de fout van de rollback **achter** die van de Apply (`Apply ... failed: ...; Rollback
... failed: ...`), en niet in de plaats ervan: anders zou je niet meer zien waarom de stap mislukte (#118).

**4. Het resultaat** is één object per host:

```text
Host     : web01
Success  : False
PlanOnly : False
Step     : c                                   (de stap die faalde)
Error    : Apply of step 'c' failed: ...
Steps    : a AlreadyDone · b Applied (Rollback Done) · c Failed (Rollback Done) · d NotRun
```

Met `-RunContext` schrijft de runner elke uitkomst ook naar het logbestand van die host (`Write-NexusLog`).

## 4. Waarom zo

- **Test vóór Apply maakt het idempotent.** Het voorstel vraagt dat "een tweede uitvoering niets wijzigt" (Klaar
  als, punt 2). Elke stap kijkt eerst of hij nodig is; bij de tweede run zegt elke Test `$true` en gebeurt er
  niets. Dat is getest: alle stappen AlreadyDone, geen enkele Apply.
- **Alleen terugdraaien wat deze run deed.** Als Docker al op de server stond voordat NexusFleet kwam, mag een
  mislukte agent-stap Docker niet verwijderen: andere software kan het gebruiken.
- **Achteruit terugdraaien.** De agent-container hangt af van Docker. Eerst de container weg, dan Docker; andersom
  kan niet.
- **Doorgaan als één rollback faalt.** Anders blijft er nog meer half-geïnstalleerd achter. De fout wordt wel
  gemeld, zodat de beheerder weet wat hij moet nakijken.
- **Zelfregistratie in plaats van een lijst in de code.** Een stap toevoegen, vervangen of weglaten is een bestand
  toevoegen, vervangen of verwijderen (criterium *uitbreidbaarheid*, en zo beloofd in het voorstel). Er is geen
  centrale lijst die je moet bijwerken en kunt vergeten.
- **Een unieke `Order` met gaten (10, 20, 30).** Zo kun je later een stap "15" ertussen zetten (bijvoorbeeld een
  firewall-stap voor de beveiligde verbinding), zonder de andere te hernummeren.
- **`-PlanOnly` in plaats van `ShouldProcess`.** De runner draait straks in `ForEach-Object -Parallel`, en daar is
  `$PSCmdlet.ShouldProcess` niet beschikbaar (CLAUDE.md, sectie 8). De publieke cmdlet heeft `-WhatIf` en zet dat
  om naar `-PlanOnly`. Beperking: in een dry run draaien alleen de Tests. Een Test die afhangt van een eerdere stap
  (de agent-test heeft Docker nodig), meldt dan gewoon "WouldApply".
- **De uitvoer van een stap wordt weggegooid** (`$null = & $current.Apply $Context`). Een Apply die tekst uitvoert,
  zou anders naast het resultaatobject in de uitvoer van de runner belanden, en een aanroeper krijgt dan een mengeling
  terug. Stappen melden wat ze doen via de logging. Gevonden met het voorbeeld in "Zelf proberen" en eerst met een
  test vastgelegd.
- **Een context-object voor alle stappen.** Elke stap krijgt hetzelfde object met de host, de configuratie en de
  transportinstellingen. Zo hoeft geen stap zelf iets op te zoeken, en kan een test een nep-context meegeven.

## 5. PowerShell-concepten

- **Scriptblokken als waarde** (`-Test { ... }`, opslaan in een object, later uitvoeren met `&`):
  https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_script_blocks
- **`$script:`-scope** (het register leeft in de scope van de module):
  https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_scopes
- **`try` / `catch` / `break` / `continue` in een lus:**
  https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_try_catch_finally ·
  https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_break
- **`GetNewClosure()`** (in de tests: een scriptblok dat de waarden van dat moment onthoudt):
  https://learn.microsoft.com/dotnet/api/system.management.automation.scriptblock.getnewclosure
- **`[PSTypeName('NexusFleet.Step')]`:** alleen echte stappen worden aanvaard.
  https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_functions_advanced_parameters#pstypename-attribute

## 6. Zelf proberen

```powershell
. ./src/core/Register-NexusStep.ps1
. ./src/core/Get-NexusStep.ps1
. ./src/core/Invoke-NexusStepSequence.ps1

# Drie nep-stappen; "web" faalt
Register-NexusStep -Name 'Docker' -Order 10 -Test { $true } -Apply { 'docker' }
Register-NexusStep -Name 'Agent' -Order 20 -Test { $false } -Apply { Write-Host 'agent geplaatst' } -Rollback { Write-Host 'agent weg' }
Register-NexusStep -Name 'Web' -Order 30 -Test { $false } -Apply { throw 'poort bezet' } -Rollback { Write-Host 'web opgeruimd' }

Get-NexusStep | Format-Table Order, Name
$r = Invoke-NexusStepSequence -HostName 'web01' -Step (Get-NexusStep) -Context @{}
$r | Format-List Host, Success, Step, Error
$r.Steps | Format-Table

# Dry run: alleen de Tests
(Invoke-NexusStepSequence -HostName 'web01' -Step (Get-NexusStep) -Context @{} -PlanOnly).Steps | Format-Table

# Tests
Import-Module Pester -MinimumVersion 5.0 -MaximumVersion 5.99
Invoke-Pester -Path ./tests/core -Output Detailed
```

Zien hoe het faalt:

```powershell
Register-NexusStep -Name 'Docker' -Order 15 -Test { $true } -Apply { }      # naam bestaat al
Register-NexusStep -Name 'Firewall' -Order 20 -Test { $true } -Apply { }    # Order 20 is van Agent
```

## 7. Controlevragen

1. Hoe zorgt de runner ervoor dat een tweede uitvoering niets wijzigt?
2. Welke stappen worden teruggedraaid als stap 3 van 4 faalt, in welke volgorde, en waarom niet stap 1 als die al
   in orde was?
3. Waarom draait de runner ook de mislukte stap zelf terug, maar alleen als zijn Apply al begonnen was?
4. Waarom gebruikt de runner `-PlanOnly` en niet `ShouldProcess`, en welke beperking heeft de dry run daardoor?
5. Wat moet je doen om een nieuwe installatiestap toe te voegen, en welke bestanden raak je daarvoor níet aan?
