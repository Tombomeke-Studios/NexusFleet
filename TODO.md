# NexusFleet — TODO

Single source of truth for progress. Every actionable line gets a GitHub issue and its `(#N)` ref when
its group starts (see CLAUDE.md, section 2a). Groups are worked top to bottom; one group = one
`feature/<topic>` branch = one PR into `dev`.

Legend: **[Tom]** = Tom does this himself (lab work, decisions, leerlogboek); everything else can be
done with Claude Code, one unit at a time.

---

## Phase 1 — Lab and experiments · `feature/lab`

Results go in `docs/ontwerpkeuzes.md`; scripts in `lab/`. These decide choices the code depends on.

- [ ] **[Tom]** E0 — Lab ready: NexusInfra control plane reachable from the VMs; one fresh Ubuntu VM with SSH key access (#14)
- [ ] **[Tom]** E0 — Add one node **by hand** following `docs/images.md` ("Adding a machine") and note the time and the mistakes (baseline for the Analyse measurement) (#15)
- [x] E1 — Remoting: compare `ssh`, PowerShell remoting over SSH and Posh-SSH on a fresh VM (setup needed, speed, error behaviour, stdin for secrets) → choose the transport (#16)
- [x] E2 — Concurrency: `ForEach-Object -Parallel` vs `Start-ThreadJob` vs `Start-Job` for 10 and 50 targets (simulated work) → time and memory (#17)
- [x] E3 — Prove that Pester mocks do not reach into `-Parallel` runspaces, and that the per-host-function pattern solves it (#18)
- [x] E4 — API token: which scopes (`write`, `admin`) are needed for `POST /nodes`, `PATCH /nodes/:id/maintenance` and `DELETE /nodes/:id` (#19)
- [ ] Confirm E4 live against the lab control plane (#21)
- [ ] **[Tom]** Confirm the decisions of E1–E4 in `docs/ontwerpkeuzes.md` (Claude Code records measurements and a proposed choice) and write your own learnings in the leerlogboek (#20)
- [ ] **[Tom]** `docs/leerlogboek.md` — create the file and the format you want to keep (per topic: verwachting, wat ik probeerde, wat ik leerde) (#9)

## Phase 2 — Foundations · `feature/foundations`

- [ ] `Write-NexusLog` — one readable line per event (UTC time, RunId, host, step, level, message) + secret redaction; tests for redaction
- [ ] Config loading — `config/nexusinfra.psd1` with every NexusInfra-specific value (agent image, env names, port 9100, volume name, health thresholds, API base URL); validation with clear errors
- [ ] `Invoke-NexusApi` — Bearer token, time-out, retry only for `GET` and network errors, `401/403/404/409` mapped to clear error types; fully mocked tests
- [ ] Transport contract + `Invoke-NexusHostCommand` (method from E1) — returns `ExitCode`, `StdOut`, `StdErr`; secrets via stdin; `BatchMode` and connect time-out
- [ ] Step contract + step runner — each step has `Test` / `Apply` / `Rollback` and declares its order; the runner reads the steps from `src/steps/` (adding a step = adding a file), applies what `Test` says is missing, rolls back applied steps in reverse on failure, and with `-WhatIf` returns the plan only

## Phase 3 — MVP cmdlets

### `feature/connect`
- [ ] `Connect-NexusInfra` — base URL + API token, validate with `GET /me`, store the token with SecretManagement, keep the session in module scope

### `feature/inventory`
- [ ] `Import-NexusInventory` — read and validate a JSON inventory (host/IP, SSH port, user, role, location) into typed objects; `config/inventory.example.json`
- [ ] Tests: valid file, missing file, broken JSON, invalid host name, duplicate host

### `feature/preflight`
- [ ] `Test-NexusHost` — per host: reachable (time-out), SSH auth, OS, sudo, disk space, Docker present, broker reachable; one result object per host
- [ ] Parallel across hosts with `-ThrottleLimit`; one failing host never stops the rest

### `feature/install` — build as a vertical slice first
- [ ] Slice: `Install-NexusNode` with only the preflight + agent step, end to end on **one** VM
- [ ] Step: Docker — test present, install if missing (idempotent)
- [ ] Step: agent container — with `--restart unless-stopped`, the port, the `nexusinfra-backups` volume, the Docker socket and the host-gateway mapping; secrets via stdin
- [ ] Step: register node — `POST /nodes` with id, name, location, `agentUrl`
- [ ] Step: verify — poll `GET /nodes` until *healthy* (thresholds 3 s / 10 s, configurable time-out)
- [ ] Rollback per step, tested with a failure in each step
- [ ] `-WhatIf` returns the plan per host and changes nothing (tested: no changing call is made)
- [ ] Second run changes nothing (idempotency test)
- [ ] Parallel across hosts; one failing host gets its own error and the rest finish

### `feature/status`
- [ ] `Get-NexusFleetStatus` — merge `GET /nodes` with host data over SSH; offline hosts reported, never fatal
- [ ] Export to JSON and CSV

## Phase 4 — MVP finished · `feature/mvp-hardening`

- [ ] Comment-based help with examples on every public function (`Get-Help -Full` reads well)
- [ ] PSScriptAnalyzer: zero warnings
- [ ] Re-enable `PSUseCorrectCasing` once PSScriptAnalyzer#2205 is fixed (#12)
- [ ] Scale test: generated inventories of 50 and 100 mocked hosts, a few offline/failing — correct result per host, no crash
- [ ] README: requirements, quick start, the demo, example output
- [ ] **[Tom]** Demo on 3–5 lab VMs; measure the automated time against the E0 baseline
- [ ] **[Tom]** Check the three "Klaar als" criteria (CLAUDE.md section 9) on the real VMs
- [ ] Merge `dev → main`, tag `v1.0.0`

## Phase 5 — Extras (only after `v1.0.0`, in this order)

### `feature/bulk-actions`
- [ ] `Invoke-NexusFleetAction` — start/stop/restart groups of servers via `POST /deployments/bulk` (max 100 ids per call, batch above that), result per server, `-WhatIf`
- [ ] `Remove-NexusNode` — deregister (`DELETE /nodes/:id`, handle `409`) and clean up the host

### `feature/drift`
- [ ] `Sync-NexusFleet` — compare a desired state (JSON) with reality; report differences; repair with `-WhatIf` support

### `feature/rolling-maintenance`
- [ ] Per node: maintenance on (`PATCH /nodes/:id/maintenance`), move or stop servers, upgrade the agent, verify, maintenance off; stop the whole run at the first failure

### `feature/connectors`
- [ ] Connector contract (connect, register node, list nodes and status, remove node, run action) with NexusInfra as the main connector; values stay in config
- [ ] Documentation: how to write a connector for another platform

### `feature/secure-connection`
- [ ] Extra steps: Caddy in front of the agent with an IP allowlist, agent bound to `127.0.0.1`
- [ ] Own revocable broker user per node (RabbitMQ Management API), TLS / `amqps://` where it works
- [ ] **[Tom]** Lab test: is the Docker-published port really closed from outside?

### `feature/backups`
- [ ] `Backup-NexusFleet` — orchestrate backups across nodes and check retention

### `feature/publish`
- [ ] Publish to the PowerShell Gallery from CI on a tag

## Phase 6 — Delivery

- [ ] **[Tom]** Final report (Dutch), with the measurements and the decisions from `docs/ontwerpkeuzes.md`
- [ ] **[Tom]** Check `docs/nexusinfra-wijzigingen.md` is complete
- [ ] **[Tom]** Rehearse the demo; final tag on `main`

---

## Done

### Phase 0 — Scaffold · `feature/scaffold`

- [x] Create the folder structure from CLAUDE.md section 7 (empty files with a one-line purpose comment) (#1)
- [x] `NexusFleet.psd1` manifest (PowerShell 7.2+, explicit empty `FunctionsToExport`) + `NexusFleet.psm1` loader in the fixed order (#2)
- [x] `PSScriptAnalyzerSettings.psd1` + a first test: the module imports and exports exactly the listed functions (#3)
- [x] `.gitignore` (`logs/`, local config with secrets) and `.gitattributes` (LF for `*.ps1`, `*.sh`, `*.psd1`, `*.psm1`) (#4)
- [x] CI: `.github/workflows/ci.yml` — `pwsh` on ubuntu-latest, Pester (no `Integration` tag) + PSScriptAnalyzer (#5)
- [x] README skeleton (what it is, requirements, quick start placeholder) (#6)
- [x] `docs/architecture.md`, `docs/ontwerpkeuzes.md`, `docs/nexusinfra-wijzigingen.md` (headers only) (#7)
- [x] `docs/uitleg/README.md` index + a first topic file `docs/uitleg/module-opbouw.md` explaining the manifest and the loader (format in CLAUDE.md 2c) (#8)
- [x] **[Tom]** GitHub: default branch `dev`, labels `type:bug|feature|refactor|test|docs|ci|lab` (#10)
- [x] Fix intermittent PSScriptAnalyzer failures in lint (#11)

