# Module-opbouw

> Uitleg gegenereerd met Claude Code als studiemateriaal. Niet mijn leerlogboek.

_Stand: unit 1 (mappenstructuur, issue #1). De manifest en de loader komen erbij in unit 2 (#2)._

## 1. Wat het doet

De repository is verdeeld in mappen die elk één taak hebben: contracten, installatiestappen, contact met
servers, contact met de API, de cmdlets zelf en hulpfuncties. De tests staan in een aparte map die
dezelfde indeling volgt. Zo weet je bij elk bestand meteen waar het hoort en waar zijn test staat.

## 2. Waar het staat

| Map | Taak |
|---|---|
| `src/core/` | De contracten: wat een *stap* is (`Test` / `Apply` / `Rollback`) en wat een *transport* is (een commando op een host uitvoeren) |
| `src/steps/` | Eén bestand per installatiestap: Docker, agent-container, node registreren, *healthy* controleren |
| `src/transports/` | Hoe de module commando's op een host uitvoert (SSH; de methode kiest experiment E1) |
| `src/api/` | `Invoke-NexusApi`: de enige plek die de REST-API van NexusInfra aanroept |
| `src/public/` | De cmdlets die de gebruiker ziet (`Connect-NexusInfra`, `Import-NexusInventory`, …) |
| `src/utils/` | Gedeelde hulp: `Write-NexusLog` en het inlezen van configuratie |
| `tests/` + submappen | Pester-tests, zelfde indeling als `src/` |
| `config/` | Alle NexusInfra-specifieke waarden en een voorbeeldinventaris, zonder geheimen |
| `lab/` | Scripts en notities van de experimenten (fase 1), geen deel van de module |

Elke map bevat voorlopig alleen een `README.md` van één regel met zijn taak.

## 3. Hoe het werkt

Er draait nog geen code. De structuur legt vast **waar** code later komt:

- De cmdlets in `public/` doen zelf weinig: ze roepen stappen (`steps/`) aan, die via een transport
  (`transports/`) op de host werken of via `api/` met NexusInfra praten.
- `core/` bevat de afspraken die `steps/` en `transports/` volgen. Daardoor kan `Install-NexusNode` met
  élke stap op dezelfde manier omgaan: eerst `Test`, dan `Apply` als het nodig is, bij een fout `Rollback`.
- `tests/steps/Agent.Tests.ps1` test `src/steps/Agent.ps1`: je vindt een test altijd door het pad te spiegelen.

Een voorbeeld van zo'n map-README (`src/api/README.md`):

```markdown
# api — Invoke-NexusApi, the only place that calls the NexusInfra REST API.
```

## 4. Waarom zo

- **Eén taak per map, en `steps/` als map van losse bestanden.** Een stap toevoegen, vervangen of weglaten
  wordt dan een bestand toevoegen, vervangen of verwijderen (criterium *uitbreidbaarheid* in het voorstel).
  Het alternatief was één groot `NexusFleet.psm1`-bestand met alle functies. Dat is in het begin sneller,
  maar wordt onleesbaar, en een stap kun je er niet los uit halen of los testen.
- **Alleen `api/` praat met NexusInfra.** Als NexusInfra zijn API verandert (bedreiging in de SWOT), moet je
  maar op één plek aanpassen, en in tests hoef je maar één ding te mocken.
- **Een `README.md` per map in plaats van lege `.ps1`-bestanden.** Git bewaart geen lege mappen, dus er moest
  iets in. Lege scriptbestanden zouden namen vastleggen die nog niet beslist zijn (de transportmethode volgt
  pas uit E1), en de loader zou ze later inlezen. Een `README.md` toont de taak van de map ook op GitHub en
  wordt door de loader nooit geladen, want die leest alleen `*.ps1`.
- **`logs/` bestaat nog niet.** Die map maakt de module zelf aan tijdens een uitvoering, en hij komt in
  `.gitignore` (issue #4). Logbestanden horen niet in de repository.

## 5. PowerShell-concepten

- **Scriptmodule:** een `.psm1`-bestand met functies, plus een manifest (`.psd1`) dat de module beschrijft.
  De mappen in `src/` worden straks door de `.psm1` ingeladen.
  https://learn.microsoft.com/powershell/scripting/developer/module/how-to-write-a-powershell-script-module
- **Publieke en interne functies:** alleen wat de manifest in `FunctionsToExport` zet, is zichtbaar voor de
  gebruiker. Daarom staan de cmdlets apart in `public/`; de rest blijft intern.
  https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_modules
- **Pester-conventie `*.Tests.ps1`:** Pester zoekt standaard naar bestanden met die naam. Het spiegelen van
  `src/` is een afspraak van dit project, geen regel van Pester.
  https://pester.dev/docs/usage/file-placement-and-naming

## 6. Zelf proberen

```powershell
# De mappenstructuur bekijken (vanuit de root van de repo)
Get-ChildItem -Directory -Recurse -Exclude .git | Select-Object FullName

# De taak van elke map in één overzicht
Get-ChildItem -Recurse -Filter README.md | ForEach-Object { Get-Content $_.FullName -TotalCount 1 }
```

Wat er *misgaat* zonder deze structuur zie je pas vanaf unit 2: als de loader een map verwacht die er niet
is, faalt `Import-Module`. Probeer het dan eens door tijdelijk een map te hernoemen.

## 7. Controlevragen

1. Waarom staat de code om NexusInfra aan te spreken in één aparte map, en wat win je daarmee bij het testen?
2. Wat moet je doen om een nieuwe installatiestap toe te voegen, en welke bestanden raak je daarbij níet aan?
3. Hoe vind je de test van `src/transports/Ssh.ps1` zonder te zoeken?
4. Waarom staat `logs/` niet in de repository?
5. Welk verschil is er tussen een functie in `src/public/` en een functie in `src/utils/` voor de gebruiker van de module?
