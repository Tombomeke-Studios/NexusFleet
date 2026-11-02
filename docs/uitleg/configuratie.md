# Configuratie

> Uitleg gegenereerd met Claude Code als studiemateriaal. Niet mijn leerlogboek.

_Stand: `config/nexusinfra.psd1`, `Get-NexusConfig` en `Merge-NexusHashtable` (#24)._

## 1. Wat het doet

Alles wat specifiek is voor NexusInfra (het adres van het panel, het agent-image, de poort, de namen van de
omgevingsvariabelen, de health-drempels) staat in één configuratiebestand en niet in de code. Wie een eigen
panel heeft, overschrijft alleen wat anders is in een lokaal bestand. Bij het inlezen wordt elke waarde
gecontroleerd, en een fout noemt meteen alle problemen.

## 2. Waar het staat

| Pad | Inhoud |
|---|---|
| `config/nexusinfra.psd1` | Alle NexusInfra-waarden, met commentaar; gecontroleerd tegen NexusInfra `docs/images.md` |
| `config/nexusinfra.local.psd1` | Optioneel, door git genegeerd: alleen de waarden die jij anders wilt |
| `src/utils/Get-NexusConfig.ps1` | Leest, voegt samen en valideert |
| `src/utils/Merge-NexusHashtable.ps1` | Past de lokale waarden toe op de basis, ook in geneste tabellen |
| `tests/utils/Get-NexusConfig.Tests.ps1`, `Merge-NexusHashtable.Tests.ps1` | 9 + 3 tests |

## 3. Hoe het werkt

**Het bestand** is een PowerShell-hashtable in een `.psd1`, met drie delen: `Api`, `Agent` en `Health`.

```powershell
Agent  = @{
    Image           = 'ghcr.io/tombomeke-studios/nexusinfra/node-agent:community'
    Port            = 9100
    RestartPolicy   = 'unless-stopped'
    ...
```

**`Get-NexusConfig`** doet drie dingen na elkaar:

1. **Inlezen.** Voor het basisbestand en (als het bestaat) het lokale bestand:
   `Import-PowerShellDataFile -Path $file`. Kan dat niet, dan volgt een fout met de bestandsnaam erin.
2. **Samenvoegen.** Het lokale bestand gaat over de basis heen met `Merge-NexusHashtable`. Die functie maakt een
   kopie van de basis en zet daarin de waarden van de overschrijving. Zijn beide kanten een tabel (zoals `Api`),
   dan roept de functie *zichzelf* aan voor die tabel (*recursie*), zodat `@{ Api = @{ BaseUrl = '...' } }` alleen
   `BaseUrl` vervangt en `TimeoutSeconds` laat staan. Een sleutel die de basis niet kent, is waarschijnlijk een
   tikfout en geeft een waarschuwing.
3. **Valideren.** Een lijst regels, één per waarde:

   ```powershell
   @{ Key = 'Agent.Port'; Expect = 'a port number 1-65535'; Test = { param($v) $v -is [int] -and $v -ge 1 -and $v -le 65535 } }
   ```

   De melding noemt ook welke bestanden gelezen werden, zodat je weet waar je moet zoeken. Voor elke regel zoekt de functie de waarde op door de sleutel op te splitsen (`'Agent.Port'` →
   `$config['Agent']['Port']`). Ontbreekt de waarde, dan komt "is missing" in de lijst; faalt de test
   (`& $rule.Test $value`), dan "must be ... but is ...". Daarna volgt één regel die twee waarden vergelijkt:
   *offline* moet later komen dan *degraded*. Staat er iets in de lijst, dan gooit de functie één fout met alle
   problemen onder elkaar:

   ```text
   NexusFleet config is not valid (...\nexusinfra.psd1):
   - Api.BaseUrl must be an http(s) URL, but is 'localhost'
   - Agent.Port must be a port number 1-65535, but is 'abc'
   ```

## 4. Waarom zo

- **Een `.psd1` in plaats van JSON.** Het is gewone PowerShell-syntax met commentaar, en
  `Import-PowerShellDataFile` leest het **zonder code uit te voeren**: een `.psd1` met `Remove-Item` erin wordt
  geweigerd. JSON kent geen commentaar, en commentaar is hier nuttig (waarom een waarde zo moet zijn).
- **Een lokaal bestand met alleen de verschillen.** Zo blijft het voorbeeld in de repo correct, en staan jouw
  adressen niet in de publieke repository. Het patroon `config/*.local.*` staat in `.gitignore`.
- **Alle problemen tegelijk melden.** Bij "alleen de eerste fout" moet je drie keer opnieuw starten voor drie
  fouten. Dat hoort bij het criterium *usability*.
- **Regels als data.** Een nieuwe waarde controleren is één regel toevoegen aan de lijst, zonder nieuwe
  `if`-blokken (criterium *uitbreidbaarheid*). Het alternatief, een `if` per waarde, wordt een lange,
  herhalende functie.
- **`RestartPolicy` alleen `unless-stopped` of `always`.** Volgens NexusInfra faalt een node zonder
  herstartbeleid stil: na een crash of herstart blijft hij offline. De configuratie laat je die fout dus niet
  maken, ook niet per ongeluk in een lokaal bestand.
- **Een waarschuwing voor onbekende sleutels.** `BaseUlr` in plaats van `BaseUrl` zou anders stil genegeerd
  worden: de oude waarde blijft gelden en je weet niet waarom.

## 5. PowerShell-concepten

- **`Import-PowerShellDataFile`:** https://learn.microsoft.com/powershell/module/microsoft.powershell.utility/import-powershelldatafile
- **Hashtables** (geneste tabellen, `ContainsKey`, `$t[$key]`):
  https://learn.microsoft.com/powershell/scripting/learn/deep-dives/everything-about-hashtable
- **Scriptblokken met `param()` en `&`** (een regel als data die je uitvoert):
  https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_script_blocks
- **`System.Collections.Generic.List[string]`** (een lijst waaraan je toevoegt zonder elke keer een nieuwe array te maken):
  https://learn.microsoft.com/dotnet/api/system.collections.generic.list-1
- **`-is`, `-in`, `-match`:** https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_comparison_operators
- **`Write-Warning` en `-WarningVariable`:**
  https://learn.microsoft.com/powershell/module/microsoft.powershell.utility/write-warning

## 6. Zelf proberen

```powershell
. ./src/utils/Merge-NexusHashtable.ps1
. ./src/utils/Get-NexusConfig.ps1

$config = Get-NexusConfig
$config.Agent.Image
$config.Health

# Een eigen panel: maak config/nexusinfra.local.psd1 aan
Set-Content ./config/nexusinfra.local.psd1 "@{ Api = @{ BaseUrl = 'https://panel.example.com' } }"
(Get-NexusConfig).Api          # BaseUrl is overschreven, TimeoutSeconds en RetryCount niet
Remove-Item ./config/nexusinfra.local.psd1
```

Zien hoe het faalt:

```powershell
# Meerdere fouten in één keer
Set-Content ./config/nexusinfra.local.psd1 "@{ Api = @{ BaseUrl = 'localhost' }; Agent = @{ Port = 70000; RestartPolicy = 'no' } }"
Get-NexusConfig

# Een tikfout in een sleutel: waarschuwing
Set-Content ./config/nexusinfra.local.psd1 "@{ Api = @{ BaseUlr = 'https://x' } }"
Get-NexusConfig | Out-Null

# Code in een .psd1 wordt geweigerd
Set-Content ./config/nexusinfra.local.psd1 "@{ Api = @{ BaseUrl = (Get-Date) } }"
Get-NexusConfig

Remove-Item ./config/nexusinfra.local.psd1
```

## 7. Controlevragen

1. Waarom staan de NexusInfra-waarden in een configuratiebestand en niet in de code?
2. Wat is het verschil tussen `Import-PowerShellDataFile` en het `.psd1`-bestand dot-sourcen, en waarom is dat
   belangrijk voor veiligheid?
3. Hoe werkt `Merge-NexusHashtable` voor geneste tabellen, en waarom roept de functie zichzelf aan?
4. Waarom meldt `Get-NexusConfig` alle problemen tegelijk?
5. Wat moet je doen om een nieuwe configuratiewaarde toe te voegen én te laten controleren?
