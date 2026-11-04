# tests/steps — tests for src/steps

One test file per installation step. Each one covers the step's three parts:
- **Test:** true when the host is in order, false when it is not;
- **Apply:** the exact command or API call it sends, and what happens when that fails;
- **Rollback:** what it undoes, and what it must never touch.

| File | Notable cases |
|---|---|
| `Docker.Tests.ps1` | Docker present or not, an unreachable host, waiting for the apt lock, a host without systemd, and a failed `apt-get` with apt's reason in the error |
| `RegisterNode.Tests.ps1` | A node that exists with other values; a rollback that deletes only a record this run created |
| `AgentContainer.Tests.ps1` | Every setting the Test inspects, including the three that fail silently. The secrets go over stdin and never appear on the command line. `-Force`. The rollback keeps the backups volume |
| `VerifyHealthy.Tests.ps1` | Waiting for healthy, a time-out, and the wait for a new agent, so an old heartbeat cannot count |

`TestStepContext.ps1` is not a test file but a shared helper. It builds a step context like
`Invoke-NexusHostInstall` does, with the real config, a fake host, a fake connection and fake secrets.
