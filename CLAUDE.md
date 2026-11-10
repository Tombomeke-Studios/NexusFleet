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

**Current phase: 3 → 4** (all five MVP cmdlets exist; phase 4 hardening and the demo on the real VMs next). The first two extras (bulk actions and removal, drift detection) were built on 2026-11-10/11 at Tom's request, while the VM demo waits. See [TODO.md](TODO.md).

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
- **Local ssh tests** (tag `LocalSsh`) run the real parallel path with the real ssh client against free loopback
  ports (every connection is refused at once); they run in CI and prove one result per host from real runspaces.
- **Install tests use a fake fleet** (`tests/core/FakeFleet.ps1`): mocks of `Invoke-NexusHostCommand` and `Invoke-NexusApi`
  that read and change a hashtable, so the real steps and runner can run twice, fail at a chosen step, and be checked.
  Shared step-test context: `tests/steps/TestStepContext.ps1`. Helper files are not `*.Tests.ps1`.
- **Local HTTP tests** (tag `LocalHttp`) use a real `HttpListener` on a free loopback port, no external hosts;
  they run with the unit tests and in CI, because they catch what mocks of `Invoke-RestMethod` cannot.
- **Integration tests** carry the `Integration` tag, are excluded from the unit run, and run against the labs:
  in CI by `integration.yml` (both labs in Docker), locally with `./tools/Invoke-NexusTests.ps1 -Suite Integration`,
  and later against the lab VMs. Put a test there only when the real thing is the only proof.
- **Every bug fix starts with the test that catches it.**
- **A mock of an external program (`ssh`) does not see piped input** (`$input` is empty). Wrap the native call in a
  minimal function with an explicit parameter (`Invoke-NexusSshClient -InputBytes`), mock that, and cover the
  wrapper with an Integration test.
- **Pin Pester to 5.x.** `-MinimumVersion 5.0` alone installs Pester 6, and Windows ships Pester 3.4.
  Tests and CI load it with `Import-Module Pester -MinimumVersion 5.0 -MaximumVersion 5.99`.
- **Import Pester 5 before running PSScriptAnalyzer in the same session.** Analysing the test files makes
  PSScriptAnalyzer load the newest Pester *assembly* (6.x); after that Pester 5 can no longer load
  ("Assembly with same name is already loaded"). Import Pester 5 first, or run lint and tests in separate
  `pwsh` processes (CI does the latter).
