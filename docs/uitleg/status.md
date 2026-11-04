# Status van de fleet

> Uitleg gegenereerd met Claude Code als studiemateriaal. Niet mijn leerlogboek.

_Stand: `Get-NexusFleetStatus` en `Export-NexusFleetStatus` (#50, #51)._

## 1. Wat het doet

`Get-NexusFleetStatus` laat per node zien hoe het ermee gaat, van twee kanten. NexusInfra vertelt wat het van de
node weet: is hij gezond, wanneer kwam de laatste heartbeat, staat hij in onderhoud. De server zelf vertelt via `ssh`
of hij bereikbaar is, of Docker er staat en of de agent-container draait. Wat niet in orde is, staat in gewone woorden
in `Problem`. `Export-NexusFleetStatus` schrijft dat naar een JSON- of CSV-bestand.

## 2. Waar het staat

| Pad | Inhoud |
|---|---|
| `src/public/Get-NexusFleetStatus.ps1` | De cmdlet: `GET /nodes`, de servers parallel bekijken, samenvoegen |
| `src/core/Get-NexusHostStatus.ps1` | Eén server bekijken over `ssh` (wordt rechtstreeks getest, gooit nooit een fout) |
| `src/core/ConvertTo-NexusNodeStatus.ps1` | Voegt het NexusInfra-record, de inventaris en de serverstatus samen tot één object |
| `src/public/Export-NexusFleetStatus.ps1` | Schrijft de statussen naar JSON of CSV |
| `tests/core/Get-NexusHostStatus.Tests.ps1` | 7 tests met een nep-transport |
| `tests/core/ConvertTo-NexusNodeStatus.Tests.ps1` | 12 tests: elke soort probleem, onderhoud, "nooit een heartbeat" |
| `tests/public/Get-NexusFleetStatus.Tests.ps1` | De cmdlet en de export, met 80 gegenereerde servers |
| `tests/public/Get-NexusFleetStatus.LocalSsh.Tests.ps1` | Echte runspaces en echte `ssh` naar gesloten poorten (in CI) |
| `tests/public/Get-NexusFleetStatus.Integration.Tests.ps1` | In het node-lab: agent stoppen en zien dat de status het toont |

## 3. Hoe het werkt

```powershell
Import-NexusInventory ./config/inventory.json | Get-NexusFleetStatus | Format-Table Name, Ok, Health, AgentState, Problem
```

1. `process` verzamelt de servers. Er mogen er ook nul zijn: dan toont de cmdlet alleen wat NexusInfra weet.
2. `end` vraagt **één keer** `GET /nodes`. Lukt dat niet, dan komt er een waarschuwing, en worden de servers toch
   bekeken (`Health` is dan `unknown`).
3. Per server `Get-NexusHostStatus`, parallel zoals bij `Test-NexusHost`. Eén `ssh`-oproep met een klein script:

   ```bash
   echo "uptime=$(cut -d. -f1 /proc/uptime)"
   echo "diskfreemb=$(df -Pm / | awk 'NR==2 {print $4}')"
   ... docker --version ...
   ... docker inspect --format '{{.State.Status}}|{{.State.StartedAt}}|{{.RestartCount}}|{{.Config.Image}}' ...
   ```
4. Samenvoegen met `ConvertTo-NexusNodeStatus`: eerst de servers van de inventaris, in hun volgorde, daarna de nodes
   die alleen NexusInfra kent. Per node worden de problemen verzameld:

   ```powershell
   if (-not $Node) { $problems.Add('not registered in NexusInfra') }
   elseif ($Node.health -ne 'healthy') { $problems.Add("NexusInfra reports it $($Node.health)") }
   ...
   Ok = $problems.Count -eq 0;  Problem = $problems -join '; '
   ```
5. `Export-NexusFleetStatus` verzamelt de objecten, zet tijden om naar ISO-8601 in UTC, en schrijft JSON
   (`{ generatedAt, nodes }`) of CSV (één rij per node).

## 4. Waarom zo

- **Twee kanten.** NexusInfra ziet alleen heartbeats: "offline" zegt niet waarom. De server zelf zegt dan bijvoorbeeld
  "de agent-container is gestopt" of "de server is onbereikbaar". Samen wijzen ze naar de oorzaak.
- **Nooit stoppen.** Een status-commando is juist nodig als er iets mis is. Een onbereikbare server, of zelfs een
  onbereikbaar paneel, wordt dus een regel in het resultaat en geen fout. Dat is het "nooit fataal" uit de TODO.
- **`Ok` en `Problem` in gewone woorden**, zodat `Where-Object { -not $_.Ok }` meteen de lijst geeft van wat aandacht
  vraagt, zonder dat je zelf alle velden moet vergelijken. Onderhoud is geen probleem: dat is een keuze van de
  beheerder.
- **Samenvoegen in een eigen functie.** Alle regels ("wat is een probleem?") zitten in `ConvertTo-NexusNodeStatus`,
  die zonder netwerk en zonder mocks getest wordt met gewone objecten.
- **"Nooit een heartbeat".** NexusInfra zet `lastHeartbeat` op 1970-01-01 voor een node die nog nooit iets stuurde.
  Dat wordt `$null`, want een datum uit 1970 zou in een tabel of export misleiden.
- **Export als aparte cmdlet**, met ISO-tijden: `Export-Csv` alleen zou tijden in het formaat van de eigen taal
  schrijven (`4/11/2026 7:49:54`), dat een ander niet correct kan inlezen.

## 5. PowerShell-concepten

- **Een niet-verplichte pijplijnparameter** (`[Parameter(ValueFromPipeline)]` zonder `Mandatory`):
  https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_functions_advanced_parameters
- **`Write-Warning` en `-WarningVariable`:** https://learn.microsoft.com/powershell/module/microsoft.powershell.utility/write-warning
- **`Export-Csv`, `ConvertTo-Json`:** https://learn.microsoft.com/powershell/module/microsoft.powershell.utility/export-csv
- **`[datetime]`, `ToUniversalTime()`, het formaat `'o'` (ISO-8601):**
  https://learn.microsoft.com/dotnet/standard/base-types/standard-date-and-time-format-strings#the-round-trip-o-o-format-specifier
- **`$PSCmdlet.GetUnresolvedProviderPathFromPSPath`** (een pad dat nog niet bestaat volledig maken):
  https://learn.microsoft.com/dotnet/api/system.management.automation.pscmdlet.getunresolvedproviderpathfrompspath
- **`switch` met een waarde** (formaat kiezen uit de extensie): https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_switch

## 6. Zelf proberen

```powershell
Import-Module ./NexusFleet.psd1 -Force
Get-Help Get-NexusFleetStatus -Full

# In het node-lab (zie installatie.md voor het starten en verbinden)
Copy-Item ./lab/node-lab/.keys/nexusinfra.lab.psd1 ./config/nexusinfra.local.psd1
Connect-NexusInfra -Token (ConvertTo-SecureString (Get-Content ./lab/node-lab/.keys/api-token -Raw) -AsPlainText -Force)
$hosts = Import-NexusInventory ./lab/node-lab/.keys/inventory.lab.json
$hosts | Get-NexusFleetStatus | Format-Table Name, Ok, Health, LastHeartbeat, AgentState, Problem
Get-NexusFleetStatus | Format-Table Name, Ok, Health        # alleen wat NexusInfra weet

# Laten mislukken: de agent op node-lab2 stoppen, 12 s wachten, opnieuw kijken
ssh -i ./lab/node-lab/.keys/id_ed25519 -p 2232 fleet@127.0.0.1 'sudo docker stop nexusinfra-node-agent'
Start-Sleep -Seconds 12
$hosts | Get-NexusFleetStatus | Format-Table Name, Ok, Health, AgentState, Problem
$hosts | Install-NexusNode -WhatIf | ForEach-Object { $_.Host; $_.Steps | Format-Table }   # wat zou herstellen?

# Exporteren
$hosts | Get-NexusFleetStatus | Export-NexusFleetStatus -Path ./status.csv
Import-Csv ./status.csv | Format-Table Name, Ok, Health, LastHeartbeat
Remove-Item ./status.csv, ./config/nexusinfra.local.psd1

# De tests
Import-Module Pester -MinimumVersion 5.0 -MaximumVersion 5.99
Invoke-Pester -Path ./tests/core/Get-NexusHostStatus.Tests.ps1, ./tests/core/ConvertTo-NexusNodeStatus.Tests.ps1, ./tests/public/Get-NexusFleetStatus*.ps1 -Output Detailed
```

## 7. Controlevragen

1. Waarom stopt `Get-NexusFleetStatus` niet als NexusInfra zelf onbereikbaar is, en wat zie je dan in het resultaat?
2. Een node is `offline` in NexusInfra. Welke twee verschillende oorzaken kan de serverkant van de status dan tonen?
3. Waarom zitten alle regels over "wat is een probleem" in `ConvertTo-NexusNodeStatus` en niet in de cmdlet zelf?
4. Waarom wordt een `lastHeartbeat` van 1970 `$null`?
5. Waarom zet `Export-NexusFleetStatus` tijden om naar ISO-8601 in UTC voordat het een CSV schrijft?
