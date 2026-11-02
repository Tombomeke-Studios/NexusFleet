# Inventaris

> Uitleg gegenereerd met Claude Code als studiemateriaal. Niet mijn leerlogboek.

_Stand: `Import-NexusInventory` (#32, #33)._

## 1. Wat het doet

De inventaris is de lijst van servers die NexusFleet moet behandelen, in een JSON-bestand. `Import-NexusInventory`
leest dat bestand, vult ontbrekende velden aan met de standaardwaarden, controleert alles, en geeft per server
één object terug. Die objecten gaan straks rechtstreeks naar `Test-NexusHost` en `Install-NexusNode`.

## 2. Waar het staat

| Pad | Inhoud |
|---|---|
| `src/public/Import-NexusInventory.ps1` | De cmdlet (geëxporteerd) |
| `config/inventory.example.json` | Een voorbeeld; je eigen `config/inventory.json` wordt door git genegeerd |
| `tests/public/Import-NexusInventory.Tests.ps1` | 17 tests |

## 3. Hoe het werkt

**Het bestand:**

```json
{
  "defaults": { "user": "fleet", "port": 22, "location": "home" },
  "hosts": [
    { "name": "node-home01", "address": "192.168.1.20" },
    { "name": "node-vps01", "address": "203.0.113.10", "port": 2222, "location": "vps" }
  ]
}
```

**De cmdlet**, in de volgorde waarin hij werkt:

1. Bestaat het bestand niet: `NexusFleet.InventoryNotFound`.
2. `ConvertFrom-Json -AsHashtable` leest de JSON. Is het geen geldige JSON: `NexusFleet.InventoryInvalid`.
3. Per server:
   - een onbekend veld (bijvoorbeeld `adress`) geeft een **waarschuwing**;
   - voor elk veld geldt: de waarde op de server zelf, anders die uit `defaults`, en voor `port` anders 22;
   - de controles: verplichte velden aanwezig, `name` een geldige node-naam, `address` een hostnaam of IP-adres,
     `port` tussen 1 en 65535, `user` een Linux-gebruikersnaam, `agentUrl` een http(s)-adres;
   - zonder `agentUrl` wordt die `http://<address>:<Agent.Port uit de configuratie>`.
4. Daarna de dubbels: twee servers met dezelfde `name`, of twee keer dezelfde `address:port`.
5. Elk probleem komt in één lijst, met de server erbij (`host 2 (node-b): port '0' must be ...`). Is die lijst niet
   leeg, dan volgt één fout met alles erin. Anders gaan de objecten één voor één de pijplijn in.

## 4. Waarom zo

- **`defaults`.** Bij tien servers met dezelfde gebruiker en locatie schrijf je die één keer. Minder herhaling is
  minder kans op een tikfout.
- **Alle problemen tegelijk**, zoals bij de configuratie: bij honderd servers wil je niet honderd keer opnieuw
  starten.
- **Dezelfde controle op het adres als in het transport.** Een adres als `-oProxyCommand=...` zou `ssh` als optie
  lezen. Het transport weigert dat al; de inventaris weigert het ook, zodat je het meteen bij het inlezen merkt
  en niet pas bij de installatie. Het patroon staat in beide bestanden, met een verwijzing naar elkaar.
- **Een eigen regel voor de node-naam.** NexusInfra aanvaardt elke niet-lege tekst als id. NexusFleet kiest een
  voorzichtige regel (kleine letters, cijfers, streepjes, max 63), omdat de naam ook de `NODE_ID` van de agent
  wordt, een logbestandsnaam, en misschien een DNS-naam. Dat staat zo in de help: het is een keuze van
  NexusFleet.
- **Dubbels weigeren.** Twee servers met dezelfde naam zouden in NexusInfra dezelfde node worden. Twee keer
  dezelfde machine zou twee agents op dezelfde server proberen te zetten.
- **Een waarschuwing voor onbekende velden** in plaats van een fout: een extra veld is onschuldig (misschien een
  opmerking), maar `adress` in plaats van `address` wil je wel weten.
- **Objecten één voor één uitvoeren.** Zo kan een volgende cmdlet in de pijplijn al met de eerste server beginnen.

## 5. PowerShell-concepten

- **`ConvertFrom-Json -AsHashtable`:** https://learn.microsoft.com/powershell/module/microsoft.powershell.utility/convertfrom-json
- **Pijplijninvoer** (`ValueFromPipeline`) en het **`process`-blok:**
  https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_functions_advanced_methods
- **`Group-Object`** (dubbels vinden): https://learn.microsoft.com/powershell/module/microsoft.powershell.utility/group-object
- **`Write-Warning`:** https://learn.microsoft.com/powershell/module/microsoft.powershell.utility/write-warning

## 6. Zelf proberen

```powershell
Import-Module ./NexusFleet.psd1 -Force
Get-Help Import-NexusInventory -Full
Import-NexusInventory ./config/inventory.example.json | Format-Table Name, Address, Port, User, Location, AgentUrl
```

Zien hoe het faalt (meerdere problemen in één keer):

```powershell
@'
{ "hosts": [
  { "name": "Node A", "address": "bad address", "user": "fleet", "location": "home" },
  { "name": "node-b", "address": "10.0.0.6", "port": 0, "user": "fleet", "location": "home", "adress": "x" },
  { "name": "node-b", "address": "10.0.0.7", "user": "fleet" }
] }
'@ | Set-Content "$env:TEMP/kapot.json"
Import-NexusInventory "$env:TEMP/kapot.json"
```

## 7. Controlevragen

1. Hoe werkt `defaults`, en wat wint als een veld zowel op de server als in `defaults` staat?
2. Waarom controleert de inventaris het adres, als het transport dat ook al doet?
3. Waarom zijn twee servers met dezelfde naam een probleem voor NexusInfra?
4. Waarom is een onbekend veld een waarschuwing en geen fout?
5. Waarom geeft de cmdlet de servers één voor één aan de pijplijn, en niet als één lijst?
