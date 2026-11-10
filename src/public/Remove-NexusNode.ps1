function Remove-NexusNode {
    <#
    .SYNOPSIS
    Removes NexusInfra nodes: deregisters each node and removes the agent from its host.

    .DESCRIPTION
    The opposite of Install-NexusNode. For every host from Import-NexusInventory:

      1. Host   looks on the host whether the agent container and its env file are there
      2. Node   deregisters the node in NexusInfra (DELETE /nodes/<name>)
      3. Agent  removes the agent container and its env file (it holds the agent's secrets) from the host

    NexusInfra refuses to deregister a node that still hosts a running server. That host is then not touched at all:
    its result says so, and nothing was changed. Stop or move its servers first (Invoke-NexusFleetAction).

    Only what is there is removed, so a second run changes nothing (Changed = $false). Docker itself and the backups
    volume stay on the host: Docker may have been there before NexusFleet, and the volume holds backups.

    Hosts run at the same time, at most -ThrottleLimit at once. One failing host never stops the others: every host
    gets its own result.

    Removing is asked per host (ConfirmImpact High); -Confirm:$false removes without asking. -WhatIf is the dry run:
    per host it reports what would be removed (WouldRemove) and changes nothing. A dry run cannot tell whether
    NexusInfra would refuse the node.

    .PARAMETER InputObject
    The hosts to remove: NexusFleet.Host objects from Import-NexusInventory, usually through the pipeline.

    .PARAMETER IgnoreUnreachableHost
    Deregister a node even when its host cannot be reached over ssh, for a machine that is gone. Without it an
    unreachable host fails and its node stays registered.

    .PARAMETER ThrottleLimit
    How many hosts are removed at the same time (1-256). Default: Install.ThrottleLimit from the config.

    .EXAMPLE
    Import-NexusInventory ./config/inventory.json | Remove-NexusNode -WhatIf

    Shows per host what would be removed, and changes nothing.

    .EXAMPLE
    Import-NexusInventory ./config/inventory.json | Where-Object Name -EQ 'node-home01' | Remove-NexusNode -Confirm:$false

    Removes one node without asking: the node record in NexusInfra, and the agent on the host.

    .EXAMPLE
    Import-NexusInventory ./config/inventory.json | Where-Object Name -EQ 'node-old' | Remove-NexusNode -IgnoreUnreachableHost

    Deregisters a node whose machine no longer exists.

    .INPUTS
    NexusFleet.Host
    The hosts from Import-NexusInventory.

    .OUTPUTS
    NexusFleet.RemoveResult
    Host, Success, PlanOnly (a -WhatIf result), Changed (did this run change anything), Step (where it failed: Host,
    Node or Agent), Error, Node and Agent (Absent, Present, Removed, WouldRemove, or Unknown).

    .NOTES
    Needs Connect-NexusInfra first (error NexusFleet.NotConnected otherwise), with a token that has the scopes write
    and admin. Logs: logs/<RunId>/<host>.log per host and run.log for the run.

    .LINK
    https://github.com/Tombomeke-Studios/NexusFleet/blob/dev/docs/user-guide.md#remove-nexusnode

    .LINK
    about_NexusFleet

    .LINK
    Install-NexusNode

    .LINK
    Invoke-NexusFleetAction
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSTypeName('NexusFleet.Host')]
        [pscustomobject[]]$InputObject,

        [switch]$IgnoreUnreachableHost,

        [ValidateRange(1, 256)]
        [int]$ThrottleLimit
    )

    begin {
        $hosts = [System.Collections.Generic.List[object]]::new()
    }

    process {
        # Only collect here; the parallel work starts in end, when all hosts are known.
        foreach ($item in $InputObject) {
            $hosts.Add($item)
        }
    }

    end {
        $session = Get-NexusSession
        $config = Get-NexusConfig
        if (-not $PSBoundParameters.ContainsKey('ThrottleLimit')) {
            $ThrottleLimit = $config.Install.ThrottleLimit
        }

        # ShouldProcess does not work inside -Parallel, so -WhatIf / -Confirm are decided here, per host.
        $work = foreach ($hostInfo in $hosts) {
            @{
                HostInfo = $hostInfo
                PlanOnly = -not $PSCmdlet.ShouldProcess($hostInfo.Name, 'Remove the NexusInfra node (deregister, remove the agent)')
            }
        }

        $token = [System.Net.NetworkCredential]::new('', $session.Token).Password
        $run = Initialize-NexusRunContext -LogRoot $config.Log.Directory -KeepRuns $config.Log.KeepRuns -Secret $token
        Write-NexusLog -Context $run -Message "Remove $($hosts.Count) node(s), $ThrottleLimit at a time"

        # Every host on its own, $ThrottleLimit at a time (see Invoke-NexusHostLoop); one result per host, always.
        $loop = @{
            InputObject     = @($work)
            FunctionName    = 'Invoke-NexusHostRemoval'
            Parameter       = @{ Config = $config; Session = $session; IgnoreUnreachableHost = [bool]$IgnoreUnreachableHost; RunContext = $run }
            FailureFunction = 'ConvertTo-NexusRemoveFailure'
            ThrottleLimit   = $ThrottleLimit
            Activity        = 'NexusFleet remove'
        }
        $results = @(Invoke-NexusHostLoop @loop)

        $succeeded = @($results | Where-Object Success).Count
        $changed = @($results | Where-Object Changed).Count
        Write-NexusLog -Context $run -Message "Remove done: $succeeded of $($hosts.Count) host(s) succeeded, $changed changed"
        foreach ($result in $results) {
            $result
        }
    }
}