- **PSScriptAnalyzer 1.24/1.25 fails intermittently** ("Object reference not set", "Get-Command is not
  recognized"): a race in its shared command lookup (PowerShell/PSScriptAnalyzer#2205). Known triggers:
  `PSUseCorrectCasing` (kept off, #12) and `Export-ModuleMember` in a `.psm1` (never use it; the manifest
  exports). Always lint with `./tools/Invoke-NexusLint.ps1`: it retries only `RULE_ERROR*` errors (max 3),
  never findings. If a new RULE_ERROR shows up, read its stack trace (`$e[0].Exception.StackTrace`) to find
  the rule, and record it in `docs/ontwerpkeuzes.md` (K2).
- **A mock body cannot see `$script:` variables of the test file** when the mocked command is called from
  another script file (that file has its own script scope). Use plain variables from `BeforeAll`/`It`, and a
  hashtable for counters. Suppress `PSUseDeclaredVarsMoreThanAssignments` per test file with a justification.

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
| Unit tests | `./tools/Invoke-NexusTests.ps1` (as CI; report in `TestResults/report-Unit.md`) or `Invoke-Pester -Path ./tests -ExcludeTagFilter Integration -Output Detailed` |
| Integration tests (labs) | `./tools/Invoke-NexusTests.ps1 -Suite Integration` (start the labs first) |
| Lint | `./tools/Invoke-NexusLint.ps1` (same as CI; retries only PSScriptAnalyzer's own `RULE_ERROR`s) |
| Check commit messages | `./tools/Test-NexusCommitMessage.ps1 -Range origin/dev..HEAD` (CI checks the PR title and every commit) |
| Build the shipped module | `./tools/Build-NexusModule.ps1` (→ `out/`) |
| Node lab / demo | `./lab/node-lab/Start-NodeLab.ps1` · `./lab/demo/Invoke-NexusDemo.ps1 -InventoryPath <file>` |
| Help for a cmdlet | `Get-Help Install-NexusNode -Full` |
| Dry run | any changing cmdlet with `-WhatIf` |
| Install tooling | `./tools/Install-NexusTooling.ps1` (pinned versions, retries) |
| Load Pester 5 (not 6, not the built-in 3.4) | `Import-Module Pester -MinimumVersion 5.0 -MaximumVersion 5.99` |

## 7. Codebase map — where is what

Every folder has a `README.md`: what it is for and one line per file (the loader only reads `*.ps1`; the build ships none of them except the root README). `logs/` is created at runtime,
never committed.

| Path | Contents |
|---|---|
| `README.md` | The front page (English): banner, badges, why, a Mermaid diagram of the flow, the steps per host, a short quick start (details in `docs/user-guide.md`), cmdlets, the demo result, docs, dev commands and workflows, layout. Update with every public cmdlet change |
| `NexusFleet.psd1` | Manifest (hand-written, minimal): PowerShell 7.6+ (LTS, decision K4), `Core` only. `FunctionsToExport` is an **explicit list** of the public cmdlets — never `*`; still `@()` until the first cmdlet lands. Cmdlets/Variables/Aliases also `@()` |
| `.gitignore` | Ignores `logs/`, local config (`config/*.local.*`, `config/inventory.json`), Pester output, OS files |
| `.gitattributes` | `* text=auto`; `eol=lf` for `*.ps1`, `*.psm1`, `*.psd1`, `*.sh` (also in the working copy on Windows) |
| `PSScriptAnalyzerSettings.psd1` | Lint rules: all severities, default rules + formatting (4-space indent, same-line braces, consistent whitespace, aligned hashtables) + syntax compatibility with 7.6. `PSUseCorrectCasing` is off on purpose (see section 4) |
| `NexusFleet.psm1` | Loader: dot-sources `src/*/*.ps1` in a fixed folder order (`core` → `utils` → `transports` → `api` → `steps` → `public`), files sorted by name; throws if a folder is missing and names the file when a script fails to load |
| `src/core/` | Per-host engines: `Invoke-NexusHostPreflight` (one ssh `true` for Reachable/SshAuth, one facts script for OS/Sudo/DiskSpace/Docker/Broker, plus AgentLink for a `reach: outbound` host (`-LinkUrl`, `-LinkUnsupported`); never throws), `ConvertTo-NexusPreflightFailure`; `Invoke-NexusHostInstall` (preflight, then builds the step context — HostInfo, Config, Ssh, Api, Secrets, RunContext, State — and runs the steps; result `NexusFleet.InstallResult` with `Changed`; never throws), `ConvertTo-NexusInstallFailure`; `Get-NexusHostStatus` (one ssh call: uptime, disk, Docker, agent container state; never throws), `ConvertTo-NexusHostStatusFailure` (an unreachable status for a host whose runspace failed), `ConvertTo-NexusNodeStatus` (merges a node record, inventory host and host status; plain-words `Problem`; 1970 heartbeat = never); `Invoke-NexusHostRemoval` (one ssh look, `GET /nodes`, `DELETE /nodes/<name>` first (409 = running servers, nothing touched), then the agent container and env file, then `DELETE` again when a last heartbeat brought the node back; result `NexusFleet.RemoveResult`; never throws), `ConvertTo-NexusRemoveFailure`; `ConvertTo-NexusSyncResult` (an install plan read as drift: every `WouldApply` step is one difference, with the step's `Detail`; a failed plan is an `Error`; `-Unmanaged` for a node the inventory does not know). Step helpers: `Invoke-NexusStepCommand` (ssh with the context; throws on ssh failure, and on a failed command unless `-AllowFailure`; names the inventory host), `Invoke-NexusStepApi`. Contracts. Transport: `ConvertTo-NexusCommandResult` builds the `NexusFleet.CommandResult` every transport returns (`HostName`, `ExitCode`, `StdOut`, `StdErr`, `Succeeded`, `TransportFailed` = exit 255). Step: `Register-NexusStep` (unique Name and Order; registry `$script:NexusStepRegistry`), `Get-NexusStep` (sorted), `Invoke-NexusStepSequence` (Test then Apply; a Test that is not in order may leave `State.Detail`, which lands on the step result as `Detail`; reverse rollback of what this run changed, `-PlanOnly` dry run, optional logging, step output discarded) |
| `src/steps/` | One file per installation step, each calling `Register-NexusStep` once with a unique `Order` (gaps: 10, 20, 30); adding, replacing or removing a step is adding, replacing or removing a file. `Docker.ps1` (10: Ubuntu `docker.io`, apt lock time-out, `systemctl` or `dockerd` without systemd), `RegisterNode.ps1` (20: `POST /nodes`, with `connection: outbound` and no agentUrl for a `reach: outbound` host; rollback deletes only a record this run created), `AgentContainer.ps1` (30: Test inspects every setting incl. the three silent ones; Apply writes `/etc/nexusinfra/agent.env` mode 600 from two stdin lines, then `docker run --env-file`; for `reach: outbound` no published port, a link token minted with `POST /nodes/<id>/link-token` as a third stdin line, and `AGENT_LINK_URL` (a `ws://` link only with `Api.AllowUnencryptedHttp`); rollback never removes the backups volume), `VerifyHealthy.ps1` (40: polls `GET /nodes`, attempts = time-out / interval; when AgentContainer started an agent this run (`State.AgentStarted`) never "already done" and waits `DegradedAfterSeconds` first, so the old agent's last heartbeat cannot count), `AgentReachable.ps1` (50: `GET /nodes/<id>/disk`, where NexusInfra calls the agent itself: healthy only proves node → broker, this proves orchestrator → agent and the shared token; changes nothing). `-Force` (context `Force`) makes the AgentContainer Test false: the way to apply a changed secret |
| `src/transports/` | `Invoke-NexusHostCommand`: one command on one host over native ssh (E1): BatchMode, ConnectTimeout, accept-new, LogLevel=INFO (Windows OpenSSH 9.5 reports a refused connection only at INFO; the known-hosts notice is filtered out), `-n` without input, secret as stdin bytes, strict host/user validation. `Invoke-NexusSshClient`: the minimal wrapper around `ssh` (seam for tests; covered by the Integration test against the E1 lab container) |
| `src/api/` | `Invoke-NexusApi` — the **only** place that calls the NexusInfra REST API. Bearer token as SecureString, time-out, retries a 429 for every method (refused before NexusInfra sees it) and only GET after network errors/502-504 (doubling delay), error ids `NexusApi.Unauthorized/Forbidden/NotFound/Conflict/Unavailable/Unreachable/RequestFailed/UnencryptedNotAllowed`, token over `http://` only to loopback unless `-AllowUnencryptedHttp` (K5) |
| `src/public/` | The exported cmdlets. `Connect-NexusInfra` (checks `GET /me` role admin/owner and `GET /users` for the admin scope, keeps `$script:NexusSession`, keeps the `features` of `GET /config` on the session (e.g. `agent-link`), `-Save` stores the token via SecretManagement with ShouldProcess). `Import-NexusInventory` (JSON `defaults` + `hosts` → `NexusFleet.Host` objects one by one; validates name `^[a-z][a-z0-9-]{0,62}$`, address with the transport's pattern, port, user, agentUrl; `reach` direct|outbound (outbound: no AgentUrl); refuses duplicates; warns on unknown fields; reports all problems at once). `Test-NexusHost` (collects hosts in `process`, runs `Invoke-NexusHostPreflight` per host in `end` through `Invoke-NexusHostLoop`; never stops on one host). `Install-NexusNode` (per host `ShouldProcess` before the loop → `PlanOnly`; agent secrets from parameters or SecretManagement (`Agent.SecretNames`), only when something is installed; all secrets redacted; `Invoke-NexusHostInstall` through `Invoke-NexusHostLoop`). `Get-NexusFleetStatus` (optional pipeline hosts; `GET /nodes` once, failure is a warning not an error; hosts via `Get-NexusHostStatus` through `Invoke-NexusHostLoop`; merge with `ConvertTo-NexusNodeStatus`: inventory order, then nodes only NexusInfra knows; `Ok` + `Problem`). `Export-NexusFleetStatus` (JSON `{generatedAt, nodes}` or CSV, format from extension or `-Format`, times ISO-8601 UTC, ShouldProcess). `Remove-NexusNode` (ConfirmImpact High, per host `ShouldProcess` → `PlanOnly`; `Invoke-NexusHostRemoval` through `Invoke-NexusHostLoop`; `-IgnoreUnreachableHost` for a machine that is gone). `Sync-NexusFleet` (drift: `Invoke-NexusHostInstall -PlanOnly` per host through the loop → `ConvertTo-NexusSyncResult`; nodes not in the inventory reported as Unmanaged; ConfirmImpact High, `ShouldProcess` per drifted host, repair by calling `Install-NexusNode -Confirm:$false`; `NexusFleet.SyncResult`). `Get-NexusServer` (`GET /deployments` page after page, `Servers.PageSize`; filters `-Node`, `-Status`, `-Name`; `NexusFleet.Server`). `Invoke-NexusFleetAction` (`POST /deployments/bulk` in batches of `Servers.BulkMaxIds`, ids from the pipeline by property name, one `ShouldProcess` for the group, `NexusFleet.ActionResult` per server; a failed batch does not stop the next). Every exported cmdlet must pass the help test in `tests/NexusFleet.Tests.ps1` |
| `src/utils/` | `Initialize-NexusRunContext` (RunId, log folder `<Log.Directory or ./logs>/<RunId>/`, secrets; a plain object so it can go into runspaces via `$using:`), `Add-NexusLogSecret` (a secret born during the run, e.g. a link token, added under a `Monitor` lock: parallel runspaces share the run context), `Write-NexusLog` (one line per event, one file per host + `run.log`, redaction of context secrets and `nxi_` tokens, writes under `-WhatIf` too). `Get-NexusConfig` (reads `config/nexusinfra.psd1` + optional `nexusinfra.local.psd1`, or the override `$env:NEXUSFLEET_CONFIG` names (must exist), validates every value with a rules list, reports all problems at once), `Merge-NexusHashtable` (deep merge, warns on unknown keys), `Get-NexusSession` (the connection or `NexusFleet.NotConnected`), `Get-NexusStoredToken` / `Save-NexusStoredToken` (the only SecretManagement callers, clear errors when it or a vault is missing), `Get-NexusSshParameter` (the `Invoke-NexusHostCommand` splat of one host: inventory address/port/user/key + config time-out/known_hosts), `Get-NexusApiParameter` (the `Invoke-NexusApi` splat of the session), `Get-NexusAgentLinkUrl` (the `ws(s)://` URL an outbound agent dials: `Agent.Link.Url` or the panel address plus `Agent.Link.Path`), `Get-NexusUrlPassword` (the password inside the broker URL, registered as a log secret of its own), `ConvertFrom-NexusFactLine` (the key=value lines a host prints → hashtable; first `=` splits), `Invoke-NexusHostLoop` (the per-host loop of the cmdlets: `-ThrottleLimit 1` sequential, else `ForEach-Object -Parallel` with the module imported per runspace; progress bar; a host whose work throws, or whose runspace cannot load the module, still gets a result from `-FailureFunction`). All internal (not exported) |
| `config/` | `nexusinfra.psd1` (every NexusInfra-specific value: `Api`, `Agent` (incl. `EnvFile`, `SecretNames`), `Docker`, `Broker` (as the nodes reach it), `Ssh`, `Preflight`, `Install`, `Health`, `Log` (`Directory`: where the run folders go; `KeepRuns`: the oldest beyond this number are removed), `Servers` (`PageSize`, `BulkMaxIds`); checked against NexusInfra `docs/images.md`), local overrides in git-ignored `nexusinfra.local.psd1`; `inventory.example.json` (format example; your own `inventory.json` is git-ignored) |
| `tests/` | Pester, mirrors `src/`. `tests/NexusFleet.Tests.ps1`: manifest, loader, exports, and the help quality test (description, parameters, two explained examples that parse, INPUTS/OUTPUTS/NOTES/LINK, about topic). `tests/Quality.Tests.ps1`: every config key has a rule, every error id is tested, every Markdown link and help link resolves |
| `lab/` | Experiments (phase 1), not part of the module, but linted; index in `lab/README.md`. `E1-transport/` (Docker lab targets + transport comparison; keys in git-ignored `.keys/`), `E2-concurrency/` (benchmark), `E3-mocks-parallel/` (Pester proof), `E4-token-scopes/` (source notes, confirmed live). `demo/`: `Invoke-NexusDemo.ps1` (preflight, plan, install, second run, status; times per phase; checks the three criteria; writes `demo/results/<time>/`, git-ignored), `Invoke-NexusLabDemo.ps1` (the demo on the node lab in one command: `NEXUSFLEET_CONFIG` on the lab override, the lab token, every lab host plus `node-broken`; run by CI) and `README.md` (what lab VMs need). `node-lab/`: `Start-NodeLab.ps1` starts a NexusInfra control plane (published images, default `0.4.1-community`, gateway `127.0.0.1:29400`) and three fresh Ubuntu hosts as privileged containers (ssh `127.0.0.1:2231/2232/2233`, fixed addresses `172.29.50.x`; node3 is the outbound host), and writes key, lab secrets, API token, config override (incl. the `ws://` agent link) and inventories (`inventory.lab.json` direct, `inventory.outbound.json` outbound) to the git-ignored `node-lab/.keys/`; `-Remove` stops it; `-BuildFrom <NexusInfra checkout>` builds the images under `-Version` and pushes the agent image into the lab registry (`172.29.50.30:5000`), for an unreleased NexusInfra (dev) |
| `en-US/` | `about_NexusFleet.help.txt` (`Get-Help about_NexusFleet`; must mention every exported cmdlet, shipped by the build) |
| `docs/` | English: `README.md` (index), `user-guide.md` (anchors per cmdlet are the help's online links), `inventory.md`, `configuration.md` (every key), `security.md`, `troubleshooting.md`, `architecture.md`, `agent-link.md` (design of `reach: outbound`, built with NexusInfra #416), `development.md`, `testing.md`; links checked by `tests/Quality.Tests.ps1`. Dutch: `projectvoorstel.md`; `ontwerpkeuzes.md` (Dutch; E1–E4 for Tom, K1–K3 = choices made during the scaffold); `nexusinfra-wijzigingen.md` (Dutch, one line per `fleet-support:` commit in NexusInfra); `leerlogboek.md` (Tom's; holds draft notes (facts only) written by Claude Code at Tom's explicit request on 2026-11-02, for Tom to rewrite — only add to it when Tom asks) |
| `docs/uitleg/` | Explanations per topic, written by Claude Code as study material (section 2c) + `README.md` index |
| `logs/` | Run logs, created at runtime, git-ignored |
| `tools/` | Dev tooling, not part of the module. `Invoke-NexusLint.ps1`: lint with the repo settings, findings as warnings or GitHub annotations (+ `-SummaryPath` Markdown), retries only `RULE_ERROR*`. `Invoke-NexusTests.ps1`: the test run of CI and of your machine (`-Suite Unit|Integration`, `-CI`), NUnit + JaCoCo + `report-<suite>.md` in `TestResults/`, throws on a failure. `Test-NexusCommitMessage.ps1`: `type(scope): summary` with the types/scopes of section 3, ≤ 100 chars, no full stop; `-Range` reads `git log --no-merges`. `Invoke-NexusLint.ps1 -SarifPath` writes SARIF 2.1.0 for code scanning; `Invoke-NexusTests.ps1 -MinimumCoverage` fails a run below it. `Write-NexusTestReport.ps1`: Pester result → Markdown (totals, each failure with reason and file:line, per file, slowest, coverage per file) + `::error` annotations (returned, printed by the caller). `Install-NexusTooling.ps1`: the pinned tool versions, with retries. `Build-NexusModule.ps1`: copies only the module files (manifest, loader, README, `src/**/*.ps1`, default config) to `out/NexusFleet/`, checks in a separate `pwsh` that it loads and exports the manifest's list, zips `out/NexusFleet-<version>.zip`. Tested in `tests/tools/` |
| `.github/workflows/ci.yml` | On PRs, pushes to `dev`/`main`, by hand, and reusable (`workflow_call`); a newer push cancels a PR's outdated run (`concurrency`). Jobs `workflows` (actionlint 1.7.7 image), `commits` (PRs: title via `env:`, commits base..head), `build` (`tools/Build-NexusModule.ps1`, zip as artifact `nexusfleet-module`), lint uploads SARIF (`security-events: write`; release.yml grants it to its `checks` call), `lint` (ubuntu, `tools/Invoke-NexusLint.ps1 -GitHubAnnotations -SummaryPath`) and `test` as a matrix on `ubuntu-latest` + `windows-latest` + `macos-latest` with `-MinimumCoverage 95` (`fail-fast: false`; `tools/Invoke-NexusTests.ps1 -Suite Unit -CI`: report in the job summary, an annotation per failure, artifacts `test-results-<os>`). Versions pinned; read-only token |
| `.github/actions/` | Composite actions for the lab jobs: `start-node-lab` (inputs `version`, `nexusinfra-ref`: checks out NexusInfra when a ref is given and starts the lab with `-BuildFrom`; inputs via `env:`), `collect-lab-logs` (container, agent and NexusFleet logs into `TestResults/`, uploaded as artifact `inputs.artifact`; its steps carry `if: always()`) |
| `lab/control-planes.json` | The control planes CI tests against: `name`, `version` (image tag), `nexusinfra-ref` (build from that branch, or empty), `id` (artifact suffix). The `control-planes` job of `integration.yml` turns it into the matrix of every lab job |
| `.github/workflows/integration.yml` | On PRs and pushes to `dev`/`main`, every night (`schedule`, catches a breaking NexusInfra dev) and by hand, as a matrix over `lab/control-planes.json` (job `control-planes` → `fromJSON`): starts the E1 lab (`-PlainOnly`) and the node lab on `ubuntu-latest`, runs `tools/Invoke-NexusTests.ps1 -Suite Integration -CI` (a skip fails the job), keeps NexusFleet's `logs/` and every container's log as artifact `integration-results`, always removes the labs. Job `demo` (same two control planes): a fresh node lab, `lab/demo/Invoke-NexusLabDemo.ps1`, its `summary.md` into the job summary, fails when a "Klaar als" criterion does not hold, artifact `demo-results[-nexusinfra-dev]` |
| `.github/pull_request_template.md`, `ISSUE_TEMPLATE/`, `CODEOWNERS` | The PR checklist of section 2b; issue forms for a bug (`type:bug`) and a feature (`type:feature`, with the NexusFleet/NexusWatch boundary); every path owned by `@tombomeke-ehb` |
| `.github/workflows/secrets.yml` | gitleaks 8.30.1 (released binary, checksum-verified): a PR's commits, the whole history on `dev`/`main` and weekly; config `.gitleaks.toml` (default rules + the tests' fake secrets by value); SARIF to code scanning |
| `.github/workflows/scorecard.yml` | OpenSSF Scorecard on `dev`, weekly, on branch-protection changes; publishes the result (badge) and SARIF |
| `.github/workflows/pr-labels.yml` | `pull_request_target` (base checkout only, title via `env:`): sets the `type:*` label from the title's type; `.github/release.yml` groups the release notes by it |
| `.github/dependabot.yml` | Weekly PRs into `dev` for newer GitHub Actions (prefix `ci(ci)`, label `type:ci`) |
| `.github/workflows/release.yml` | On a tag `v*` (main only, milestones): the CI checks, tag must equal `v<ModuleVersion>`, `tools/Build-NexusModule.ps1`, `gh release create` with the zip. `workflow_dispatch` = dry run (build + artifact, no release) |

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
  **not** visible in the runspaces — import the module inside the block by path. Internal (non-exported)
  functions are still invisible after that import: run the work in the module's scope with
  `$m = Import-Module $using:manifest -PassThru; & $m { param(...) ... } $args` (tested in
  `tests/utils/Write-NexusLog.Tests.ps1`). Module variables do not carry over either: pass a context object.
  Always pass `-ThrottleLimit` from a parameter.
- **`-WhatIf` is inherited** (`$WhatIfPreference`) by every command below a cmdlet. Anything that must happen
  in a dry run too (logging) uses `-WhatIf:$false` explicitly.
- **In a `catch`, save the error first** (`$caught = $_`): inside a `switch` (and `ForEach-Object`, `Where-Object`)
  `$_` is that block's current value, not the error.
- **`Invoke-RestMethod` refuses a bearer token over `http://`** unless `-AllowUnencryptedAuthentication`;
  `Invoke-NexusApi` only allows it for loopback or with `-AllowUnencryptedHttp` (K5).
- **`Invoke-RestMethod` writes a JSON array as one object.** `return Invoke-RestMethod ...` hands the caller one array
  object, so `Where-Object` on it finds nothing (#47). Assign to a variable and return that: then it is enumerated.
- **`HttpResponseException` derives from `HttpRequestException`**: check for an HTTP status first, then treat
  `HttpRequestException`/`TaskCanceledException`/`TimeoutException` without a status as a network error.
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

### GitHub Actions
- **Every `uses:` is a full commit SHA with `# vX.Y.Z`** (a tag can be moved); `tests/Quality.Tests.ps1` fails otherwise.
  Find a SHA with `gh api repos/<owner>/<repo>/git/ref/tags/<tag>`; Dependabot keeps them current.
- **Docker images by digest** (`image:tag@sha256:...`): the lab base images, the lab's RabbitMQ and registry, the
  actionlint image. Dependabot (`docker`, `docker-compose`) proposes new digests.
- **Never paste `${{ }}` text into a `run:` script** (PR titles, inputs, refs): pass it through `env:` (script injection).
- `permissions: contents: read` at the top; a job gets more only for what it does (`security-events: write`, `id-token: write`).
- A composite action's steps that must run after a failure carry their own `if: always()`.

### SSH and the hosts
- Native `ssh` must never wait for input: `-o BatchMode=yes -o ConnectTimeout=<n>`. Check
  `$LASTEXITCODE` after every call.
- Scripts sent to a Linux host need **LF** line endings (`.gitattributes`); CRLF breaks bash.
- **A string piped to `ssh` gets CRLF appended on Windows** (`[Environment]::NewLine`), so a secret arrives
  with a trailing `
`. Pipe bytes instead: `[Text.Encoding]::UTF8.GetBytes($secret) | ssh ...` (PowerShell 7.4+,
  see `docs/ontwerpkeuzes.md` E1 and K4).
- Use `StrictHostKeyChecking=accept-new` (never `no`): new hosts are trusted, a changed host key is refused.
- In the lab, address containers as `127.0.0.1`: `localhost` tries IPv6 first and costs ~2 s per connection.
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
- **A heartbeat creates the node** (`upsertNode`): deleting a node whose agent still runs brings the record back
  within a second, without its name and location. `Remove-NexusNode` therefore deletes again after the agent is gone.
- **Servers:** `GET /deployments?limit=&offset=&nodeId=&status=&q=` answers `{ items, total, limit, offset }`,
  at most 200 per page, default 25.
- **Bulk:** `POST /deployments/bulk` `{ action: start|stop|restart|kill, ids: [...] }`, at most 100 ids,
  always `200` with a result per server.
- **The agent** (`docs/images.md`, "Adding a machine"): image
  `ghcr.io/tombomeke-studios/nexusinfra/node-agent:community`, env `NODE_ID`, `RABBITMQ_URL`,
  `INTERNAL_API_TOKEN`, `AGENT_URL`; port `9100`; Docker socket mounted; `--add-host=host.docker.internal:host-gateway`.
  **Three options fail silently when forgotten:** `--restart unless-stopped`, the port publication,
  and the `nexusinfra-backups` volume. The agent step must always set all three.
- The agent speaks **plain HTTP**; `/health` is open, everything else needs the shared
  `INTERNAL_API_TOKEN`. `AGENT_URL` must be an address the orchestrator can reach.
- The broker default `guest/guest` must not be used on anything reachable (RabbitMQ refuses `guest` from another
  machine anyway). Since NexusInfra #409/#410 (`fleet-support:`) the bundles publish the broker through
  `BROKER_BIND`/`BROKER_PORT` (default `127.0.0.1`), and the installer generates `RABBITMQ_USER`/`RABBITMQ_PASS`.
- `DELETE /nodes/:id` for an unknown node answers `404` since NexusInfra #411 (in the next release; 0.4.0 answers
  `500`).
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
