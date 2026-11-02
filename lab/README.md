# lab — experiments of phase 1; not part of the module.

Each experiment has its own folder. Results and decisions: [docs/ontwerpkeuzes.md](../docs/ontwerpkeuzes.md).

| Experiment | Folder | Run (repo root, `pwsh`) |
|---|---|---|
| E1 — transport (`ssh`, PowerShell remoting, Posh-SSH) | `E1-transport/` | `./lab/E1-transport/Start-LabTarget.ps1`, then `./lab/E1-transport/Measure-Transport.ps1 \| Format-Table` |
| E2 — concurrency (`-Parallel`, ThreadJob, Start-Job) | `E2-concurrency/` | `./lab/E2-concurrency/Measure-Concurrency.ps1 \| Format-Table` |
| E3 — Pester mocks and `-Parallel` | `E3-mocks-parallel/` | `Invoke-Pester -Path ./lab/E3-mocks-parallel -Output Detailed` |
| E4 — API token scopes | `E4-token-scopes/` | source analysis, see its README |

E1 needs Docker (the lab targets are containers) and the Posh-SSH module
(`Install-Module Posh-SSH -Scope CurrentUser`). Lab SSH keys live in `E1-transport/.keys/`, which is git-ignored.
Remove the lab targets with `./lab/E1-transport/Start-LabTarget.ps1 -Remove`.
