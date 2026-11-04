# Gedeelde hulpfuncties

> Uitleg gegenereerd met Claude Code als studiemateriaal. Niet mijn leerlogboek.

## 1. Wat het doet

Vier stukjes code stonden twee of drie keer bijna letterlijk in de module. Nu staan ze elk één keer in een eigen
functie, en roepen de andere functies die op. Wat de module doet, verandert niet. Op één punt is ze wel sterker
geworden: een server waarvan de parallelle runspace de module niet kan laden, krijgt nu toch een resultaat.

## 2. Waar het staat

| Functie | Bestand | Wordt gebruikt door |
|---|---|---|
| `Get-NexusSshParameter` | `src/utils/Get-NexusSshParameter.ps1` | `Invoke-NexusHostPreflight`, `Invoke-NexusHostInstall`, `Get-NexusHostStatus` |
| `Get-NexusApiParameter` | `src/utils/Get-NexusApiParameter.ps1` | `Invoke-NexusHostInstall`, `Get-NexusFleetStatus` |
| `ConvertFrom-NexusFactLine` | `src/utils/ConvertFrom-NexusFactLine.ps1` | `Invoke-NexusHostPreflight`, `Get-NexusHostStatus` |
| `Invoke-NexusHostLoop` | `src/utils/Invoke-NexusHostLoop.ps1` | `Test-NexusHost`, `Install-NexusNode`, `Get-NexusFleetStatus` |
| `ConvertTo-NexusHostStatusFailure` | `src/core/ConvertTo-NexusHostStatusFailure.ps1` | `Get-NexusFleetStatus` (via de lus) |

De tests staan op dezelfde plaats onder `tests/` (bijvoorbeeld `tests/utils/Invoke-NexusHostLoop.Tests.ps1`).

## 3. Hoe het werkt

### De drie kleine helpers

**`Get-NexusSshParameter`** bouwt de hashtable waarmee je `Invoke-NexusHostCommand` oproept. Adres, poort en gebruiker
komen uit de inventaris, de time-out uit de configuratie. De sleutel en het `known_hosts`-bestand worden alleen
toegevoegd als ze ingevuld zijn; anders gebruikt `ssh` zijn eigen standaard.

```powershell
$ssh = Get-NexusSshParameter -HostInfo $HostInfo -Config $Config
$answer = Invoke-NexusHostCommand @ssh -Command 'uptime'
```

**`Get-NexusApiParameter`** doet hetzelfde voor `Invoke-NexusApi`: het neemt de vijf verbindingsinstellingen uit de
sessie van `Connect-NexusInfra` (adres, token, time-out, herhalingen, http-toelating).

**`ConvertFrom-NexusFactLine`** leest het antwoord van een server die `sleutel=waarde`-regels afdrukt:

