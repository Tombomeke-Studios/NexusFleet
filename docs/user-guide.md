# User guide

This guide takes you from a fresh admin machine to a fleet of healthy NexusInfra nodes. Each cmdlet's full
reference is in its help: `Get-Help <cmdlet> -Full`, and the overview is in `Get-Help about_NexusFleet`.

- [What NexusFleet does](#what-nexusfleet-does)
- [Before you start](#before-you-start)
- [Install the module](#install-the-module)
- [Connect-NexusInfra](#connect-nexusinfra)
- [Import-NexusInventory](#import-nexusinventory)
- [Test-NexusHost](#test-nexushost)
- [Install-NexusNode](#install-nexusnode)
- [Get-NexusFleetStatus](#get-nexusfleetstatus)
- [Export-NexusFleetStatus](#export-nexusfleetstatus)
- [Logs](#logs)
- [Results are objects](#results-are-objects)

Related: [configuration](configuration.md) · [inventory format](inventory.md) · [security](security.md) ·
[troubleshooting](troubleshooting.md)

## What NexusFleet does

A machine becomes a [NexusInfra](https://github.com/Tombomeke-Studios/NexusInfra) node when the NexusInfra node agent
runs on it. The agent sends heartbeats to NexusInfra's broker, and NexusInfra then shows the node as *healthy* and
places servers on it. By hand that means, per machine: install Docker, start the agent container with four
environment variables and five options (three of which fail silently when forgotten), register the node, and check
that it becomes healthy.

NexusFleet does that for a list of machines at once:

```text
inventory.json ─► Import-NexusInventory ─► Test-NexusHost ─► Install-NexusNode ─► Get-NexusFleetStatus
                  (read and check)         (ready?)          (Docker, register,     (NexusInfra + host)
                                                              agent, healthy)
```

- **Idempotent:** every step checks first whether it is still needed. Run it twice, and the second run changes
  nothing.
- **Rollback:** when a step fails on a host, what that run changed on the host is undone.
- **Parallel:** hosts are handled at the same time. One failing host never stops the others.
- **A result per host:** every cmdlet returns objects you can filter, sort and export.
- **Dry run:** `-WhatIf` shows what would happen and changes nothing.

## Before you start

**On your admin machine** (Windows, Linux or macOS):

- PowerShell 7.6 or later (`pwsh`).
- The OpenSSH client (`ssh`), with a key the hosts accept.
- To store secrets: SecretManagement and a vault.

  ```powershell
  Install-Module Microsoft.PowerShell.SecretManagement, Microsoft.PowerShell.SecretStore -Scope CurrentUser
  Register-SecretVault -Name NexusFleet -ModuleName Microsoft.PowerShell.SecretStore -DefaultVault
  ```

**A NexusInfra control plane** (v0.4.0 or later) that the hosts can reach:

- The **broker** (RabbitMQ, port 5672) must be reachable **from the hosts**. NexusInfra's bundles publish it on
  `127.0.0.1` only: set `BROKER_BIND` in the control plane's `.env` to its address on the network the hosts share.
  The broker needs a user of its own (`RABBITMQ_USER`/`RABBITMQ_PASS`; NexusInfra's installer generates them),
  because RabbitMQ refuses `guest` from another machine. Before these NexusInfra changes, publish the port by hand.
- The **orchestrator** must reach each host's agent on port 9100.
- You need its `INTERNAL_API_TOKEN` (from its `.env`) and the broker URL `amqp://user:password@host:5672`.
- An **API token** of a platform administrator, with the scopes `write` and `admin`.

**Each host:**

- Ubuntu (tested on 24.04), with at least 2 GB free on `/`, and internet access for `apt` and `ghcr.io`. Docker is
  installed by NexusFleet when it is missing.
- A user that logs in with an SSH key and may use `sudo` without a password.

  ```bash
  useradd --create-home --shell /bin/bash fleet
  echo 'fleet ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/fleet && chmod 440 /etc/sudoers.d/fleet
  install -d -m 700 -o fleet -g fleet /home/fleet/.ssh
  echo '<your public key>' > /home/fleet/.ssh/authorized_keys
  chown fleet:fleet /home/fleet/.ssh/authorized_keys && chmod 600 /home/fleet/.ssh/authorized_keys
  ```

## Install the module

From a release ([GitHub releases](https://github.com/Tombomeke-Studios/NexusFleet/releases)): unzip
`NexusFleet-<version>.zip` into a folder in `$env:PSModulePath`, or anywhere, and import it by path:

```powershell
Import-Module ./NexusFleet/NexusFleet.psd1
Get-Command -Module NexusFleet
```

From the repository: `Import-Module ./NexusFleet.psd1`.

Then tell NexusFleet where things are, in `config/nexusinfra.local.psd1` next to the module's own config:

```powershell
@{
    Api    = @{ BaseUrl = 'https://panel.example.com' }
    Broker = @{ Host = '10.0.0.2' }            # the broker as the hosts reach it
}
```

Every value is described in [configuration.md](configuration.md).

## Connect-NexusInfra

Connects to the panel and checks, before anything else, that the token may manage nodes. It checks that the account
is `admin` or `owner`, and that the token has the `admin` scope. `-Save` stores the token for the next session.

```powershell
Connect-NexusInfra -Token (Read-Host -AsSecureString 'API token') -Save
```

```text
BaseUrl      : https://panel.example.com
User         : admin@example.com
PlatformRole : owner
TokenSaved   : True
RunId        : 20261104T073500Z-1a2b3c
```

In a later session, `Connect-NexusInfra` alone is enough. The connection lasts for the PowerShell session.

## Import-NexusInventory

Reads the list of hosts, checks every field, and reports every problem at once. The format is in
[inventory.md](inventory.md).

```powershell
$hosts = Import-NexusInventory -Path ./config/inventory.json
$hosts | Format-Table Name, Address, Port, User, Location
```

## Test-NexusHost

Checks every host in parallel, and changes nothing: Reachable, SshAuth, OS, Sudo, DiskSpace, Docker (a warning only)
and Broker (from the host itself).

```powershell
$hosts | Test-NexusHost | Format-Table Host, Success, Step, Error
```

```text
Host        Success Step      Error
----        ------- ----      -----
node-home01    True
node-home02   False Sudo      fleet cannot use sudo without a password (needed to install Docker and the agent)
node-vps01    False Reachable cannot reach 203.0.113.10:2222 over ssh: ... Connection timed out
```

`($hosts | Test-NexusHost)[0].Checks` shows every check of a host. Fix what fails, then check again.

## Install-NexusNode

Store the agent's two secrets once (or pass `-RabbitMqUrl` and `-InternalApiToken` each time):

```powershell
Set-Secret -Name NexusFleet-RabbitMqUrl -Secret (Read-Host -AsSecureString 'RABBITMQ_URL')
Set-Secret -Name NexusFleet-InternalApiToken -Secret (Read-Host -AsSecureString 'INTERNAL_API_TOKEN')
```

First the plan, then the installation:

```powershell
$hosts | Install-NexusNode -WhatIf | ForEach-Object { $_.Host; $_.Steps | Format-Table Step, Outcome }
$hosts | Install-NexusNode | Format-Table Host, Success, Changed, Step, Error
```

Per host:

| Step | Checks first | Then |
|---|---|---|
| Preflight | the checks of `Test-NexusHost` | a host that is not ready is not touched |
| Docker | is Docker there and running? | installs `docker.io` and starts it |
| RegisterNode | is the node in NexusInfra, with the same name, location and agentUrl? | `POST /nodes` |
| AgentContainer | does the agent run with every setting, including the restart policy, the port and the backups volume? | writes the env file (secrets over stdin, mode 600) and (re)creates the container |
| VerifyHealthy | does NexusInfra report the node healthy? | waits until it does, or until `Health.VerifyTimeoutSeconds` |

Each step reports one of these outcomes:
- `AlreadyDone`: nothing was needed.
- `Applied`: the step changed the host.
- `WouldApply`: the step would change the host (`-WhatIf`).
- `Failed`: the step failed.
- `NotRun`: the step was not reached because an earlier step failed.

When a step fails, the steps this run applied are rolled back in reverse order, and `Rollback` says `Done` per step.
Anything that was there before the run is left alone.

Run it again: every host reports `Changed = False`. After changing the broker password or the `INTERNAL_API_TOKEN`,
run it with `-Force` to recreate the agents with the new secrets.

## Get-NexusFleetStatus

What NexusInfra says about every node, merged with what the host itself says over SSH:

```powershell
$hosts | Get-NexusFleetStatus | Format-Table Name, Ok, Health, LastHeartbeat, AgentState, Problem
```

```text
Name        Ok    Health  LastHeartbeat        AgentState Problem
----        --    ------  -------------        ---------- -------
node-home01 True  healthy 04/11/2026 07:49:54  running
node-home02 False offline 04/11/2026 07:20:11  exited     NexusInfra reports it offline; the agent container is exited
```

- Without an inventory (`Get-NexusFleetStatus` alone), you get NexusInfra's view only.
- Nodes NexusInfra knows but the inventory does not are listed after the inventory.
- `Where-Object { -not $_.Ok }` lists what needs attention.
- An unreachable host, or even an unreachable panel, is reported in the result and never stops the command.

## Export-NexusFleetStatus

```powershell
$hosts | Get-NexusFleetStatus | Export-NexusFleetStatus -Path ./status.csv
Get-NexusFleetStatus | Export-NexusFleetStatus -Path ./status.json
```

JSON holds `generatedAt` and every field of every node. CSV has one row per node. Times are ISO-8601 UTC in both.

## Logs

Every run writes to `logs/<RunId>/` in the current folder, or under `Log.Directory` when you set that in your config
(see [configuration](configuration.md#log-the-run-logs)): `run.log` for the run, and one file per host. One line per
event, with secrets replaced by `***`:

```text
2026-11-04T07:34:06.512Z INFO    run=20261104T073356Z-c117f1 host=node-lab1 step=AgentContainer applied
2026-11-04T07:34:09.640Z INFO    run=20261104T073356Z-c117f1 host=node-lab1 step=VerifyHealthy applied
```

A dry run is logged too. Add `-Verbose` to see the lines while the cmdlet runs.

## Results are objects

Every cmdlet returns objects, not text. Filter, sort, group and export them like any PowerShell output:

```powershell
$results = $hosts | Install-NexusNode
$results | Where-Object { -not $_.Success } | Format-List Host, Step, Error
$results | Group-Object Success
($results | Where-Object Host -EQ 'node-home02').Steps
```
