# tests — the Pester 5 tests

The folders mirror `src/`: `src/steps/Docker.ps1` is tested in `tests/steps/Docker.Tests.ps1`. Every bug fix starts
with a test that shows the bug.

```powershell
./tools/Invoke-NexusTests.ps1                      # the unit tests, with coverage, as CI runs them
./tools/Invoke-NexusTests.ps1 -NoCoverage          # faster
./tools/Invoke-NexusTests.ps1 -Suite Integration   # against the labs (start them first)
```

The run writes `TestResults/report-<suite>.md`, with every failure, its reason and its `file:line`.

## Folders and files

| Path | What it tests |
|---|---|
| `NexusFleet.Tests.ps1` | The module as a whole: the manifest, the loader, the exports, and the **help test**. Every cmdlet needs a real description, every parameter, two explained examples that parse, inputs, outputs, notes, links and the about topic |
| `Quality.Tests.ps1` | **Tests about the tests.** Every config value has a validation rule, every error id is asserted somewhere, every link in the docs works, and every cmdlet passes the log settings |
| [`core/`](core/README.md) | The step runner, the per-host engines, the contracts |
| [`steps/`](steps/README.md) | Each installation step |
| [`transports/`](transports/README.md) | Running commands over ssh |
| [`api/`](api/README.md) | The REST client, also against a real local HTTP server |
| [`utils/`](utils/README.md) | Config, logging, secrets, the per-host loop |
| [`public/`](public/README.md) | The cmdlets, and the scale tests with 50 and 100 hosts |
| [`tools/`](tools/README.md) | The scripts in `tools/`: lint, build, the test report |

## Tags

| Tag | Runs | Needs |
|---|---|---|
| none | always | nothing: no network, no ssh, no NexusInfra |
| `LocalHttp` | always | a free loopback port (a real `HttpListener`) |
| `LocalSsh` | always | the `ssh` client and closed loopback ports: real parallel runspaces, every connection refused at once |
| `Integration` | `-Suite Integration`, and in CI by `integration.yml` | the E1 lab and the node lab in Docker |

## Rules

- **Mock the edges.** Unit tests mock `Invoke-NexusHostCommand`, `Invoke-NexusSshClient` and `Invoke-NexusApi`, and
  check the calls with `Should -Invoke`.
- **Mocks and runspaces.** A mock does not reach into a `ForEach-Object -Parallel` runspace. So the work for one host
  is tested directly, and the cmdlets with `-ThrottleLimit 1`.
- **Load Pester 5 explicitly** (`Import-Module Pester -MinimumVersion 5.0 -MaximumVersion 5.99`). Otherwise Pester 6
  or Windows' Pester 3.4 loads.
- **Helpers are not tests.** Shared helpers are plain `.ps1` files, without `.Tests`: `core/FakeFleet.ps1` and
  `steps/TestStepContext.ps1`.

More: [docs/testing.md](../docs/testing.md).
