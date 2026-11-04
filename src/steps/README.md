# src/steps — the installation steps

One file per step. Each file calls `Register-NexusStep` once when the module loads. `Install-NexusNode` runs the
steps in the order of their `Order` number.

| Order | File | Ensures | Rollback |
|---|---|---|---|
| 10 | `Docker.ps1` | Docker is installed and running: Ubuntu's `docker.io`, waiting for a busy apt, with or without systemd | removes the package, but only when this run installed it |
| 20 | `RegisterNode.ps1` | NexusInfra has a node record with the host's name, location and agent URL (`POST /nodes`) | deletes the record, but only when this run created it |
| 30 | `AgentContainer.ps1` | The agent runs with every setting, including the three that fail silently (restart policy, port, backups volume). Its secrets go to `/etc/nexusinfra/agent.env` (mode 600) over stdin | removes the container and the env file; never the backups volume |
| 40 | `VerifyHealthy.ps1` | NexusInfra reports the node healthy. After a new agent started, it first waits until the old agent's last heartbeat no longer counts | nothing to undo |
| 50 | `AgentReachable.ps1` | NexusInfra can call the agent: `GET /nodes/<id>/disk` makes the orchestrator call it with the `INTERNAL_API_TOKEN`. Healthy only proves that heartbeats arrive (node → broker); deploying goes the other way | nothing to undo |

## Writing a step

Every step has three parts:

- **`Test`** returns `$true` when the host is already in order. It never changes anything, because `-WhatIf` runs
  only the Tests.
- **`Apply`** makes the change, and throws when it fails.
- **`Rollback`** undoes `Apply`. It runs only when this run applied the step, and must be safe after an `Apply` that
  stopped halfway.

Leave gaps in the numbers (10, 20, 30) so a new step fits in between. Adding, replacing or removing a step means
adding, replacing or removing a file here. The runner, the cmdlet and `-WhatIf` pick the change up by themselves. A
template and the step context: [docs/development.md](../../docs/development.md#adding-an-installation-step).
Tests: [`tests/steps/`](../../tests/steps/README.md).
