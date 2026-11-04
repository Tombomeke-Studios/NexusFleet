# NexusFleet — Architecture

How the module is built: its parts, the contracts between them and how data flows through a run.
The design follows the [proposal](projectvoorstel.md). How to work on it is in [development.md](development.md),
how it is tested in [testing.md](testing.md), and how to use it in the [user guide](user-guide.md).

## Overview

A PowerShell 7.6 module that talks to NexusInfra over its REST API (`Invoke-NexusApi`) and to hosts over SSH
(`Invoke-NexusHostCommand`), and turns an inventory of hosts into healthy nodes by running a sequence of steps per
host (`Invoke-NexusStepSequence`). The public cmdlets that tie this together come in phase 3.

## Module loading

The manifest (`NexusFleet.psd1`) requires PowerShell 7.6+ (Core, LTS) and exports an explicit list of public
cmdlets. The loader (`NexusFleet.psm1`) dot-sources `src/` folder by folder in a fixed order:
`core` → `utils` → `transports` → `api` → `steps` → `public`.

## Components

One responsibility per folder in `src/`. All functions below are internal (not exported); the public cmdlets in
`src/public/` (phase 3) are built on them.

| Folder | Functions | Responsibility |
|---|---|---|
| `core` | `ConvertTo-NexusCommandResult`, `Register-NexusStep`, `Get-NexusStep`, `Invoke-NexusStepSequence`, `Invoke-NexusStepCommand`, `Invoke-NexusStepApi`, `Invoke-NexusHostPreflight`, `Invoke-NexusHostInstall`, `ConvertTo-NexusPreflightFailure`, `ConvertTo-NexusInstallFailure`, `Get-NexusHostStatus`, `ConvertTo-NexusNodeStatus` | The two contracts, the step runner, the helpers steps use, the per-host engines, and the status merge |
| `utils` | `Initialize-NexusRunContext`, `Write-NexusLog`, `Get-NexusConfig`, `Merge-NexusHashtable`, `Get-NexusSession`, `Get-NexusStoredToken`, `Save-NexusStoredToken`, `ConvertTo-NexusShellArgument` | Run context, logging, configuration, session, secrets, shell quoting |
| `transports` | `Invoke-NexusHostCommand`, `Invoke-NexusSshClient` | Running a command on a host (native ssh) |
| `api` | `Invoke-NexusApi` | The only caller of the NexusInfra REST API |
| `steps` | `Docker` (10), `RegisterNode` (20), `AgentContainer` (30), `VerifyHealthy` (40), `AgentReachable` (50) | One file per installation step, each calling `Register-NexusStep` |
| `public` | `Connect-NexusInfra`, `Import-NexusInventory`, `Test-NexusHost`, `Install-NexusNode`, `Get-NexusFleetStatus`, `Export-NexusFleetStatus` | The exported cmdlets |

## Contracts

### Step

A step is registered with `Register-NexusStep -Name -Order -Description -Test -Apply -Rollback`; each file in
`src/steps/` registers one step when the module loads (the loader loads `core` before `steps`). Names and
`Order` values are unique. All three script blocks receive one argument, the step context:

| Block | Contract |
|---|---|
| `Test` | Returns `$true` when the host is already in the desired state, else `$false` (anything else is an error) |
| `Apply` | Brings the host into that state; throws on failure. Output is discarded |
| `Rollback` | Undoes `Apply`; must be safe after a half-finished `Apply`. Default: nothing |

`Invoke-NexusStepSequence` runs the steps for one host in `Order`: `Test`, then `Apply` when needed. On a failure
it stops, and rolls back the failed step (if its `Apply` started) and every step it applied in this run, in
reverse order; steps that were already in order are left alone. `-PlanOnly` (the dry run) runs only `Test`.
Result: one `NexusFleet.StepRunResult` with `Host`, `Success`, `PlanOnly`, `Step`, `Error` and per step
`Step`, `Outcome` (`AlreadyDone`, `Applied`, `WouldApply`, `Failed`, `NotRun`), `Rollback` (`Done`, `Failed`)
and `Error`.

### Transport

A transport runs one shell command on one host and returns a `NexusFleet.CommandResult`
(`ConvertTo-NexusCommandResult`): `HostName`, `ExitCode`, `StdOut`, `StdErr`, `Succeeded` (exit 0) and
`TransportFailed` (the transport itself failed; for ssh exit code 255). Steps only use these properties, so another
transport is another file in `src/transports/` returning the same object.

The SSH transport, `Invoke-NexusHostCommand`, calls native `ssh` (experiment E1) with `BatchMode=yes`,
`ConnectTimeout`, `StrictHostKeyChecking=accept-new` and `LogLevel=INFO` (the only harmless INFO line, the known-hosts notice of a new host, is filtered out; Windows OpenSSH 9.5 reports a refused connection only at INFO); stdin is closed (`-n`) unless a secret is
sent, and secrets go to stdin as bytes, one line each ending in LF only (never on a command line). Host and user names are validated so
an inventory value can never become an ssh option.

### Step context

`Invoke-NexusHostInstall` builds one context per host and passes it to every `Test`, `Apply` and `Rollback`. It holds
everything a step needs, because module variables do not exist in a parallel runspace:

| Key | Contents |
|---|---|
| `HostInfo` | The `NexusFleet.Host` from the inventory (name = node id, location, agentUrl) |
| `Config` | The validated config |
| `Ssh` | Arguments for `Invoke-NexusHostCommand` (address, port, user, key, known_hosts, time-out) |
| `Api` | Arguments for `Invoke-NexusApi` (base URL, token, time-out, retries), from the session |
| `Secrets` | `RabbitMqUrl` and `InternalApiToken` (SecureStrings); `$null` in a dry run |
| `RunContext` | For logging |
| `State` | A hashtable a step uses to remember something between its `Test` and its `Rollback` |

