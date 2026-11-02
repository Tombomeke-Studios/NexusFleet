# NexusFleet — Architecture

How the module is built: its parts, the contracts between them and how data flows through a run.
Sections marked _planned_ describe the design from the [proposal](projectvoorstel.md) and are filled in as
the code lands. The working rules live in [CLAUDE.md](../CLAUDE.md).

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
| `core` | `ConvertTo-NexusCommandResult`, `Register-NexusStep`, `Get-NexusStep`, `Invoke-NexusStepSequence` | The two contracts and the step runner |
| `utils` | `Initialize-NexusRunContext`, `Write-NexusLog`, `Get-NexusConfig`, `Merge-NexusHashtable` | Run context, logging, configuration |
| `transports` | `Invoke-NexusHostCommand`, `Invoke-NexusSshClient` | Running a command on a host (native ssh) |
| `api` | `Invoke-NexusApi` | The only caller of the NexusInfra REST API |
| `steps` | _(phase 3)_ | One file per installation step, each calling `Register-NexusStep` |
| `public` | _(phase 3)_ | The exported cmdlets |

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
`ConnectTimeout`, `StrictHostKeyChecking=accept-new` and `LogLevel=ERROR`; stdin is closed (`-n`) unless a secret is
sent, and a secret goes to stdin as bytes (no CR/LF, never on a command line). Host and user names are validated so
an inventory value can never become an ssh option.

## Data flow of `Install-NexusNode`

_Planned._ Inventory → preflight → steps per host → register → verify healthy → result per host.

## Configuration

`config/nexusinfra.psd1` holds every NexusInfra-specific value (`Api`, `Agent`, `Health`). An optional, git-ignored
`config/nexusinfra.local.psd1` overrides only what differs (deep merge; unknown keys give a warning).
`Get-NexusConfig` validates every value against a list of rules and reports all problems in one error.

## REST API

`Invoke-NexusApi` sends the API token as a bearer token (SecureString) with a time-out; it retries only `GET`
after network errors or 502-504, with a doubling delay. Errors get ids: `NexusApi.Unauthorized` (401),
`Forbidden` (403), `NotFound` (404), `Conflict` (409), `Unavailable` (502-504), `Unreachable` (no answer),
`RequestFailed` (other), `UnencryptedNotAllowed` (token over `http://` to a non-loopback host without
`Api.AllowUnencryptedHttp`).

## Results, errors and rollback

One result object per host: `NexusFleet.StepRunResult` (see Step above). Rollback runs in reverse order and only
for what the run itself changed. The parallel cmdlets (phase 3) will catch per host, so one failing host never
stops the others.

## Parallelism

_Planned for phase 3, design fixed by E2 and E3._ `ForEach-Object -Parallel` with `-ThrottleLimit` from a parameter;
the work for one host lives in its own function, tested directly. Inside a runspace the module is imported by path
and internal functions are called in the module's scope (`& $module { ... }`); module variables do not carry over,
so a run context object is passed with `$using:`.

## Logging

`Initialize-NexusRunContext` creates a RunId and the folder `logs/<RunId>/`. `Write-NexusLog` writes one line per
event (UTC time, level, RunId, host, step, message) to `<host>.log` (one file per host, so parallel runspaces never
share a file) or `run.log`, redacting the context's secrets and `nxi_` tokens. Logging also happens under `-WhatIf`.

## Testing

Pester 5 tests in `tests/`, mirroring `src/`; no network, SSH or real NexusInfra in unit tests. Tests tagged
`LocalHttp` use a real HTTP listener on loopback and run with the unit tests. Tests tagged `Integration` need the
lab (for now the E1 Docker target) and are run by hand. CI runs `tools/Invoke-NexusLint.ps1` and Pester as
separate jobs on every push and pull request.