```powershell
foreach ($line in $Text -split "`n") {
    $key, $value = $line -split '=', 2
    if ($key.Trim()) {
        $facts[$key.Trim()] = "$value".Trim()
    }
}
```

`-split '=', 2` splitst op het **eerste** `=`; de rest blijft samen, zodat een waarde zelf een `=` mag bevatten.
`Trim()` haalt spaties en de `\r` van Windows-regeleinden weg.

### De gedeelde lus: `Invoke-NexusHostLoop`

De drie cmdlets doen hetzelfde: een functie draaien voor elke server, meerdere tegelijk, met een voortgangsbalk, en
nooit stoppen door één server. De lus krijgt:

- `-InputObject`: per server een hashtable met de parameters van die server (minstens `HostInfo`; bij de installatie
  ook `PlanOnly`);
- `-Parameter`: wat voor elke server hetzelfde is (config, run-context, sessie, ...);
- `-FunctionName`: de functie per server, bijvoorbeeld `Invoke-NexusHostPreflight`;
- `-FailureFunction`: maakt het resultaat van een server waarbij iets misging, bijvoorbeeld
  `ConvertTo-NexusPreflightFailure`;
- `-ThrottleLimit` en `-Activity` (de titel van de voortgangsbalk).

Zo roept `Test-NexusHost` hem op:

```powershell
$loop = @{
    InputObject     = @($hosts | ForEach-Object { @{ HostInfo = $_ } })
    FunctionName    = 'Invoke-NexusHostPreflight'
    Parameter       = @{ Config = $config; RunContext = $run }
    FailureFunction = 'ConvertTo-NexusPreflightFailure'
    ThrottleLimit   = $ThrottleLimit
    Activity        = 'NexusFleet preflight'
}
$results = @(Invoke-NexusHostLoop @loop)
```

Binnen de lus, in deze volgorde:

1. **Per server de parameters samenvoegen:** `$Parameter + $item` maakt één nieuwe hashtable.
2. **De functie oproepen**, op een van twee manieren:
   - `-ThrottleLimit 1`: een gewone `foreach` in de eigen runspace. Daar werken de mocks van Pester (E3).
   - anders: `ForEach-Object -Parallel`. Elke runspace begint leeg, dus de module wordt er ingeladen, en de interne
     functie draait in de scope van de module:

     ```powershell
     $module = Import-Module -Name $using:manifest -PassThru -ErrorAction Stop
     $splat = $using:Parameter + $item
     & $module { param($Name, $Splat) & $Name @Splat } $using:FunctionName $splat
     ```
3. **Een fout wordt een merkteken.** Rond de oproep (en rond `Import-Module`) staat een `try`. Gaat er iets mis, dan
   geeft de runspace geen resultaat terug maar een klein object van het type `NexusFleet.HostLoopFailure`, met de
   parameters van de server en de foutmelding.
4. **Terug in de eigen runspace** gaat elk antwoord door een tweede `ForEach-Object`. Die werkt de voortgangsbalk bij
   en vervangt elk merkteken door een echt resultaat van `-FailureFunction`. Die functie krijgt alleen de parameters
   die ze zelf kent (`HostInfo`, en bij de installatie ook `PlanOnly`) en `-Message`.

De twee oproepmanieren staan samen in `& { ... }`, en dat blok wordt meteen doorgegeven met `|`. Daardoor bereikt
elk antwoord de voortgangsbalk zodra die server klaar is, ook terwijl de andere servers nog bezig zijn.

## 4. Waarom zo

- **Eén plaats per regel.** Als er een ssh-instelling bijkomt, of de voortgangsbalk anders moet, verander je één
  functie in plaats van drie. Met drie kopieën vergeet je er vroeg of laat één.
- **Waarom het merkteken, en niet meteen de failure-functie in de runspace?** Als `Import-Module` in de runspace
  mislukt, bestaat de failure-functie daar niet. Vroeger kreeg die server dan géén resultaat. De eigen runspace heeft
  de module altijd, dus daar wordt het merkteken omgezet.
- **De functienaam als tekst, geen scriptblok.** Een scriptblok mag niet via `$using:` naar een runspace (PowerShell
  weigert dat). Een naam wel; de runspace zoekt de functie dan op in de module die hij net inlaadde.
- **Alleen de parameters die de failure-functie kent.** De server-hashtable kan sleutels hebben die de failure-functie
  niet heeft. `& $FailureFunction @failed` met een onbekende sleutel zou zelf weer een fout geven.
- **Afgewezen:** één grote functie met een `switch` op de cmdlet ("als preflight dan ..., als installatie dan ...").
  Dan moet de lus elke cmdlet kennen, en verandert hij voor elke nieuwe cmdlet. Nu weet hij van geen enkele.
- **Gedrag blijft gelijk**, op één tekst na: de voortgangsbalk zegt nu overal "N of M hosts done".

## 5. PowerShell-concepten

- **Splatting** (`@ssh`, `@splat`: een hashtable als parameters doorgeven):
  https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_splatting
- **Hashtables optellen** (`$a + $b`; een dubbele sleutel geeft een fout):
  https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_hash_tables
- **`-split` met een maximum aantal delen** (`$line -split '=', 2`):
  https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_split
- **`ForEach-Object -Parallel`, `$using:`:** https://learn.microsoft.com/powershell/module/microsoft.powershell.core/foreach-object
- **De call-operator `&`** (een functie oproepen via haar naam, een scriptblok in de scope van een module):
  https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_operators#call-operator-
- **`Get-Command ... .Parameters`** (welke parameters heeft een functie?):
  https://learn.microsoft.com/powershell/module/microsoft.powershell.core/get-command
- **`Write-Progress`:** https://learn.microsoft.com/powershell/module/microsoft.powershell.utility/write-progress

## 6. Zelf proberen

```powershell
Import-Module ./NexusFleet.psd1 -Force
$module = Get-Module NexusFleet

# De feiten van een server lezen
& $module { ConvertFrom-NexusFactLine -Text "os=ubuntu`nsudo=yes`nagent=a=b" }

# De lus met een interne functie die geen netwerk nodig heeft, drie tegelijk
& $module {
    $items = 1..5 | ForEach-Object { @{ HostInfo = [pscustomobject]@{ Name = "node-$_"; Address = "10.0.0.$_"; Port = 22; User = 'fleet' } } }
    Invoke-NexusHostLoop -InputObject $items -FunctionName Get-NexusSshParameter -Parameter @{ Config = @{ Ssh = @{ ConnectTimeoutSeconds = 3 } } } `
        -FailureFunction ConvertTo-NexusPreflightFailure -ThrottleLimit 3 -Activity 'proef'
}

# Zie het mislukken: Config is geen hashtable, dus elke server krijgt een mislukt resultaat in plaats van een crash
& $module {
    $items = 1..3 | ForEach-Object { @{ HostInfo = [pscustomobject]@{ Name = "node-$_" } } }
    Invoke-NexusHostLoop -InputObject $items -FunctionName Get-NexusSshParameter -Parameter @{ Config = 'fout' } `
        -FailureFunction ConvertTo-NexusPreflightFailure -ThrottleLimit 3 -Activity 'proef' | Format-Table Host, Success, Error
}

# De tests
Invoke-Pester -Path ./tests/utils/Invoke-NexusHostLoop.Tests.ps1, ./tests/utils/ConvertFrom-NexusFactLine.Tests.ps1 -Output Detailed
```

## 7. Controlevragen

1. Waarom geeft de runspace bij een fout een merkteken terug, en niet meteen het mislukte resultaat?
2. Wat gebeurt er als je de functie per server als scriptblok in plaats van als naam aan de lus geeft?
3. Waarom staan de twee manieren van oproepen samen in `& { ... }` met een `|` erachter, en niet in een variabele?
4. `ConvertFrom-NexusFactLine` krijgt de regel `agent=running|0|image=x`. Welke sleutel en welke waarde komen eruit, en
   waarom?
5. Hoe test je de parallelle tak van de lus, als mocks daar niet werken?
