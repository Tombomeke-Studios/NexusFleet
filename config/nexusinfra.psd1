# Every NexusInfra-specific value NexusFleet uses. Nothing here is secret.
# Override any value for your own setup in config/nexusinfra.local.psd1 (git-ignored): that file only
# needs the keys you change, with the same structure, e.g. @{ Api = @{ BaseUrl = 'https://panel.example.com' } }
# Values verified against NexusInfra docs/images.md ("Adding a machine") at nexusfleet-baseline (v0.4.0).
@{
    Api    = @{
        # The gateway (port 9400) fronts the orchestrator and passes nxi_ tokens through.
        BaseUrl              = 'http://localhost:9400'
        TimeoutSeconds       = 30
        # Extra attempts for GET requests and network errors only; changing requests are never retried.
        RetryCount           = 2
        # The API token is only sent over plain http:// to this machine (localhost). Set to $true in your
        # local file only when the panel runs without TLS on a trusted network.
        AllowUnencryptedHttp = $false
    }

    Agent  = @{
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
        # Names of the environment variables the agent reads.
        EnvNames        = @{
            NodeId           = 'NODE_ID'
            RabbitMqUrl      = 'RABBITMQ_URL'
            InternalApiToken = 'INTERNAL_API_TOKEN'
            AgentUrl         = 'AGENT_URL'
        }
    }

    Health = @{
        # NexusInfra marks a node degraded after 3 s and offline after 10 s without a heartbeat.
        DegradedAfterSeconds = 3
        OfflineAfterSeconds  = 10
        # How long Install-NexusNode waits for a new node to become healthy, and how often it checks.
        VerifyTimeoutSeconds = 60
        PollIntervalSeconds  = 2
    }
}
