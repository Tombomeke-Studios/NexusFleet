# Step 20: the node record in NexusInfra (POST /nodes). Before the agent, so the first heartbeat already finds the
# node with its name and location. The record alone is not a node: it stays offline until the agent sends heartbeats.
Register-NexusStep -Name 'RegisterNode' -Order 20 -Description 'Node registered in NexusInfra (POST /nodes)' -Test {
    param($Context)
    $hostInfo = $Context.HostInfo
    $node = @(Invoke-NexusStepApi -Context $Context -Method GET -Path '/nodes') | Where-Object id -EQ $hostInfo.Name
    # Remembered for Rollback: only a record this run created may be deleted.
    $Context.State.NodeExisted = [bool]$node
    [bool]$node -and $node.name -eq $hostInfo.Name -and $node.location -eq $hostInfo.Location -and $node.agentUrl -eq $hostInfo.AgentUrl
} -Apply {
    param($Context)
    $hostInfo = $Context.HostInfo
    # POST /nodes creates the record, or updates the labels of an existing one.
    $body = @{ id = $hostInfo.Name; name = $hostInfo.Name; location = $hostInfo.Location; agentUrl = $hostInfo.AgentUrl }
    $null = Invoke-NexusStepApi -Context $Context -Method POST -Path '/nodes' -Body $body
} -Rollback {
    param($Context)
    if (-not $Context.State.NodeExisted) {
        $null = Invoke-NexusStepApi -Context $Context -Method DELETE -Path "/nodes/$($Context.HostInfo.Name)"
    }
}
