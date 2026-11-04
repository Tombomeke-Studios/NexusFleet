# Security

NexusFleet logs in to your machines with sudo rights and handles three secrets. This page says what it does with
them, and what it deliberately does not do.

## The secrets

| Secret | What it is | Where NexusFleet keeps it |
|---|---|---|
| API token (`nxi_...`) | NexusInfra token of a platform administrator, with the scopes `write` and `admin` | SecretManagement (`Api.SecretName`) or the `-Token` parameter |
| Broker URL | `amqp://user:password@host:5672`, so it contains the broker's password | SecretManagement (`Agent.SecretNames.RabbitMqUrl`) or `-RabbitMqUrl` |
| `INTERNAL_API_TOKEN` | NexusInfra's shared token between the orchestrator and the agents | SecretManagement (`Agent.SecretNames.InternalApiToken`) or `-InternalApiToken` |

Rules the code follows (and tests):

- **Always a `SecureString`** in parameters and in memory. The plain text exists only at the moment it is sent, and
  the bytes sent to ssh are cleared right after.
- **Never on a command line.** A secret on the command line of ssh or of `docker run` would show in the process list
  of the admin machine or the host. NexusFleet sends secrets over the **stdin** of ssh, one line each. On the host,
  bash reads them and writes `/etc/nexusinfra/agent.env`: folder mode 700, file mode 600, owner root. The agent gets
  them with `docker run --env-file`.
- **Never in a log.** Every run knows its secrets (`Initialize-NexusRunContext -Secret`), and `Write-NexusLog`
  replaces them with `***` (and any `nxi_...` token with `nxi_***`) before a line is written. A test checks every log file of an
  install run for the three test secrets.
- **Never in the repository.** Your config (`config/*.local.*`) and inventory (`config/inventory.json`) are
  git-ignored, and so are the lab keys (`lab/**/.keys/`). Being ignored is not secret storage, though: the secrets
  themselves belong in SecretManagement.
- **Never read back.** The check of the agent step reads only `NODE_ID` and `AGENT_URL` from the container on the
  host. The secrets never leave the host. That is also why a changed secret needs `Install-NexusNode -Force`.

What remains visible: root on a host can read the env file, and anyone allowed to run `docker inspect` there sees the
agent's environment. That is inherent to how the NexusInfra agent takes its configuration.

## The API token over HTTP

`Invoke-RestMethod` refuses to send a bearer token over `http://`. NexusFleet allows it only to this machine
(`localhost`, `127.0.0.1`, `::1`), where nothing leaves the machine. For any other `http://` address you must set
`Api.AllowUnencryptedHttp = $true` in your local config, and every request then shows a warning. Without that setting
the request is refused before anything is sent (`NexusApi.UnencryptedNotAllowed`). Use `https://` for a panel on
another machine.

The token needs `write` and `admin`. Create a separate token for NexusFleet in the panel, so it can be revoked without
touching anything else.

## SSH

- **Keys only.** ssh runs with `BatchMode=yes`, so it never asks for a password and never waits for input.
- **Host keys:** `StrictHostKeyChecking=accept-new`. A host seen for the first time is trusted and remembered. A
  **changed** host key is refused, which is what protects against a machine that pretends to be your host. Never use
  `no`.
- **Input is validated** before it reaches ssh. Host names, addresses and user names have strict patterns (a host
  name starting with `-` would become an ssh option), and every value put into a remote command goes through
  `ConvertTo-NexusShellArgument`, which single-quotes it for bash.
- The host user needs `sudo` without a password: NexusFleet installs packages and runs Docker. Give that right to a
  dedicated user (for example `fleet`) with an SSH key only.

## The network

- The agent speaks **plain HTTP** on port 9100. Its `/health` route is open; everything else needs the
  `INTERNAL_API_TOKEN`. Allow port 9100 only from the orchestrator's address.
- **Docker-published ports bypass `ufw`**, because Docker writes its own iptables rules. Do not rely on `ufw` alone to
  close 9100; restrict it at the network level, or in the `DOCKER-USER` chain.
- The broker must not use NexusInfra's default `guest/guest` credentials on any network the hosts share.

Restricting the agent port, a broker user per node and TLS to the broker are planned as the "secured connection"
extra ([TODO.md](../TODO.md), phase 5).
