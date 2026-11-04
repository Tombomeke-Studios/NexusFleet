# Installatie

> Uitleg gegenereerd met Claude Code als studiemateriaal. Niet mijn leerlogboek.

_Stand: `Install-NexusNode` (#38–#46), de vier installatiestappen en het node-lab._

## 1. Wat het doet

`Install-NexusNode` maakt van gewone Linux-servers *healthy* NexusInfra-nodes. Per server controleert het eerst of de
server klaar is (de preflight), en doet het daarna alleen wat nog ontbreekt: Docker installeren, de node aanmelden
bij NexusInfra, de agent starten en wachten tot NexusInfra de node gezond noemt. Lukt een stap niet, dan wordt wat
deze run veranderd heeft weer teruggedraaid. Een tweede keer draaien verandert niets meer.

## 2. Waar het staat

| Pad | Inhoud |
|---|---|
| `src/public/Install-NexusNode.ps1` | De cmdlet: `-WhatIf`/`-Confirm` per server, geheimen, de dunne parallelle schil |
| `src/core/Invoke-NexusHostInstall.ps1` | Het werk voor één server: preflight, stapcontext, de stappen (wordt rechtstreeks getest) |
| `src/core/ConvertTo-NexusInstallFailure.ps1` | Maakt van een onverwachte fout een mislukt resultaat |
| `src/core/Invoke-NexusStepCommand.ps1` | Hoe een stap een opdracht op zijn server uitvoert (gooit een fout als het mislukt) |
| `src/core/Invoke-NexusStepApi.ps1` | Hoe een stap het paneel aanspreekt |
| `src/utils/ConvertTo-NexusShellArgument.ps1` | Zet een waarde veilig tussen enkele aanhalingstekens voor bash |
| `src/steps/Docker.ps1` | Stap 10: Docker Engine |
| `src/steps/RegisterNode.ps1` | Stap 20: `POST /nodes` |
| `src/steps/AgentContainer.ps1` | Stap 30: de agent-container |
| `src/steps/VerifyHealthy.ps1` | Stap 40: wachten op *healthy* |
| `tests/steps/*.Tests.ps1` | Elke stap apart: Test, Apply, Rollback |
| `tests/core/FakeFleet.ps1` | Een nep-fleet: nep-servers en een nep-paneel die echt "veranderen" |
| `tests/core/Invoke-NexusHostInstall.Tests.ps1` | De echte stappen en de echte runner tegen de nep-fleet |
| `tests/public/Install-NexusNode.Tests.ps1` | De cmdlet: geheimen, `-WhatIf`, 60 servers |
| `tests/public/Install-NexusNode.LocalSsh.Tests.ps1` | Echte runspaces en echte `ssh` naar gesloten poorten (in CI) |
| `tests/public/Install-NexusNode.Integration.Tests.ps1` | De drie criteria van "Klaar als" in het node-lab |
| `lab/node-lab/` | Het node-lab: NexusInfra en twee verse Ubuntu-"servers" in Docker |

## 3. Hoe het werkt

```powershell
Import-NexusInventory ./config/inventory.json | Install-NexusNode
```

**`Install-NexusNode`** (het patroon van `Test-NexusHost`):

1. `process` verzamelt de servers.
2. `end` haalt de verbinding op (`Get-NexusSession`: zonder `Connect-NexusInfra` stopt het hier) en de config.
3. **Per server `ShouldProcess`**, vóór de parallelle lus, want in `-Parallel` bestaat `ShouldProcess` niet. Met
   `-WhatIf` wordt elke server `PlanOnly`:

   ```powershell
   PlanOnly = -not $PSCmdlet.ShouldProcess($hostInfo.Name, 'Turn into a NexusInfra node ...')
   ```
4. **De geheimen** (`RABBITMQ_URL`, `INTERNAL_API_TOKEN`) uit de parameters of uit SecretManagement, maar alleen als
   er echt iets geïnstalleerd wordt. Een dry run heeft ze niet nodig.
5. Een run-context met alle geheimen, zodat de logs ze wegpoetsen. Dan per server `Invoke-NexusHostInstall`, in
   volgorde (`-ThrottleLimit 1`) of in parallelle runspaces (de module wordt per runspace ingeladen; dat registreert
   daar ook de stappen).

**`Invoke-NexusHostInstall`** (één server, gooit nooit een fout):

1. De preflight. Faalt een check, dan wordt er **niets** aangeraakt en zegt het resultaat welke check.
2. De **stapcontext**: alles wat een stap nodig heeft, in één hashtable (server, config, ssh-instellingen,
   API-instellingen, geheimen, logging, en `State` om iets te onthouden tussen Test en Rollback).
3. `Invoke-NexusStepSequence` met de stappen uit `src/steps/`: per stap eerst `Test`, en alleen als dat `$false`
   zegt `Apply`. Mislukt een stap, dan rolt de runner terug wat deze run deed, in omgekeerde volgorde.
4. Het resultaat: `Success`, `Changed` (heeft deze run iets toegepast?), `Step`/`Error`, alle `Steps`, de preflight.

**De vier stappen:**

| Stap | Test ("al in orde?") | Apply | Rollback |
|---|---|---|---|
| Docker | `command -v docker && sudo -n docker info` | `apt-get install docker.io`, daemon starten | pakket weer verwijderen |
| RegisterNode | staat de node in `GET /nodes`, met dezelfde naam, locatie, agentUrl? | `POST /nodes` | `DELETE /nodes/:id`, alleen als het record vóór de run niet bestond |
| AgentContainer | draait de container, met het juiste image, restart policy, poort, volume, socket, host-gateway, `NODE_ID`, `AGENT_URL`? | env-bestand schrijven (geheimen via stdin), container (opnieuw) maken | container en env-bestand weg, het backup-volume nooit |
| VerifyHealthy | zegt `GET /nodes` `healthy`? | `GET /nodes` herhalen tot `healthy`, of opgeven na de time-out | niets |

De agent-stap stuurt de twee geheimen als twee regels over stdin; op de server leest bash ze en schrijft ze in een
bestand dat alleen root kan lezen:

```bash
IFS= read -r rabbitmq_url
IFS= read -r internal_token
printf '%s=%s\n' 'NODE_ID' 'node-lab1' 'RABBITMQ_URL' "$rabbitmq_url" ... | sudo -n tee '/etc/nexusinfra/agent.env'
sudo -n chmod 600 '/etc/nexusinfra/agent.env'
sudo -n docker run -d --name 'nexusinfra-node-agent' --restart 'unless-stopped' --env-file '/etc/nexusinfra/agent.env' ...
```

## 4. Waarom zo

- **Test vóór Apply, bij elke stap.** Daardoor is een tweede run vanzelf "niets te doen" (criterium 2), en kan
  `-WhatIf` gewoon alleen de Tests draaien.
- **De agent-Test controleert elke instelling apart**, ook de drie die stil falen (restart policy, poort,
  backup-volume). Een container die iemand met de hand en zonder die opties gestart heeft, wordt zo hersteld. Een
  vingerafdruk-label op de container zou eenvoudiger zijn, maar ziet zo'n handgemaakte container niet.
- **Registreren vóór de agent** (K6): de eerste heartbeat vindt de node dan al met naam en locatie, en de rollback
  weet zeker of het record van deze run is.
- **Geheimen via stdin en een env-bestand** (K7): `docker run -e` zou ze in `ps` op de server zetten.
- **Wachten met een aantal pogingen in plaats van een klok**: `time-out / interval` pogingen. Even duidelijk, en
  testbaar zonder echt te wachten (`Start-Sleep` wordt in de tests vervangen).
- **Een nep-fleet in de tests in plaats van losse mocks per oproep.** De nep-servers onthouden of Docker en de agent
  er staan, het nep-paneel onthoudt de nodes. Zo kunnen de tests de echte stappen twee keer draaien
  (idempotentie), een stap laten falen (rollback) en daarna kijken wat er "gebeurd" is.
- **Toch nog een lab.** Het node-lab vond twee fouten die geen mock kon vinden: `Invoke-RestMethod` gaf de
  nodelijst als één object terug (#47), en Ubuntu's Docker-pakket kan zonder systemd niet starten (K8).

## 5. PowerShell-concepten

- **`SupportsShouldProcess`, `-WhatIf`, `-Confirm`** (per server beslist, vóór de parallelle lus):
  https://learn.microsoft.com/powershell/scripting/learn/deep-dives/everything-about-shouldprocess
- **`ForEach-Object -Parallel`, `$using:`:** https://learn.microsoft.com/powershell/module/microsoft.powershell.core/foreach-object
- **Splatting** (`Invoke-NexusHostCommand @ssh`): https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_splatting
- **Here-strings** (`@" ... "@` met `$(...)` erin, `@' ... '@` zonder): https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_quoting_rules
- **`SecureString` en `NetworkCredential`** (de leesbare tekst van een geheim, alleen op het moment dat het nodig is):
  https://learn.microsoft.com/dotnet/api/system.net.networkcredential
- **Pester: `Mock -ModuleName`, `Should -Invoke`, `-ForEach`:** https://pester.dev/docs/usage/mocking
- **Hoe een functie een lijst teruggeeft** (een lijst in een variabele wordt item per item doorgegeven):
  https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_pipelines
- **Bash:** `IFS= read -r` (een regel van stdin ongewijzigd lezen), `'...'` (niets wordt uitgevoerd), `set -eu`.

## 6. Zelf proberen

```powershell
Import-Module ./NexusFleet.psd1 -Force
Get-Help Install-NexusNode -Full

# Het node-lab starten (alleen Docker nodig; de eerste keer een paar minuten)
./lab/node-lab/Start-NodeLab.ps1

# Verbinden en installeren met de lab-instellingen
Copy-Item ./lab/node-lab/.keys/nexusinfra.lab.psd1 ./config/nexusinfra.local.psd1
$lab = @{}; Get-Content ./lab/node-lab/.keys/.env | ForEach-Object { $k, $v = $_ -split '=', 2; $lab[$k] = $v }
Connect-NexusInfra -Token (ConvertTo-SecureString (Get-Content ./lab/node-lab/.keys/api-token -Raw) -AsPlainText -Force)
$rabbit = ConvertTo-SecureString "amqp://$($lab.RABBITMQ_USER):$($lab.RABBITMQ_PASS)@172.29.50.10:5672" -AsPlainText -Force
$internal = ConvertTo-SecureString $lab.INTERNAL_API_TOKEN -AsPlainText -Force
$hosts = Import-NexusInventory ./lab/node-lab/.keys/inventory.lab.json

$hosts | Install-NexusNode -WhatIf | ForEach-Object { $_.Host; $_.Steps | Format-Table }
$hosts | Install-NexusNode -RabbitMqUrl $rabbit -InternalApiToken $internal | Format-Table Host, Success, Changed, Step, Error
$hosts | Install-NexusNode -RabbitMqUrl $rabbit -InternalApiToken $internal | Format-Table Host, Success, Changed   # tweede keer

# Laten mislukken: de agent stoppen en een verkeerd broker-wachtwoord meegeven -> VerifyHealthy faalt, rollback
$wrong = ConvertTo-SecureString 'amqp://fleet:wrong@172.29.50.10:5672' -AsPlainText -Force
ssh -i ./lab/node-lab/.keys/id_ed25519 -p 2231 fleet@127.0.0.1 'sudo docker rm -f nexusinfra-node-agent'
$hosts[0] | Install-NexusNode -RabbitMqUrl $wrong -InternalApiToken $internal | Select-Object -ExpandProperty Steps

Remove-Item ./config/nexusinfra.local.psd1

# De tests
Import-Module Pester -MinimumVersion 5.0 -MaximumVersion 5.99
Invoke-Pester -Path ./tests/steps, ./tests/core/Invoke-NexusHostInstall.Tests.ps1, ./tests/public/Install-NexusNode*.ps1 -Output Detailed
Invoke-Pester -Path ./tests/public/Install-NexusNode.Integration.Tests.ps1 -TagFilter Integration -Output Detailed
```

## 7. Controlevragen

1. Waarom maakt een tweede run van `Install-NexusNode` niets meer, zonder dat er ergens "al geïnstalleerd" wordt
   bijgehouden?
2. Waarom wordt `-WhatIf` per server beslist vóór de parallelle lus, en niet in de lus zelf?
3. Hoe komen de twee geheimen op de server, en waarom niet met `docker run -e`?
4. Waarom verwijdert de rollback van RegisterNode een node soms wel en soms niet?
5. Welke twee fouten vond het node-lab die de tests met mocks niet vonden, en waarom konden mocks ze niet vinden?
