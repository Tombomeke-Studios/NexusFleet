# src/core — contracts, the step runner and the per-host engines

- **Contracts:** `ConvertTo-NexusCommandResult` (what every transport returns); `Register-NexusStep` and
  `Get-NexusStep` (what an installation step is).
- **The step runner:** `Invoke-NexusStepSequence` runs the steps for one host: Test, then Apply where needed,
  rollback in reverse on failure, and only the Tests with `-PlanOnly`.
- **Helpers for steps:** `Invoke-NexusStepCommand` (a command on the step's host), `Invoke-NexusStepApi`.
- **Per-host engines**, the work for one host that the public cmdlets run in parallel; each never throws:
  `Invoke-NexusHostPreflight`, `Invoke-NexusHostInstall`, `Get-NexusHostStatus`, plus
  `ConvertTo-NexusPreflightFailure`, `ConvertTo-NexusInstallFailure`, `ConvertTo-NexusHostStatusFailure` and
  `ConvertTo-NexusNodeStatus`.

See docs/architecture.md.
