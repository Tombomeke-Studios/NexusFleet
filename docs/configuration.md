# Configuration reference

Every value NexusFleet needs about NexusInfra and about your hosts lives in
[config/nexusinfra.psd1](../config/nexusinfra.psd1). None of it is secret. The functions never hard-code any of it.

## Changing a value

Do not edit `config/nexusinfra.psd1` for your own setup. Create `config/nexusinfra.local.psd1` with only the keys
you change, in the same structure. That file is git-ignored.

```powershell
@{
    Api    = @{ BaseUrl = 'https://panel.example.com' }
    Broker = @{ Host = '10.0.0.2' }
    Health = @{ VerifyTimeoutSeconds = 120 }
}
```

The local file is merged into the default one key by key, so nested tables keep the keys you do not mention. A key
that does not exist in the default config, which is probably a typo, gives a warning.

## Validation

Every cmdlet reads the config when it starts (`Get-NexusConfig`) and checks every value against a rule. All problems
are reported in one error, with the file(s) read:

```text
NexusFleet config is not valid (read from: .../config/nexusinfra.psd1, .../config/nexusinfra.local.psd1):
- Agent.Port must be a port number 1-65535, but is '70000'
- Health.OfflineAfterSeconds must be greater than Health.DegradedAfterSeconds
```

The test `tests/Quality.Tests.ps1` makes sure every key below has such a rule.

## Keys

### `Api`: the NexusInfra panel

| Key | Default | Rule | Meaning |
|---|---|---|---|
| `BaseUrl` | `http://localhost:9400` | http(s) URL | The panel's gateway. `Connect-NexusInfra -BaseUrl` overrides it for one session. |
| `TimeoutSeconds` | `30` | 1-300 | Time-out per API request. |
| `RetryCount` | `2` | 0-10 | Extra attempts, for GET requests after a network error or 502/503/504 only. Changing requests are never repeated. |
| `AllowUnencryptedHttp` | `$false` | boolean | Allow sending the API token over plain `http://` to a host other than this machine. Set it only on a trusted lab network; see [security.md](security.md). |
| `SecretName` | `NexusFleet-ApiToken` | secret name | Where `Connect-NexusInfra -Save` stores the token with SecretManagement. |

### `Agent`: the NexusInfra node agent on each host

| Key | Default | Rule | Meaning |
|---|---|---|---|
| `Image` | `ghcr.io/tombomeke-studios/nexusinfra/node-agent:community` | image name | The agent image. Pin a version (for example `...:0.4.0-community`) so every node runs the same agent as the control plane. |
| `ContainerName` | `nexusinfra-node-agent` | container name | The name of the container on each host. |
| `Port` | `9100` | 1-65535 | The agent's port, published on the host. It is also the port in the default `agentUrl` of the inventory. |
| `RestartPolicy` | `unless-stopped` | `unless-stopped` or `always` | Without one, a crashed agent or a rebooted host leaves the node offline, and nothing reports it. Other policies are refused. |
| `BackupVolume` | `nexusinfra-backups` | volume name | The named volume for the agent's backups. Without it, backups are lost when the container is replaced. |
| `BackupMountPath` | `/var/lib/nexusinfra/backups` | absolute path | Where the backup volume is mounted in the container. |
| `DockerSocket` | `/var/run/docker.sock` | absolute path | The host's Docker socket, mounted so the agent can run servers. |
| `HostGateway` | `host.docker.internal:host-gateway` | `<name>:host-gateway` | Lets the agent reach a server's published port on the host. |
| `EnvFile` | `/etc/nexusinfra/agent.env` | absolute file path | On the host: the agent's environment, secrets included. NexusFleet writes it with mode 600, owned by root. |
| `EnvNames.NodeId` | `NODE_ID` | variable name | The environment variable names the agent reads. Change them only when NexusInfra does. |
| `EnvNames.RabbitMqUrl` | `RABBITMQ_URL` | variable name | |
| `EnvNames.InternalApiToken` | `INTERNAL_API_TOKEN` | variable name | |
| `EnvNames.AgentUrl` | `AGENT_URL` | variable name | |
| `SecretNames.RabbitMqUrl` | `NexusFleet-RabbitMqUrl` | secret name | Where `Install-NexusNode` finds the broker URL with SecretManagement when `-RabbitMqUrl` is not given. |
| `SecretNames.InternalApiToken` | `NexusFleet-InternalApiToken` | secret name | Likewise for `-InternalApiToken`. |

