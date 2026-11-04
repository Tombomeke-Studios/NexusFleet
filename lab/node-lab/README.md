# node-lab — a NexusInfra control plane and two fresh hosts, on your machine

The whole installation end to end, with nothing but Docker. The integration tests run here: locally, and in CI by
`integration.yml`.

```text
Docker network 172.29.50.0/24
  control plane   rabbitmq · orchestrator · gateway (127.0.0.1:29400) · control-room
  node1           fresh Ubuntu, ssh on 127.0.0.1:2231
  node2           fresh Ubuntu, ssh on 127.0.0.1:2232
```

Only the gateway and the two ssh ports are published, and only on this machine.

| File | What it is |
|---|---|
| `Start-NodeLab.ps1` | Starts the lab, prepares everything NexusFleet needs, and waits until the broker is reachable from the hosts. `-Remove` stops it again |
| `docker-compose.yml` | The control plane from NexusInfra's published images (`-Version`, default `0.4.0-community`), and the two hosts |
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
- a config override;
- an inventory of the two hosts.

To start over with new secrets, delete `.keys/` after `-Remove`.

The hosts are privileged containers, because Docker runs inside them. That is fine for a lab on your own machine,
and is why the lab never replaces a test on real VMs ([../demo/README.md](../demo/README.md)).
