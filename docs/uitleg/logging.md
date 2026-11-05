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
| `src/utils/Add-NexusLogSecret.ps1` | Voegt een geheim toe dat pas tijdens de run ontstaat (een link-token), met een slot |
| `tests/utils/Add-NexusLogSecret.Tests.ps1` | 3 tests, waaronder 40 runspaces tegelijk |
| `tests/utils/Initialize-NexusRunContext.Tests.ps1` | 5 tests |
| `tests/utils/Write-NexusLog.Tests.ps1` | 11 tests, waaronder redactie en een test vanuit `-Parallel` |

Beide functies zijn **intern**: ze staan niet in `FunctionsToExport`. De gebruiker roept ze nooit zelf aan; de
publieke cmdlets doen dat.

## 3. Hoe het werkt

**1. Een run begint.** Een cmdlet roept één keer `Initialize-NexusRunContext` aan, met de twee loginstellingen uit de
configuratie en de geheimen van de run:

```powershell
$run = Initialize-NexusRunContext -LogRoot $config.Log.Directory -KeepRuns $config.Log.KeepRuns -Secret $apiToken
```

De functie:

1. kiest de logmap: `Log.Directory`, of `logs/` in de huidige map als die instelling leeg is (`''`);
2. maakt een RunId zoals `20261102T153012Z-a1b2c3` (tijd in UTC, plus zes willekeurige tekens) en de map
   `<logmap>/<RunId>/`;
3. ruimt oude runs op: alleen mappen met een naam die op een RunId lijkt, worden bekeken. Gesorteerd op naam (de naam
   begint met de tijd, dus dat is ook op leeftijd), en alles na de nieuwste `KeepRuns` wordt verwijderd. Bij `0`, of
   bij een dry run (`-WhatIf`), wordt niets verwijderd. Lukt verwijderen niet, dan komt er een waarschuwing;
4. geeft een object terug:

```powershell
[pscustomobject]@{
    PSTypeName   = 'NexusFleet.RunContext'
    RunId        = $runId
    LogDirectory = $logDirectory
    Secrets      = @($Secret | Where-Object { -not [string]::IsNullOrEmpty($_) } | Sort-Object -Property Length -Descending)
}
```

`Install-NexusNode` geeft ook het wachtwoord uit de broker-URL mee als apart geheim (`Get-NexusUrlPassword`).

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
2. Elk bekend geheim wordt `***`, het langste eerst, en alles wat op een NexusInfra-token lijkt (`nxi_` +
   base64url) wordt `nxi_***`, ook als niemand het als geheim opgaf.
3. De regel wordt opgebouwd met de `-f`-operator: `{1,-7}` betekent "het tweede argument, links uitgelijnd, 7
   tekens breed", zodat de kolommen netjes onder elkaar staan.
4. De bestandsnaam is de hostnaam. Tekens die Windows niet toelaat in een bestandsnaam (zoals `:` in een
   IPv6-adres) worden `_`. Zonder host gaat de regel naar `run.log`.
5. `Add-Content ... -WhatIf:$false -ErrorAction Stop` voegt de regel toe, in een `try`. Mislukt dat (een bestand dat
   vergrendeld is, een volle schijf), dan wordt het een waarschuwing en gaat de run verder. `Write-Verbose` toont de
   regel ook live bij `-Verbose`.

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
- **Logs standaard in `./logs` van de huidige map, en instelbaar.** Een geïnstalleerde module staat soms in een map
  waar je niet mag schrijven (`Program Files`), dus de module-map is geen goede plek. De werkmap wel, maar wie vanuit
  verschillende mappen werkt, krijgt zo verspreide logs: daarvoor is `Log.Directory`. `./logs` staat in `.gitignore`.
- **Een logfout laat het werk nooit mislukken.** Zonder de `try` zou een vergrendeld logbestand onder
  `-ErrorAction Stop` een fout gooien. De `catch` van de server zou die server dan als mislukt melden, terwijl hij wel
  geïnstalleerd is. Een waarschuwing vertelt het probleem zonder het resultaat te vervalsen.
