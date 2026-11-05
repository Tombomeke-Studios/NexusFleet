# Step 20: the node record in NexusInfra (POST /nodes). Before the agent, so the first heartbeat already finds the
# node with its name and location. The record alone is not a node: it stays offline until the agent sends heartbeats.
# A host with reach "outbound" is registered with connection "outbound" and no agentUrl: its agent connects to the
# control plane itself (docs/agent-link.md). A direct host is registered with connection "direct", so a host that was outbound is switched back (#113).
Register-NexusStep -Name 'RegisterNode' -Order 20 -Description 'Node registered in NexusInfra (POST /nodes)' -Test {
    param($Context)
    $hostInfo = $Context.HostInfo
    $node = @(Invoke-NexusStepApi -Context $Context -Method GET -Path '/nodes') | Where-Object id -EQ $hostInfo.Name
    # Remembered for Rollback: only a record this run created may be deleted.
    $Context.State.NodeExisted = [bool]$node
    $sameLabels = [bool]$node -and $node.name -eq $hostInfo.Name -and $node.location -eq $hostInfo.Location
    if ($hostInfo.Reach -eq 'outbound') {
        $sameLabels -and $node.connection -eq 'outbound'
    }
    else {
        # NexusInfra 0.4.0 reports no connection at all: that is direct.
        $sameLabels -and $node.agentUrl -eq $hostInfo.AgentUrl -and $node.connection -ne 'outbound'
    }
} -Apply {
    param($Context)
    $hostInfo = $Context.HostInfo
    # POST /nodes creates the record, or updates the labels of an existing one.
    $body = @{ id = $hostInfo.Name; name = $hostInfo.Name; location = $hostInfo.Location }
    if ($hostInfo.Reach -eq 'outbound') {
        $body.connection = 'outbound'
    }
    else {
        # Said out loud: NexusInfra keeps an existing node outbound when the body names no connection (and then
        # ignores the agentUrl). NexusInfra 0.4.0 does not know the field and ignores it.
        $body.connection = 'direct'
        $body.agentUrl = $hostInfo.AgentUrl
    }
    $null = Invoke-NexusStepApi -Context $Context -Method POST -Path '/nodes' -Body $body
} -Rollback {
    param($Context)
    if (-not $Context.State.NodeExisted) {
        $null = Invoke-NexusStepApi -Context $Context -Method DELETE -Path "/nodes/$($Context.HostInfo.Name)"
    }
}
