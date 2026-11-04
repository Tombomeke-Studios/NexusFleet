# tests/public — tests for the cmdlets

Most cmdlets have up to three test files, from fast to real:

| Kind | Example | How |
|---|---|---|
| `<Cmdlet>.Tests.ps1` | `Install-NexusNode.Tests.ps1` | With `-ThrottleLimit 1`, so the hosts run in this runspace and the mocks work |
| `<Cmdlet>.LocalSsh.Tests.ps1` | `Test-NexusHost.LocalSsh.Tests.ps1` | The real parallel path with the real `ssh` against closed loopback ports. Every host must get its own result from a real runspace, and the logs must be written from there |
| `<Cmdlet>.Integration.Tests.ps1` | `Install-NexusNode.Integration.Tests.ps1` | Against the labs in Docker: a real NexusInfra and fresh Ubuntu hosts. The three MVP criteria are tested here |

Plus:

| File | What it proves |
|---|---|
| `Connect-NexusInfra.LocalHttp.Tests.ps1` | The connection against a real local HTTP server, which a mock of `Invoke-RestMethod` cannot replace |
| `Import-NexusInventory.Tests.ps1` | Every field rule of the inventory, defaults, duplicates, and every problem reported at once |
| `Scale.Tests.ps1` | Generated inventories of 50 and 100 hosts, some unreachable and some failing. Exactly one correct result per host, and no crash |

The integration tests skip themselves without a running lab. In CI a skip fails the job, because there the labs are
always started first.
