# Bulkacties en uitschrijven

> Uitleg gegenereerd met Claude Code als studiemateriaal. Niet mijn leerlogboek.

_Stand: `Remove-NexusNode` (#157), `Get-NexusServer` en `Invoke-NexusFleetAction` (#158). De eerste extra uit het voorstel._

## 1. Wat het doet

`Remove-NexusNode` is het omgekeerde van `Install-NexusNode`: het schrijft een node uit bij NexusInfra en haalt de
agent van de server. `Get-NexusServer` geeft de lijst van servers (gameservers, "deployments") die NexusInfra draait.
`Invoke-NexusFleetAction` start, stopt of herstart een hele groep van die servers in één keer en geeft per server
terug of het gelukt is.

## 2. Waar het staat

| Pad | Inhoud |
|---|---|
| `src/public/Remove-NexusNode.ps1` | De cmdlet: servers verzamelen, per server vragen (`ShouldProcess`), de gedeelde lus |
| `src/core/Invoke-NexusHostRemoval.ps1` | Het werk voor één server (wordt rechtstreeks getest, gooit nooit een fout) |
| `src/core/ConvertTo-NexusRemoveFailure.ps1` | Het resultaat van een server waarvan het werk onverwacht mislukte |
| `src/public/Get-NexusServer.ps1` | `GET /deployments`, pagina na pagina |
| `src/public/Invoke-NexusFleetAction.ps1` | `POST /deployments/bulk`, in pakketten van hoogstens 100 |
| `config/nexusinfra.psd1` | `Servers.PageSize` (200) en `Servers.BulkMaxIds` (100) |
| `tests/core/Invoke-NexusHostRemoval.Tests.ps1` | Het uitschrijven tegen de nep-fleet |
| `tests/public/Remove-NexusNode.Tests.ps1` | De cmdlet met `-ThrottleLimit 1` |
| `tests/public/Get-NexusServer.Tests.ps1`, `Invoke-NexusFleetAction.Tests.ps1` | Met een nagebootste `Invoke-NexusApi` |
| `tests/public/Remove-NexusNode.Integration.Tests.ps1` | Alles echt, in het node-lab (draait in CI) |

## 3. Hoe het werkt

### Een node uitschrijven

`Remove-NexusNode` is opgebouwd zoals `Install-NexusNode`: in `process` worden de servers alleen verzameld, in `end`
wordt per server beslist of het echt gebeurt, en daarna doet `Invoke-NexusHostLoop` het werk parallel.

```powershell
$work = foreach ($hostInfo in $hosts) {
    @{
        HostInfo = $hostInfo
        PlanOnly = -not $PSCmdlet.ShouldProcess($hostInfo.Name, 'Remove the NexusInfra node (deregister, remove the agent)')
    }
}
```

Bovenaan staat `ConfirmImpact = 'High'`. Daardoor vraagt PowerShell per server om bevestiging, ook zonder `-Confirm`.
Met `-Confirm:$false` vraagt het niets, met `-WhatIf` geeft `ShouldProcess` altijd `$false` terug en wordt het een
droge run.

Het werk voor één server staat in `Invoke-NexusHostRemoval`, in vijf stappen:

1. **Host**: één `ssh`-aanroep die alleen kijkt. Het script drukt `exists=yes|no` (de container) en `envfile=yes|no`
   af; `ConvertFrom-NexusFactLine` maakt daar een hashtable van. Antwoordt de server niet, dan stopt het hier en is
   er niets veranderd (tenzij `-IgnoreUnreachableHost`).
2. **Node**: `GET /nodes` en kijken of de naam erin staat. Een droge run stopt hier en meldt `WouldRemove`.
3. **Node**: `DELETE /nodes/<naam>`. NexusInfra weigert dat met `409` zolang er nog een server op de node draait.
   Die fout wordt herkend aan zijn id en krijgt een duidelijke tekst:

   ```powershell
   catch {
       if ($_.FullyQualifiedErrorId -like 'NexusApi.Conflict*') {
           throw "node $name still hosts a running server, nothing was changed. Stop or move its servers first."
       }
       throw
   }
   ```

4. **Agent**: de container en het env-bestand (met de geheimen) weg. Alleen wat stap 1 gezien heeft.
5. **Node**: nog één keer `GET /nodes`. Staat de node er weer, dan nog een `DELETE`.

Vóór elke stap wordt `$result.Step` gezet. Gaat er iets mis, dan vangt de ene `catch` onderaan de fout op en zegt
`Step` waar het was. Lukt alles, dan wordt `Step` weer leeg gemaakt.

Stap 5 lijkt overbodig maar is het niet. NexusInfra maakt een node aan zodra er een heartbeat van binnenkomt
(`upsertNode` in de orchestrator). De agent stuurt elke seconde een heartbeat. Tussen de `DELETE` van stap 3 en het
stoppen van de agent in stap 4 komt er dus bijna altijd nog één binnen, en dan staat de node er opnieuw, zonder naam
of locatie.

### De servers opvragen

NexusInfra geeft de servers in pagina's: `{ items, total, limit, offset }`. `Get-NexusServer` vraagt telkens de
volgende pagina tot het alles heeft:

```powershell
$offset = 0
do {
    $page = Invoke-NexusApi @api -Method GET -Path "/deployments?limit=$pageSize&offset=$offset$filter"
    $items = @($page.items)
    foreach ($item in $items) { [pscustomobject]@{ PSTypeName = 'NexusFleet.Server'; Id = $item.id; ... } }
    $offset += $items.Count
} while ($items.Count -gt 0 -and $offset -lt $page.total)
```

De voorwaarde `$items.Count -gt 0` zorgt dat de lus ook stopt als `total` niet klopt met wat er echt terugkomt. De
filters gaan mee in de URL, met `[uri]::EscapeDataString` zodat een spatie of `&` in een naam de URL niet breekt.

### Een actie op een groep

`Invoke-NexusFleetAction` krijgt de ids via de pipeline. Omdat de parameter `ValueFromPipelineByPropertyName` heeft,
neemt PowerShell van elk `NexusFleet.Server`-object vanzelf de eigenschap `Id`. In `process` worden de ids verzameld
(elk één keer), in `end` worden ze in pakketten verstuurd:

```powershell
for ($start = 0; $start -lt $ids.Count; $start += $batchSize) {
    $batch = @($ids.GetRange($start, [math]::Min($batchSize, $ids.Count - $start)))
    ...
    $response = Invoke-NexusApi @api -Method POST -Path '/deployments/bulk' -Body @{ action = $Action; ids = $batch }
```

NexusInfra antwoordt altijd met `200` en een lijst `results`, één per server (`ok`, `status`, `error`). Per id zoekt de
cmdlet zijn antwoord op en maakt er een `NexusFleet.ActionResult` van. Mislukt het hele verzoek (NexusInfra
onbereikbaar), dan krijgt elke server van dat pakket die fout, en het volgende pakket wordt toch nog geprobeerd.

`ShouldProcess` wordt hier één keer gevraagd voor de hele groep, niet per server: bij 300 servers wil je niet 300 keer
bevestigen.

## 4. Waarom zo

- **Eerst uitschrijven, dan de agent weghalen.** Alleen de `DELETE` zelf vertelt of NexusInfra de node weigert. Zou
  de agent eerst weggaan, dan staat een geweigerde node zonder agent en zijn de servers erop onbestuurbaar. De prijs
  is stap 5 (de tweede `DELETE`). Verworpen: eerst zelf de draaiende servers tellen met `GET /deployments`. Dat is een
  tweede plaats waar de regel van NexusInfra nagebootst wordt, en die kan anders worden.
- **Geen stappencontract (`Register-NexusStep`) voor het uitschrijven.** De stappen van de installatie hebben Test,
  Apply en Rollback omdat een halve installatie teruggedraaid moet worden. Uitschrijven heeft geen rollback: iets dat
  weg is, hoeft niet terug. Vijf regels onder elkaar zijn dan makkelijker te lezen dan vijf stapbestanden.
- **Docker en het backup-volume blijven staan.** Docker stond er misschien al vóór NexusFleet, en het volume is data.
  Dezelfde regel als bij de rollback van de agent-stap.
- **`-IgnoreUnreachableHost` in plaats van `-Force`.** `-Force` betekent bij `Install-NexusNode` al iets anders (de
  agent opnieuw maken). Een lange naam die zegt wat hij doet, is hier duidelijker.
- **De grens van 100 staat in de config**, niet in de functie: het is een waarde van NexusInfra (`MAX_BULK`).
- **Geen parallelle lus bij de actie.** NexusInfra verwerkt de servers van één verzoek zelf na elkaar, omdat het bij
  elke start de bezetting van de nodes leest. Tegelijk versturen zou dat doorkruisen.

## 5. PowerShell-concepten

| Concept | Wat het is | Meer |
|---|---|---|
| `ConfirmImpact = 'High'` | Zegt hoe ingrijpend een cmdlet is. Bij `High` vraagt PowerShell standaard om bevestiging | [about_Functions_CmdletBindingAttribute](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_functions_cmdletbindingattribute) |
| `ShouldProcess` | Vraagt of een wijziging mag doorgaan; geeft `$false` bij `-WhatIf` | [Everything about ShouldProcess](https://learn.microsoft.com/powershell/scripting/learn/deep-dives/everything-about-shouldprocess) |
| `ValueFromPipelineByPropertyName` | Een parameter krijgt de eigenschap met dezelfde naam van het pipeline-object | [about_Functions_Advanced_Parameters](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_functions_advanced_parameters) |
| `begin` / `process` / `end` | `process` loopt per pipeline-object, `end` één keer aan het einde | [about_Functions_Advanced_Methods](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_functions_advanced_methods) |
| `do { } while ( )` | Een lus die minstens één keer loopt en daarna de voorwaarde test | [about_Do](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_do) |
| `FullyQualifiedErrorId` | De vaste id van een fout, betrouwbaarder om op te testen dan de tekst | [about_Try_Catch_Finally](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_try_catch_finally) |
| `throw` zonder argument | Gooit in een `catch` dezelfde fout opnieuw | [about_Throw](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_throw) |
| `Should -Invoke -ParameterFilter` | Telt in Pester alleen de aanroepen van een mock die aan een voorwaarde voldoen | [Pester: Should -Invoke](https://pester.dev/docs/commands/Should) |

## 6. Zelf proberen

```powershell
# De tests van dit onderwerp
Import-Module Pester -MinimumVersion 5.0 -MaximumVersion 5.99
Invoke-Pester -Path ./tests/core/Invoke-NexusHostRemoval.Tests.ps1, ./tests/public/Invoke-NexusFleetAction.Tests.ps1 -Output Detailed
```

In het node-lab (Docker moet draaien):

```powershell
./lab/node-lab/Start-NodeLab.ps1
./lab/demo/Invoke-NexusLabDemo.ps1          # maakt de lab-servers tot nodes
$env:NEXUSFLEET_CONFIG = './lab/node-lab/.keys/nexusinfra.lab.psd1'
Import-Module ./NexusFleet.psd1 -Force
Connect-NexusInfra -Token (Get-Content ./lab/node-lab/.keys/api-token -Raw | ConvertTo-SecureString -AsPlainText -Force)
$hosts = Import-NexusInventory ./lab/node-lab/.keys/inventory.lab.json

$hosts | Remove-NexusNode -WhatIf            # het plan, er verandert niets
$hosts | Remove-NexusNode -Confirm:$false    # echt
$hosts | Remove-NexusNode -Confirm:$false    # tweede keer: Changed = False
Get-NexusServer                              # het lab draait geen servers: leeg
Invoke-NexusFleetAction -Action stop -Id 'bestaat-niet'   # zie het mislukken: Status 404
```

Zie het weigeren: zet in `tests/core/Invoke-NexusHostRemoval.Tests.ps1` de regel `$fake.Busy.Add('node-web01')` in een
andere test en kijk welke verwachting dan breekt.

## 7. Controlevragen

1. Waarom schrijft `Invoke-NexusHostRemoval` de node uit vóór het de agent weghaalt, en wat zou er misgaan in de
   omgekeerde volgorde?
2. Waarom is er na het weghalen van de agent een tweede `DELETE /nodes/<naam>` nodig?
3. `Remove-NexusNode` vraagt per server om bevestiging en `Invoke-NexusFleetAction` één keer voor de hele groep. Waar
   in de code zie je dat verschil, en waarom is het zo gekozen?
4. Wat gebeurt er met 250 ids in `Invoke-NexusFleetAction` als het tweede verzoek mislukt? Welke servers krijgen
   welk resultaat?
5. Hoe weet `Get-NexusServer` dat het alle pagina's gelezen heeft, en waarom staat `$items.Count -gt 0` in de
   voorwaarde van de lus?
