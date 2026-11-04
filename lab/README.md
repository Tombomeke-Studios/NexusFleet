# lab — the experiments, the node lab and the demo

Nothing here is part of the module, but it is all linted. The experiments of phase 1 settled the design. The node lab
and the demo prove that the module works. The results and decisions are in
[docs/ontwerpkeuzes.md](../docs/ontwerpkeuzes.md).

## Experiments

| | Question | Outcome | Folder |
|---|---|---|---|
| **E1** | How does NexusFleet talk to a host? | native `ssh`, secrets over stdin | [E1-transport/](E1-transport/README.md) |
| **E2** | How does it handle many hosts at once? | `ForEach-Object -Parallel` | [E2-concurrency/](E2-concurrency/README.md) |
| **E3** | Do Pester mocks reach into parallel runspaces? | no, so the work per host is its own function | [E3-mocks-parallel/](E3-mocks-parallel/README.md) |
| **E4** | Which token rights does managing nodes need? | a platform admin with the scopes `write` and `admin` | [E4-token-scopes/](E4-token-scopes/README.md) |

## Proving it works

| | What | Folder |
|---|---|---|
| **Node lab** | A NexusInfra control plane and two fresh Ubuntu hosts in Docker, on your machine. The integration tests run here, locally and in CI | [node-lab/](node-lab/README.md) |
| **Demo** | The whole flow on an inventory, timed per phase, with the three MVP criteria checked. Also: what real lab VMs need | [demo/](demo/README.md) |

```powershell
./lab/node-lab/Start-NodeLab.ps1                       # start the node lab
./tools/Invoke-NexusTests.ps1 -Suite Integration       # the integration tests against it
./lab/node-lab/Start-NodeLab.ps1 -Remove               # and remove it again
```

The demo against the node lab, step by step: [demo/README.md](demo/README.md).

The labs need Docker. Keys and secrets for the labs are created in each lab's git-ignored `.keys/` folder, and are
for the lab only.
