# Step 40: the proof. A node exists only once its agent sends heartbeats; NexusInfra then reports it healthy.
Register-NexusStep -Name 'VerifyHealthy' -Order 40 -Description 'Node reported healthy by NexusInfra' -Test {
    param($Context)
    $node = @(Invoke-NexusStepApi -Context $Context -Method GET -Path '/nodes') | Where-Object id -EQ $Context.HostInfo.Name
    [bool]$node -and $node.health -eq 'healthy'
} -Apply {
    param($Context)
    # Nothing to change here: wait until the heartbeats arrive. A count of attempts instead of a clock, so the
    # wait is easy to follow (and to test): time-out / interval attempts, with a pause between them.
    $health = $Context.Config.Health
    $attempts = [math]::Max(1, [math]::Ceiling($health.VerifyTimeoutSeconds / $health.PollIntervalSeconds))
    $last = 'not registered'
    for ($attempt = 1; $attempt -le $attempts; $attempt++) {
        $node = @(Invoke-NexusStepApi -Context $Context -Method GET -Path '/nodes') | Where-Object id -EQ $Context.HostInfo.Name
        if ($node) {
            $last = $node.health
        }
        if ($last -eq 'healthy') {
            return
        }
        if ($attempt -lt $attempts) {
            Start-Sleep -Seconds $health.PollIntervalSeconds
        }
    }
    throw "node $($Context.HostInfo.Name) did not become healthy within $($health.VerifyTimeoutSeconds) s (last health: $last). " +
    'Does the agent reach the broker, and is the RABBITMQ_URL right? See: sudo docker logs ' + $Context.Config.Agent.ContainerName
}
