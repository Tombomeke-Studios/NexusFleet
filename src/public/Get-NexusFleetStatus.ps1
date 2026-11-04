function Get-NexusFleetStatus {
    <#
    .SYNOPSIS
    Shows the status of every node: what NexusInfra reports, merged with what ssh sees on the hosts.

    .DESCRIPTION
    Asks NexusInfra once for all nodes (GET /nodes: health, last heartbeat, maintenance, CPU and RAM). When hosts
    come in from Import-NexusInventory, each host is also looked at over ssh, in parallel (at most -ThrottleLimit at
    once): reachable, Docker, the agent container's state and restarts, uptime and free disk. Nothing is changed.

    One NexusFleet.NodeStatus per node, first the hosts of the inventory in their order, then nodes NexusInfra knows
    but the inventory does not. Ok says whether all is well; Problem says what is not, in plain words. A host that
    cannot be reached is reported as such, and when NexusInfra itself cannot be asked, the hosts are still checked
    (Health 'unknown', and a warning): nothing in this command stops the run.

    Needs Connect-NexusInfra first. Each run is logged in logs/<RunId>/. Export the result with Export-NexusFleetStatus.

    .PARAMETER InputObject
    The hosts to look at over ssh: NexusFleet.Host objects from Import-NexusInventory, through the pipeline. Without
    hosts only NexusInfra's view is shown.

    .PARAMETER ThrottleLimit
    How many hosts are looked at the same time. Default: Preflight.ThrottleLimit from the config. 1 = one after the
    other.

    .EXAMPLE
    Get-NexusFleetStatus | Format-Table Name, Ok, Health, LastHeartbeat, Problem

    NexusInfra's view of all nodes, without ssh.

    .EXAMPLE
    Import-NexusInventory ./config/inventory.json | Get-NexusFleetStatus | Format-Table Name, Ok, Health, AgentState, Problem

    Every host of the inventory, with what NexusInfra and the host itself say.

    .EXAMPLE
    Import-NexusInventory ./config/inventory.json | Get-NexusFleetStatus | Where-Object { -not $_.Ok }

    Only the nodes that need attention.

    .EXAMPLE
    Import-NexusInventory ./config/inventory.json | Get-NexusFleetStatus | Export-NexusFleetStatus -Path ./status.csv

    Writes the status of the fleet to a CSV file.

    .OUTPUTS
    NexusFleet.NodeStatus: Name, Ok, Health, Problem, InInventory, Registered, Maintenance, LastHeartbeat, Location,
    AgentUrl, CpuPercent, RamUsedMb, RamTotalMb, Address, Reachable, Docker, AgentState, AgentRestarts, UptimeSeconds,
    DiskFreeMB.
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
            $api = @{
                BaseUrl              = $session.BaseUrl
                Token                = $session.Token
                TimeoutSeconds       = $session.TimeoutSeconds
                RetryCount           = $session.RetryCount
                AllowUnencryptedHttp = [bool]$session.AllowUnencryptedHttp
            }
            $nodes = @(Invoke-NexusApi @api -Method GET -Path '/nodes')
        }
        catch {
            $panelError = $_.Exception.Message
            Write-Warning "NexusInfra could not be asked for the nodes; only the hosts are checked: $panelError"
            Write-NexusLog -Context $run -Level Warning -Message "GET /nodes failed: $panelError"
        }

        # 2. The hosts, over ssh (same pattern as Test-NexusHost).
        $done = 0
        $showProgress = {
            process {
                $done++
                Write-Progress -Activity 'NexusFleet status' -Status "$done of $($hosts.Count) hosts checked" `
                    -PercentComplete ([math]::Floor(100 * $done / [math]::Max(1, $hosts.Count)))
                $_
            }
        }
        $seen = @()
        if ($hosts.Count -gt 0 -and $ThrottleLimit -eq 1) {
            $seen = @($hosts | ForEach-Object { Get-NexusHostStatus -HostInfo $_ -Config $config -RunContext $run } | & $showProgress)
        }
        elseif ($hosts.Count -gt 0) {
            $manifest = Join-Path -Path $PSScriptRoot -ChildPath '../../NexusFleet.psd1'
            $seen = @($hosts | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
                    $module = Import-Module -Name $using:manifest -PassThru
                    & $module {
                        param($HostInfo, $Config, $Run)
                        Get-NexusHostStatus -HostInfo $HostInfo -Config $Config -RunContext $Run
                    } $_ $using:config $using:run
                } | & $showProgress)
        }
        Write-Progress -Activity 'NexusFleet status' -Completed

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