- **Oude runs opruimen, maar voorzichtig.** Zonder opruimen groeit `logs/` bij elke run. Alleen mappen met de vorm
  van een RunId worden verwijderd, zodat iets anders in die map (je eigen notities) nooit verdwijnt. Een dry run
  verwijdert niets: `-WhatIf` belooft dat er niets verandert, behalve het eigen log.
- **Het langste geheim eerst.** Het broker-wachtwoord zit ín de broker-URL. Wordt eerst het wachtwoord vervangen, dan
  herkent niemand de URL nog en blijven de gebruiker en het brokeradres in het log staan
  (`amqp://fleet:***@broker:5672`). Met de langste eerst wordt de hele URL `***`.
- **Het broker-wachtwoord apart.** Een foutmelding van een programma kan alleen het wachtwoord tonen, zonder de rest
  van de URL. Daarom is het ook een geheim op zich.
- **Een geheim dat pas tijdens de run ontstaat, met een slot (#115).** Het link-token van een outbound node maakt
  NexusInfra pas in de stap AgentContainer. Alle hosts van een run delen dezelfde run-context, ook in parallelle
  runspaces: `$using:` geeft hetzelfde object door, geen kopie. "Lijst lezen, token erbij, lijst terugschrijven" is
  dan een race: twee hosts lezen tegelijk dezelfde lijst, en wie als laatste schrijft, wist het token van de ander.
  De test met 40 runspaces verloor zonder slot 16 tokens. `Add-NexusLogSecret` doet het daarom onder
  `[System.Threading.Monitor]::Enter($Context)`: één runspace tegelijk. De nieuwe lijst vervangt de oude in één
  toewijzing, zodat `Write-NexusLog` altijd een hele lijst ziet. Verworpen: een `ConcurrentBag`, want die houdt
  geen volgorde bij, en "langste eerst" is nodig.

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
- **`try` / `catch` en `-ErrorAction Stop`** (een niet-fatale fout opvangen):
  https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_try_catch_finally
- **`Select-Object -Skip`** en **`Sort-Object -Descending`** (alles na de nieuwste N):
  https://learn.microsoft.com/powershell/module/microsoft.powershell.utility/select-object
- **`[uri]::TryCreate` en `UserInfo`** (een URL ontleden zonder fout):
  https://learn.microsoft.com/dotnet/api/system.uri.trycreate
- **Pester `TestDrive` en `Should -Match`:** https://pester.dev/docs/usage/testdrive
- **`[System.Threading.Monitor]`** (een slot: `Enter` wacht tot niemand anders het heeft, `Exit` in een `finally`
  geeft het altijd terug): https://learn.microsoft.com/dotnet/api/system.threading.monitor

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
# Een logbestand dat niet te schrijven is (hier: een map met die naam) geeft een waarschuwing, geen fout
$null = New-Item -ItemType Directory -Path (Join-Path $context.LogDirectory 'web02.log')
Write-NexusLog -Context $context -HostName 'web02' -Message 'gaat niet' -ErrorAction Stop   # WARNING: ... could not write

# Alleen de nieuwste 2 runs houden (de nieuwe inbegrepen)
1..4 | ForEach-Object { $null = Initialize-NexusRunContext -LogRoot "$env:TEMP/nexuslogs" }
$null = Initialize-NexusRunContext -LogRoot "$env:TEMP/nexuslogs" -KeepRuns 2
(Get-ChildItem "$env:TEMP/nexuslogs" -Directory).Count                                  # 2

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
6. Waarom verwijdert `Initialize-NexusRunContext` alleen mappen waarvan de naam op een RunId lijkt?
7. Wat zou er in het log staan als de geheimen in de volgorde "kortste eerst" vervangen werden, met het
   broker-wachtwoord en de broker-URL als geheimen?
8. Waarom staat `Monitor.Exit` in een `finally`, en wat gebeurt er met de andere hosts als dat niet zo was en het
   toevoegen een fout gaf?
