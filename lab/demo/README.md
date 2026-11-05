# The demo on lab VMs

What the lab VMs (#14) need, and how to run the phase 4 demo on them with `Invoke-NexusDemo.ps1`. The same script
runs against the node lab (`../node-lab/`), which needs only Docker.

## 1. The control plane (NexusInfra)

A NexusInfra community install the VMs can reach, for example on your own machine or a separate VM
(`deploy/community` in the NexusInfra repository, at least v0.4.0). Two things differ from a single-machine install:

- **The broker must be reachable from the VMs.** Since NexusInfra's `fleet-support` changes (on its `dev` branch,
  in the next release; see [docs/nexusinfra-wijzigingen.md](../../docs/nexusinfra-wijzigingen.md)):
  - the installer (`deploy/install.sh` or `install.ps1`) asks for the address to publish the broker on and writes
    it as `BROKER_BIND`. With an `.env` of your own, set `BROKER_BIND` to the control plane's address on the lab
    network, then `docker compose up -d`;
  - the installer writes a broker user and password (`RABBITMQ_USER`, `RABBITMQ_PASS`). With a hand-written
    `.env`, set both before the first start. RabbitMQ refuses `guest` from another machine.

  The agents then connect with `amqp://<user>:<password>@<control-plane-address>:5672`. With the 0.4.0 bundle, add
  `ports: ['<lab-address>:5672:5672']` to its `rabbitmq` service yourself.
