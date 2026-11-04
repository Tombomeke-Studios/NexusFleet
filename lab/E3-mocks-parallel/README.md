# E3 — do Pester mocks reach into parallel runspaces?

**Question:** does a Pester `Mock` also work for code that runs in `ForEach-Object -Parallel`? And does the pattern
"the work for one host in its own function" solve it?

**Outcome:**
- **No.** A runspace imports its own copy of the module, which the mock never sees.
- **Yes, the pattern solves it.** The function for one host is tested directly, with mocks. The parallel loop
  around it stays thin, and is tested with real runspaces.

NexusFleet follows that pattern everywhere. Details:
[docs/ontwerpkeuzes.md](../../docs/ontwerpkeuzes.md#e3--pester-mocks-en--parallel-runspaces).

| File | What it is |
|---|---|
| `FleetDemo.psm1` | A mini module with the same shape as NexusFleet. `Get-DemoAnswer` stands in for ssh or the API. `Invoke-DemoHostWork` is the work for one host. Two thin wrappers run it: a plain loop, and `ForEach-Object -Parallel` with the module imported in each runspace |
| `MocksAndParallel.Tests.ps1` | Three tests: where the mock works (called directly, and in the plain loop) and where it does not (`-Parallel`) |

```powershell
Import-Module Pester -MinimumVersion 5.0 -MaximumVersion 5.99
Invoke-Pester -Path ./lab/E3-mocks-parallel -Output Detailed
```
