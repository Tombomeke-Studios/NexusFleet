> Uitleg gegenereerd met Claude Code als studiemateriaal. Niet mijn leerlogboek.

# Bereik: hosts achter NAT (`reach: outbound`)

## Wat het doet

Normaal belt NexusInfra de agent op een node: de orchestrator opent een verbinding naar poort 9100 van die host.
Een host achter NAT (een laptop op de school-wifi, een server thuis, 4G) heeft geen adres dat de orchestrator kan
bellen. Met `"reach": "outbound"` in de inventaris draait NexusFleet de richting om: de agent opent zelf één
verbinding naar de control plane, en NexusInfra stuurt zijn opdrachten daarover terug. Op die host staat dan geen
enkele poort open.

## Waar het staat

| Wat | Bestand |
|---|---|
| Het ontwerp (beide repo's) | `docs/agent-link.md`; de keuze in `docs/ontwerpkeuzes.md` (K11) |
| Het veld `reach` lezen | `src/public/Import-NexusInventory.ps1` |
| De instellingen | `config/nexusinfra.psd1`: `Agent.Link` en `Agent.EnvNames.Link*` |
| De features van NexusInfra onthouden | `src/public/Connect-NexusInfra.ps1` (`GET /config`) |
| De link-URL afleiden | `src/utils/Get-NexusAgentLinkUrl.ps1` |
| De preflightcheck `AgentLink` | `src/core/Invoke-NexusHostPreflight.ps1`, aangeroepen door `Test-NexusHost` en `Invoke-NexusHostInstall` |
| Registreren als outbound | `src/steps/RegisterNode.ps1` |
| De agent starten zonder open poort | `src/steps/AgentContainer.ps1` |
| Tonen in de status | `src/core/ConvertTo-NexusNodeStatus.ps1` (`Connection`, `Linked`) |
| De kant van NexusInfra | NexusInfra #416 (`fleet-support:`), zie `docs/nexusinfra-wijzigingen.md` |

## Hoe het werkt

1. **Inventaris.** `reach` is `direct` (standaard) of `outbound`. Een outbound host krijgt geen `AgentUrl`: hij wordt
   nooit op een eigen adres gebeld. Een `agentUrl` bij een outbound host wordt geweigerd, want die zou nooit gebruikt
   worden:

   ```powershell
   $agentUrl = if ($value.reach -eq 'outbound') { $null }
   elseif ($value.agentUrl) { $value.agentUrl }
   else { "http://$($value.address):$($config.Agent.Port)" }
   ```

2. **Verbinden.** `Connect-NexusInfra` vraagt ook `GET /config` en bewaart `features` op de sessie. Een NexusInfra
   met de link zegt daar `agent-link`; 0.4.0 zegt niets. Een fout bij die vraag weigert de verbinding niet: dan
   zijn er gewoon geen extra features.

3. **De link-URL.** De agent belt de gateway, dus hetzelfde adres als de API, maar als WebSocket:
   `https://nexus.voorbeeld.be` wordt `wss://nexus.voorbeeld.be/agent-link`. Bereiken de nodes de control plane
   onder een andere naam, dan zet je `Agent.Link.Url` zelf.

   ```powershell
   $base = $BaseUrl.TrimEnd('/') -replace '^http', 'ws'
   ```

4. **Preflight.** Voor een outbound host komt er een check `AgentLink` bij: ondersteunt de control plane de link,
   en kan de host zelf de host en poort van de link bereiken (`/dev/tcp`, zoals bij de broker)? Alleen een gewone
   hostnaam of een gewoon adres komt in het script, nooit iets anders.

5. **RegisterNode.** `POST /nodes` met `connection = 'outbound'` en zonder `agentUrl`. Een directe host wordt
   geregistreerd zoals vroeger, zodat NexusInfra 0.4.0 blijft werken.

6. **AgentContainer.** Voor een outbound host:
   - eerst `POST /nodes/<id>/link-token`: NexusInfra maakt een nieuw token **voor deze ene node** en geeft het één
     keer terug;
   - dat token gaat als derde regel over stdin naar de host, net als de twee andere geheimen, en zo in het
     env-bestand (mode 600);
   - in het env-bestand komen `AGENT_LINK_URL` en `AGENT_LINK_TOKEN`, en geen `AGENT_URL`;
   - `docker run` krijgt geen `-p 9100:9100`: er staat niets open.

   De Test van de stap controleert omgekeerd dat er **geen** poort gepubliceerd is, en dat `AGENT_LINK_URL` klopt.
   Een `ws://`-link (zonder TLS) wordt geweigerd, behalve met `Api.AllowUnencryptedHttp` in een lab.

7. **VerifyHealthy en AgentReachable** veranderen niet. `GET /nodes/<id>/disk` gaat bij een outbound node gewoon
   over de link: dezelfde stap bewijst dus voor beide manieren dat NexusInfra de node kan besturen.

8. **Status.** `Get-NexusFleetStatus` toont `Connection` en, voor outbound, `Linked`. Een outbound node die
   *healthy* is maar geen link heeft, krijgt een probleem: NexusInfra hoort hem, maar kan hem niets sturen.

## Waarom zo

- **De agent verbindt zelf, en niet een VPN:** met een VPN moet elke node eerst in een privénetwerk, en dat sluit het
  voorstel uit. Een verbinding die de agent zelf opent, werkt overal waar de node naar buiten mag.
- **Niet een SSH-tunnel vanuit NexusFleet (voor NexusInfra):** die werkt voor elk platform, maar vraagt een sshd op
  de control plane en een tunnel-account per node, en past slecht op een netwerk dat alleen 443 doorlaat. NexusInfra
  kunnen we zelf aanpassen, dus daar is een link die de agent zelf opent netter. De tunnel blijft een plan voor
  andere platformen (de extra over connectors).
- **Een eigen token per node, niet het gedeelde `INTERNAL_API_TOKEN`:** met het gedeelde token kan één node een link
  openen als een andere node, en dan krijgt hij de bestanden en commando's van die andere node. Met een token per
  node kan dat niet, en je kunt het token van één node intrekken.
- **Een directe host blijft precies zoals hij was:** zo werkt NexusFleet ook met een NexusInfra zonder de link.

## PowerShell-concepten

- **`BeforeDiscovery`** (Pester): code die draait vóór Pester de tests vindt. De outbound-integratietest vraagt daar of
  de control plane de link kent, en een gewone `if` bepaalt dan welke `Context` er bestaat. Zo wordt er nooit een test
  overgeslagen terwijl het lab draait. [Pester: Discovery and Run](https://pester.dev/docs/usage/discovery-and-run)

- **`-replace` met een reguliere expressie** (`'^http'`): `^` betekent "aan het begin", dus alleen `http` vooraan
  wordt `ws`, en `https` wordt vanzelf `wss`.
  [about_Comparison_Operators](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_comparison_operators#replacement-operator)
- **`[uri]`**: maakt van een tekst een adres met delen (`DnsSafeHost`, `Port`); de poort staat er ook als je hem
  niet schreef (443 voor `wss`).
  [System.Uri](https://learn.microsoft.com/dotnet/api/system.uri)
- **Splatting met een lege hashtable** (`@link`): zonder outbound host is `$link` leeg en krijgt de functie geen extra
  parameters. [about_Splatting](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_splatting)
- **`[System.Net.NetworkCredential]::new('', $tekst).SecurePassword`**: maakt een SecureString van tekst die al in
  het geheugen staat (het token uit het API-antwoord).
  [NetworkCredential](https://learn.microsoft.com/dotnet/api/system.net.networkcredential)
- **`Add-Member -NotePropertyName`** in de tests: een eigenschap toevoegen aan een object (`Reach`) zonder het
  helemaal opnieuw te maken.
  [Add-Member](https://learn.microsoft.com/powershell/module/microsoft.powershell.utility/add-member)

## Zelf proberen

```powershell
Import-Module ./NexusFleet.psd1 -Force

# Een inventaris met één outbound host lezen: Reach is outbound, AgentUrl leeg.
Import-NexusInventory -Path ./config/inventory.example.json | Format-Table Name, Reach, AgentUrl

# De link-URL die een outbound agent zou bellen.
& (Get-Module NexusFleet) { Get-NexusAgentLinkUrl -Link @{ Url = ''; Path = '/agent-link' } -BaseUrl 'https://nexus.voorbeeld.be' }

# De tests van dit onderwerp.
Invoke-Pester -Path ./tests/steps/AgentContainer.Tests.ps1, ./tests/core/Invoke-NexusHostInstall.Tests.ps1 -Output Detailed
```

In het node-lab is `node3` (ssh `127.0.0.1:2233`) zo'n outbound host. Met de integratietest zie je beide kanten:
tegen NexusInfra 0.4.0 weigert `Test-NexusHost` hem bij `AgentLink`; tegen een NexusInfra met de link wordt hij een
*healthy* node zonder open poort. De test kiest zelf welk deel hij draait, door vóór de tests `GET /config` te vragen.

```powershell
./lab/node-lab/Start-NodeLab.ps1
Invoke-Pester -Path ./tests/public/Install-NexusNode.Outbound.Integration.Tests.ps1 -TagFilter Integration -Output Detailed
```

Zien falen: zet bij een host in je inventaris zowel `"reach": "outbound"` als een `agentUrl`; `Import-NexusInventory`
weigert dat. Of verbind met een NexusInfra 0.4.0 en test een outbound host: `Test-NexusHost` faalt bij `AgentLink`.

## Controlevragen

1. Waarom wordt een host achter NAT wel *healthy*, maar kan NexusInfra er niets op doen zonder de link?
2. Waarom krijgt elke node een eigen link-token, en wat zou er mis kunnen gaan met het gedeelde `INTERNAL_API_TOKEN`?
3. Waarom controleert de Test van `AgentContainer` bij een outbound host dat er géén poort gepubliceerd is?
4. Welke verbinding heeft een outbound node nog altijd nodig naast de link, en wat betekent dat op een netwerk dat
   alleen 443 doorlaat?
5. Waarom hoeft `AgentReachable` niet te veranderen voor outbound hosts?