- **The orchestrator must reach the agents** on `http://<vm-address>:9100` (that is each VM's `agentUrl`); see
  [over the internet](#over-the-internet-without-a-vpn).

Note the `INTERNAL_API_TOKEN` from the control plane's `.env`: the agents need the same value.

In the panel: sign in as the admin, create an API token with the scopes **write** and **admin** (`POST /me/tokens`,
or the panel's API token page).

## Over the internet, without a VPN

NexusFleet is built for hosts anywhere, so the demo does not use a VPN: every new node would first have to join it
(see the proposal, "Hoe het werkt"). The orchestrator reaches each agent directly, and each agent reaches the broker
directly. Four connections have to work:

| From | To | Port | Over |
|---|---|---|---|
| the admin machine (NexusFleet) | each host | 22 | ssh, key |
| the admin machine | the gateway | 9400 | HTTP, API token |
| each host's agent | the broker | 5672 | AMQP, broker password |
| the orchestrator | each host's agent | 9100 | HTTP, `INTERNAL_API_TOKEN` |

The last row is the one people forget: deploying, files, the console and backups are calls from the orchestrator
**to** the agent. A node whose heartbeats arrive is *healthy* even when that direction is closed. NexusFleet's
last step, `AgentReachable`, checks exactly this direction, so a node that NexusInfra cannot control is reported as
failed, with the reason.

### The control plane: a public name and port forwarding

For example the control plane on a desktop at home (Docker Desktop, home address `192.168.0.6`):

1. **DNS at your domain's provider:** an `A` record, for example `nexus.<your-domain>`, pointing to the public address
   of the home connection. If that address changes, the record has to follow (ask the provider about dynamic DNS).
2. **Port forwarding on the home router** to the desktop:

   | Outside | To | For |
   |---|---|---|
   | 5672 | `192.168.0.6:5672` | the broker: the agents |
   | 9400 | `192.168.0.6:9400` | the gateway: NexusFleet and the panel's API |

   And in Windows Firewall an inbound rule for those two ports.
3. **The NexusInfra installer:** answer its broker question with the desktop's own address (`192.168.0.6`): that is
   where the router forwards to. It writes `BROKER_BIND` and prints the broker URL with that address; the agents
   come in from outside, so theirs has the public name: `amqp://nexusinfra:<RABBITMQ_PASS>@nexus.<your-domain>:5672`.
4. **NexusFleet's `config/nexusinfra.local.psd1`:**

   ```powershell
   @{
       Api    = @{ BaseUrl = 'http://nexus.<your-domain>:9400'; AllowUnencryptedHttp = $true }
       Broker = @{ Host = 'nexus.<your-domain>' }
   }
   ```

`AllowUnencryptedHttp` sends the API token unencrypted, with a warning every run. For anything beyond the demo, put
TLS in front of the gateway (NexusInfra `docs/deployment.md`, reverse proxy) and use `https://`. A Cloudflare
Tunnel is another way to publish the panel and the gateway over `https://` without opening 9400, but not the
broker: AMQP is not HTTP.

### The hosts

| Host | `address` (ssh) | `agentUrl` (the orchestrator calls it) | Open |
|---|---|---|---|
| a cloud VM (Azure, or any VPS) | its public address | default: `http://<public address>:9100` | in the network security group: 22, and 9100 only from the home address |
| a VM at home, next to the control plane (VirtualBox, bridged) | `nexus.<your-domain>`, `port` 2222 (router: 2222 → the VM's 22) | `http://<the VM's home address>:9100`: the orchestrator is on the same network | nothing for 9100 |
| a VM on a laptop at school | its address on the laptop | none: `"reach": "outbound"` | nothing: its agent connects to `wss://nexus.<your-domain>/agent-link` itself |

The orchestrator at home can never open a connection to the laptop VM at school: the school's network is in between,
and no port forwarding at home changes that. So that host gets `"reach": "outbound"`: its agent connects to the
control plane over the agent link, through the same gateway as the panel, and the control plane's calls come back
over that connection ([agent-link.md](../../docs/agent-link.md), K11). It needs a NexusInfra with the agent link
(NexusInfra #416) and TLS in front of the gateway (`wss://`). Until then, this host shows criterion 3 honestly: it
fails at `AgentReachable` with the reason, and the other hosts are not stopped by it. Run NexusFleet itself from the
laptop.

The broker still needs its own port (5672) from every host, also the outbound one: a network that only lets 443
out (some school and guest networks) blocks the heartbeats. Test the school network beforehand.

Two things to check before the demo:
- **The broker from each host:** `Test-NexusHost` checks it from the host itself (`Broker`).
- **The VM at home and the public name:** that VM reaches the broker through `nexus.<your-domain>`, so through the
  router from the inside. Not every router allows that (*NAT loopback*). If its `Broker` check fails, add
  `192.168.0.6 nexus.<your-domain>` to its `/etc/hosts`.

**Security in the MVP:** the broker password and the `INTERNAL_API_TOKEN` travel unencrypted. The security group on
the cloud VM (9100 only from home) and a broker user of its own limit that for the demo. Closing it properly is the
extra "secured connection": Caddy as the only entry with an IP allowlist, TLS and `amqps://`, a broker user per node.

## 2. Each VM

- Ubuntu 24.04 (fresh is fine; NexusFleet installs Docker itself), at least 2 GB free on `/`, internet access for
  `apt` and `ghcr.io`.
- A user that logs in with an SSH key only and may use sudo without a password. As root on the VM:

  ```bash
  useradd --create-home --shell /bin/bash fleet
  echo 'fleet ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/fleet && chmod 440 /etc/sudoers.d/fleet
  install -d -m 700 -o fleet -g fleet /home/fleet/.ssh
  echo '<your public key>' > /home/fleet/.ssh/authorized_keys
  chown fleet:fleet /home/fleet/.ssh/authorized_keys && chmod 600 /home/fleet/.ssh/authorized_keys
  ```
- Port 22 reachable from the admin machine; port 9100 reachable from the control plane.
- The broker reachable from the VM: `Test-NexusHost` checks this (`Broker`).

Docker-published ports bypass `ufw`; restricting 9100 to the orchestrator is part of the "secured connection" extra.

## 3. The admin machine

PowerShell 7.6, OpenSSH client, and SecretManagement with a vault:

```powershell
Install-Module Microsoft.PowerShell.SecretManagement, Microsoft.PowerShell.SecretStore -Scope CurrentUser
Register-SecretVault -Name NexusFleet -ModuleName Microsoft.PowerShell.SecretStore -DefaultVault
```

`config/nexusinfra.local.psd1` (git-ignored) with your addresses, e.g.:

```powershell
@{
    Api    = @{ BaseUrl = 'http://192.168.56.1:9400'; AllowUnencryptedHttp = $true }   # $true only on a lab network
    Broker = @{ Host = '192.168.56.1' }
}
```

`config/inventory.json` (git-ignored), e.g. three VMs and one host that cannot work, to show criterion 3:

```json
{
  "defaults": { "user": "fleet", "location": "lab", "keyFile": "C:/Users/you/.ssh/nexusfleet_lab" },
  "hosts": [
    { "name": "node-vm1", "address": "192.168.56.11" },
    { "name": "node-vm2", "address": "192.168.56.12" },
    { "name": "node-vm3", "address": "192.168.56.13" },
    { "name": "node-broken", "address": "192.168.56.99" }
  ]
}
```

Store the secrets once:

```powershell
Import-Module ./NexusFleet.psd1
Connect-NexusInfra -Token (Read-Host -AsSecureString 'API token') -Save
Set-Secret -Name NexusFleet-RabbitMqUrl -Secret (Read-Host -AsSecureString 'RABBITMQ_URL')
Set-Secret -Name NexusFleet-InternalApiToken -Secret (Read-Host -AsSecureString 'INTERNAL_API_TOKEN')
```

## 4. The demo

```powershell
Import-Module ./NexusFleet.psd1
Connect-NexusInfra
./lab/demo/Invoke-NexusDemo.ps1 -InventoryPath ./config/inventory.json
```

It runs the preflight, the plan (`-WhatIf`), the installation, a second run and the status, times each phase, checks
the three "Klaar als" criteria on the results, and writes to `lab/demo/results/<time>/` (git-ignored):
`summary.md` (times and criteria, for the report), `measurements.json`, `results.json`, `status.json`, `status.csv`.
Compare the installation time with the manual baseline of E0 (#15).

To run it again on fresh VMs: restore a VM snapshot (best), or remove what NexusFleet installed:
`sudo docker rm -f nexusinfra-node-agent; sudo rm -f /etc/nexusinfra/agent.env; sudo apt-get remove -y docker.io`,
and delete the nodes in the panel.

## The same against the node lab

One command, after starting the lab:

```powershell
./lab/node-lab/Start-NodeLab.ps1
./lab/demo/Invoke-NexusLabDemo.ps1
```

`Invoke-NexusLabDemo.ps1` reads everything from `lab/node-lab/.keys/`: it points `NEXUSFLEET_CONFIG` at the lab's
config override (and puts it back afterwards, so `config/` is never touched), connects with the lab's API token, and
builds a demo inventory. That inventory has the two direct hosts, the outbound host when the control plane has the
agent link (a lab started with `-BuildFrom`), and `node-broken`, a host on a port where nothing listens: the failing
host of criterion 3. Then it runs `Invoke-NexusDemo.ps1` with the lab's agent secrets.

CI does the same on every pull request (the `Demo` jobs of `integration.yml`). It puts `summary.md` in the job
summary and fails when a criterion does not hold.

Times in the node lab are not representative: Docker's packages and the agent image are cached after the first run.
