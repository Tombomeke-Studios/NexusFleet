# Step 50: NexusInfra can control the node, not only see it.
# "Healthy" (step 40) says the heartbeats arrive: the node calls the broker. Deploying, files, the console and
# backups go the other way: the orchestrator calls the agent at the node's agentUrl, with the INTERNAL_API_TOKEN.
# A closed or unforwarded port, or a different token, leaves a node that is healthy but cannot run anything.
# GET /nodes/<id>/disk is the smallest NexusInfra call that makes that trip: it only reads, it is for platform
# administrators, and NexusInfra answers 502 when the agent cannot be reached or refuses the token.
Register-NexusStep -Name 'AgentReachable' -Order 50 -Description 'NexusInfra reaches the agent' -Test {
    param($Context)
    try {
        $null = Invoke-NexusStepApi -Context $Context -Method GET -Path "/nodes/$($Context.HostInfo.Name)/disk"
        $true
    }
    catch {
        $false
    }
} -Apply {
    param($Context)
    # Nothing to change here: check once more, and when it still fails, say what to look at.
    try {
        $null = Invoke-NexusStepApi -Context $Context -Method GET -Path "/nodes/$($Context.HostInfo.Name)/disk"
    }
    catch {
        $caught = $_
        throw "NexusInfra cannot reach the agent of $($Context.HostInfo.Name) at $($Context.HostInfo.AgentUrl): " +
        "$($caught.Exception.Message) Can the control plane open port $($Context.Config.Agent.Port) on this host " +
        '(firewall, port forwarding, the agentUrl in the inventory), and is the INTERNAL_API_TOKEN the same as in its .env?'
    }
}
