# src/public — the exported cmdlets

`Connect-NexusInfra`, `Import-NexusInventory`, `Test-NexusHost`, `Install-NexusNode`, `Get-NexusFleetStatus`
and `Export-NexusFleetStatus`. Each is listed in `FunctionsToExport` in the manifest and has full comment-based
help (checked by `tests/NexusFleet.Tests.ps1`). The cmdlets that work per host collect the hosts in `process` and
run the per-host engine of `src/core` in `end`, in parallel. See docs/user-guide.md.
