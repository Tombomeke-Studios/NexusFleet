# NexusFleet — CLAUDE.md

PowerShell 7 module that turns Linux hosts into NexusInfra nodes and manages them as a fleet:
inventory, preflight, idempotent installation with rollback, status, and later bulk actions.
School project for **System Automation & Scripting** (EhB, Toegepaste Informatica) by Tom Dekoning.
This file is **context + rules only** — all tasks and progress live in [TODO.md](TODO.md).

Design source of truth: [docs/projectvoorstel.md](docs/projectvoorstel.md) (the approved proposal, Dutch).
External tool it drives: [Tombomeke-Studios/NexusInfra](https://github.com/Tombomeke-Studios/NexusInfra)
(TypeScript; separate repository, **not** part of this assessment).

---

## 0. Where we are — read this first

**Only this PowerShell module is assessed.** NexusInfra is the external tool it talks to. Three things
follow from that, and they outrank everything else in this file:

1. **Tom has to understand, know and be able to explain every line.** The course penalises code the
   student cannot explain. Work in small slices, prefer plain and readable PowerShell over clever
   tricks, and explain each unit to Tom when it is done (see 2b, step 8). If a construct needs a
   paragraph to explain, look for a simpler one first.
2. **No translated work.** Nothing in this repo may be a translation of existing NexusInfra scripts
   (`deploy/install.sh`, `deploy/install.ps1`). Those install the control plane; NexusFleet does
   something that did not exist (turning a host into a node). Never port them.
3. **The MVP comes first, and it must work.** A non-working MVP cannot pass. No extra is started before
   every "Klaar als" criterion in section 9 holds.

**Current phase: 0 — scaffold.** See [TODO.md](TODO.md).

**Boundaries — keep these distinct:**

| | Belongs where |
|---|---|
| Node onboarding, fleet status, bulk actions, drift, maintenance, connectors | **NexusFleet** (this repo) |
| Continuous monitoring, alerts, dashboards, mobile app | **Final Work** (NexusWatch, NexusInfra app) — never add these here |
| Changes NexusInfra needs for NexusFleet | NexusInfra repo, see section 2d |

---

## 1. Language policy

- **English:** code, identifiers, comments, comment-based help (`Get-Help`), log output, error
  messages, test names, README, `docs/architecture.md`, commit messages, PR titles/bodies, this file.
- **Dutch:** the course documents — `docs/projectvoorstel.md`, `docs/leerlogboek.md`, `docs/uitleg/`,
  `docs/ontwerpkeuzes.md`, `docs/nexusinfra-wijzigingen.md`, the final report.

## 2. Branch strategy — two tiers

```
feature/<topic>  →  dev  →  main
```

| Branch | Purpose | Who merges into it |
|---|---|---|
| `feature/<topic>` | One logical topic per branch | PR into `dev` |
| `dev` | Integration — always CI-green; GitHub default branch | PRs from feature branches |
| `main` | Milestones only (MVP, each finished extra, final delivery) | PR from `dev` |

- A feature branch **never** targets `main`.
- `main` is permanent; tag every merge into it (`v0.x.0` while building, `v1.0.0` = MVP complete).
- After a `dev → main` merge, back-merge `main` into `dev` so `git log --oneline origin/dev..origin/main`
  is empty again.
- A red CI on `dev` is fixed before anything else.

## 2a. GitHub issues — every task is a trackable issue

**TODO.md** is the source of truth for progress; **GitHub issues** mirror every open item for linking.

| Moment | Action |
|---|---|
| You add an actionable item to TODO.md | Create its issue (`gh issue create --title ... --body ... --label type:<x>`) and put `(#N)` on the TODO line |
| You start a branch group | Verify every item in it has an issue; create missing ones first |
| You discover a bug | Issue immediately (`type:bug`), then fix now or backlog |
| You open a PR | One `Closes #N` line **per issue, each on its own line** |
| The PR merges | Verify the issues closed; move the group to Done in TODO.md |

Labels: one `type:*` per issue (`bug` `feature` `refactor` `test` `docs` `ci` `lab`). Title = the TODO
line, imperative. Body = context, acceptance criteria, affected files.

## 2b. The iteration loop (every unit of work)

A unit is the smallest shippable slice: one function, one step, one fix.

1. **Pick** the next unticked item of the active group in TODO.md.
2. **Read context**: the codebase map (section 7), the matching section of the proposal, and section 8.
3. **Write the Pester test first** for the expected behaviour.
4. **Implement** the slice. Match the existing style and reuse existing helpers.
5. **Run** tests and PSScriptAnalyzer (section 6). Both must be clean.
6. **Document**: comment-based help for every new public function; update the affected doc;
   new files also update the codebase map in this file.
7. **Tick** the item in TODO.md; add follow-ups you discovered to the backlog.
8. **Explain it to Tom**, in Dutch, and save the explanation in `docs/uitleg/` (see 2c). In the chat,
   give a short summary and the command he can run to see it work. **Never write
   `docs/leerlogboek.md`**: it is Tom's own account of what he learned.
9. **Commit** (section 3) — code + tests + docs + TODO tick together — and **push**.

**Branch finish:** run the full checks locally, open a PR into `dev`, wait for green CI, merge, move
the group to Done.

## 2c. Explanations — `docs/uitleg/`

The explanations are for Tom to study the code until he can explain it himself. They are written in
Dutch, in plain language, and are **clearly marked as written by Claude Code**.

- **One file per topic**, not per commit: `docs/uitleg/<onderwerp>.md` (e.g. `logging.md`,
  `parallel-uitvoering.md`, `stappen-en-rollback.md`, `api-client.md`). Update the file when the
  topic changes; do not start a new one for every unit.
- Every file starts with: `> Uitleg gegenereerd met Claude Code als studiemateriaal. Niet mijn leerlogboek.`
- Every file has these sections:
  1. **Wat het doet** — in two or three sentences, without jargon.
  2. **Waar het staat** — the files and functions, with paths.
  3. **Hoe het werkt** — walk through the code in the order it runs; quote the few lines that matter.
  4. **Waarom zo** — the choice made and the alternative that was rejected, with the reason.
  5. **PowerShell-concepten** — each concept used (e.g. `$using:`, `ShouldProcess`, `Mock`), what it is,
     and a link to the Microsoft Learn or Pester page.
  6. **Zelf proberen** — commands Tom can run to see it work, and to see it fail.
  7. **Controlevragen** — three to five questions a teacher could ask about this code. **No answers.**
     Tom answers them himself; if he cannot, the code or the explanation is not simple enough yet.
- Keep [docs/uitleg/README.md](docs/uitleg/README.md) as an index: one line per topic file.
- An explanation never claims something Tom did or learned. That belongs in his leerlogboek.

## 2d. Changes to NexusInfra

Allowed — the two tools are built for each other — but they never happen from this repo.

- The NexusInfra state at the start of this project is the tag **`nexusfleet-baseline`** in the
  NexusInfra repo. Everything after it is visible with `git diff nexusfleet-baseline..HEAD` there.
- A change NexusFleet needs is made **in the NexusInfra repo**, following that repo's own CLAUDE.md,
  with the commit prefix `fleet-support:` (e.g. `fleet-support: feat(orchestrator): accept ...`).
- Every such change gets one line in [docs/nexusinfra-wijzigingen.md](docs/nexusinfra-wijzigingen.md)
  (date, commit, what, why NexusFleet needs it). That list is how the teachers see the separation.
- Prefer solving it in NexusFleet when that is reasonable. Ask Tom before touching NexusInfra.

## 3. Commit rules

- **One logical change per commit.** If the message needs "and", split it.
- Never mix refactoring with behaviour changes.
- Format: `type(scope): imperative summary` — body explains *why* when not obvious.
  - **Types:** `feat` `fix` `docs` `chore` `refactor` `test` `ci`
  - **Scopes:** `core` `steps` `transport` `api` `public` `log` `config` `tests` `docs` `ci` `lab`
  - Example: `feat(steps): add agent container step with rollback`
- Before every commit: Pester and PSScriptAnalyzer clean.

## 4. Testing rules

- **Pester v5.** Tests live in `tests/`, mirroring `src/` (`src/steps/Agent.ps1` →
  `tests/steps/Agent.Tests.ps1`).
- **Unit tests never touch the network, SSH or a real NexusInfra.** Mock `Invoke-RestMethod` and the
  transport function (`Invoke-NexusHostCommand`); assert calls with `Should -Invoke`.
- **Mocks do not reach inside `ForEach-Object -Parallel` runspaces.** Therefore the work for one host
  always lives in its own function, which is tested directly; the parallel loop is a thin wrapper.
- **Scale is tested with generated inventories** of 50–100 mocked hosts, a few of them offline or
  failing: every host gets its own correct result and nothing crashes.
- **Integration tests** carry the `Integration` tag, are excluded by default, and run by hand against
  the lab VMs. Put a test there only when the real thing is the only proof.
- **Every bug fix starts with the test that catches it.**
- **Pin Pester to 5.x.** `-MinimumVersion 5.0` alone installs Pester 6, and Windows ships Pester 3.4.
  Tests and CI load it with `Import-Module Pester -MinimumVersion 5.0 -MaximumVersion 5.99`.
- **Import Pester 5 before running PSScriptAnalyzer in the same session.** Analysing the test files makes
  PSScriptAnalyzer load the newest Pester *assembly* (6.x); after that Pester 5 can no longer load
  ("Assembly with same name is already loaded"). Import Pester 5 first, or run lint and tests in separate
  `pwsh` processes (CI does the latter).
- **PSScriptAnalyzer 1.24/1.25 fails intermittently** ("Object reference not set", "Get-Command is not
  recognized") when `PSUseCorrectCasing` is on: a race in its command lookup (PowerShell/PSScriptAnalyzer#2205).
  Measured: ~1 in 10 runs with the rule, 0 in 105 without; 1.24, per-file analysis and retries did not fix it.
  Keep the rule off until fixed. CI runs the analyzer with `-ErrorAction Stop` so a tool failure is never green.

## 5. Documentation rules — which doc owns what

| You changed... | Update |
|---|---|
| A public cmdlet's behaviour or parameters | Its comment-based help **and** README |
| Structure, contracts (step, transport), data flow | [docs/architecture.md](docs/architecture.md) |
| A design choice or an experiment result | [docs/ontwerpkeuzes.md](docs/ontwerpkeuzes.md) (Dutch) |
| Anything in the NexusInfra repo | [docs/nexusinfra-wijzigingen.md](docs/nexusinfra-wijzigingen.md) (Dutch) |
| Any code a unit added or changed | Its topic file in [docs/uitleg/](docs/uitleg/) (Dutch, see 2c) |
| New/moved/renamed files, new commands, new gotchas | **This file** (sections 6–8) |
| Tasks, progress, follow-ups | [TODO.md](TODO.md) — and only there |
| The proposal | **Do not edit** `docs/projectvoorstel.md` unless Tom says the teacher agreed; then add a changelog line at its top |

`docs/leerlogboek.md` belongs to Tom. Never write in it.

## 6. Commands

| What | Command (repo root, `pwsh`) |
|---|---|
| Load the module | `Import-Module ./NexusFleet.psd1 -Force` |
| Check the manifest | `Test-ModuleManifest ./NexusFleet.psd1` |
| Unit tests | `Invoke-Pester -Path ./tests -ExcludeTagFilter Integration -Output Detailed` |
| Integration tests (lab VMs) | `Invoke-Pester -Path ./tests -TagFilter Integration` |
| Lint | `Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1` |
| Help for a cmdlet | `Get-Help Install-NexusNode -Full` |
| Dry run | any changing cmdlet with `-WhatIf` |
| Install tooling | `Install-Module Pester -RequiredVersion 5.7.1 -Scope CurrentUser -SkipPublisherCheck; Install-Module PSScriptAnalyzer -Scope CurrentUser` |
| Load Pester 5 (not 6, not the built-in 3.4) | `Import-Module Pester -MinimumVersion 5.0 -MaximumVersion 5.99` |

## 7. Codebase map — where is what

Status: the folders exist, each with a one-line `README.md` stating its purpose (placeholder until code
lands; the loader only reads `*.ps1`). File contents below are still **planned** — replace by a real
description as files land. `logs/` is created at runtime, never committed.

| Path | Contents |
|---|---|
| `README.md` | English user docs: what/why, planned MVP cmdlets, requirements, quick start (placeholder until the MVP), dev commands, layout. Update with every public cmdlet change |
| `NexusFleet.psd1` | Manifest (hand-written, minimal): PowerShell 7.2+, `Core` only. `FunctionsToExport` is an **explicit list** of the public cmdlets — never `*`; still `@()` until the first cmdlet lands. Cmdlets/Variables/Aliases also `@()` |
| `.gitignore` | Ignores `logs/`, local config (`config/*.local.*`, `config/inventory.json`), Pester output, OS files |
| `.gitattributes` | `* text=auto`; `eol=lf` for `*.ps1`, `*.psm1`, `*.psd1`, `*.sh` (also in the working copy on Windows) |
| `PSScriptAnalyzerSettings.psd1` | Lint rules: all severities, default rules + formatting (4-space indent, same-line braces, consistent whitespace, aligned hashtables) + syntax compatibility with 7.2. `PSUseCorrectCasing` is off on purpose (see section 4) |
| `NexusFleet.psm1` | Loader: dot-sources `src/*/*.ps1` in a fixed folder order (`core` → `utils` → `transports` → `api` → `steps` → `public`), files sorted by name; throws if a folder is missing and names the file when a script fails to load |
| `src/core/` | Contracts: the **step** (`Test` / `Apply` / `Rollback`) and the **transport** (run a command on a host) |
| `src/steps/` | One file per installation step: Docker, agent container, register node, verify healthy. Each declares its order; `Install-NexusNode` reads them from this folder, so adding, replacing or removing a step is adding, replacing or removing a file |
| `src/transports/` | `Invoke-NexusHostCommand` over SSH (method chosen by experiment E1) |
| `src/api/` | `Invoke-NexusApi` — the **only** place that calls the NexusInfra REST API |
| `src/public/` | The cmdlets: `Connect-NexusInfra`, `Import-NexusInventory`, `Test-NexusHost`, `Install-NexusNode`, `Get-NexusFleetStatus` |
| `src/utils/` | `Write-NexusLog` (with secret redaction), config loading |
| `config/` | `nexusinfra.psd1` (every NexusInfra-specific value), `inventory.example.json` |
| `tests/` | Pester, mirrors `src/`. `tests/NexusFleet.Tests.ps1` covers the manifest and the loader (fake module copy in `TestDrive` with probe scripts) and that the module exports exactly the manifest list |
| `lab/` | Scripts and notes for the experiments (TODO phase 1) — not part of the module |
| `docs/` | `projectvoorstel.md`; `architecture.md` (English, sections marked _planned_ until filled); `ontwerpkeuzes.md` (Dutch; E1–E4 for Tom, K1–K3 = choices made during the scaffold); `nexusinfra-wijzigingen.md` (Dutch, table of `fleet-support:` commits, empty so far); `leerlogboek.md` (Tom's; holds one draft note written by Claude Code at Tom's explicit request, 2026-11-02, for Tom to rewrite — never add to it otherwise) |
| `docs/uitleg/` | Explanations per topic, written by Claude Code as study material (section 2c) + `README.md` index |
| `logs/` | Run logs, created at runtime, git-ignored |
| `.github/workflows/ci.yml` | On every push and PR: two jobs on `ubuntu-latest` — `lint` (PSScriptAnalyzer 1.25.0, findings as `::error` annotations) and `test` (Pester 5.7.1, `Run.Exit`, `Integration` excluded). Versions pinned; read-only token |

## 8. Conventions & gotchas

### PowerShell
- **Approved verbs only** (`Get-Verb`), `Verb-Noun`, noun prefix `Nexus`.
- **Return objects, never formatted text.** No `Write-Host` for data; `Write-Verbose`,
  `Write-Warning`, `Write-Progress` for the human.
- **Pipeline:** cmdlets that take hosts accept pipeline input; collect in `process`, do the parallel
  work in `end`.
- **Every changing cmdlet** has `[CmdletBinding(SupportsShouldProcess)]`. `$PSCmdlet.ShouldProcess`
  is not available inside a `-Parallel` block: decide what will run **before** the parallel loop,
  and with `-WhatIf` only run each step's `Test` and return the plan.
- **`ForEach-Object -Parallel`:** variables come in through `$using:`; the module's functions are
  **not** visible in the runspaces — import the module inside the block by path. Always pass
  `-ThrottleLimit` from a parameter.
- **One host failing never stops the others.** Catch per host and return a result object with
  `Host`, `Success`, `Step`, `Error`.
- **Validate parameters** with `ValidateNotNullOrEmpty`, `ValidatePattern`, `ValidateRange`,
  `ValidateScript`, not with checks deep inside the function.
- **Classes** defined in the module are not visible to callers without `using module`. Use them
  internally; return `[pscustomobject]` with a `PSTypeName` from public cmdlets.
- **No hard-coded infrastructure values** in functions: they come from `config/` or parameters.

### Secrets and logging
- Secrets (API token, `INTERNAL_API_TOKEN`, broker password) **never** go on a command line, in a
  log, or in the repo. Store with SecretManagement; send to a host over **stdin** of the SSH call or
  as a file with mode `600`.
- **Local config** (real addresses, your own inventory) lives in `config/*.local.*` and `config/inventory.json`,
  both git-ignored. The repo only holds the examples. Ignoring is not secret storage: secrets still go to SecretManagement.
- Every public cmdlet run gets a `RunId`. `Write-NexusLog` writes one human-readable line per event:
  time (UTC ISO-8601), RunId, host, step, level, message. It redacts known secrets before writing.
- A dry run is logged too.

### SSH and the hosts
- Native `ssh` must never wait for input: `-o BatchMode=yes -o ConnectTimeout=<n>`. Check
  `$LASTEXITCODE` after every call.
- Scripts sent to a Linux host need **LF** line endings (`.gitattributes`); CRLF breaks bash.
- Target hosts: fresh Ubuntu VMs with a key-authorised user that may `sudo`.

### NexusInfra facts (verified at `nexusfleet-baseline`, v0.4.0 — re-check when NexusInfra changes)
- **API:** `Authorization: Bearer nxi_…` (API token, minted with `POST /me/tokens`). Reading is
  always allowed; changing needs scope `write`; `admin` is a separate scope. `GET /me` validates a
  token. Node routes are for platform administrators.
- **Nodes:** `GET /nodes`; `POST /nodes` with `{ id, name, location, agentUrl }` writes **only a
  record**; `PATCH /nodes/:id/maintenance` `{ "maintenance": true|false }`; `DELETE /nodes/:id`
  answers `409` while the node hosts a running deployment.
- **A node exists only once its agent sends heartbeats.** Health: *degraded* after 3 s without a
  heartbeat, *offline* after 10 s. `Install-NexusNode` is done only when `GET /nodes` shows it healthy.
- **No access answers `404`**, too few rights `403`, conflict `409`. `Invoke-NexusApi` turns these into
  clear errors.
- **Bulk:** `POST /deployments/bulk` `{ action: start|stop|restart|kill, ids: [...] }`, at most 100 ids,
  always `200` with a result per server.
- **The agent** (`docs/images.md`, "Adding a machine"): image
  `ghcr.io/tombomeke-studios/nexusinfra/node-agent:community`, env `NODE_ID`, `RABBITMQ_URL`,
  `INTERNAL_API_TOKEN`, `AGENT_URL`; port `9100`; Docker socket mounted; `--add-host=host.docker.internal:host-gateway`.
  **Three options fail silently when forgotten:** `--restart unless-stopped`, the port publication,
  and the `nexusinfra-backups` volume. The agent step must always set all three.
- The agent speaks **plain HTTP**; `/health` is open, everything else needs the shared
  `INTERNAL_API_TOKEN`. `AGENT_URL` must be an address the orchestrator can reach.
- The broker default `guest/guest` must not be used on anything reachable.
- **Docker-published ports bypass `ufw`** (Docker writes its own iptables rules). Relevant for the
  security extra; do not rely on `ufw` alone.
- Orchestrator `:9200`, gateway `:9400` (fronts the orchestrator, passes `nxi_` tokens through, rate
  limits by address). The base URL is configuration.

## 9. MVP — "Klaar als" (from the proposal)

MVP cmdlets: `Connect-NexusInfra`, `Import-NexusInventory`, `Test-NexusHost`, `Install-NexusNode`,
`Get-NexusFleetStatus` — with dry run (`-WhatIf`), logging, Pester tests, `Get-Help` on every
function, PSScriptAnalyzer clean, README, and no hard-coded NexusInfra values.

The MVP is done when:
1. one command turns the lab VMs into *healthy* nodes,
2. a second run changes nothing,
3. one failing host does not stop the others.

Extras, in this order and only after the MVP: bulk actions and removal → drift detection → rolling
maintenance → connectors for other platforms → secured connection → backups → publication.
