function Get-NexusFleetStatus {
    <#
    .SYNOPSIS
    Shows the status of every node: what NexusInfra reports, merged with what SSH sees on the hosts.

    .DESCRIPTION
    Asks NexusInfra once for all nodes (GET /nodes): health (healthy, degraded or offline, from the time of the last
    heartbeat), the last heartbeat, maintenance, CPU and RAM. When hosts come in from Import-NexusInventory, each host
    is also looked at over SSH, in parallel: is it reachable, which Docker version, the agent container's state and
    restart count, uptime and free disk space. Nothing is changed.

    Both sides together say why a node is not well. NexusInfra only sees that heartbeats stopped ("offline"); the
    host then says whether the agent container exited, is missing, or the host itself is unreachable.

    The result is one status per node: first the hosts of the inventory, in their order, then the nodes NexusInfra
    knows but the inventory does not. Ok says whether all is well; Problem says what is not, in plain words, e.g.
    "NexusInfra reports it offline; the agent container is exited". Maintenance is shown, but is not a problem.

    Nothing in this command stops the run: an unreachable host is reported in its status, and when NexusInfra itself
    cannot be asked, the hosts are still looked at (Health 'unknown') and a warning says why.

    .PARAMETER InputObject
    The hosts to look at over SSH: NexusFleet.Host objects from Import-NexusInventory, through the pipeline. Without
    hosts, only NexusInfra's view is shown.

    .PARAMETER ThrottleLimit
    How many hosts are looked at the same time (1-256). Default: Preflight.ThrottleLimit from the config. 1 looks at
    them one after the other.

    .EXAMPLE
    Get-NexusFleetStatus | Format-Table Name, Ok, Health, LastHeartbeat, Problem

    NexusInfra's view of all nodes, without SSH.

    .EXAMPLE
    Import-NexusInventory ./config/inventory.json | Get-NexusFleetStatus | Format-Table Name, Ok, Health, AgentState, Problem

    Every host of the inventory, with what NexusInfra and the host itself say.

    .EXAMPLE
    Import-NexusInventory ./config/inventory.json | Get-NexusFleetStatus | Where-Object { -not $_.Ok }

    Only the nodes that need attention.

    .EXAMPLE
    Import-NexusInventory ./config/inventory.json | Get-NexusFleetStatus | Export-NexusFleetStatus -Path ./status.csv

    Writes the status of the fleet to a CSV file.

    .INPUTS
    NexusFleet.Host
    The hosts from Import-NexusInventory (optional).

    .OUTPUTS
    NexusFleet.NodeStatus
    Name, Ok, Health, Problem, InInventory, Registered, Maintenance, LastHeartbeat (UTC, empty when the node never sent
    one), Location, AgentUrl, CpuPercent, RamUsedMb, RamTotalMb, and from the host: Address, Reachable, Docker,
    AgentState (running, exited, ... or missing), AgentRestarts, UptimeSeconds, DiskFreeMB.

    .NOTES
    Needs Connect-NexusInfra first (error NexusFleet.NotConnected otherwise); reading nodes needs no extra scope.
    Looking at hosts needs what Test-NexusHost needs (SSH with a key, sudo without a password for docker inspect).
    Each run is logged in logs/<RunId>/.

    .LINK
    https://github.com/Tombomeke-Studios/NexusFleet/blob/dev/docs/user-guide.md#get-nexusfleetstatus

    .LINK
    about_NexusFleet

    .LINK
    Export-NexusFleetStatus

    .LINK
    Install-NexusNode
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(ValueFromPipeline)]
        [PSTypeName('NexusFleet.Host')]
        [pscustomobject[]]$InputObject,

        [ValidateRange(1, 256)]
        [int]$ThrottleLimit
    )

    begin {
        $hosts = [System.Collections.Generic.List[object]]::new()
    }

    process {
        foreach ($item in $InputObject) {
            $hosts.Add($item)
        }
    }

    end {
        $session = Get-NexusSession
        $config = Get-NexusConfig
        if (-not $PSBoundParameters.ContainsKey('ThrottleLimit')) {
            $ThrottleLimit = $config.Preflight.ThrottleLimit
        }
        $run = Initialize-NexusRunContext -Secret ([System.Net.NetworkCredential]::new('', $session.Token).Password)
        Write-NexusLog -Context $run -Message "Fleet status: NexusInfra and $($hosts.Count) host(s)"

        # 1. NexusInfra's view. A failure here is reported, not fatal: the hosts can still be looked at.
        $nodes = @()
        $panelError = $null
        try {
            $api = Get-NexusApiParameter -Session $session
            $nodes = @(Invoke-NexusApi @api -Method GET -Path '/nodes')
        }
        catch {
            $panelError = $_.Exception.Message
            Write-Warning "NexusInfra could not be asked for the nodes; only the hosts are checked: $panelError"
            Write-NexusLog -Context $run -Level Warning -Message "GET /nodes failed: $panelError"
        }

        # 2. The hosts, over ssh, $ThrottleLimit at a time (see Invoke-NexusHostLoop); one status per host, always.
        $loop = @{
            InputObject     = @($hosts | ForEach-Object { @{ HostInfo = $_ } })
            FunctionName    = 'Get-NexusHostStatus'
            Parameter       = @{ Config = $config; RunContext = $run }
            FailureFunction = 'ConvertTo-NexusHostStatusFailure'
            ThrottleLimit   = $ThrottleLimit
            Activity        = 'NexusFleet status'
        }
        $seen = @(Invoke-NexusHostLoop @loop)

        # 3. One status per node: the inventory first, in its order, then the nodes only NexusInfra knows.
        $results = foreach ($hostInfo in $hosts) {
            $node = $nodes | Where-Object id -EQ $hostInfo.Name | Select-Object -First 1
            $hostStatus = $seen | Where-Object Host -EQ $hostInfo.Name | Select-Object -First 1
            ConvertTo-NexusNodeStatus -Name $hostInfo.Name -Node $node -HostInfo $hostInfo -HostStatus $hostStatus -PanelError $panelError
        }
        $results = @($results) + @(foreach ($node in $nodes | Where-Object { $_.id -notin $hosts.Name } | Sort-Object -Property id) {
                ConvertTo-NexusNodeStatus -Name $node.id -Node $node -HostInfo $null -HostStatus $null
            })

        $okCount = @($results | Where-Object Ok).Count
        Write-NexusLog -Context $run -Message "Fleet status: $okCount of $($results.Count) node(s) ok"
        foreach ($result in $results) {
            $result
        }
    }
}
