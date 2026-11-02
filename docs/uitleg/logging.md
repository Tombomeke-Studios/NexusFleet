# Logging

> Uitleg gegenereerd met Claude Code als studiemateriaal. Niet mijn leerlogboek.

_Stand: `Initialize-NexusRunContext` en `Write-NexusLog` (#23)._

## 1. Wat het doet

Elke uitvoering van een NexusFleet-cmdlet krijgt een eigen RunId en een eigen logmap. Elke gebeurtenis wordt één
leesbare regel: wanneer, hoe erg, welke run, welke host, welke stap, en wat er gebeurde. Geheimen zoals het
API-token worden eruit gehaald voordat de regel geschreven wordt. Zo kun je achteraf nagaan wat er per host
gebeurde, zonder dat er een geheim in een bestand belandt.

## 2. Waar het staat

| Pad | Inhoud |
|---|---|
| `src/utils/Initialize-NexusRunContext.ps1` | Maakt de run-context: RunId, logmap, geheimen |
| `src/utils/Write-NexusLog.ps1` | Schrijft één logregel, met redactie |
| `tests/utils/Initialize-NexusRunContext.Tests.ps1` | 5 tests |
| `tests/utils/Write-NexusLog.Tests.ps1` | 11 tests, waaronder redactie en een test vanuit `-Parallel` |

Beide functies zijn **intern**: ze staan niet in `FunctionsToExport`. De gebruiker roept ze nooit zelf aan; de
publieke cmdlets doen dat.

## 3. Hoe het werkt

**1. Een run begint.** Een cmdlet roept één keer `Initialize-NexusRunContext` aan, met het API-token als geheim:

```powershell
$context = Initialize-NexusRunContext -Secret $apiToken
```

De functie maakt een RunId zoals `20261102T153012Z-a1b2c3` (tijd in UTC, plus zes willekeurige tekens), maakt de
map `logs/<RunId>/` aan, en geeft een object terug:

```powershell
[pscustomobject]@{
    PSTypeName   = 'NexusFleet.RunContext'
    RunId        = $runId
    LogDirectory = $logDirectory
    Secrets      = @($Secret | Where-Object { -not [string]::IsNullOrEmpty($_) })
}
```

**2. Een gebeurtenis loggen:**

```powershell
Write-NexusLog -Context $context -HostName 'web01' -Step 'agent' -Message 'Container started'
```

geeft in `logs/<RunId>/web01.log`:

```text
2026-11-02T15:30:12.345Z INFO    run=20261102T153012Z-a1b2c3 host=web01 step=agent Container started
```

Wat `Write-NexusLog` stap voor stap doet:

1. Regeleinden in het bericht worden ` | `, zodat één gebeurtenis één regel blijft.
2. Elk bekend geheim wordt `***`, en alles wat op een NexusInfra-token lijkt (`nxi_` + base64url) wordt
   `nxi_***`, ook als niemand het als geheim opgaf.
3. De regel wordt opgebouwd met de `-f`-operator: `{1,-7}` betekent "het tweede argument, links uitgelijnd, 7
   tekens breed", zodat de kolommen netjes onder elkaar staan.
4. De bestandsnaam is de hostnaam. Tekens die Windows niet toelaat in een bestandsnaam (zoals `:` in een
   IPv6-adres) worden `_`. Zonder host gaat de regel naar `run.log`.
5. `Add-Content ... -WhatIf:$false` voegt de regel toe, en `Write-Verbose` toont hem ook live bij `-Verbose`.

**3. Vanuit `-Parallel`.** De context is een gewoon object, dus hij gaat met `$using:` een runspace in. Omdat
`Write-NexusLog` intern is, kan een runspace hem na `Import-Module` niet rechtstreeks aanroepen. Een scriptblok
uitvoeren *in de scope van de module* kan wel:

```powershell
$module = Import-Module -Name $using:manifest -PassThru -Force
& $module { param($Context, $HostName) Write-NexusLog -Context $Context -HostName $HostName -Message '...' } $using:context $_
```

## 4. Waarom zo

- **Eén bestand per host in plaats van één gedeeld bestand.** Hosts worden parallel behandeld. Als tien
  runspaces tegelijk naar hetzelfde bestand schrijven, kan dat botsen ("file in use") of kunnen regels door
  elkaar raken. Een host wordt door één runspace behandeld, dus met een bestand per host schrijven er nooit
  twee tegelijk naar hetzelfde bestand. Het alternatief, één bestand met een lock (een *mutex*), is ingewikkelder
  en trager. Het voorstel vraagt bovendien een logbestand "per host en per stap".
- **Een context-object in plaats van modulevariabelen.** Een modulevariabele (`$script:RunId`) bestaat niet in
  een `-Parallel`-runspace: daar wordt de module opnieuw ingeladen. Een object dat je meegeeft, werkt overal.
- **`[PSTypeName('NexusFleet.RunContext')]`** op de parameter: PowerShell weigert dan elk object dat geen
  run-context is. Een vergissing valt meteen op, niet pas als een eigenschap leeg blijkt.
- **Redactie met een lijst én een patroon.** De lijst vangt geheimen die de cmdlet kent (het token, later het
  `INTERNAL_API_TOKEN`). Het patroon is een vangnet voor een token dat ergens in een foutmelding opduikt zonder
  dat iemand het registreerde.
- **Lege geheimen weggooien.** `'abc'.Replace('', '***')` geeft een fout, en een leeg patroon zou op elke positie
  passen. Dat geval wordt dus vooraf weggefilterd.
- **`-WhatIf:$false`.** Bij `Install-NexusNode -WhatIf` zet PowerShell `$WhatIfPreference` op `$true`, en dat erven
  alle commando's eronder, ook `New-Item` en `Add-Content`. Zonder `-WhatIf:$false` zou een dry run dus geen log
  schrijven, terwijl het voorstel zegt dat een dry run ook gelogd wordt. Twee tests bewijzen dat.
- **Tijd in UTC met milliseconden.** Hosts en de controlemachine kunnen in verschillende tijdzones zitten; UTC
  is overal hetzelfde, en milliseconden tonen de volgorde van snelle stappen.
- **Logs in `./logs` van de huidige map.** Een geïnstalleerde module staat soms in een map waar je niet mag
  schrijven (`Program Files`); de werkmap van de beheerder is een betere plek. De map staat in `.gitignore`.

## 5. PowerShell-concepten

- **De `-f`-formatteeroperator** (`{0}`, `{1,-7}`):
  https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_operators#format-operator--f
- **`-replace` met reguliere expressies:**
  https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_comparison_operators#replacement-operator
- **`[PSTypeName()]`-attribuut en `PSTypeName` in een `[pscustomobject]`:**
  https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_functions_advanced_parameters#pstypename-attribute
- **`$WhatIfPreference` en `-WhatIf:$false`:**
  https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_preference_variables#whatifpreference
- **Een scriptblok in de scope van een module uitvoeren** (`& $module { }`, de call operator met een
  `PSModuleInfo`): https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_operators#call-operator-
- **`Add-Content`:** https://learn.microsoft.com/powershell/module/microsoft.powershell.management/add-content
- **Pester `TestDrive` en `Should -Match`:** https://pester.dev/docs/usage/testdrive

## 6. Zelf proberen

```powershell
# Vanuit de root van de repo. De functies zijn intern, dus we laden de bestanden rechtstreeks.
. ./src/utils/Initialize-NexusRunContext.ps1
. ./src/utils/Write-NexusLog.ps1

$context = Initialize-NexusRunContext -LogRoot "$env:TEMP/nexuslogs" -Secret 'mijn-geheim'
Write-NexusLog -Context $context -HostName 'web01' -Step 'agent' -Message 'Token mijn-geheim verstuurd' -Verbose
Write-NexusLog -Context $context -Level Error -Message "Fout:`nBearer nxi_abcDEF123"
Get-ChildItem $context.LogDirectory
Get-Content (Join-Path $context.LogDirectory 'web01.log')   # ... Token *** verstuurd
Get-Content (Join-Path $context.LogDirectory 'run.log')     # ... Fout: | Bearer nxi_***

# De tests
Import-Module Pester -MinimumVersion 5.0 -MaximumVersion 5.99
Invoke-Pester -Path ./tests/utils -Output Detailed
```

Zien hoe het faalt:

```powershell
# Een object dat geen run-context is, wordt geweigerd
Write-NexusLog -Context ([pscustomobject]@{ RunId = 'x' }) -Message 'm'

# Zonder -WhatIf:$false zou dit niets schrijven: probeer het effect van $WhatIfPreference
$WhatIfPreference = $true
Add-Content -Path "$env:TEMP/proef.txt" -Value 'test'           # "What if: ..." en er gebeurt niets
Add-Content -Path "$env:TEMP/proef.txt" -Value 'test' -WhatIf:$false
$WhatIfPreference = $false
```

## 7. Controlevragen

1. Waarom krijgt elke host een eigen logbestand in plaats van één bestand voor de hele run?
2. Waarom is de run-context een object dat je meegeeft, en geen modulevariabele?
3. Wat zou er gebeuren bij `Install-NexusNode -WhatIf` als `Add-Content` geen `-WhatIf:$false` had?
4. Welke twee manieren van redactie zijn er, en waarom allebei?
5. Hoe roep je een interne modulefunctie aan vanuit een `-Parallel`-runspace?
