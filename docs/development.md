# Development

How the code is organised, how work flows into it, and how to extend it. The design is described in
[architecture.md](architecture.md). Testing is described in [testing.md](testing.md).

## Setup

```powershell
git clone https://github.com/Tombomeke-Studios/NexusFleet.git
cd NexusFleet
./tools/Install-NexusTooling.ps1
Import-Module ./NexusFleet.psd1 -Force
./tools/Invoke-NexusTests.ps1 -NoCoverage
./tools/Invoke-NexusLint.ps1
```

PowerShell 7.6 or later. Import Pester 5 before PSScriptAnalyzer in the same session, or run them in separate `pwsh`
processes as the scripts do. Analysing the test files makes PSScriptAnalyzer load Pester 6's assembly, and after that
Pester 5 cannot load.

## Layout

| Path | Contents |
|---|---|
| `NexusFleet.psd1` | The manifest. `FunctionsToExport` is an explicit list of the public cmdlets |
| `NexusFleet.psm1` | The loader: dot-sources `src/<folder>/*.ps1` in the order `core`, `utils`, `transports`, `api`, `steps`, `public` |
| `src/core/` | The contracts (a step, a transport result), the step runner, and the per-host engines (preflight, install, status) |
| `src/steps/` | One file per installation step |
| `src/transports/` | Running a command on a host: native ssh |
| `src/api/` | `Invoke-NexusApi`, the only caller of the NexusInfra REST API |
| `src/utils/` | Config, logging, run context, session, secrets, shell quoting |
| `src/public/` | The exported cmdlets |
| `config/` | The default config and an example inventory |
| `en-US/` | `about_NexusFleet` |
| `tests/` | Pester tests, mirroring `src/` |
| `tools/` | Lint, tests, report, build, tooling: the same scripts locally and in CI |
| `lab/` | The labs and the experiments of phase 1 (not part of the module) |
| `docs/` | English documentation, plus the Dutch course documents (see [README.md](README.md)) |

## Conventions

- **Approved verbs**, `Verb-Noun`, with the noun prefix `Nexus`. Public cmdlets return `[pscustomobject]` with a
  `PSTypeName`, never formatted text.
- **Comment-based help on every function**, public or internal. For public cmdlets the help test enforces a real
  description, every parameter, two explained examples that parse, `.INPUTS`, `.OUTPUTS`, `.NOTES` and `.LINK`.
- **Comments say why**, not what. Every file starts with what it is for.
- **No hard-coded infrastructure values.** Anything about NexusInfra or the hosts comes from `config/` or a parameter.
  A new config key needs a validation rule in `Get-NexusConfig`; `tests/Quality.Tests.ps1` fails otherwise.
- **Parameters are validated** with `ValidatePattern`, `ValidateRange` and the like, not deep inside the function.
- **Every changing cmdlet** has `SupportsShouldProcess`. `ShouldProcess` does not work inside `-Parallel`, so decide
  per host before the loop and pass the decision in.
- **One host failing never stops the others.** The per-host function catches everything and returns a result.
- **Secrets** are `SecureString`s. They go to a host over stdin, never on a command line and never into a log.
- **Values put into a remote command** go through `ConvertTo-NexusShellArgument`.
- **Scripts sent to Linux** need LF line endings; `.gitattributes` enforces them.

## Workflow

```text
feature/<topic>  →  dev  →  main
```

- Every task is a line in [TODO.md](../TODO.md) with a GitHub issue. A branch covers one group of lines.
- Per unit:
  1. write the test first;
  2. implement;
  3. tests and lint clean;
  4. update the docs;
  5. tick the item in TODO.md;
  6. commit.
- **Commits:** `type(scope): summary`, one logical change each. Types: `feat`, `fix`, `docs`, `chore`, `refactor`,
  `test`, `ci`. Scopes: `core`, `steps`, `transport`, `api`, `public`, `log`, `config`, `tests`, `docs`, `ci`, `lab`.
- **Pull requests** go into `dev`, with one `Closes #N` line per issue, and are merged only when all four checks are
  green: lint, Pester on Linux, Pester on Windows, and Integration.
- `main` gets milestones only, each tagged (`v1.0.0` = the MVP). A tag `v<ModuleVersion>` builds a GitHub release.

## Adding an installation step

Each step is one file in `src/steps/` that registers itself when the module loads:

```powershell
# Step 25: <what it ensures, and why it is needed>.
Register-NexusStep -Name 'Firewall' -Order 25 -Description 'Agent port open only for the orchestrator' -Test {
    param($Context)
    # Return $true when the host is already in order, $false when Apply is needed. Never change anything here:
    # -WhatIf runs only the Tests.
    $answer = Invoke-NexusStepCommand -Context $Context -Purpose 'check the firewall' -Command '...' -AllowFailure
    $answer.Succeeded
} -Apply {
    param($Context)
    # Make the change. Throw on failure (Invoke-NexusStepCommand does that for you).
    $null = Invoke-NexusStepCommand -Context $Context -Purpose 'open the agent port' -Command '...'
} -Rollback {
    param($Context)
    # Undo Apply. It must be safe after an Apply that stopped halfway. It runs only when this run applied the step.
}
```

- **The `Order` decides where the step runs.** Leave gaps (10, 20, 30, 40) so new steps fit in between. The order
  must be unique.
- **The step context** (`$Context`) has everything a step needs:
  - `HostInfo`: the inventory host;
  - `Config`;
  - `Ssh` and `Api`: splats for the transport and the API;
  - `Secrets`;
  - `RunContext`: for logging;
  - `Force`;
  - `State`: a hashtable to remember something between this step's Test and its Rollback, or to pass it to a later
    step.
- **Talk to the host** with `Invoke-NexusStepCommand`, and to the panel with `Invoke-NexusStepApi`.
- **Test the step** in `tests/steps/<Name>.Tests.ps1`, with `tests/steps/TestStepContext.ps1`: Test true and false,
  Apply's command, a failing Apply, and Rollback. Teach the fake fleet (`tests/core/FakeFleet.ps1`) the new commands,
  so the install tests cover the step too.

Nothing else changes: the runner, the cmdlet and `-WhatIf` pick the step up.

## Adding a public cmdlet

1. Write `src/public/<Verb>-Nexus<Noun>.ps1`, with full comment-based help.
2. Add it to `FunctionsToExport` in the manifest. The export test fails otherwise.
3. Put the per-host work in its own function in `src/core/`, with a failure function next to it, and run it with
   `Invoke-NexusHostLoop`. The cmdlet stays a thin wrapper: collect the hosts in `process`, call the loop in `end`.
4. Write tests: the per-host function directly, the cmdlet with `-ThrottleLimit 1`, a LocalSsh test, and an
   integration test when only the real thing proves it.
5. Document it in `about_NexusFleet`, the user guide and the README. The about test checks that every cmdlet is
   mentioned there.

## Building and releasing

```powershell
./tools/Build-NexusModule.ps1      # out/NexusFleet/ and out/NexusFleet-<version>.zip
```

The build copies only what the module needs, then checks in a separate `pwsh` process that the result loads and
exports exactly the manifest's cmdlets. To release:
1. bump `ModuleVersion` in the manifest;
2. merge `dev` into `main`;
3. tag `v<version>` on `main`.

The release workflow refuses a tag that does not match the version.
