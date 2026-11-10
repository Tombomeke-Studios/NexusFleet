# Step 40: the proof. A node exists only once its agent sends heartbeats; NexusInfra then reports it healthy.
# When this run (re)started the agent, "healthy" may still come from the old agent's last heartbeat (it counts for
# Health.DegradedAfterSeconds). Then the Test is never "already in order", and Apply first waits that long.
Register-NexusStep -Name 'VerifyHealthy' -Order 40 -Description 'Node reported healthy by NexusInfra' -Test {
    param($Context)
    if ($Context.State.AgentStarted) {
        return $false
    }
    $node = @(Invoke-NexusStepApi -Context $Context -Method GET -Path '/nodes') | Where-Object id -EQ $Context.HostInfo.Name
    $healthy = [bool]$node -and $node.health -eq 'healthy'
    if (-not $healthy) {
        $Context.State.Detail = if ($node) { "NexusInfra reports the node $($node.health)" } else { 'the node is not registered' }
    }
    $healthy
} -Apply {
    param($Context)
    # Nothing to change here: wait until the heartbeats arrive. A count of attempts instead of a clock, so the
    # wait is easy to follow (and to test): time-out / interval attempts, with a pause between them.
    $health = $Context.Config.Health
    if ($Context.State.AgentStarted) {
        Start-Sleep -Seconds $health.DegradedAfterSeconds
    }
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
