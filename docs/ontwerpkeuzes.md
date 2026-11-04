# NexusFleet — Ontwerpkeuzes

Per keuze: de vraag, de opties die bekeken of uitgetest zijn, het resultaat, wat weerhouden werd en waarom.
De experimenten E1–E4 (fase 1) bepalen keuzes waar de code van afhangt; hun resultaten vult Tom in.

Format per keuze:

- **Vraag** — wat er beslist moest worden
- **Opties** — wat bekeken of uitgetest werd
- **Resultaat** — metingen of observaties
- **Keuze** — wat weerhouden werd, en waarom
- **Gevolg** — wat dit betekent voor de code

---

## Experimenten (fase 1)

### E1 — Transport: `ssh`, PowerShell-remoting over SSH of Posh-SSH

- **Vraag:** hoe voert NexusFleet commando's uit op een Linux-host?
- **Opzet:** `lab/E1-transport/`. Twee Docker-containers als stand-in voor een verse Ubuntu 24.04-VM: OpenSSH,
  een gebruiker `fleet` die alleen met een sleutel inlogt en zonder wachtwoord `sudo` mag
  (`Start-LabTarget.ps1`). De tweede container heeft ook PowerShell en het `powershell`-subsystem in sshd,
  nodig voor remoting. `Measure-Transport.ps1` meet per transport. Controlemachine: Windows 10, PowerShell 7.6.9,
  OpenSSH-client van Windows, Posh-SSH 4.0.0. Een echte VM volgt in E0 (#14).
- **Wat er nodig is:**

  | | Op de controlemachine | Op elke host |
  |---|---|---|
  | `ssh` | OpenSSH-client (standaard in Windows 10+, Linux, macOS) | niets extra |
  | PowerShell-remoting | niets extra | **PowerShell installeren** (Microsoft-repository, image +87 MB) en sshd aanpassen |
  | Posh-SSH | externe module (Posh-SSH, op SSH.NET) | niets extra |

- **Resultaat** (verbinding via `127.0.0.1`):

  | Test | `ssh` | PowerShell-remoting | Posh-SSH |
  |---|---|---|---|
  | Verbinden | 0,21 s (één volledige oproep) | 0,46 s | 0,23 s |
  | Per commando (10×) | 0,20 s (telkens nieuwe verbinding) | 0,09 s (sessie hergebruikt) | 0,07 s (sessie hergebruikt) |
  | Exitcode `exit 7` | `$LASTEXITCODE` = 7 | 7, als object terug | `ExitStatus` = 7 |
  | Geheim via stdin | ja, als `byte[]` (zie hieronder) | als argument, versleuteld naar de host | **geen stdin** bij `Invoke-SSHCommand` |
  | Verkeerde sleutel | exit 255 na 0,21 s, geen prompt | fout na 0,17 s | fout na 0,19 s |
  | Onbereikbaar (time-out 5 s) | exit 255 na 5,1 s | fout na 5,1 s | fout na 5,1 s |

- **Twee valkuilen gevonden:**
  1. **`localhost` kost 2 s per verbinding** op deze Windows-machine: eerst wordt IPv6 (`::1`) geprobeerd,
     terwijl de lab-poorten alleen op IPv4 luisteren. Met `127.0.0.1` 0,2 s. Geldt voor het lab, niet voor
     echte hosts, maar het verklaart trage verbindingen bij een hostnaam die naar IPv6 én IPv4 wijst.
  2. **Een string die je in PowerShell naar `ssh` pijpt, krijgt `\r\n` erachter op Windows.** Een geheim komt
     aan als `...E1\r`: één onzichtbaar teken te veel, dus een token zou niet werken. Opgelost door **bytes** te
     pijpen (`[Text.Encoding]::UTF8.GetBytes($secret) | ssh ...`): dan komen exact die bytes aan. Dat kan sinds
     PowerShell 7.4 (`PSNativeCommandPreserveBytePipe`). Alternatief dat ook op 7.2 werkt: de `\r` op de host
     wegknippen (`s=${s%$'\r'}`).
- **Voorstel (Claude Code, door Tom te bevestigen):** native `ssh`.
  - Niets te installeren op de hosts (PowerShell-remoting vraagt PowerShell op élke host: een extra
    installatiestap bij de onboarding en meer aanvalsoppervlak) en geen externe module (Posh-SSH).
  - Geheimen gaan via stdin, en dat lukt alleen met `ssh` en remoting; Posh-SSH zou ze op de commandoregel of
    in een bestand moeten zetten.
  - Exitcodes en fouten zijn duidelijk, en met `BatchMode=yes` hangt er nooit een prompt.
  - Nadeel: een nieuwe verbinding per commando (0,2 s). Met een paar commando's per stap en parallelle
    hosts (E2) is dat klein. Kan later met minder, grotere scripts per oproep.
- **Gevolg:** `Invoke-NexusHostCommand` roept `ssh` aan met `BatchMode=yes`, `ConnectTimeout`, een eigen
  `UserKnownHostsFile`-keuze en `StrictHostKeyChecking=accept-new`; geheimen gaan als `byte[]` naar stdin.
  Minimumversie: 7.6 (keuze K4), dus de byte-pijp is altijd beschikbaar.

### E2 — Parallel werken: `ForEach-Object -Parallel`, `Start-ThreadJob` of `Start-Job`

- **Vraag:** welke manier van parallel werken gebruikt NexusFleet om veel hosts tegelijk te behandelen?
- **Opzet:** `lab/E2-concurrency/Measure-Concurrency.ps1`. Per host gesimuleerd werk: 0,5 s wachten (staat voor
  SSH) en een kleine rekenlus. Elke meting draait in een nieuw `pwsh`-proces; mediaan van 3 rondes;
  `ThrottleLimit` 10. Machine: 16 logische CPU's, PowerShell 7.6.9, Windows 10.
- **Resultaat:**

  | Methode | 10 hosts | 50 hosts | Geheugen bij 50 hosts |
  |---|---|---|---|
  | Na elkaar (referentie) | 5,25 s | 26,02 s | 99 MB |
  | `ForEach-Object -Parallel` | **0,71 s** | **2,89 s** | **124 MB** |
  | `Start-ThreadJob` | 0,89 s | 3,36 s | 173 MB |
  | `Start-Job` | 2,69 s | 9,57 s | 464 MB* |

  Het theoretische minimum voor 50 hosts is 50 / 10 × 0,5 s = 2,5 s. `-Parallel` zit daar dicht bij.
  `Start-Job` start voor elke job een volledig nieuw `pwsh`-proces: dat opstarten domineert de tijd, en er
  is geen `-ThrottleLimit`.

  \* Gemeten door elke 100 ms de werkgeheugens van de kindprocessen op te tellen. Omdat de jobs na elkaar
  opstarten en snel klaar zijn, leven er maar een paar tegelijk; bij langer werk per host loopt dit verder op
  (ongeveer 60–70 MB per proces).
- **Voorstel (Claude Code, door Tom te bevestigen):** `ForEach-Object -Parallel` met `-ThrottleLimit` uit een
  parameter. Het snelst, het minst geheugen, ingebouwd, en de uitvoer komt gewoon door de pijplijn.
  `Start-ThreadJob` is een redelijk alternatief (job-objecten, dus later opvragen), maar trager en zwaarder
  zonder dat NexusFleet de jobfuncties nodig heeft. `Start-Job` valt af.
- **Gevolg:** de patronen uit CLAUDE.md sectie 8 gelden: variabelen via `$using:`, de module per runspace
  importeren, en `ShouldProcess` beslissen vóór de parallelle lus. Het werk per host zit in een eigen functie
  (E3).

### E3 — Pester-mocks en `-Parallel`-runspaces

- **Vraag:** werkt een Pester-`Mock` ook voor code die in `ForEach-Object -Parallel` draait? En lost het
  patroon "het werk voor één host in een eigen functie" dat op?
- **Opzet:** `lab/E3-mocks-parallel/`. Een mini-module `FleetDemo.psm1` met dezelfde opbouw als NexusFleet:
  `Get-DemoAnswer` (staat voor SSH of de API, wordt gemockt), `Invoke-DemoHostWork` (het werk voor één host),
  en twee dunne wrappers: een gewone lus en een `ForEach-Object -Parallel` die de module per runspace
  importeert. Uitvoeren: `Invoke-Pester -Path ./lab/E3-mocks-parallel -Output Detailed`.
- **Resultaat** (3 van 3 tests slagen, Pester 5.7.1, PowerShell 7.6):

  | Hoe aangeroepen | Uitkomst | Mock-oproepen geteld |
  |---|---|---|
  | `Invoke-DemoHostWork` rechtstreeks | `mock:host1` | 1 |
  | Gewone lus (`ForEach-Object`) | `mock:host1`, `mock:host2` | 2 |
  | `ForEach-Object -Parallel` | `real:host1`, `real:host2`, `real:host3` | **0** |

  In `-Parallel` draait de **echte** functie. Elke runspace is een nieuwe, lege omgeving die de module opnieuw
  importeert; de mock bestaat alleen in de runspace van de test.
- **Voorstel (Claude Code, door Tom te bevestigen):** het patroon uit CLAUDE.md houden. Het werk voor één host
  staat altijd in een eigen functie die rechtstreeks getest wordt met mocks; de parallelle lus is een dunne
  wrapper zonder logica. Die wrapper test je met een echte, onschuldige uitvoering (zoals hier) of in een
  integratietest.
- **Gevolg:** in `Test-NexusHost`, `Install-NexusNode` en `Get-NexusFleetStatus` komt de logica per host in
  een aparte functie (bijv. `Test-NexusHostSingle`); unit tests mocken nooit iets "door" een `-Parallel` heen.

### E4 — Scopes van het API-token

- **Vraag:** welke rechten heeft het API-token van NexusFleet nodig voor `POST /nodes`,
  `PATCH /nodes/:id/maintenance` en `DELETE /nodes/:id`?
- **Opzet:** broncode van de orchestrator gelezen in de lokale NexusInfra-clone (branch `dev`, tag
  `nexusfleet-baseline` aanwezig): `services/orchestrator/src/api.ts`, `auth.ts`, `apiTokens.ts`, en de eigen
  tests van NexusInfra (`api.test.ts`, `auth.test.ts`). Notities in `lab/E4-token-scopes/README.md`.
- **Resultaat:** twee controles, die allebei moeten slagen:
  1. *Methode-controle* (`requireAuth` → `scopeAllowsMethod`): `GET`/`HEAD`/`OPTIONS` mag elk token; elke
     andere methode vraagt scope **`write`**.
  2. *Beheerroutes* (`requirePlatformAdmin`): het **account** moet `platformRole` `admin` of `owner` hebben,
     en een token moet daarbovenop scope **`admin`** hebben ("this API token does not have the admin scope").

  | Route | Account | Token-scopes |
  |---|---|---|
  | `GET /nodes` | elk aangemeld account | geen extra |
  | `POST /nodes` | admin of owner | `write` + `admin` |
  | `PATCH /nodes/:id/maintenance` | admin of owner | `write` + `admin` |
  | `DELETE /nodes/:id` | admin of owner | `write` + `admin` (`409` zolang er een deployment draait) |

  Verder: een token kan geen nieuw token aanmaken (`POST /me/tokens` → `403`), en een token valt niet onder de
  verplichte 2FA-inschrijving (`requireTotpEnrolment` laat `principal.tokenId` door).
- **Wat `Connect-NexusInfra` vooraf kan controleren:** `GET /me` geeft het account terug met `platformRole`,
  maar **niet** de scopes van het token. De `admin`-scope kan wel zonder bijwerkingen getest worden met
  `GET /users` (een leesroute achter `requirePlatformAdmin`: `200` met de scope, `403` zonder). De
  `write`-scope kan niet zonder iets te wijzigen getest worden.
- **Voorstel (Claude Code, door Tom te bevestigen):** NexusFleet vraagt een token met scopes `write` en `admin`
  van een platformbeheerder. `Connect-NexusInfra` controleert `platformRole` via `GET /me` en de `admin`-scope
  via `GET /users`, en geeft meteen een duidelijke fout in plaats van pas bij `POST /nodes` een `403`. Een
  ontbrekende `write`-scope vangt `Invoke-NexusApi` op bij de eerste wijzigende oproep (`403` → duidelijke
  fout). Mogelijke kleine NexusInfra-wijziging voor later: de scopes van het huidige token in `GET /me`
  teruggeven (`fleet-support:`, alleen na overleg met Tom).
- **Live bevestigd (2026-11-04, #21)** tegen het node-lab (`lab/node-lab/`, NexusInfra `0.4.0-qa-community`), met
  een token per combinatie van scopes van het lab-account (rol `owner`). Gemeten HTTP-statussen:

  | Scopes | `GET /nodes` | `GET /users` | `POST /nodes` | `PATCH /nodes/:id/maintenance` | `DELETE /nodes/:id` |
  |---|---|---|---|---|---|
  | geen | 200 | 403 | 403 | 403 | 403 |
  | `write` | 200 | 403 | 403 | 403 | 403 |
  | `admin` | 200 | 200 | 403 | 403 | 403 |
  | `write` + `admin` | 200 | 200 | 201 | 200 | 204 |

  Dat is precies wat de broncode zei: de drie wijzigende node-routes vragen `write` **en** `admin`, en `GET /users`
  test de `admin`-scope zonder iets te wijzigen. `Connect-NexusInfra` en `Install-NexusNode` werken met zo'n token
  end-to-end in het lab (`tests/public/Install-NexusNode.Integration.Tests.ps1`).

---

## Keuzes tijdens de opbouw (fase 0)

### K1 — Pester 5.x vastpinnen

- **Vraag:** welke Pester-versie gebruiken lokaal en in de CI?
- **Opties:** de nieuwste (`-MinimumVersion 5.0`), of een vaste 5.x-versie.
- **Resultaat:** `Install-Module Pester -MinimumVersion 5.0` installeerde Pester 6.2.0. Windows levert zelf
  Pester 3.4.0 mee.
- **Keuze:** Pester 5.7.1, vast (`-RequiredVersion`) in de CI, en lokaal geladen met
  `Import-Module Pester -MinimumVersion 5.0 -MaximumVersion 5.99`. Het voorstel en de tests gaan uit van
  Pester 5, en een vaste versie geeft vandaag en later hetzelfde resultaat.
- **Gevolg:** CLAUDE.md (secties 4 en 6), README en CI gebruiken deze versie.

### K2 — PSScriptAnalyzer stabiel krijgen (`PSUseCorrectCasing` uit, lintscript met herkansing)

- **Vraag:** hoe voorkomen dat PSScriptAnalyzer af en toe zelf faalt (`Object reference not set to an
  instance of an object`, of `The term 'Get-Command' is not recognized`)?
- **Opties en resultaat, ronde 1** (telkens een nieuw `pwsh`-proces per run, analyzer op de hele repo):

  | Optie | Mislukte runs |
  |---|---|
  | 1.25.0, alle regels | ongeveer 1 op 10 |
  | 1.24.0 (voorgesteld in het upstream-issue) | 10 op 40 |
  | Bestand per bestand analyseren | 8 op 30 |
  | Tot drie keer opnieuw proberen | 1 op 40 (ook na drie pogingen) |
  | 1.25.0 zonder `PSUseCorrectCasing` | 0 op 105 |

- **Ronde 2:** na het toevoegen van E3 kwam de fout terug (3 op 30). De stack trace toonde
  `PSReservedCmdletChar` → `Helper.GetExportedFunction` → `CommandInfo.ResolveParameter`, uitgelokt door
  `Export-ModuleMember` in `lab/E3-mocks-parallel/FleetDemo.psm1`. De oorzaak is dus de gedeelde
  commando-opzoeking van PSScriptAnalyzer (race condition,
  [PowerShell/PSScriptAnalyzer#2205](https://github.com/PowerShell/PSScriptAnalyzer/issues/2205)), niet één regel.
  Zonder `Export-ModuleMember`: 0 op 60.
- **Keuze:**
  1. `PSUseCorrectCasing` uit (cosmetisch; terug aan zodra de bug opgelost is, issue #12).
  2. Geen `Export-ModuleMember` in de repo; exporteren gebeurt via de manifest.
  3. `tools/Invoke-NexusLint.ps1`, lokaal en in de CI: probeert alleen fouten met `FullyQualifiedErrorId`
     `RULE_ERROR*` opnieuw (max. 3 keer). Meldingen over code en andere fouten worden nooit opnieuw
     geprobeerd; na 3 mislukte pogingen faalt het script.
- **Gevolg:** één lintcommando voor iedereen, getest met een gemockte analyzer (6 tests). Bug: #11.

### K3 — Lint en tests als aparte CI-jobs

- **Vraag:** PSScriptAnalyzer en Pester in één job of in twee?
- **Resultaat:** PSScriptAnalyzer laadt bij het analyseren van de testbestanden de assembly van de nieuwste
  Pester (6.x). Daarna kan Pester 5 niet meer laden in hetzelfde proces ("Assembly with same name is already
  loaded").
- **Keuze:** twee aparte jobs. Ze draaien tegelijk, tonen apart welke controle faalt, en de botsing kan niet
  optreden.
- **Gevolg:** lokaal eerst Pester 5 importeren, of lint en tests in aparte processen draaien (CLAUDE.md, sectie 4).

### K4 — Minimale PowerShell-versie

- **Vraag:** blijft de manifest op PowerShell 7.2, of gaat de ondergrens omhoog?
- **Feiten** ([PowerShell support lifecycle](https://learn.microsoft.com/powershell/scripting/install/powershell-support-lifecycle),
  geraadpleegd 2 november 2026):

  | Versie | Einde ondersteuning |
  |---|---|
  | 7.2 (LTS) | 8 november 2024 — al voorbij |
  | 7.4 (LTS) | 10 november 2026 |
  | 7.5 | 10 november 2026 |
  | 7.6 (LTS) | 14 november 2028 |

  Uit E1: geheimen als `byte[]` naar stdin pijpen kan pas vanaf 7.4. Op 7.2 moet elke host de `\r` zelf
  wegknippen.
- **Opties:** 7.2 houden (breedst, maar niet meer ondersteund) · 7.4 (byte-pijpen, nog een week ondersteund) ·
  7.6 (de enige ondersteunde LTS na 10 november 2026).
- **Voorstel (Claude Code):** 7.6. Dat is na volgende week de enige ondersteunde versie, de CI draait er al op
  (`PowerShell 7.6.9 on Ubuntu 26.04.1 LTS`, uit het CI-log), en
  het maakt de byte-pijp uit E1 vanzelfsprekend. Het voorstel noemt "PowerShell 7" zonder subversie, dus dit
  verandert het goedgekeurde voorstel niet.
- **Keuze (Tom, 2 november 2026):** 7.6, voor de langdurige ondersteuning (LTS). Doorgevoerd in de manifest,
  de PSScriptAnalyzer-instellingen en de documentatie (#28).

### K5 — Het API-token over `http://`

- **Vraag:** mag NexusFleet het API-token over gewone `http://` sturen? NexusInfra draait in de MVP zonder TLS
  (`http://localhost:9400`), en `Invoke-RestMethod` weigert standaard een token over `http://` te sturen
  (gevonden met de lokale HTTP-test).
- **Opties:** altijd toestaan (eenvoudig, maar een token met beheerrechten kan onderweg meegelezen worden) ·
  nooit (dan werkt de MVP niet met een lokaal panel) · alleen naar de eigen machine, en voor andere hosts alleen
  als het uitdrukkelijk aangezet is.
- **Keuze (Claude Code, door Tom te bevestigen):** de laatste. `localhost`, `127.0.0.1` en `::1` mogen altijd
  (het verkeer verlaat de machine niet). Voor een andere `http://`-host is `Api.AllowUnencryptedHttp = $true` in
  `config/nexusinfra.local.psd1` nodig, met een waarschuwing bij elke oproep. Anders stopt `Invoke-NexusApi` met
  `NexusApi.UnencryptedNotAllowed`, vóór er iets verstuurd is.
- **Gevolg:** veilig als standaard; de beveiligde verbinding (TLS, extra) maakt de uitzondering overbodig.

---

## Keuzes tijdens de MVP (fase 3)

### K6 — De volgorde van de installatiestappen

- **Vraag:** in welke volgorde gaan Docker, de agent, de registratie en de controle?
- **Keuze (Claude Code, door Tom te bevestigen):** Docker (10) → RegisterNode (20) → AgentContainer (30) →
  VerifyHealthy (40). De registratie komt vóór de agent: `POST /nodes` maakt het record aan of werkt het bij, en de
  eerste heartbeat vindt de node dan al met de juiste naam en locatie. Andersom zou de heartbeat eerst een record
  zonder naam maken, en zou de rollback van de registratie niet weten of dat record van deze run was.
- **Gevolg:** de rollback van RegisterNode verwijdert het record alleen als het vóór de run niet bestond (de Test
  onthoudt dat in de stapcontext).

### K7 — De geheimen van de agent op de host

- **Vraag:** hoe komen `RABBITMQ_URL` en `INTERNAL_API_TOKEN` in de agent zonder op een opdrachtregel te staan?
- **Opties:** `docker run -e NAAM=waarde` (staat in `ps` op de host) · een env-bestand · Docker secrets (vraagt
  Swarm).
- **Keuze:** beide geheimen gaan over stdin van één `ssh`-oproep (één regel per geheim, het transport kan nu
  meerdere geheimen sturen) en worden op de host weggeschreven in `/etc/nexusinfra/agent.env` (map `700`, bestand
  `600`, eigenaar root). `docker run --env-file` leest ze daar. De Test van de stap leest van de omgeving alleen
  `NODE_ID` en `AGENT_URL`, zodat de geheimen de host nooit verlaten.
- **Beperking:** wie op de host `docker inspect` mag doen (root), ziet de waarden wel. Een gewijzigd geheim wordt
  niet opgemerkt door de Test (die leest de geheimen nooit terug, en kent ze niet in een dry run).
- **Gevolg (#48):** `Install-NexusNode -Force` maakt de agent-container opnieuw, ook als hij in orde lijkt. Gekozen
  boven een hash van de geheimen als label op de container: eenvoudiger, en er staat niets over de geheimen op de
  host buiten het env-bestand. Mislukt zo'n vervanging (bijvoorbeeld een fout wachtwoord), dan verwijdert de rollback
  de nieuwe container en is de oude al weg; een gewone run met de juiste geheimen herstelt de node.
- **Gevonden in het node-lab:** na het opnieuw starten van de agent zei VerifyHealthy meteen "in orde": de laatste
  heartbeat van de **oude** agent hield de node nog tot `DegradedAfterSeconds` *healthy*. Een nieuwe agent met een
  fout geheim zou zo als geslaagd gemeld zijn. Nu onthoudt de agent-stap dat hij een agent startte, en dan is
  VerifyHealthy nooit "al in orde" en wacht hij eerst `DegradedAfterSeconds` voor de eerste controle.

### K8 — Docker installeren

- **Keuze:** het pakket `docker.io` uit Ubuntu zelf, met `apt-get` zonder vragen (`DEBIAN_FRONTEND=noninteractive`)
  en een wachttijd voor het apt-slot (`DPkg::Lock::Timeout`, voor unattended-upgrades op een verse VM). Geen extra
  apt-repository of sleutel die vertrouwd moet worden. Pakketnaam en wachttijd staan in de config.
- **Gevonden in het node-lab:** het Ubuntu-pakket heeft geen init-script, dus op een host zonder systemd (een
  container, WSL) startte de daemon niet (`docker: unrecognized service`). Daar start de stap `dockerd` nu zelf op de
  achtergrond; een echte VM gebruikt altijd `systemctl enable --now docker`. De rollback van die mislukte poging
  verwijderde Docker netjes weer.

### K9 — Het node-lab (in plaats van, en vóór, de echte VM's)

- **Vraag:** hoe bewijs je `Install-NexusNode` end-to-end voordat de lab-VM's (#14) klaar zijn?
- **Keuze:** `lab/node-lab/`: een NexusInfra-controlekant uit de gepubliceerde images (RabbitMQ, orchestrator,
  gateway, control-room) en twee verse Ubuntu-"hosts" als *privileged* containers, op vaste adressen in één
  Docker-netwerk. `Start-NodeLab.ps1` maakt sleutels en lab-geheimen, een API-token (`write` + `admin`), een
  config-override en een inventaris. De integratietest doorloopt daar de drie criteria van "Klaar als".
- **Beperking:** Docker in Docker is geen VM (geen systemd, gedeelde kernel). De echte bevestiging blijft de demo op
  de lab-VM's (#14, fase 4).
- **Gevonden met het lab, niet met mocks:** `Invoke-RestMethod` geeft een JSON-lijst terug als één object, zodat
  `Where-Object` op `GET /nodes` nooit een node vond (#47); en het ontbrekende init-script van K8.


### K10 — Controleren dat NexusInfra de agent bereikt (#101)

- **Vraag:** is *healthy* genoeg om een installatie geslaagd te noemen?
- **Gevonden:** nee. *Healthy* betekent dat de heartbeats aankomen, en die gaan van de node naar de broker. Deployen,
  bestanden, de console en backups gaan de andere kant op: de orchestrator belt de agent op zijn `agentUrl`, met het
  `INTERNAL_API_TOKEN` (gezien in de broncode van NexusInfra: `agentFetch` in `services/orchestrator/src/api.ts`).
  Over het internet kan die richting dicht zitten (firewall, security group, geen port forwarding, een adres dat
  alleen thuis werkt), of het token kan verschillen. De node is dan *healthy*, maar er kan niets op draaien.
- **Keuze:** een aparte stap `AgentReachable` (50) die `GET /nodes/<id>/disk` vraagt. Bij die vraag belt NexusInfra
  zelf de agent, met het token, en antwoordt `502` als het niet lukt. Ze bestaat al in 0.4.0, leest alleen, en is
  alleen voor platformbeheerders: NexusInfra hoeft niet te veranderen.
- **Verworpen:** `GET <agentUrl>/health` vanaf de beheermachine. Dat test de verkeerde richting: de beheermachine is
  niet de orchestrator (een `agentUrl` in het thuisnetwerk werkt voor de orchestrator, niet vanaf school), en
  `/health` vraagt geen token. Ook verworpen: een nieuw endpoint in NexusInfra, omdat er al een is.

### K11 — Nodes achter NAT: de agent verbindt zelf (#105)

- **Vraag:** hoe kan NexusInfra een node besturen die geen adres heeft dat de orchestrator kan bellen, zoals de VM
  op een laptop op de school-wifi, een server thuis of een 4G-verbinding (CGNAT)?
- **Gevonden:** zo'n node wordt *healthy* (de heartbeats gaan naar buiten), maar `GET /nodes/<id>/disk` faalt
  (K10): de orchestrator belt de agent op zijn `agentUrl`, en dat adres bestaat niet van buitenaf. Bovendien gaat
  het gedeelde `INTERNAL_API_TOKEN` op die weg in klare tekst over het internet.
- **Keuze:** per host een `reach`. `direct` is wat er al was. `outbound` is nieuw: de agent opent zelf één
  WebSocket naar de gateway (`wss://`, dus via 443 en TLS), en de orchestrator stuurt zijn aanroepen daarover
  terug. Elke node krijgt een eigen link-token. Dit wordt gebouwd in NexusInfra (#416, `fleet-support:`); NexusFleet
  registreert de node als `outbound`, publiceert poort 9100 niet en geeft de agent de link-URL en het token.
  Ontwerp: [agent-link.md](agent-link.md).
- **Verworpen:** een VPN (Tailscale): dan moet elke node eerst in een privénetwerk, wat het voorstel uitsluit.
  Een SSH-tunnel per node vanuit NexusFleet: werkt voor elk platform, maar vraagt een sshd op de control plane en
  een tunnel-account per node, en past slecht op een netwerk dat alleen 443 doorlaat. Voor NexusInfra, dat we zelf
  kunnen aanpassen, is een verbinding die de agent zelf opent netter. De tunnel blijft een optie (`reach: tunnel`)
  voor andere platformen, bij de extra over connectors. Ook verworpen: het gedeelde `INTERNAL_API_TOKEN` als
  sleutel van de link, want daarmee kan een node zich voordoen als een andere node.
- **Nog niet opgelost:** de broker heeft nog zijn eigen poort (5672) nodig. Een netwerk dat alleen 443 doorlaat,
  blokkeert dus nog altijd de heartbeats.
