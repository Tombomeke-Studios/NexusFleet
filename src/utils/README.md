# src/utils — shared helpers

Small internal functions the rest of the module builds on. None is exported.

| File | What it does |
|---|---|
| **Configuration** | |
| `Get-NexusConfig.ps1` | Reads `config/nexusinfra.psd1` and your `nexusinfra.local.psd1`, checks every value against a rule, and reports every problem at once |
| `Merge-NexusHashtable.ps1` | Puts your local config over the default (a deep merge). Warns about unknown keys, which are usually a typo |
| **Runs and logging** | |
| `Initialize-NexusRunContext.ps1` | Starts a run: a RunId, its log folder (`Log.Directory`), removing old runs (`Log.KeepRuns`), and the secrets to hide |
| `Write-NexusLog.ps1` | One line per event, one file per host plus `run.log`. Secrets become `***`, longest first. A write that fails gives a warning, never an error |
| **The connection and secrets** | |
| `Get-NexusSession.ps1` | The connection of `Connect-NexusInfra`, or the error `NexusFleet.NotConnected` |
| `Get-NexusStoredToken.ps1`, `Save-NexusStoredToken.ps1` | The only callers of SecretManagement, with clear errors when it or a vault is missing |
| `Get-NexusUrlPassword.ps1` | The password inside the broker URL, so the log can hide it on its own too |
| **Talking to hosts** | |
| `Get-NexusSshParameter.ps1` | The ssh settings of one host (from the inventory and the config), as a splat for `Invoke-NexusHostCommand` |
| `Get-NexusApiParameter.ps1` | The connection settings of the session, as a splat for `Invoke-NexusApi` |
| `ConvertTo-NexusShellArgument.ps1` | Single-quotes a value for bash, so no value can break out of a remote command |
| `ConvertFrom-NexusFactLine.ps1` | Reads the `key=value` lines a host prints into a hashtable |
| **The per-host loop** | |
| `Invoke-NexusHostLoop.ps1` | Runs a per-host function for every host, one after the other or in parallel. In parallel, the module is loaded in each runspace. It shows a progress bar, and every host gets a result, also when its work fails |

Tests: [`tests/utils/`](../../tests/utils/README.md). The design of the loop and of the logging:
[docs/architecture.md](../../docs/architecture.md).
