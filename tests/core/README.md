# tests/core — tests for src/core

| File | What it proves |
|---|---|
| `Register-NexusStep.Tests.ps1`, `ConvertTo-NexusCommandResult.Tests.ps1` | The two contracts: a step needs a unique name and order; a transport result says whether ssh itself failed |
| `Invoke-NexusStepSequence.Tests.ps1` | The step runner: Test, then Apply where needed. On a failure it rolls back only what this run applied, in reverse. `-PlanOnly` runs only the Tests |
| `Invoke-NexusStepCommand.Tests.ps1`, `Invoke-NexusStepApi.Tests.ps1` | The helpers steps use, with the settings of the step context |
| `Invoke-NexusHostPreflight.Tests.ps1` | Every preflight check, passing and failing, from one fact at a time |
| `Invoke-NexusHostInstall.Tests.ps1` | A whole install against the fake fleet: twice in a row (the second run changes nothing), a failure at each step (with rollback), and the dry run |
| `Get-NexusHostStatus.Tests.ps1` | The facts one host reports about itself, an unreachable host, and odd answers |
| `ConvertTo-NexusNodeStatus.Tests.ps1` | Merging NexusInfra's view and the host's view: `Ok` and a `Problem` in plain words |
| `ConvertTo-Nexus*Failure.Tests.ps1` | The failure results that keep "one result per host" true |

## The fake fleet

`FakeFleet.ps1` is not a test file, but the helper the install tests share. It mocks `Invoke-NexusHostCommand` and
`Invoke-NexusApi` with functions that read and change a hashtable: fake hosts and a fake panel that remember what
was installed. With it, the **real** steps run through the **real** step runner, and a test can:
- run twice and check that nothing changed;
- make any step fail on any host;
- look afterwards at what "happened" on the host and in NexusInfra.
