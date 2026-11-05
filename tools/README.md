# tools — development scripts

The same scripts run on your machine and in CI, so both check the same way. None of them is part of the module.
Run them from the repository root in `pwsh`.

| Script | What it does | Used by |
|---|---|---|
| `Install-NexusTooling.ps1` | Installs the pinned tools: Pester 5.7.1, PSScriptAnalyzer 1.25.0, SecretManagement 1.1.2. Skips what is already there, and retries when the PowerShell Gallery does not answer | CI, and once on a new machine |
| `Invoke-NexusTests.ps1` | Runs a suite (`-Suite Unit` or `Integration`). Writes NUnit XML, JaCoCo coverage and a readable report to `TestResults/`, and throws when a test fails, or with `-MinimumCoverage` when the coverage of `src/` is too low. `-CI` adds GitHub annotations, and makes a skipped integration test a failure | CI and you |
| `Write-NexusTestReport.ps1` | Turns a Pester result into Markdown: the totals, every failed test with its reason and `file:line`, broken test files, results per file, the slowest tests, and coverage per file | `Invoke-NexusTests.ps1` |
| `Invoke-NexusLint.ps1` | Runs PSScriptAnalyzer with the repository's settings. Prints the findings, as GitHub annotations with `-GitHubAnnotations`, as a Markdown table with `-SummaryPath`, and as SARIF for GitHub code scanning with `-SarifPath`. Retries only the analyzer's own intermittent `RULE_ERROR`s, never a finding | CI and you |
| `Test-NexusCommitMessage.ps1` | Checks commit messages or a pull request title against `type(scope): summary` (CLAUDE.md, section 3). `-Range origin/dev..HEAD` checks every commit of your branch | CI (pull requests) and you |
| `Build-NexusModule.ps1` | Copies only the module's files into `out/NexusFleet/`. It then checks in a separate `pwsh` that the result loads and exports exactly the manifest's cmdlets, and zips it | the release workflow and you |

```powershell
./tools/Install-NexusTooling.ps1
./tools/Invoke-NexusTests.ps1 -NoCoverage
./tools/Invoke-NexusLint.ps1
./tools/Build-NexusModule.ps1
./tools/Test-NexusCommitMessage.ps1 -Range origin/dev..HEAD
```

Tests for these scripts: [`tests/tools/`](../tests/tools/README.md). What CI shows: [docs/testing.md](../docs/testing.md).
