# NexusFleet

[![CI](https://github.com/Tombomeke-Studios/NexusFleet/actions/workflows/ci.yml/badge.svg?branch=dev)](https://github.com/Tombomeke-Studios/NexusFleet/actions/workflows/ci.yml)
[![Integration](https://github.com/Tombomeke-Studios/NexusFleet/actions/workflows/integration.yml/badge.svg?branch=dev)](https://github.com/Tombomeke-Studios/NexusFleet/actions/workflows/integration.yml)

A PowerShell 7 module that turns Linux hosts into [NexusInfra](https://github.com/Tombomeke-Studios/NexusInfra)
nodes and manages them as a fleet: read an inventory, check every host, install Docker and the node agent,
register the node, wait until it is healthy, and roll back when something fails.

> **Status: phase 4, finishing the MVP.** All MVP cmdlets are available and proven end to end in the
> [node lab](lab/node-lab/); the demo on real lab VMs follows. Progress is tracked in [TODO.md](TODO.md).

## Why

Adding a machine to NexusInfra is manual work today: install Docker, start the agent container with the
right variables, register the node and check that it sends heartbeats. Three of the `docker run` options
fail silently when forgotten. That is tedious for one host, error-prone for ten and unworkable for a hundred.
NexusFleet turns it into one repeatable, idempotent PowerShell pipeline with a result per host.

## Cmdlets (MVP)

| Cmdlet | What it does |
|---|---|
| `Connect-NexusInfra` | Connect to the NexusInfra panel with an API token, check its rights, optionally store it |
| `Import-NexusInventory` | Read and validate a JSON list of target hosts |
| `Test-NexusHost` | Check every host in parallel: reachable, SSH login, OS, sudo, disk space, Docker, broker |
| `Install-NexusNode` | Turn hosts into healthy nodes in parallel: Docker, register, agent, verify; idempotent, rollback on failure |
| `Get-NexusFleetStatus` | The status of every node: NexusInfra's view merged with what ssh sees on the host |
| `Export-NexusFleetStatus` | Write that status to JSON or CSV |

Every changing cmdlet supports `-WhatIf` (dry run), and every run writes a readable log without secrets
(`logs/<RunId>/`, one file per host and `run.log`).

## Requirements

**Control machine** (where you run NexusFleet)

- PowerShell 7.6 or later (`pwsh`, the current LTS) on Windows, Linux or macOS
- An OpenSSH client (`ssh`), with a key the target hosts accept
- A NexusInfra control plane you can reach (v0.4.0 or later), and an API token for it, created by a platform
  administrator with the scopes `write` and `admin`
- NexusInfra's broker URL (`amqp://user:password@host:5672`) and `INTERNAL_API_TOKEN`, for the agents
- To store the token: [SecretManagement](https://learn.microsoft.com/powershell/utility-modules/secretmanagement/overview)
  and a vault (see Quick start)

**Target hosts**

- Ubuntu (tested on 24.04), reachable over SSH, with at least 2 GB free on `/` and internet access for `apt` and
  `ghcr.io`; Docker is installed by NexusFleet when it is missing
- A user that logs in with an SSH key and may use `sudo` without a password
- The broker reachable from the host, and the host's port 9100 reachable from the orchestrator
- Step by step, with commands: [lab/demo/README.md](lab/demo/README.md)

**For development**

- [Pester](https://pester.dev) **5.x** (not 6, and not the Pester 3.4 that ships with Windows)
- [PSScriptAnalyzer](https://learn.microsoft.com/powershell/utility-modules/psscriptanalyzer/overview)

```powershell
Install-Module Pester -RequiredVersion 5.7.1 -Scope CurrentUser -SkipPublisherCheck
Install-Module PSScriptAnalyzer -Scope CurrentUser
```

## Quick start

```powershell
git clone https://github.com/Tombomeke-Studios/NexusFleet.git
cd NexusFleet
Import-Module ./NexusFleet.psd1
```

**Connect to your panel.** Set your panel's address in `config/nexusinfra.local.psd1`
(`@{ Api = @{ BaseUrl = 'https://panel.example.com' } }`), then:

```powershell
Connect-NexusInfra -Token (Read-Host -AsSecureString 'API token')
```

```text
BaseUrl      : https://panel.example.com
User         : admin@example.com
PlatformRole : owner
TokenSaved   : False
RunId        : 20261102T153012Z-a1b2c3
```

`Connect-NexusInfra` checks that the account is a platform administrator and that the token has the `admin`
scope, and stops with a clear error otherwise.

**Store the token (optional).** Once per machine, set up a vault (you choose its password):

```powershell
Install-Module Microsoft.PowerShell.SecretManagement, Microsoft.PowerShell.SecretStore -Scope CurrentUser
Register-SecretVault -Name NexusFleet -ModuleName Microsoft.PowerShell.SecretStore -DefaultVault
Connect-NexusInfra -Token (Read-Host -AsSecureString 'API token') -Save
```

After that, `Connect-NexusInfra` without `-Token` uses the stored token. The token never goes into a NexusFleet
file or log.

**Describe your hosts.** Copy `config/inventory.example.json` to `config/inventory.json` (git-ignored) and
list your hosts; `defaults` fills in what every host shares:

```json
{
  "defaults": { "user": "fleet", "port": 22, "location": "home" },
  "hosts": [
    { "name": "node-home01", "address": "192.168.1.20" },
    { "name": "node-vps01", "address": "203.0.113.10", "port": 2222, "location": "vps" }
  ]
}
```

```powershell
Import-NexusInventory ./config/inventory.json | Format-Table Name, Address, Port, User, Location
```

Every problem in the file (missing fields, invalid names or addresses, duplicates) is reported in one error.

**Check the hosts (changes nothing).** Set the broker address as the hosts reach it in your local config
(`@{ Broker = @{ Host = 'broker.example.com' } }`), then:

```powershell
Import-NexusInventory ./config/inventory.json | Test-NexusHost | Format-Table Host, Success, Step, Error
```

```text
Host          Success Step      Error
----          ------- ----      -----
node-home01      True
node-home02     False Sudo      fleet cannot use sudo without a password (needed to install Docker and the agent)
node-vps01      False Reachable cannot reach 203.0.113.10:2222 over ssh: ... Connection timed out
```

Hosts are checked in parallel (`-ThrottleLimit`, default 10); one failing host never stops the others.
`$result.Checks` shows every check of a host.

**Turn the hosts into nodes.** The agents need two of NexusInfra's secrets: the broker URL (with its password) and
the `INTERNAL_API_TOKEN`. Store them once with SecretManagement (or pass `-RabbitMqUrl` / `-InternalApiToken`):

```powershell
Set-Secret -Name NexusFleet-RabbitMqUrl -Secret (Read-Host -AsSecureString 'RABBITMQ_URL')
Set-Secret -Name NexusFleet-InternalApiToken -Secret (Read-Host -AsSecureString 'INTERNAL_API_TOKEN')
```

First the dry run, then the real one:

```powershell
Import-NexusInventory ./config/inventory.json | Install-NexusNode -WhatIf
Import-NexusInventory ./config/inventory.json | Install-NexusNode | Format-Table Host, Success, Changed, Step, Error
```

```text
Host        Success Changed Step      Error
----        ------- ------- ----      -----
node-home01    True    True
node-home02    True    True
node-vps01    False   False Reachable preflight failed, nothing was changed: cannot reach 203.0.113.10:2222 ...
```

Per host: the preflight, then four steps, each only when its check says it is needed: **Docker** (Ubuntu's
`docker.io`), **RegisterNode** (`POST /nodes`), **AgentContainer** (with the restart policy, the port, the backups
volume, the Docker socket and the host-gateway mapping; the secrets in `/etc/nexusinfra/agent.env`, mode 600) and
**VerifyHealthy** (until NexusInfra reports the node healthy). A failing step rolls back what that run changed on
that host. Run it again and every host reports `Changed = False`. `$result.Steps` shows each step. After changing
the broker password or `INTERNAL_API_TOKEN`, run it with `-Force`: that recreates the agent with the new secrets.

**See how the fleet is doing.** NexusInfra's view (health, last heartbeat, maintenance, CPU, RAM) merged with what
the host itself says over ssh (reachable, Docker, the agent container, uptime, free disk):

```powershell
Import-NexusInventory ./config/inventory.json | Get-NexusFleetStatus | Format-Table Name, Ok, Health, AgentState, Problem
```

```text
Name        Ok    Health  AgentState Problem
----        --    ------  ---------- -------
node-home01 True  healthy running
node-home02 False offline exited     NexusInfra reports it offline; the agent container is exited
node-vps01  False offline            NexusInfra reports it offline; cannot reach 203.0.113.10:2222 over ssh: ...
```

Without an inventory, `Get-NexusFleetStatus` shows only NexusInfra's view. Nodes NexusInfra knows but the inventory
does not are listed after the inventory. An unreachable host, or even an unreachable panel, is reported in the result
and never stops the run. Export it:

```powershell
Import-NexusInventory ./config/inventory.json | Get-NexusFleetStatus | Export-NexusFleetStatus -Path ./status.csv
Get-NexusFleetStatus | Export-NexusFleetStatus -Path ./status.json
```

## Configuration

Every NexusInfra-specific value (panel address, agent image, port, environment variable names, health
thresholds) is in [config/nexusinfra.psd1](config/nexusinfra.psd1). To change values for your own setup, create
`config/nexusinfra.local.psd1` with only the keys you change; it is git-ignored:

```powershell
@{ Api = @{ BaseUrl = 'https://panel.example.com' } }
```

The configuration is validated when it is read; an invalid file stops the run with a list of every problem.

The API token is only sent over plain `http://` to this machine (`localhost`). For a panel on another host
without TLS, set `Api = @{ AllowUnencryptedHttp = $true }` in your local file, and only on a trusted network.

## Development

Run from the repository root in `pwsh`. Import Pester 5 first: PSScriptAnalyzer otherwise loads the newest
Pester assembly and blocks Pester 5 in that session.

```powershell
Import-Module Pester -MinimumVersion 5.0 -MaximumVersion 5.99
./tools/Invoke-NexusLint.ps1
Invoke-Pester -Path ./tests -ExcludeTagFilter Integration -Output Detailed
```

CI runs both on every push and pull request ([.github/workflows/ci.yml](.github/workflows/ci.yml)).

**The demo** runs the whole flow on an inventory, times every phase and checks the three "Klaar als" criteria of
the MVP: `./lab/demo/Invoke-NexusDemo.ps1 -InventoryPath ./config/inventory.json` (see
[lab/demo/README.md](lab/demo/README.md), also for preparing lab VMs). In the node lab:

```text
Phase                          Seconds
-----                          -------
Preflight (Test-NexusHost)         2.7
Plan (Install-NexusNode -WhatIf)   2.6
Install (Install-NexusNode)       14.9
Second run (Install-NexusNode)     2.6
Status (Get-NexusFleetStatus)      2.7

Criterion                                         Holds Detail
---------                                         ----- ------
1. one command turns the hosts into healthy nodes  True 2 of 3 host(s) installed; healthy now: node-lab1, node-lab2
2. a second run changes nothing                    True changed in the second run:
3. one failing host does not stop the others       True failed on their own: node-lab-broken (Reachable)
```

**Releases.** Pushing a tag `v<ModuleVersion>` on `main` runs the checks, builds the module with
`./tools/Build-NexusModule.ps1` (only the module files, in `out/`) and publishes a GitHub release with the zip
([.github/workflows/release.yml](.github/workflows/release.yml)). CI keeps the test results and the code coverage
of every run as an artifact.

**The node lab** proves the installation end to end on this machine, with only Docker: a NexusInfra control plane
(published images) and two fresh Ubuntu hosts in containers ([lab/node-lab/](lab/node-lab/)).

```powershell
./lab/node-lab/Start-NodeLab.ps1
Invoke-Pester -Path ./tests -TagFilter Integration -Output Detailed
./lab/node-lab/Start-NodeLab.ps1 -Remove
```

Branches: `feature/<topic>` → `dev` (default, always green) → `main` (milestones only, tagged).

## Repository layout

| Path | Contents |
|---|---|
| `NexusFleet.psd1` / `NexusFleet.psm1` | Module manifest and loader |
| `src/core/` | Contracts (a step, a transport), the step runner and the per-host engines (preflight, install) |
| `src/steps/` | One file per installation step |
| `src/transports/` | Running commands on a host (SSH) |
| `src/api/` | The only place that calls the NexusInfra REST API |
| `src/public/` | The exported cmdlets |
| `src/utils/` | Logging, configuration, session and secret helpers |
| `config/` | NexusInfra-specific values and an example inventory |
| `tests/` | Pester tests, mirroring `src/` |
| `tools/` | Lint and build scripts, the same locally and in CI |
| `lab/` | Experiments of phase 1 and the node lab (not part of the module) |
| `docs/` | Proposal, architecture, design decisions, explanations (Dutch course documents) |

## Documentation

Index: [docs/README.md](docs/README.md). In the shell: `Get-Help about_NexusFleet` and `Get-Help <cmdlet> -Full`.

**Using NexusFleet:** [user guide](docs/user-guide.md) · [inventory format](docs/inventory.md) ·
[configuration](docs/configuration.md) · [security](docs/security.md) · [troubleshooting](docs/troubleshooting.md)

**Working on NexusFleet:** [architecture](docs/architecture.md) · [development](docs/development.md) ·
[testing](docs/testing.md) · [labs](lab/README.md)

**Course documents (Dutch):** [project proposal](docs/projectvoorstel.md) · [design decisions](docs/ontwerpkeuzes.md) ·
[changes in NexusInfra](docs/nexusinfra-wijzigingen.md) · [explanations per topic](docs/uitleg/README.md)

## About

School project for *System Automation & Scripting* (EhB, Toegepaste Informatica) by Tom Dekoning.
NexusInfra is a separate project and is not part of this module.
