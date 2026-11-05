# Testing

NexusFleet is tested with [Pester 5](https://pester.dev). The tests live in `tests/`, in the same layout as `src/`
(`src/steps/Docker.ps1` is tested in `tests/steps/Docker.Tests.ps1`). Every bug fix starts with a test that shows the
bug.

## Running the tests

```powershell
./tools/Install-NexusTooling.ps1          # once: Pester 5.7.1, PSScriptAnalyzer 1.25.0, SecretManagement 1.1.2
./tools/Invoke-NexusTests.ps1             # the unit tests, with coverage, as CI runs them
./tools/Invoke-NexusTests.ps1 -NoCoverage # faster, for a quick check
./tools/Invoke-NexusLint.ps1              # PSScriptAnalyzer with the repository's settings
```

`Invoke-NexusTests.ps1` writes to `TestResults/`:
- `pester-<suite>.xml`: the results in NUnit XML;
- `coverage-<suite>.xml`: JaCoCo coverage of `src/`;
- `report-<suite>.md`: the readable report, with every failure, its reason and its file and line.

It throws when a test fails.

Plain Pester works too. Load Pester 5 explicitly, because `-MinimumVersion 5.0` alone would load Pester 6, and
Windows ships Pester 3.4:

```powershell
Import-Module Pester -MinimumVersion 5.0 -MaximumVersion 5.99
Invoke-Pester -Path ./tests/steps -Output Detailed
```

## Kinds of tests

| Kind | Tag | Runs in | What it proves |
|---|---|---|---|
| Unit | none | every CI run, on Linux and Windows | The logic, with the transport (`Invoke-NexusHostCommand`) and the API (`Invoke-NexusApi`) mocked. No network, no SSH, no NexusInfra. |
| Fake fleet | none | every CI run | The real steps and the real step runner against `tests/core/FakeFleet.ps1`. Its fake hosts and fake panel remember what was installed, so a test can run an install twice (idempotency), make any step fail (rollback), and check what "happened". |
| Scale | none | every CI run | 50 and 100 generated hosts, some unreachable and some failing, for `Test-NexusHost`, `Install-NexusNode` and `Get-NexusFleetStatus`: exactly one correct result per host, and no crash. |
| Local HTTP | `LocalHttp` | every CI run | `Invoke-NexusApi` against a real `HttpListener` on a free loopback port. This catches what a mock of `Invoke-RestMethod` cannot (it found three bugs). |
| Local SSH | `LocalSsh` | every CI run | The real `ForEach-Object -Parallel` path with the real ssh client against closed loopback ports. One result per host comes from real runspaces, and logging works from inside them. |
| Integration | `Integration` | `integration.yml`, and by hand | The real thing: the E1 lab (an Ubuntu host with sshd) and the node lab (a NexusInfra 0.4.0 control plane and two fresh Ubuntu hosts in Docker). It includes the three "Klaar als" criteria of the MVP. |
| Quality | none | every CI run | Tests about the tests: every config value has a validation rule, every error id is tested, and the help of every cmdlet is complete and its examples are valid. |

### Why the parallel code is tested this way

Pester mocks do not reach into `ForEach-Object -Parallel` runspaces (experiment E3). So the work for one host always
lives in its own function, such as `Invoke-NexusHostPreflight` or `Invoke-NexusHostInstall`, and is tested directly
with mocks. The cmdlet's parallel loop is a thin wrapper. That wrapper is tested three ways:
- with `-ThrottleLimit 1`, where it runs sequentially and the mocks work;
- by the LocalSsh tests, with real runspaces and real ssh;
- by the integration tests.

### Mocking a native program

A mock of `ssh` does not see the bytes piped into it, so the secret-over-stdin path could not be tested that way.
The real call therefore sits in a minimal wrapper, `Invoke-NexusSshClient -InputBytes`. The unit tests mock that
wrapper, and the integration test covers it for real.

## Integration tests

They need Docker. Start the labs, run, and remove them:

```powershell
./lab/E1-transport/Start-LabTarget.ps1 -PlainOnly
./lab/node-lab/Start-NodeLab.ps1
./tools/Invoke-NexusTests.ps1 -Suite Integration
./lab/node-lab/Start-NodeLab.ps1 -Remove
./lab/E1-transport/Start-LabTarget.ps1 -Remove
```

Without a running lab, the integration tests skip themselves. In CI a skip fails the job, because there the labs are
always started first.

The install test starts by undoing an earlier run (the agent, the env file, Docker and the node records), so it can be
run again and again.

## Continuous integration

| Workflow | When | Jobs |
|---|---|---|
| [ci.yml](../.github/workflows/ci.yml) | pull requests, pushes to `dev` and `main`, by hand | `PSScriptAnalyzer` (also to code scanning), `actionlint`, the commit messages, `Pester` on `ubuntu-latest`, `windows-latest` and `macos-latest` (at least 95 % coverage), and the build |
| [integration.yml](../.github/workflows/integration.yml) | pull requests and pushes to `dev` and `main`, every night, and by hand | both labs in Docker, then the `Integration` tests; and the demo on a fresh node lab, with the three criteria in the summary. Each against NexusInfra 0.4.0 and NexusInfra `dev` |
| [release.yml](../.github/workflows/release.yml) | a `v*` tag, and by hand (dry run) | the CI checks, then build, checksum, provenance and release |
| [secrets.yml](../.github/workflows/secrets.yml) | pull requests, pushes to `dev` and `main`, weekly | gitleaks over the commits |
| [scorecard.yml](../.github/workflows/scorecard.yml) | pushes to `dev`, weekly | OpenSSF Scorecard |
| [pr-labels.yml](../.github/workflows/pr-labels.yml) | every pull request | the `type:*` label from the title |

What a run shows:

- **The summary page** of the run has a report per job:
  - the totals;
  - every failed test, with its full name, `file:line` and Pester's message (what was expected, what came instead);
  - test files whose setup failed;
  - the results per test file;
  - the slowest tests;
  - the coverage per source file, with the missed lines.

  The lint job lists its findings in a table.
- **Annotations:** every failure is also shown on its line in the pull request's *Files changed* tab.
- **Artifacts:**
  - `test-results-<os>`: NUnit XML, JaCoCo and the report;
  - `integration-results`: the same, plus NexusFleet's run logs and every lab container's log.

## Writing a test

- Name the test after the behaviour, as a sentence: `It 'rolls back the failed step and the steps it applied'`.
- Unit tests never touch the network. Mock `Invoke-NexusHostCommand` and `Invoke-NexusApi`, and assert the calls with
  `Should -Invoke`.
- When a test needs the module's internal functions, import the module and use `Mock -ModuleName NexusFleet`, or run
  code in the module's scope with `& $module { ... }`.
- A mock body cannot see `$script:` variables of the test file. Use plain variables from `BeforeAll`/`BeforeEach`,
  and a hashtable for anything a mock changes.
- Shared helpers are plain `.ps1` files without `.Tests`: `tests/core/FakeFleet.ps1` and
  `tests/steps/TestStepContext.ps1`.
- Put a test under `Integration` only when the real thing is the only proof.