### `Docker`: installing Docker on a host that has none

| Key | Default | Rule | Meaning |
|---|---|---|---|
| `Package` | `docker.io` | Debian package name | Ubuntu's own Docker package, so no extra apt repository or signing key is needed. |
| `AptLockTimeoutSeconds` | `300` | 0-3600 | How long apt waits for another apt run to finish. On a fresh VM, unattended-upgrades often holds the lock. |

### `Broker`: the RabbitMQ broker, as the hosts reach it

| Key | Default | Rule | Meaning |
|---|---|---|---|
| `Host` | `localhost` | host name or IP | The broker's address **as seen from the hosts**. `Test-NexusHost` checks it from each host. Set it in your local file. |
| `Port` | `5672` | 1-65535 | The AMQP port. |

The full broker URL contains a password, so it is not here. It is a secret, passed at install time (see
[security.md](security.md)).

### `Ssh`: the connection to the hosts

| Key | Default | Rule | Meaning |
|---|---|---|---|
| `ConnectTimeoutSeconds` | `10` | 1-300 | How long ssh waits for a host to answer. |
| `KnownHostsFile` | `''` | a path, or empty | Your own known_hosts file; empty means ssh's default (`~/.ssh/known_hosts`). |

### `Preflight`: `Test-NexusHost`

| Key | Default | Rule | Meaning |
|---|---|---|---|
| `MinDiskFreeMB` | `2048` | 0-1000000 | A host with less free space on `/` fails the DiskSpace check. |
| `SupportedOs` | `@('ubuntu')` | list of OS ids | Accepted values of `ID` in `/etc/os-release`. |
| `ThrottleLimit` | `10` | 1-256 | Hosts checked at the same time. Also the default for `Get-NexusFleetStatus`. |

### `Install`: `Install-NexusNode`

| Key | Default | Rule | Meaning |
|---|---|---|---|
| `ThrottleLimit` | `5` | 1-256 | Hosts installed at the same time. Each one downloads Docker and the agent image, so keep it modest on a slow uplink. |

### `Health`: when a node counts as healthy

| Key | Default | Rule | Meaning |
|---|---|---|---|
| `DegradedAfterSeconds` | `3` | 1-300 | NexusInfra's own threshold: a node without a heartbeat for this long is *degraded*. After a new agent starts, `Install-NexusNode` waits this long first, so the old agent's last heartbeat cannot count. |
| `OfflineAfterSeconds` | `10` | 1-300, more than `DegradedAfterSeconds` | NexusInfra's threshold for *offline*. |
| `VerifyTimeoutSeconds` | `60` | 1-3600 | How long `Install-NexusNode` waits for a new node to become healthy before the step fails and the install is rolled back. |
| `PollIntervalSeconds` | `2` | 1-60 | How often it asks while waiting. |

The two thresholds mirror NexusInfra (v0.4.0) and must match the panel you use.

### `Log`: the run logs

| Key | Default | Rule | Meaning |
|---|---|---|---|
| `Directory` | `''` | a folder path, or `''` | The folder that holds one folder per run (`<RunId>/`). `''` means `logs/` in the folder you run NexusFleet from. A relative path is relative to that folder too; an absolute path (`C:/NexusFleet/logs`, `~/nexusfleet/logs`) keeps every run in one place. The folder is created when it does not exist. |
