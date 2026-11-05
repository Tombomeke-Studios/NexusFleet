# node-lab — a NexusInfra control plane and three fresh hosts, on your machine

The whole installation end to end, with nothing but Docker. The integration tests run here: locally, and in CI by
`integration.yml`.

```text
Docker network 172.29.50.0/24
  control plane   rabbitmq · orchestrator · gateway (127.0.0.1:29400) · control-room
  node1           fresh Ubuntu, ssh on 127.0.0.1:2231
  node2           fresh Ubuntu, ssh on 127.0.0.1:2232
  node3           fresh Ubuntu, ssh on 127.0.0.1:2233, the outbound host (reach "outbound")
```

Only the gateway and the three ssh ports are published, and only on this machine.

node3 is the host behind NAT of [docs/agent-link.md](../../docs/agent-link.md). Its agent publishes no port, so the
orchestrator cannot call it on its address; it can only reach it over the agent link that the agent opens to the
gateway (`ws://172.29.50.12:9400/agent-link`, without TLS because this is a lab). It needs a NexusInfra with the
agent link. Against 0.4.0 the integration test checks that `Test-NexusHost` refuses it with a clear reason instead.

## A NexusInfra that is not released yet

The agent link (NexusInfra #417) is on NexusInfra's `dev`, not in a release. Build the images from a checkout:

```powershell
./lab/node-lab/Start-NodeLab.ps1 -Version agentlink-community -BuildFrom ../NexusInfra
```

That builds the four images under the published names with that tag, so the compose file uses them. The hosts run
their own Docker and cannot see this machine's images, so the agent image also goes into the lab registry
(`registry`, 172.29.50.30:5000, pushed through `127.0.0.1:29500`), and the lab config points `Agent.Image` there.
The host image allows that registry over plain HTTP (`node/Dockerfile`, `/etc/docker/daemon.json`). CI does the same
in the `Integration (NexusInfra dev)` job.

| File | What it is |
|---|---|
| `Start-NodeLab.ps1` | Starts the lab, prepares everything NexusFleet needs, and waits until the broker is reachable from the hosts. `-Remove` stops it again |
| `docker-compose.yml` | The control plane from NexusInfra's published images (`-Version`, default `0.4.0-community`), and the three hosts |
| `node/Dockerfile` | A fresh Ubuntu host: sshd and a `fleet` user with passwordless `sudo`. No Docker: NexusFleet installs it |

## Run it

```powershell
./lab/node-lab/Start-NodeLab.ps1
./tools/Invoke-NexusTests.ps1 -Suite Integration
./lab/node-lab/Start-NodeLab.ps1 -Remove
```

`Start-NodeLab.ps1` writes everything into the git-ignored `.keys/` folder:
- an SSH key and an empty `known_hosts`;
- lab-only secrets (`.env`);
- an API token with `write` and `admin`, checked again on every start;
- a config override (with the agent link URL, and `ws://` allowed for this lab);
- an inventory of the two direct hosts (`inventory.lab.json`), and one of the outbound host (`inventory.outbound.json`).

To start over with new secrets, delete `.keys/` after `-Remove`.

The hosts are privileged containers, because Docker runs inside them. That is fine for a lab on your own machine,
and is why the lab never replaces a test on real VMs ([../demo/README.md](../demo/README.md)).