Steps talk to the host with `Invoke-NexusStepCommand` (throws on an ssh failure, and on a failed command unless
`-AllowFailure`) and to the panel with `Invoke-NexusStepApi`. Every value put into a remote command goes through
`ConvertTo-NexusShellArgument`.

## Data flow of `Install-NexusNode`

```
Import-NexusInventory ──► Install-NexusNode (process: collect hosts)
                          end: Get-NexusSession, Get-NexusConfig
                               per host ShouldProcess  ──► PlanOnly yes/no   (-WhatIf / -Confirm, decided here)
                               secrets (parameters or SecretManagement), only when something is installed
                               Initialize-NexusRunContext (all secrets redacted)
                               Invoke-NexusHostLoop -ThrottleLimit N ──► per host, in its runspace:
                                   Invoke-NexusHostInstall
                                     Invoke-NexusHostPreflight ── not ready ──► result (nothing touched)
                                     Invoke-NexusStepSequence (Get-NexusStep)
                                       Docker → RegisterNode → AgentContainer → VerifyHealthy → AgentReachable
                                       failure ──► rollback of what this run applied, in reverse
                                     NexusFleet.InstallResult
                          one result per host, summary in run.log
```

`NexusFleet.InstallResult`: `Host`, `Success`, `PlanOnly`, `Changed` (did this run apply anything), `Step`, `Error`,
`Steps` (as in the step runner) and `Preflight` (the checks).

## Data flow of `Get-NexusFleetStatus`

```
Import-NexusInventory ──► Get-NexusFleetStatus (process: collect hosts; none is fine)
                          end: GET /nodes once (failure → warning, Health 'unknown', hosts still checked)
                               Invoke-NexusHostLoop ──► Get-NexusHostStatus per host (one ssh call, never throws)
                               ConvertTo-NexusNodeStatus per node: inventory order first, then nodes only NexusInfra knows
                          NexusFleet.NodeStatus: Ok + Problem in plain words, NexusInfra fields, host fields
                          ──► Export-NexusFleetStatus -Path x.json | x.csv
```

## Configuration

`config/nexusinfra.psd1` holds every NexusInfra-specific value (`Api`, `Agent`, `Docker`, `Broker`, `Ssh`, `Preflight`, `Install`, `Health`). An optional, git-ignored
`config/nexusinfra.local.psd1` overrides only what differs (deep merge; unknown keys give a warning).
`Get-NexusConfig` validates every value against a list of rules and reports all problems in one error.

## REST API

`Invoke-NexusApi` sends the API token as a bearer token (SecureString) with a time-out; it retries only `GET`
after network errors, 429 (the gateway's rate limit) or 502-504, with a doubling delay. Errors get ids: `NexusApi.Unauthorized` (401),
`Forbidden` (403), `NotFound` (404), `Conflict` (409), `RateLimited` (429), `Unavailable` (502-504), `Unreachable` (no answer),
`RequestFailed` (other), `UnencryptedNotAllowed` (token over `http://` to a non-loopback host without
`Api.AllowUnencryptedHttp`).

## Results, errors and rollback

One result object per host: `NexusFleet.StepRunResult` (see Step above). Rollback runs in reverse order and only
for what the run itself changed. The per-host engines never throw, and the host loop (below) catches anything that
still escapes, so one failing host never stops the others.

## Parallelism

`Test-NexusHost`, `Install-NexusNode` and `Get-NexusFleetStatus` share one loop, `Invoke-NexusHostLoop`:

- Its input is one hashtable of parameters per host. The shared parameters (config, run context, session) are added
  to it, and a per-host function (`Invoke-NexusHostPreflight`, `Invoke-NexusHostInstall`, `Get-NexusHostStatus`) is
  called with the result. That function is tested directly, with mocks.
- `-ThrottleLimit 1` runs the hosts one after the other in the caller's runspace, where mocks work (E3).
- Otherwise `ForEach-Object -Parallel`. Inside a runspace the module is imported by path and the internal function
  is called in the module's scope (`& $module { ... }`). Module variables do not carry over, so everything comes in
  as parameters.
- When the function throws, or the module cannot be loaded in a runspace, the runspace returns a marker. Back in the
  caller's runspace a failure function (`ConvertTo-NexusPreflightFailure`, `ConvertTo-NexusInstallFailure`,
  `ConvertTo-NexusHostStatusFailure`) turns it into a normal failed result: one result per host, always.
- A progress bar moves with every finished host.

## Logging

`Initialize-NexusRunContext` creates a RunId and the folder `logs/<RunId>/`. `Write-NexusLog` writes one line per
event (UTC time, level, RunId, host, step, message) to `<host>.log` (one file per host, so parallel runspaces never
share a file) or `run.log`, redacting the context's secrets and `nxi_` tokens. Logging also happens under `-WhatIf`.

## Testing

Pester 5 tests in `tests/`, mirroring `src/`; no network, SSH or real NexusInfra in unit tests. Tests tagged
`LocalHttp` use a real HTTP listener on loopback and run with the unit tests. Tests tagged `Integration` need the
lab (for now the E1 Docker target) and are run by hand. CI runs `tools/Invoke-NexusLint.ps1` and Pester as
separate jobs on every push and pull request.
