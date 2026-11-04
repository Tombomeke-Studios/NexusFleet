# E1 — how NexusFleet talks to a host

**Question:** which transport should run commands on the hosts: native `ssh`, PowerShell remoting over SSH, or the
Posh-SSH module?

**Outcome:** native `ssh`.
- It needs nothing extra on the host or on the admin machine.
- It is the only one of the three that takes a secret over stdin.
- Remoting needs PowerShell installed on every host, and Posh-SSH's `Invoke-SSHCommand` has no stdin.

The measurements and the reasoning: [docs/ontwerpkeuzes.md](../../docs/ontwerpkeuzes.md#e1--transport-ssh-powershell-remoting-over-ssh-of-posh-ssh).

| File | What it is |
|---|---|
| `Start-LabTarget.ps1` | Creates a lab-only key pair in the git-ignored `.keys/`. Builds and starts two Ubuntu containers with sshd: a plain one, and one with PowerShell for remoting. `-PlainOnly` starts only the plain one, which is all NexusFleet's integration tests need (CI uses it). `-Remove` stops them |
| `Measure-Transport.ps1` | Measures each transport against the targets. It records the time to connect and per command (`-Calls`), and checks whether an exit code comes back. It also checks whether a secret arrives intact over stdin, and what happens with a wrong key or an unreachable address. A call that could hang runs with a time-out (`-GuardSeconds`) |
| `target/Dockerfile` | The lab target: Ubuntu with sshd and a key-only user that may `sudo` |

```powershell
./lab/E1-transport/Start-LabTarget.ps1
./lab/E1-transport/Measure-Transport.ps1 | Format-Table
./lab/E1-transport/Start-LabTarget.ps1 -Remove
```

Needs Docker. Posh-SSH is needed for its part of the comparison: `Install-Module Posh-SSH -Scope CurrentUser`.
