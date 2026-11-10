# Drift detection

> Uitleg gegenereerd met Claude Code als studiemateriaal. Niet mijn leerlogboek.

_Stand: `Sync-NexusFleet` (#160). De tweede extra uit het voorstel._

## 1. Wat het doet

Nodes groeien langzaam weg van wat je bedoeld had: iemand past een locatie aan in het paneel, een agent-container
wordt met de hand opnieuw gemaakt zonder herstartbeleid, een container verdwijnt. Dat heet drift. `Sync-NexusFleet`
vergelijkt elke server met de inventaris en de config, zegt per server in woorden wat er afwijkt, en zet het terug
goed.

## 2. Waar het staat

| Pad | Inhoud |
|---|---|
| `src/public/Sync-NexusFleet.ps1` | De cmdlet: vergelijken, onbekende nodes zoeken, vragen, herstellen |
| `src/core/ConvertTo-NexusSyncResult.ps1` | Leest het plan van één server als een lijst verschillen |
| `src/core/Invoke-NexusStepSequence.ps1` | De step runner: neemt `State.Detail` van een `Test` over in het resultaat van de stap |
| `src/steps/RegisterNode.ps1`, `AgentContainer.ps1`, `VerifyHealthy.ps1` | Hun `Test` zegt nu ook wat er niet klopt |
| `tests/public/Sync-NexusFleet.Tests.ps1` | Drift tegen de nep-fleet |
| `tests/public/Sync-NexusFleet.Integration.Tests.ps1` | Echte drift in het node-lab (draait in CI) |

## 3. Hoe het werkt

### De vergelijking is de droge run van de installatie

Elke installatiestap heeft een `Test` die nagaat of de server voor die stap in orde is. `Install-NexusNode -WhatIf`
draait alleen die tests. Dat is precies een vergelijking van "gewenst" met "werkelijk", dus `Sync-NexusFleet` roept
hetzelfde werk aan, met `PlanOnly`:

```powershell
$loop = @{
    InputObject     = @($hosts | ForEach-Object { @{ HostInfo = $_; PlanOnly = $true } })
    FunctionName    = 'Invoke-NexusHostInstall'
    ...
}
$results = @(Invoke-NexusHostLoop @loop | ForEach-Object { ConvertTo-NexusSyncResult -Plan $_ -Step $steps })
```

### Een stap zegt wat er afwijkt

Een `Test` gaf alleen `$true` of `$false` terug. Voor drift wil je weten *wat* er niet klopt. Een test die niet in
orde is, laat dat nu achter in de context:

```powershell
if ($node.location -ne $hostInfo.Location) { "location is '$($node.location)', not '$($hostInfo.Location)'" }
...
if ($differs.Count -gt 0) {
    $Context.State.Detail = $differs -join '; '
}
$differs.Count -eq 0
```

De step runner neemt dat over in het resultaat van die stap en maakt het daarna leeg, zodat het niet bij de volgende
stap terechtkomt:

```powershell
if ($Context.State -and $Context.State.Detail) {
    $outcomes[$i].Detail = $Context.State.Detail
    $Context.State.Remove('Detail')
}
```

### Van plan naar verschillen

`ConvertTo-NexusSyncResult` leest het plan. Elke stap met uitkomst `WouldApply` wordt één regel:
`"RegisterNode: location is 'attic', not 'home'"`. Gaf de stap geen detail, dan staat de beschrijving van de stap er.
Mislukte het plan zelf (de preflight: de server antwoordt niet), dan is dat een fout: `Repairable` is dan `$false`,
want vanop afstand valt er niets te herstellen.

### Nodes die niet in de inventaris staan

```powershell
$unmanaged = @($nodes | Where-Object { $_.id -notin $hosts.Name } | ForEach-Object { ConvertTo-NexusSyncResult -Unmanaged $_.id })
```

Die worden alleen gemeld. Lukt `GET /nodes` niet, dan is dat een waarschuwing en gaat de rest gewoon door.

### Herstellen

Alleen voor servers met verschillen wordt `ShouldProcess` gevraagd, met de verschillen in de vraag. Onder `-WhatIf`
is het antwoord altijd `$false` en stopt het hier. De servers waarvoor het antwoord ja is, gaan naar
`Install-NexusNode`:

```powershell
$install = @{ ThrottleLimit = $ThrottleLimit; Confirm = $false }
...
$installed = @($repair | Install-NexusNode @install)
```

`Install-NexusNode` draait de tests opnieuw en past alleen toe wat niet in orde is. `Confirm = $false` omdat de
gebruiker net al ja gezegd heeft. Het resultaat van de installatie komt per server in `Repaired`, `Success` en `Error`.

## 4. Waarom zo

- **Geen apart bestand voor de gewenste staat.** De inventaris (JSON) en de config zeggen al hoe een node hoort te
  zijn. Een tweede bestand met een eigen vergelijker zou dezelfde kennis op twee plaatsen zetten.
- **De stappen hergebruiken.** De `Test` van een stap is de vergelijking, de `Apply` is het herstel. Een stap die
  later bijkomt (bijvoorbeeld voor de beveiligde verbinding), wordt daardoor vanzelf ook op drift gecontroleerd.
- **Herstellen via de publieke cmdlet `Install-NexusNode`**, niet via een eigen lus. Dan is er één plaats die
  geheimen ophaalt, logt en terugdraait bij een fout. De prijs: de tests draaien een tweede keer, en de herstelling
  heeft een eigen RunId in de logs.
- **Onbekende nodes worden nooit verwijderd.** Eén vergeten regel in de inventaris zou anders een draaiende node
  kosten. Verwijderen doe je bewust, met `Remove-NexusNode`.
- **`ConfirmImpact = 'High'`.** Een herstel kan een agent-container vervangen. Daarom vraagt de cmdlet per server,
  tenzij je `-Confirm:$false` meegeeft.
- **Wat het niet ziet:** een gewijzigd geheim. De geheimen worden nooit teruggelezen van een server, dus de test van
  de agent-stap kan het niet weten. Daarvoor dient `Install-NexusNode -Force`.

## 5. PowerShell-concepten

| Concept | Wat het is | Meer |
|---|---|---|
| Parameter sets | Een functie met twee manieren van aanroepen (`-Plan` of `-Unmanaged`) die elkaar uitsluiten | [about_Parameter_Sets](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_parameter_sets) |
| Splatting (`@install`) | Parameters in een hashtable opbouwen en in één keer meegeven; handig als sommige alleen soms meegaan | [about_Splatting](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_splatting) |
| `-notin` | Waar als de waarde links niet in de lijst rechts staat | [about_Comparison_Operators](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_comparison_operators) |
| `@( if ... )` | Een array opbouwen uit alles wat de code erbinnen teruggeeft; leeg als niets terugkomt | [about_Arrays](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_arrays) |
| `ShouldProcess(target, action)` | Vraagt bevestiging voor één doel; `$false` onder `-WhatIf` | [Everything about ShouldProcess](https://learn.microsoft.com/powershell/scripting/learn/deep-dives/everything-about-shouldprocess) |
| `-WarningVariable` | Vangt de waarschuwingen van een commando op in een variabele (gebruikt in de test) | [about_CommonParameters](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters) |
| `BeforeEach` | Pester: draait vóór elke test; hier installeert het telkens drie gezonde nodes | [Pester: Setup and teardown](https://pester.dev/docs/usage/setup-and-teardown) |

## 6. Zelf proberen

```powershell
Import-Module Pester -MinimumVersion 5.0 -MaximumVersion 5.99
Invoke-Pester -Path ./tests/public/Sync-NexusFleet.Tests.ps1 -Output Detailed
```

In het node-lab (Docker moet draaien), na `./lab/demo/Invoke-NexusLabDemo.ps1`:

```powershell
$env:NEXUSFLEET_CONFIG = './lab/node-lab/.keys/nexusinfra.lab.psd1'
Import-Module ./NexusFleet.psd1 -Force
Connect-NexusInfra -Token (Get-Content ./lab/node-lab/.keys/api-token -Raw | ConvertTo-SecureString -AsPlainText -Force)
$hosts = Import-NexusInventory ./lab/node-lab/.keys/inventory.lab.json

$hosts | Sync-NexusFleet -WhatIf | Format-Table Host, InSync, Differences   # alles in orde

# Maak zelf drift: haal de agent van node-lab2 weg
ssh -i ./lab/node-lab/.keys/id_ed25519 -p 2232 fleet@127.0.0.1 'sudo docker rm -f nexusinfra-node-agent'

$hosts | Sync-NexusFleet -WhatIf | Format-Table Host, InSync, Differences   # node-lab2 wijkt af
$hosts | Sync-NexusFleet                                                    # vraagt, en herstelt
```

Voor het herstel van een agent heeft `Sync-NexusFleet` de twee geheimen nodig (zie `Get-Help Install-NexusNode`).

## 7. Controlevragen

1. Waarom heeft `Sync-NexusFleet` geen eigen bestand met de gewenste staat? Waar staat die dan?
2. Hoe komt de tekst `location is 'attic', not 'home'` van de stap `RegisterNode` in het resultaat van
   `Sync-NexusFleet` terecht? Volg de weg langs de step runner.
3. Waarom wordt `State.Detail` na het overnemen weer verwijderd?
4. Waarom vraagt `Sync-NexusFleet` onder `-WhatIf` geen geheimen op, en bij een echt herstel wel?
5. Wat doet `Sync-NexusFleet` met een node die NexusInfra kent maar die niet in de inventaris staat, en waarom niet
   meer dan dat?
