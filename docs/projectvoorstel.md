# NexusFleet

Projectvoorstel van Tom Dekoning · System Automation & Scripting · Toegepaste Informatica, EhB

PowerShell 7 · Externe tools: NexusInfra (REST-API), Docker, OpenSSH, RabbitMQ, Caddy

---

## Het probleem en waarom ik het oplos

Honderd Linux-servers toevoegen aan een beheerpaneel is met de hand dagen werk vol kleine fouten. **NexusFleet** maakt er één PowerShell-pipeline van: controleren, installeren, koppelen, bewaken en in bulk aansturen.

NexusInfra is mijn self-hosted serverpanel (TypeScript, dashboard, REST-API) dat containers op meerdere hosts beheert. Het begint pas te werken nadat een machine een node is geworden. Dat toevoegen gebeurt nu met de hand: Docker installeren, een agent-container starten met de juiste variabelen, de toegang beveiligen en nakijken of het werkt. Drie van die opties falen stil als je ze vergeet. Voor één machine is dat lastig, voor tien foutgevoelig, voor honderd onhaalbaar, en na een paar maanden weet niemand nog hoe elke node precies is opgezet.

**Waarom PowerShell:** dit is typisch infrastructuurwerk. Het gaat om veel hosts, om dezelfde stappen, om foutafhandeling per host, en om een bestaande REST-API die al voor scripts bedoeld is. Het resultaat is een tool die ik nodig heb om NexusInfra bruikbaar te maken buiten één privénetwerk, en die elke beheerder met een vloot servers kan gebruiken.

**Demo:** één commando zet 3 tot 5 verse Ubuntu-VM's (laptop en thuis, over het internet) om tot nodes die live op het dashboard verschijnen.

## Analyse van de bestaande infrastructuur

