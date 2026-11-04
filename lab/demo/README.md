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
- **The orchestrator must reach the agents** on `http://<vm-address>:9100` (that is each VM's `agentUrl`).

Note the `INTERNAL_API_TOKEN` from the control plane's `.env`: the agents need the same value.

In the panel: sign in as the admin, create an API token with the scopes **write** and **admin** (`POST /me/tokens`,
or the panel's API token page).

## Machines on different networks

For example: the control plane on a desktop at home (Docker Desktop), one VM in VirtualBox on that desktop, one on
a laptop, one on Azure, and the demo shown from school. Four connections have to work:

| From | To | Port | Over |
|---|---|---|---|
| the admin machine | each host | 22 | ssh |
| the admin machine | the gateway | 9400 | HTTP, API token |
| each host's agent | the broker | 5672 | AMQP, broker password |
| the orchestrator | each host's agent | 9100 | HTTP, `INTERNAL_API_TOKEN` |

The last row decides it: the orchestrator at home opens the connection to each agent. A laptop on the school
network is behind that network's NAT, so nothing at home can reach it, and port forwarding at home does not
change that. Publishing 5672 and 9100 on the internet would also send the broker password and the
`INTERNAL_API_TOKEN` unencrypted.

**Use an overlay network instead**, such as [Tailscale](https://tailscale.com/kb/1017/install) (free for personal
use). Install it on the desktop, on each VM, and on the laptop you run NexusFleet from. Every machine then gets a
fixed address (`100.x.y.z`) that works from any network, school included, and the traffic between them is
encrypted. No port forwarding is needed. Use those addresses everywhere:

| Setting | Value |
|---|---|
| The installer's broker question (`BROKER_BIND`) | the desktop's Tailscale address |
| `Broker.Host` in `config/nexusinfra.local.psd1` | the desktop's Tailscale address |
| `Api.BaseUrl` | `http://<desktop's Tailscale address>:9400`, with `AllowUnencryptedHttp = $true` (Tailscale encrypts it) |
| `address` of each host in the inventory | the VM's Tailscale address |
| `agentUrl` (default `http://<address>:9100`) | follows from the address |

Then check:
- Docker Desktop publishes the broker on that address: `Test-NexusHost` checks the broker from each VM (`Broker`).
  If the check fails, set `BROKER_BIND=0.0.0.0` and allow port 5672 in Windows Firewall only from `100.64.0.0/10`.
- On Azure, open no ports in the network security group for 9100 or 5672: Tailscale needs none.
- Port forwarding the panel is only needed to show it to someone outside the overlay. Then only behind TLS
  (NexusInfra `docs/deployment.md`).

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

```powershell
./lab/node-lab/Start-NodeLab.ps1
Copy-Item ./lab/node-lab/.keys/nexusinfra.lab.psd1 ./config/nexusinfra.local.psd1
$lab = @{}; Get-Content ./lab/node-lab/.keys/.env | ForEach-Object { $k, $v = $_ -split '=', 2; $lab[$k] = $v }
Import-Module ./NexusFleet.psd1
Connect-NexusInfra -Token (ConvertTo-SecureString (Get-Content ./lab/node-lab/.keys/api-token -Raw) -AsPlainText -Force)
./lab/demo/Invoke-NexusDemo.ps1 -InventoryPath ./lab/node-lab/.keys/inventory.lab.json `
    -RabbitMqUrl (ConvertTo-SecureString "amqp://$($lab.RABBITMQ_USER):$($lab.RABBITMQ_PASS)@172.29.50.10:5672" -AsPlainText -Force) `
    -InternalApiToken (ConvertTo-SecureString $lab.INTERNAL_API_TOKEN -AsPlainText -Force)
Remove-Item ./config/nexusinfra.local.psd1
```

Times in the node lab are not representative: Docker's packages and the agent image are cached after the first run.
