# NexusFleet — Architecture

How the module is built: its parts, the contracts between them and how data flows through a run.
Sections marked _planned_ describe the design from the [proposal](projectvoorstel.md) and are filled in as
the code lands. The working rules live in [CLAUDE.md](../CLAUDE.md).

## Overview

_Planned._ The big picture: a PowerShell module that talks to NexusInfra over its REST API and to hosts over
SSH, and turns an inventory of hosts into healthy nodes.

## Module loading

The manifest (`NexusFleet.psd1`) requires PowerShell 7.2+ (Core) and exports an explicit list of public
cmdlets. The loader (`NexusFleet.psm1`) dot-sources `src/` folder by folder in a fixed order:
`core` → `utils` → `transports` → `api` → `steps` → `public`.

## Components

_Planned._ One responsibility per folder in `src/`: `core`, `utils`, `transports`, `api`, `steps`, `public`.

## Contracts

### Step

_Planned._ `Test` / `Apply` / `Rollback`, and how a step declares its order.

### Transport

_Planned._ Running a command on a host: input, result (`ExitCode`, `StdOut`, `StdErr`), secrets via stdin.

## Data flow of `Install-NexusNode`

_Planned._ Inventory → preflight → steps per host → register → verify healthy → result per host.

## Configuration

_Planned._ `config/nexusinfra.psd1` holds every NexusInfra-specific value; local overrides in `*.local.*`.

## Results, errors and rollback

_Planned._ One result object per host (`Host`, `Success`, `Step`, `Error`); rollback in reverse order.

## Parallelism

_Planned._ `ForEach-Object -Parallel` with `-ThrottleLimit`; the work for one host lives in its own function.

## Logging

_Planned._ `Write-NexusLog`: one line per event with RunId, host, step and level; secrets redacted.

## Testing

Pester 5 tests in `tests/`, mirroring `src/`; no network, SSH or real NexusInfra in unit tests.
CI runs PSScriptAnalyzer and Pester as separate jobs on every push and pull request.
