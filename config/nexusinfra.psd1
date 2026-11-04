# Every NexusInfra-specific value NexusFleet uses. Nothing here is secret.
# Override any value for your own setup in config/nexusinfra.local.psd1 (git-ignored): that file only
# needs the keys you change, with the same structure, e.g. @{ Api = @{ BaseUrl = 'https://panel.example.com' } }
# Values verified against NexusInfra docs/images.md ("Adding a machine") at nexusfleet-baseline (v0.4.0).
@{
    Api       = @{
        # The gateway (port 9400) fronts the orchestrator and passes nxi_ tokens through.
        BaseUrl              = 'http://localhost:9400'
        TimeoutSeconds       = 30
        # Extra attempts for GET requests and network errors only; changing requests are never retried.
        RetryCount           = 2
        # The API token is only sent over plain http:// to this machine (localhost). Set to $true in your
        # local file only when the panel runs without TLS on a trusted network.
        AllowUnencryptedHttp = $false
        # Name under which Connect-NexusInfra -Save stores the API token with SecretManagement.
        SecretName           = 'NexusFleet-ApiToken'
    }

    Agent     = @{
        Image           = 'ghcr.io/tombomeke-studios/nexusinfra/node-agent:community'
        ContainerName   = 'nexusinfra-node-agent'
        Port            = 9100
        # Without a restart policy a crashed agent or a rebooted host leaves the node offline (fails silently).
        RestartPolicy   = 'unless-stopped'
        # Without this named volume, backups are lost when the container is replaced (fails silently).
        BackupVolume    = 'nexusinfra-backups'
        BackupMountPath = '/var/lib/nexusinfra/backups'
        DockerSocket    = '/var/run/docker.sock'
        HostGateway     = 'host.docker.internal:host-gateway'
        # On the host: the agent's environment, secrets included (mode 600, only root can read it).
        EnvFile         = '/etc/nexusinfra/agent.env'
        # Names of the environment variables the agent reads.
        EnvNames        = @{
            NodeId           = 'NODE_ID'
            RabbitMqUrl      = 'RABBITMQ_URL'
            InternalApiToken = 'INTERNAL_API_TOKEN'
            AgentUrl         = 'AGENT_URL'
            # Only for a host with reach "outbound" (docs/agent-link.md).
            LinkUrl          = 'AGENT_LINK_URL'
            LinkToken        = 'AGENT_LINK_TOKEN'
            LinkInsecure     = 'AGENT_LINK_ALLOW_INSECURE'
        }
        # The agent link: how an agent with reach "outbound" connects to the control plane (docs/agent-link.md).
        Link            = @{
            # The WebSocket URL the agents dial, as the nodes reach it. Empty: Api.BaseUrl with http -> ws and
            # https -> wss, plus Path. Set it when the nodes reach the control plane under another name.
            Url  = ''
            Path = '/agent-link'
        }
        # Names under which Install-NexusNode finds the agent's secrets with SecretManagement, when they are not
        # passed as parameters. Store them with: Set-Secret -Name NexusFleet-RabbitMqUrl -Secret (Read-Host -AsSecureString)
        SecretNames     = @{
            RabbitMqUrl      = 'NexusFleet-RabbitMqUrl'
            InternalApiToken = 'NexusFleet-InternalApiToken'
        }
    }

    Docker    = @{
        # Installed by Install-NexusNode when Docker is missing: Ubuntu's own package, no extra apt repository.
        Package               = 'docker.io'
        # How long apt waits for another apt (unattended-upgrades on a fresh VM) to finish.
        AptLockTimeoutSeconds = 300
    }

    # The RabbitMQ broker as the nodes reach it (the agent connects to it). Only host and port: the full
    # RABBITMQ_URL contains credentials and is passed as a secret at install time.
    Broker    = @{
        Host = 'localhost'
        Port = 5672
    }

    Ssh       = @{
        # How long ssh waits for a connection.
        ConnectTimeoutSeconds = 10
        # Own known_hosts file, or '' for ssh's default (~/.ssh/known_hosts).
        KnownHostsFile        = ''
    }

    Preflight = @{
        # Test-NexusHost fails a host below this free space on / (Docker images and the agent need room).
        MinDiskFreeMB = 2048
        # Values of ID in /etc/os-release that NexusFleet supports.
        SupportedOs   = @('ubuntu')
        # How many hosts are checked at the same time.
        ThrottleLimit = 10
    }

    Install   = @{
        # How many hosts Install-NexusNode installs at the same time (each one downloads Docker and the agent image).
        ThrottleLimit = 5
    }

    Health    = @{
        # NexusInfra marks a node degraded after 3 s and offline after 10 s without a heartbeat.
        DegradedAfterSeconds = 3
        OfflineAfterSeconds  = 10
        # How long Install-NexusNode waits for a new node to become healthy, and how often it checks.
        VerifyTimeoutSeconds = 60
        PollIntervalSeconds  = 2
    }

    Log       = @{
        # The folder that holds one folder per run (<RunId>/), or '' for logs/ in the folder you run NexusFleet from.
        Directory = ''
        # How many run folders to keep; starting a run removes the oldest beyond this number. 0 keeps every run.
        KeepRuns  = 50
    }
}
