# en-US — help that is not tied to one cmdlet

| File | Shown by |
|---|---|
| `about_NexusFleet.help.txt` | `Get-Help about_NexusFleet` |

The about topic is the overview in the shell. It covers what NexusFleet does, the usual order of the cmdlets, what a
host needs, the configuration, the secrets, the logs, and where to look when something fails.

The help of each cmdlet lives in its own source file (comment-based help in `src/public/`). `Get-Help <cmdlet> -Full`
shows it.

`tests/NexusFleet.Tests.ps1` checks that the topic exists, that `Get-Help` finds it, and that it mentions every
exported cmdlet. The build (`tools/Build-NexusModule.ps1`) ships this folder with the module.
