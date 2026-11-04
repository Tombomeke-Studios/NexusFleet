# src/core — the step runner, the contracts and the per-host engines

The heart of the module. Nothing here is exported: the cmdlets in [`../public/`](../public/README.md) call it.

## Files

| File | What it is |
|---|---|
| **Contracts** | |
| `ConvertTo-NexusCommandResult.ps1` | Builds the `NexusFleet.CommandResult` every transport returns: `HostName`, `ExitCode`, `StdOut`, `StdErr`, `Succeeded`, and `TransportFailed` (ssh's exit 255) |
| `Register-NexusStep.ps1` | What an installation step is: a `Name`, a unique `Order`, and three script blocks (`Test`, `Apply`, `Rollback`). Called once by every file in [`../steps/`](../steps/README.md) |
| `Get-NexusStep.ps1` | The registered steps, sorted by `Order` |
| **The step runner** | |
| `Invoke-NexusStepSequence.ps1` | Runs the steps for one host: each `Test`, then `Apply` where needed. When a step fails, it rolls back what this run applied, in reverse order. With `-PlanOnly` (the dry run) it runs only the Tests |
| `Invoke-NexusStepCommand.ps1` | Runs a command on the step's host, with the ssh settings of the step context. Throws on a failure, naming the host |
| `Invoke-NexusStepApi.ps1` | Calls the NexusInfra API with the connection of the step context |
| **Per-host engines** (each never throws) | |
| `Invoke-NexusHostPreflight.ps1` | Is one host ready? Two ssh calls: a login, then one script that prints every fact as `key=value` |
| `Invoke-NexusHostInstall.ps1` | Turns one host into a node: the preflight, then the step runner with the full step context |
| `Get-NexusHostStatus.ps1` | What one host says about itself: uptime, disk, Docker, the agent container. One ssh call, changes nothing |
| **Failure results and the merge** | |
| `ConvertTo-NexusPreflightFailure.ps1`, `ConvertTo-NexusInstallFailure.ps1`, `ConvertTo-NexusHostStatusFailure.ps1` | The result of a host whose work failed unexpectedly, so every host still gets a result |
| `ConvertTo-NexusNodeStatus.ps1` | Merges what NexusInfra and the host say into one `NexusFleet.NodeStatus`, with `Ok` and a `Problem` in plain words |

## How the pieces fit

```text
public cmdlet ──► Invoke-NexusHostLoop (utils) ──► per host: Invoke-NexusHostInstall
                                                     ├─ Invoke-NexusHostPreflight
                                                     └─ Invoke-NexusStepSequence ──► the steps (src/steps)
                                                          └─ Invoke-NexusStepCommand / Invoke-NexusStepApi
```

The engines get everything as parameters: the config, the session and the run context. They also run in parallel
runspaces, where module variables do not exist. More: [docs/architecture.md](../../docs/architecture.md).
Tests: [`tests/core/`](../../tests/core/README.md).
