# src/public — the exported cmdlets

The six commands a user runs. Each one is listed in `FunctionsToExport` in the manifest, and the export test fails
when the two do not match.

| File | Cmdlet | In short |
|---|---|---|
| `Connect-NexusInfra.ps1` | `Connect-NexusInfra` | Connects to the panel. Checks the account role and the token's `admin` scope. `-Save` stores the token with SecretManagement |
| `Import-NexusInventory.ps1` | `Import-NexusInventory` | Reads the inventory JSON into `NexusFleet.Host` objects. Checks every field and reports every problem at once |
| `Test-NexusHost.ps1` | `Test-NexusHost` | The preflight of every host, in parallel; changes nothing |
| `Install-NexusNode.ps1` | `Install-NexusNode` | Turns hosts into healthy nodes, idempotent and with rollback. `-WhatIf` shows the plan; `-Force` is for after a secret changed |
| `Get-NexusFleetStatus.ps1` | `Get-NexusFleetStatus` | NexusInfra's view of every node, merged with what the host itself says over ssh |
| `Export-NexusFleetStatus.ps1` | `Export-NexusFleetStatus` | Writes that status to JSON or CSV |
| `Get-NexusServer.ps1` | `Get-NexusServer` | Lists NexusInfra's servers (`GET /deployments`, every page), filtered by node, status or name |
| `Invoke-NexusFleetAction.ps1` | `Invoke-NexusFleetAction` | One action for a group of servers (`POST /deployments/bulk`), in batches of at most 100, with a result per server |
| `Sync-NexusFleet.ps1` | `Sync-NexusFleet` | Drift detection: the install's dry run per host, the differences in words, unmanaged nodes, and the repair through `Install-NexusNode` |
| `Remove-NexusNode.ps1` | `Remove-NexusNode` | Deregisters nodes and removes the agent from their hosts, in parallel; asks per host, `-WhatIf` shows the plan |

## How a cmdlet is built

- **Collect, then work.** A cmdlet that works per host collects the hosts in `process`. It does the work in `end`
  through `Invoke-NexusHostLoop` ([`../utils/`](../utils/README.md)). The work for one host lives in
  [`../core/`](../core/README.md), so it can be tested directly.
- **`-WhatIf` is decided first.** A changing cmdlet has `SupportsShouldProcess`. `ShouldProcess` does not work inside
  the parallel loop, so the cmdlet decides per host before the loop starts.
- **Objects, never text.** Every result is a `[pscustomobject]` with a `PSTypeName`.
- **Full help.** Every cmdlet has comment-based help: a description, every parameter, at least two explained
  examples, inputs, outputs, notes and links. `tests/NexusFleet.Tests.ps1` checks all of it.

User documentation: [docs/user-guide.md](../../docs/user-guide.md). Tests: [`tests/public/`](../../tests/public/README.md).
