# Troubleshooting

Start with the result object. Every cmdlet that works per host returns `Step` (where it went wrong) and `Error`
(why, in plain words). `Install-NexusNode` also returns `Steps` (each step's outcome) and `Preflight` (the checks).
For more detail, open the host's log in `logs/<RunId>/<host>.log`, or add `-Verbose`.

```powershell
$results = $hosts | Install-NexusNode
$results | Where-Object { -not $_.Success } | Format-List Host, Step, Error
($results | Where-Object Host -EQ 'node-home02').Steps | Format-Table
```

## Connecting

| Message or error id | Cause | Fix |
|---|---|---|
| `NexusFleet.NotConnected`: "not connected to a NexusInfra panel" | `Install-NexusNode` or `Get-NexusFleetStatus` without a connection in this session | `Connect-NexusInfra` |
| `NexusApi.Unauthorized` (401) | The token is wrong, expired or revoked | Create a new token in the panel; `Connect-NexusInfra -Token ... -Save` |
| `NexusFleet.NotPlatformAdmin` | The token's account is not `admin` or `owner` | Use a token of a platform administrator |
| `NexusFleet.TokenMissingAdminScope` | The token lacks the `admin` scope | Create a token with the scopes `write` and `admin` |
| `NexusApi.Forbidden` (403) on the first change | The token lacks the `write` scope | As above |
| `NexusApi.Unreachable`: "cannot reach the panel at ..." | Wrong `Api.BaseUrl`, the panel is down, or a firewall | Check the address in your local config; open it in a browser |
| `NexusApi.RateLimited` (429) | The gateway allows 50 requests/s per token. A GET is retried first; this error means it stayed full, usually with very many hosts at once | Lower `-ThrottleLimit`, or raise `Health.PollIntervalSeconds` |
| `NexusApi.UnencryptedNotAllowed` | `http://` to another machine | Use `https://`, or on a trusted lab network set `Api.AllowUnencryptedHttp = $true` |
| `NexusFleet.TokenNotStored` | No `-Token`, and nothing stored | `Connect-NexusInfra -Token (Read-Host -AsSecureString 'API token') -Save` |
| `NexusFleet.SecretManagementMissing` / `TokenNotSaved` | SecretManagement or a vault is missing | See [the user guide](user-guide.md#before-you-start) |

## Preflight (`Test-NexusHost`, and the first step of `Install-NexusNode`)

| Step | Error | Fix |
|---|---|---|
| `Reachable` | "cannot reach ... over ssh: Connection refused / timed out" | Is the address and port right? Is sshd running? Is a firewall in between? `ssh -p <port> <user>@<address>` by hand |
| `SshAuth` | "the host refused the key for user ..." | Is the public key in `~/.ssh/authorized_keys` of that user? Is `keyFile` in the inventory right? |
| `OS` | "OS '...' is not supported" | NexusFleet supports Ubuntu (`Preflight.SupportedOs`) |
| `Sudo` | "... cannot use sudo without a password" | Add `<user> ALL=(ALL) NOPASSWD:ALL` in `/etc/sudoers.d/` |
| `DiskSpace` | "... MB free on /, at least ... MB needed" | Free up space, or lower `Preflight.MinDiskFreeMB` |
| `Broker` | "broker ...:5672 is not reachable from the host" | `Broker.Host` must be the broker **as the host sees it**. Is 5672 published on the control plane, and open on the network? |

A changed host key is refused by ssh ("REMOTE HOST IDENTIFICATION HAS CHANGED"). If the host was really
reinstalled, remove its old line from your `known_hosts` (`ssh-keygen -R <address>`); otherwise, find out why the key
changed.

## Installation steps

| Step | Error | Cause and fix |
|---|---|---|
| `Docker` | "Could not install Docker on ... (exit 100): E: ..." | apt could not install the package. Is there internet access, and a working apt source? The last lines of apt's output are in the error |
| `Docker` | "Docker was installed but the daemon does not answer" | Look at `sudo systemctl status docker` on the host |
| `RegisterNode` | `NexusApi.Forbidden` | The token lacks `write` or `admin` |
| `AgentContainer` | "the agent needs RABBITMQ_URL and INTERNAL_API_TOKEN, and none were given" | Store them with `Set-Secret`, or pass `-RabbitMqUrl` and `-InternalApiToken` |
| `AgentContainer` | "Could not start the agent container ... port is already allocated" | Something else uses port 9100 on the host (`sudo ss -ltnp`) |
| `AgentContainer` | a pull error from `ghcr.io` | The host has no internet access, or `Agent.Image` is wrong |
| `VerifyHealthy` | "did not become healthy within 60 s (last health: offline)" | The agent runs but sends no heartbeats. Usually a wrong broker URL or password, or the broker is not reachable. See `sudo docker logs nexusinfra-node-agent` on the host |
| `VerifyHealthy` | "... (last health: not registered)" | The node record was not found. Is `Api.BaseUrl` the same panel the agents report to? |
| `AgentReachable` | "NexusInfra cannot reach the agent of ... at http://...:9100" | The node is healthy (its heartbeats arrive), but the control plane cannot call the agent, so it could not run anything there. A firewall or security group closes port 9100, a port forward is missing, the `agentUrl` in the inventory is an address the control plane cannot reach, or ("answered 401") the `INTERNAL_API_TOKEN` differs from the control plane's `.env` |

A failed step rolls back what this run did on that host, so the host is as it was. Fix the cause and run again.
Steps that are already in order are skipped.

**After changing a secret** (broker password, `INTERNAL_API_TOKEN`), a normal run changes nothing, because the check
never reads secrets back from a host. Run `Install-NexusNode -Force`.

## Status (`Get-NexusFleetStatus`)

| Problem | Meaning |
|---|---|
| `NexusInfra reports it offline; the agent container is exited` | The agent stopped. `sudo docker logs nexusinfra-node-agent` says why; `Install-NexusNode` starts it again |
| `NexusInfra reports it offline; the agent container is missing` | The container was removed; `Install-NexusNode` recreates it |
| `NexusInfra reports it offline` (agent running) | The agent runs but its heartbeats do not arrive: broker URL, password, or network |
| `not registered in NexusInfra` | The host is in the inventory but not in the panel: run `Install-NexusNode` |
| `cannot reach ... over ssh` | The host itself is down or unreachable |
| Health `unknown`, with a warning | NexusInfra itself could not be asked; only the hosts were checked |

## Configuration

"NexusFleet config is not valid" lists every wrong value, with the file it was read from. Fix those values in
`config/nexusinfra.local.psd1`. Every key, its rule and its meaning are in [configuration.md](configuration.md). A
warning about an unknown key usually means a typo in your local file.
