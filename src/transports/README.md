# src/transports — running a command on a host

How NexusFleet reaches a host: native OpenSSH, the choice of experiment E1
([docs/ontwerpkeuzes.md](../../docs/ontwerpkeuzes.md)).

| File | What it is |
|---|---|
| `Invoke-NexusHostCommand.ps1` | Runs one shell command on one host and returns a `NexusFleet.CommandResult`. It never waits for input (`BatchMode`, a connect time-out). It trusts a new host key and refuses a changed one (`accept-new`). Host and user names are validated strictly, and a secret goes in as stdin bytes, never on the command line |
| `Invoke-NexusSshClient.ps1` | The minimal wrapper around `ssh` itself. Unit tests replace it with a mock, because a mock of `ssh` cannot see piped input. The real one is covered by an integration test |

Two rules worth knowing:
- On Windows, PowerShell adds a line break (CRLF) to a string piped to `ssh`. That is why secrets are piped as bytes.
- Windows OpenSSH reports a refused connection only at `LogLevel=INFO`. The known-hosts notice that comes with it
  is filtered out.

Another transport would be another file that returns the same `NexusFleet.CommandResult`.
Tests: [`tests/transports/`](../../tests/transports/README.md).
