# NexusFleet

[![CI](https://github.com/Tombomeke-Studios/NexusFleet/actions/workflows/ci.yml/badge.svg?branch=dev)](https://github.com/Tombomeke-Studios/NexusFleet/actions/workflows/ci.yml)

A PowerShell 7 module that turns Linux hosts into [NexusInfra](https://github.com/Tombomeke-Studios/NexusInfra)
nodes and manages them as a fleet: read an inventory, check every host, install Docker and the node agent,
register the node, wait until it is healthy, and roll back when something fails.

> **Status: phase 0, scaffold.** The module loads but has no cmdlets yet. Progress is tracked in
> [TODO.md](TODO.md). This README grows as the cmdlets land.

## Why

Adding a machine to NexusInfra is manual work today: install Docker, start the agent container with the
right variables, register the node and check that it sends heartbeats. Three of the `docker run` options
fail silently when forgotten. That is tedious for one host, error-prone for ten and unworkable for a hundred.
NexusFleet turns it into one repeatable, idempotent PowerShell pipeline with a result per host.

## Planned cmdlets (MVP)

| Cmdlet | What it will do |
|---|---|
| `Connect-NexusInfra` | Connect to the NexusInfra panel with an API token |
| `Import-NexusInventory` | Read and validate a JSON list of target hosts |
| `Test-NexusHost` | Check every host in parallel: reachable, SSH, OS, disk space, Docker |
| `Install-NexusNode` | Turn a host into a healthy node, idempotent, with rollback on failure |
| `Get-NexusFleetStatus` | Get and export the status of all nodes; offline hosts never break the run |

Every changing cmdlet will support `-WhatIf` (dry run), and every run writes a readable log without secrets.

## Requirements

**Control machine** (where you run NexusFleet)

- PowerShell 7.2 or later (`pwsh`) on Windows, Linux or macOS
- An OpenSSH client (`ssh`) — the transport is confirmed by experiment E1 in phase 1
- A NexusInfra control plane you can reach, and an API token for it

**Target hosts**

- A fresh Ubuntu machine, reachable over SSH
- A user that logs in with an SSH key and may use `sudo`

**For development**

- [Pester](https://pester.dev) **5.x** (not 6, and not the Pester 3.4 that ships with Windows)
- [PSScriptAnalyzer](https://learn.microsoft.com/powershell/utility-modules/psscriptanalyzer/overview)

```powershell
Install-Module Pester -RequiredVersion 5.7.1 -Scope CurrentUser -SkipPublisherCheck
Install-Module PSScriptAnalyzer -Scope CurrentUser
```

## Quick start

_Coming with the MVP cmdlets._ For now you can load the module and run the checks:

```powershell
git clone https://github.com/Tombomeke-Studios/NexusFleet.git
cd NexusFleet
Import-Module ./NexusFleet.psd1
```

## Development

Run from the repository root in `pwsh`. Import Pester 5 first: PSScriptAnalyzer otherwise loads the newest
Pester assembly and blocks Pester 5 in that session.

```powershell
Import-Module Pester -MinimumVersion 5.0 -MaximumVersion 5.99
Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
Invoke-Pester -Path ./tests -ExcludeTagFilter Integration -Output Detailed
```

CI runs both on every push and pull request ([.github/workflows/ci.yml](.github/workflows/ci.yml)).

Branches: `feature/<topic>` → `dev` (default, always green) → `main` (milestones only, tagged).

## Repository layout

| Path | Contents |
|---|---|
| `NexusFleet.psd1` / `NexusFleet.psm1` | Module manifest and loader |
| `src/core/` | Contracts: a step (Test / Apply / Rollback) and a transport |
| `src/steps/` | One file per installation step |
| `src/transports/` | Running commands on a host (SSH) |
| `src/api/` | The only place that calls the NexusInfra REST API |
| `src/public/` | The exported cmdlets |
| `src/utils/` | Logging and configuration helpers |
| `config/` | NexusInfra-specific values and an example inventory |
| `tests/` | Pester tests, mirroring `src/` |
| `docs/` | Proposal, architecture, design decisions, explanations (Dutch course documents) |

## Documentation

- [docs/projectvoorstel.md](docs/projectvoorstel.md) — the approved project proposal (Dutch)
- [docs/uitleg/](docs/uitleg/README.md) — explanations per topic, written as study material (Dutch)

## About

School project for *System Automation & Scripting* (EhB, Toegepaste Informatica) by Tom Dekoning.
NexusInfra is a separate project and is not part of this module.
