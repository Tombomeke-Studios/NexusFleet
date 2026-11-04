function ConvertTo-NexusNodeStatus {
    <#
    .SYNOPSIS
    Merges what NexusInfra knows about a node with what ssh saw on its host, into one NexusFleet.NodeStatus.

    .DESCRIPTION
    Every part is optional, because a node can be in NexusInfra without being in the inventory, a host can be in the
    inventory without being registered, and a host is only looked at when Get-NexusFleetStatus checks hosts.
    Ok is $true when nothing is wrong; Problem lists what is, in plain words:
      - not registered in NexusInfra
      - NexusInfra reports it degraded / offline
      - the host cannot be reached
      - the agent container is missing or not running
    Maintenance is shown but is not a problem: it is a choice.

    .PARAMETER Name
    The node id (= the host name in the inventory).

    .PARAMETER Node
    The node record from GET /nodes, or $null when NexusInfra does not know the node.

    .PARAMETER HostInfo
    The host from the inventory, or $null when the node is not in the inventory.

    .PARAMETER HostStatus
    What Get-NexusHostStatus saw, or $null when the host was not checked.

    .PARAMETER PanelError
    Set when GET /nodes failed: then nothing is known about registration and health.

    .EXAMPLE
    ConvertTo-NexusNodeStatus -Name 'node-web01' -Node $record -HostInfo $host -HostStatus $seen
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [AllowNull()]
        [object]$Node,

        [AllowNull()]
        [object]$HostInfo,

        [AllowNull()]
        [object]$HostStatus,

        [string]$PanelError
    )

    $problems = [System.Collections.Generic.List[string]]::new()

    if ($PanelError) {
        $health = 'unknown'
        $problems.Add("NexusInfra could not be asked: $PanelError")
    }
    elseif (-not $Node) {
        $health = 'not registered'
        $problems.Add('not registered in NexusInfra')
    }
    else {
        $health = $Node.health
        if ($health -ne 'healthy') {
            $problems.Add("NexusInfra reports it $health")
        }
        # An outbound node is only controllable while its agent link is up (docs/agent-link.md).
        if ($Node.connection -eq 'outbound' -and -not $Node.linked) {
            $problems.Add('its agent link is down: NexusInfra hears its heartbeats but cannot send it anything')
        }
    }

    # How NexusInfra reaches the agent. NexusInfra 0.4.0 says nothing, and then it is direct.
    $connection = if ($Node -and $Node.connection) { $Node.connection } elseif ($HostInfo -and $HostInfo.Reach) { $HostInfo.Reach } else { 'direct' }

    if ($HostStatus) {
        if (-not $HostStatus.Reachable) {
            $problems.Add($HostStatus.Error)
        }
        elseif ($HostStatus.AgentState -ne 'running') {
            $problems.Add("the agent container is $($HostStatus.AgentState)")
        }
    }

    # A node that never sent a heartbeat has lastHeartbeat 1970-01-01: that is "never", not a time.
    $lastHeartbeat = $null
    # Invoke-RestMethod already turns an ISO-8601 text into a [datetime]; a mock or another source may give the text.
    if ($Node -and $Node.lastHeartbeat) {
        $parsed = if ($Node.lastHeartbeat -is [datetime]) {
            $Node.lastHeartbeat.ToUniversalTime()
        }
        else {
            [datetime]::Parse("$($Node.lastHeartbeat)", [cultureinfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal)
        }
        if ($parsed.Year -gt 1970) { $lastHeartbeat = $parsed }
    }

    [pscustomobject]@{
        PSTypeName    = 'NexusFleet.NodeStatus'
        Name          = $Name
        Ok            = $problems.Count -eq 0
        Health        = $health
        Problem       = $problems -join '; '
        InInventory   = [bool]$HostInfo
        Registered    = if ($PanelError) { $null } else { [bool]$Node }
        Maintenance   = if ($Node) { [bool]$Node.maintenance } else { $null }
        LastHeartbeat = $lastHeartbeat
        Location      = if ($Node -and $Node.location) { $Node.location } elseif ($HostInfo) { $HostInfo.Location } else { $null }
        Connection    = $connection
        Linked        = if ($connection -eq 'outbound' -and $Node) { [bool]$Node.linked } else { $null }
        AgentUrl      = if ($Node -and $Node.agentUrl) { $Node.agentUrl } elseif ($HostInfo) { $HostInfo.AgentUrl } else { $null }
        CpuPercent    = if ($Node) { $Node.cpuPercent } else { $null }
        RamUsedMb     = if ($Node) { $Node.ramUsedMb } else { $null }
        RamTotalMb    = if ($Node) { $Node.ramTotalMb } else { $null }
        Address       = if ($HostInfo) { $HostInfo.Address } else { $null }
        Reachable     = if ($HostStatus) { $HostStatus.Reachable } else { $null }
        Docker        = if ($HostStatus) { $HostStatus.Docker } else { $null }
        AgentState    = if ($HostStatus) { $HostStatus.AgentState } else { $null }
        AgentRestarts = if ($HostStatus) { $HostStatus.AgentRestarts } else { $null }
        UptimeSeconds = if ($HostStatus) { $HostStatus.UptimeSeconds } else { $null }
        DiskFreeMB    = if ($HostStatus) { $HostStatus.DiskFreeMB } else { $null }
    }
}