NexusInfra bestaat uit een **orchestrator** (REST-API en planning), een **gateway** (eerste controle van aanmeldingen), een **node agent** op elke host die Docker aanstuurt, en een **RabbitMQ-bus** waarover ze berichten uitwisselen. Een node komt in het systeem doordat zijn agent, gestart met een eigen `NODE_ID`, heartbeats over de bus stuurt. Tot dan staat hij als *offline*. Voor directe oproepen (bestanden, commando's, logs, terminal, backups) belt de orchestrator rechtstreeks naar het `agentUrl` van die node, met een gedeeld intern token.

Ik heb de documentatie en de broncode doorgenomen (branch `dev`, versie 0.4.0). Dit zijn de bevindingen die het ontwerp bepalen:

| Bevinding | Gevolg voor NexusFleet |
|---|---|
| Een node bestaat pas als zijn agent heartbeats stuurt. `POST /nodes` en "New node" in het dashboard schrijven enkel een record (naam, locatie, `agentUrl`) | `Install-NexusNode` is pas klaar als de node *healthy* is; de module controleert dat via `GET /nodes` |
| Een node is *degraded* na 3 seconden zonder heartbeat en *offline* na 10 seconden | De verificatiestap heeft een time-out en een peilinterval die daarbij passen |
| De agent luistert via gewone HTTP, zonder TLS, en zijn endpoints sturen Docker rechtstreeks aan (commando's, bestanden, shell) achter één token | De toegang tot poort 9100 moet beperkt worden; de beveiligingsstappen zijn daarom een extra bovenop de MVP |
| Orchestrator en alle agents delen één `INTERNAL_API_TOKEN` | Geheimen gaan nooit via de commandoregel of in logs |
| De agent verbindt met de broker zonder TLS-opties, en `guest/guest` is de standaard | Een eigen broker-gebruiker per node en `amqps://` zijn de logische extra stappen |
| De orchestrator gebruikt het `agentUrl` van een node zoals het is, dus ook `https://` | Een TLS-toegangspoort voor de agent kan zonder codewijziging in NexusInfra |
| Er is geen script of tool die een host tot node maakt | Dat is precies wat NexusFleet toevoegt |

## SWOT-analyse

| | Positief | Negatief |
|---|---|---|
| **Intern** | **Sterktes**<br>• Een echt, werkend platform met een REST-API en API-tokens die voor scripts bedoeld zijn<br>• Ik ken NexusInfra en kan het zelf aanpassen waar de module dat nodig heeft<br>• Een concreet, meetbaar probleem: de handmatige onboarding | **Zwaktes**<br>• Node-onboarding is nu handwerk en foutgevoelig<br>• De agent spreekt standaard geen TLS en alle agents delen één token<br>• SSH vanuit PowerShell, runspaces en Pester met mocks zijn nieuw voor mij<br>• `Install-NexusNode` bundelt veel stappen en kan groter uitvallen dan gepland |
| **Extern** | **Kansen**<br>• Automatisering maakt schalen naar tientallen en honderden nodes haalbaar<br>• Extra's zoals drift detection en rolling onderhoud maken van onboarding een volledig beheerhulpmiddel<br>• Met connectoren kan NexusFleet ook andere platformen dan NexusInfra aansturen | **Bedreigingen**<br>• Nodes bij externe partijen vergroten het aanvalsoppervlak<br>• Een fout in een bulkactie raakt snel veel servers<br>• Thuis-VM's hebben geen publiek IP<br>• Een wijziging in NexusInfra kan de module breken |

**Wat ik met de SWOT doe:**

- Zwakte *handwerk* is het probleem dat de MVP oplost.
- Bedreiging *bulkfouten*: dry run (`-WhatIf`), begrensde parallelle uitvoering en een resultaat per host.
- Bedreiging *aanvalsoppervlak* en zwakte *geen TLS*: de beveiligingsstappen komen als extra stappen bovenop de MVP.
- Zwakte *te grote cmdlet*: `Install-NexusNode` is opgebouwd uit kleine, afzonderlijke stappen.
- Zwakte *nieuwe kennis*: een leerlogboek en tests per onderdeel.
- Bedreiging *wijzigingen in NexusInfra*: de module gaat enkel via de REST-API en heeft tests met mocks die onafhankelijk van NexusInfra draaien.

## Wat is nieuw voor dit vak en wat bestond al

NexusFleet komt in een **aparte repository**. Enkel die PowerShell-module wordt beoordeeld.

| Onderdeel | Bestond al in NexusInfra | Nieuw voor dit vak (NexusFleet) |
|---|---|---|
| Node toevoegen | Beschreven als handmatige `docker run` in `docs/images.md` (sectie "Adding a machine"). "New node" in het dashboard en `POST /nodes` registreren enkel naam en locatie; de agent op de host start je zelf. Er is geen script of tool die een host tot node maakt | De volledige onboarding in PowerShell: controleren, Docker, agent, registreren, verifiëren, terugdraaien |
| Hosts controleren | Niets | `Test-NexusHost`: parallelle preflight per host |
| Inventaris | Niets | `Import-NexusInventory`: inlezen en valideren van een hostlijst |
| Status van de vloot | Dashboard, `GET /nodes` en `nexusctl nodes list` (TypeScript-CLI, toont enkel de lijst) | `Get-NexusFleetStatus`: API en hostgegevens samenvoegen, exporteren, offline hosts opvangen |
| Bulkacties | `POST /deployments/bulk` bestaat in de API | Aansturing per host vanuit PowerShell met dry run en resultaat per host (extra) |
| Logging en dry run | Niets voor de onboarding | Eigen logger en `-WhatIf` voor alle cmdlets |
| Installatie van de controlekant | `deploy/install.sh` en `deploy/install.ps1`: kiezen van een editie, geheimen genereren, `.env` schrijven, de stack starten. Enkel voor de controlekant, niet voor nodes | Blijft in NexusInfra, wordt niet herschreven en niet beoordeeld |

**Peilpunt in NexusInfra:** de stand van NexusInfra voor dit vak is vastgelegd met de git-tag `nexusfleet-baseline` (versie 0.4.0). Alles wat in NexusInfra sinds die tag verandert, is zichtbaar met `git diff nexusfleet-baseline..HEAD`. De bestaande automatisering (de installatiescripts van de controlekant) blijft ongewijzigd en telt niet mee.

**Aanpassingen in NexusInfra** die de module nodig heeft, maak ik in de NexusInfra-repository, in aparte commits met het voorvoegsel `fleet-support:`. In de NexusFleet-repository houd ik ze bij in `docs/nexusinfra-wijzigingen.md`. Die code wordt niet beoordeeld; de tag en de lijst maken de scheiding zichtbaar.

**Final Work:** NexusInfra gebruik ik later ook voor mijn Final Work, met een eigen tag (`final-work-baseline`). Dat is een apart werkstuk. NexusFleet zit niet in het Final Work, en de scheidingslijn leg ik ook vast met mijn Final Work-begeleider.

## De MVP (het minimum)

| Cmdlet | Taak |
|---|---|
| `Connect-NexusInfra` | Verbinden met het panel via een API-token |
| `Import-NexusInventory` | JSON-lijst van doelhosts inlezen en valideren |
| `Test-NexusHost` | Parallelle controle per host: bereikbaar, SSH, OS, schijfruimte, Docker |
| `Install-NexusNode` | Host idempotent tot node maken en registreren; draait terug bij falen |
| `Get-NexusFleetStatus` | Status van alle nodes ophalen en exporteren; offline hosts breken niets af |

- **Dry run:** `-WhatIf` toont per host wat er zou gebeuren, zonder iets te wijzigen.
- **Logging:** elke uitvoering schrijft per host en per stap een leesbaar logbestand, zonder geheimen, zodat je achteraf kunt nagaan wat er gebeurd is.
- **Geen vaste waarden:** alles wat specifiek is voor NexusInfra (adressen, agent-image, omgevingsvariabelen, poorten) staat in configuratie, niet in de code.
- **Kwaliteit:** Pester-tests, `Get-Help` op elke functie, PSScriptAnalyzer zonder waarschuwingen, README, leerlogboek.

**Klaar als:** één commando de VM's tot *healthy* nodes maakt, een tweede uitvoering niets wijzigt, en één mislukte host de rest niet stopt.

## Extra's

Pas na de MVP. De eerste drie zijn de extra's die ik zeker wil realiseren:

| Extra | Wat en waarom |
|---|---|
| Bulkacties en uitschrijven | `Invoke-NexusFleetAction` start, stopt of herstart groepen servers in één keer, `Remove-NexusNode` schrijft een node netjes uit en ruimt op. Zo beheer je de vloot en niet alleen de onboarding. |
| Drift detection | `Sync-NexusFleet` vergelijkt een gewenste staat (JSON) met de werkelijkheid en herstelt afwijkingen. Dit lost het probleem van nodes op die langzaam uit elkaar groeien. |
| Rolling onderhoud | Per node: in onderhoud zetten, servers verplaatsen, agent upgraden, terugzetten, en stoppen zodra er iets misloopt. Zo upgrade je een vloot zonder downtime. |
| Connectoren voor andere platformen | Op voorstel van de docent: NexusFleet ook een ander platform dan NexusInfra laten aansturen. Alles wat specifiek is voor NexusInfra (verbinden, node registreren, status ophalen, node verwijderen, en de waarden van de agent zoals image, omgevingsvariabelen en poorten) komt achter een connector met een vast contract. NexusInfra blijft de hoofdconnector; een ander platform aansluiten is een nieuwe connector schrijven, niet de module herschrijven. Hetzelfde model gebruikt SecretManagement: één module met vaste cmdlets, en per achterliggend systeem een aparte extensie. Dat andere tools NexusFleet zelf kunnen aanroepen, volgt al uit de opbouw: objecten als uitvoer, alles via parameters, niets interactief en publicatie als module. |
| Beveiligde verbinding | Extra stappen voor nodes bij externe partijen: Caddy als enige toegang met IP-allowlist, een eigen intrekbare broker-gebruiker per node, TLS en `amqps://`. |
| Backups | `Backup-NexusFleet` orkestreert backups over alle nodes en controleert de retentie. |
| Publicatie | CI met publicatie op de PowerShell Gallery. |

## Hoe het werkt

De module praat met NexusInfra via de REST-API en met de servers via SSH. `Install-NexusNode` werkt een lijst van stappen af per host: controleren, Docker installeren indien nodig, agent starten, node registreren en wachten tot hij *healthy* is. Elke stap kan zichzelf controleren, uitvoeren en terugdraaien. Gaat er iets mis, dan draait alles van die host terug.

Voor de verbinding over het internet kies ik geen VPN, want dan moet elke nieuwe node eerst in een VPN. In de MVP bereikt de orchestrator de agent rechtstreeks en gaan geheimen nooit via de commandoregel. De extra beveiliging (Caddy als enige toegang met IP-allowlist, een eigen broker-gebruiker per node, TLS) komt als extra stappen bovenop dezelfde opbouw.

Ik onderzoek en test per keuze: SSH vanuit PowerShell (`ssh`, PowerShell-remoting of Posh-SSH), parallel werken (`ForEach-Object -Parallel` tegenover jobs), de toegangspoort, certificaten, Docker en firewalls, en geheimenbeheer.

## Opbouw

De module is opgesplitst in kleine onderdelen met elk één taak. Een onderdeel toevoegen, vervangen of weglaten raakt de rest niet: `Install-NexusNode` leest de stappen uit een map, het contact met servers zit achter één interface, en inventaris, rollen en de waarden van NexusInfra staan in configuratie.

```
NexusFleet/
├─ NexusFleet.psd1 / NexusFleet.psm1
├─ src/
│  ├─ core/        contracten: stap (controleren, uitvoeren, terugdraaien) en transport
│  ├─ steps/       Docker, agent, registreren, verifiëren (+ later beveiliging)
│  ├─ transports/  SSH (een ander transport is een ander bestand)
│  ├─ api/         REST-client voor NexusInfra
│  ├─ public/      de cmdlets
│  └─ utils/       Logger
├─ config/         voorbeeldinventaris en rollen
├─ docs/           leerlogboek, nexusinfra-wijzigingen.md
├─ tests/          spiegelt src/
└─ README.md
```

Het ontwerp volgt dezelfde lijn als goede werkstukken uit vorige jaren: een contract in `core`, uitwisselbare onderdelen ernaast, een eigen logger en tests die de bronstructuur volgen.

## Argumentatie per onderdeel

| Onderdeel | Argument |
|---|---|
| Analyse | Het probleem komt uit een eigen, werkend platform. Ik heb de documentatie en broncode van NexusInfra doorgenomen om te begrijpen hoe een node in het systeem komt en waar de handmatige onboarding faalt (stille opties, gedeelde geheimen, geen TLS). Dat staat in de analyse van de infrastructuur en de SWOT hierboven, en elke bevinding heeft een gevolg voor het ontwerp. Daarnaast meet ik de handmatige tegenover de geautomatiseerde procedure. |
| Design | Elke keuze onderzoek en test ik: remoting, parallellisme, toegangspoort, firewall, geheimenbeheer. De beveiliging zit in de onboarding zelf, zonder VPN en zonder het platform te herschrijven. |
| Kennisverwerving | Nieuw voor mij: SSH vanuit PowerShell, runspaces en hun valkuilen, Pester v5 met mocks, PowerShell-klassen, SecretManagement, reverse proxies en RabbitMQ-gebruikersbeheer. Het leerlogboek toont per onderwerp wat ik verwachtte, probeerde en leerde. |
| Usability | Gemaakt voor systeembeheerders: `Get-Help` met voorbeelden, dry run met `-WhatIf`, voortgang, duidelijke fouten per host, en logs om het verloop na te gaan. |
| Robuustheid | Parameter-validatie, preflight vóór zware acties, time-outs, resultaat per host zodat één mislukte host de rest niet blokkeert, idempotentie en terugdraaien bij een halve installatie. |
| Uitbreidbaarheid | Elke installatiestap, het transport, de API-laag en de configuratie zijn aparte onderdelen met een vast contract. Een stap toevoegen, vervangen of weglaten is een bestand toevoegen, vervangen of verwijderen, en de extra's (beveiliging, onderhoud, backups) zijn gewoon extra stappen en cmdlets op dezelfde basis. Omdat de waarden van NexusInfra in configuratie staan en niet in de code, kan NexusInfra later achter een connector komen en kan een ander platform aansluiten (extra). |
| Best practices | Goedgekeurde werkwoorden, pipeline met objecten in plaats van tekst, comment-based help, PSScriptAnalyzer zonder waarschuwingen, een vaste mappenstructuur met één verantwoordelijkheid per bestand, en tests die de bronstructuur spiegelen. |
| Testing | Pester met mocks, zonder servers, elk onderdeel apart getest. Het ontwerp is gebouwd voor honderden hosts: begrensde parallelle uitvoering, geen gedeelde status tussen hosts, een time-out per host en veilig opnieuw uit te voeren. Gesimuleerde inventarissen van 50 tot 100 hosts, waarvan enkele offline of falend, controleren dat dit klopt. CI draait de tests bij elke push. |

## Onzekerheden

- Voor de beveiligingsextra: of de orchestrator een eigen certificaatautoriteit vertrouwt; zo niet, dan blijft TLS achterwege.
- Voor dezelfde extra: welke broker-rechten een agent minimaal nodig heeft en of een firewallregel een Docker-poort echt afschermt. Beide test ik in de praktijk.
- Thuis-VM's hebben geen publiek IP; ik los dat op met port-forwarding of een goedkope VPS.

## Referenties

- Microsoft Learn, *PowerShell remoting over SSH*: https://learn.microsoft.com/powershell/scripting/security/remoting/ssh-remoting-in-powershell
- Microsoft Learn, *ForEach-Object (-Parallel)*: https://learn.microsoft.com/powershell/module/microsoft.powershell.core/foreach-object
- Microsoft Learn, *Everything you wanted to know about ShouldProcess*: https://learn.microsoft.com/powershell/scripting/learn/deep-dives/everything-about-shouldprocess
- Microsoft Learn, *Approved verbs for PowerShell commands*: https://learn.microsoft.com/powershell/scripting/developer/cmdlet/approved-verbs-for-windows-powershell-commands
- Microsoft Learn, *PSScriptAnalyzer*: https://learn.microsoft.com/powershell/utility-modules/psscriptanalyzer/overview
- Microsoft Learn, *SecretManagement*: https://learn.microsoft.com/powershell/utility-modules/secretmanagement/overview
- Pester, documentatie: https://pester.dev/docs/quick-start
- RabbitMQ, *TLS support*: https://www.rabbitmq.com/docs/ssl
- RabbitMQ, *Access control*: https://www.rabbitmq.com/docs/access-control
- RabbitMQ, *Management HTTP API*: https://www.rabbitmq.com/docs/management
- Docker, *Install Docker Engine on Ubuntu*: https://docs.docker.com/engine/install/ubuntu/
- Docker, *Packet filtering and firewalls*: https://docs.docker.com/engine/network/packet-filtering-firewalls/
- Caddy, documentatie: https://caddyserver.com/docs/
- Node.js, `NODE_EXTRA_CA_CERTS`: https://nodejs.org/api/cli.html
- NexusInfra, eigen documentatie en broncode (`docs/security.md`, `docs/images.md`, `docs/deployment.md`, `docs/api.md`, services `node-agent` en `orchestrator`), repository `Tombomeke-Studios/NexusInfra`, branch `dev`, geraadpleegd op 22 oktober 2026
