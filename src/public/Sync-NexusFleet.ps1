function Sync-NexusFleet {
    <#
    .SYNOPSIS
    Finds nodes that are no longer as the inventory wants them (drift), and repairs them.

    .DESCRIPTION
    The inventory and the config are the desired state: which hosts are nodes, under which name and location, how
    NexusInfra reaches them, and how the agent container must run. Nodes drift away from that over time: someone
    changes a label in the panel, an agent container is recreated by hand without its restart policy, a node is
    removed. Sync-NexusFleet compares the desired state with reality and brings the fleet back.

      1. Compare  every host gets the checks of the installation, without changing anything (the same as
                  Install-NexusNode -WhatIf). Every step that is not in order is one difference, in words.
      2. Report   one result per host, and one per node NexusInfra knows that is not in the inventory (Unmanaged).
      3. Repair   the hosts with differences are given to Install-NexusNode, which applies only the steps that are
                  not in order. You are asked per host, with its differences.

    -WhatIf stops after the report: nothing is changed, and no secrets are needed. -Confirm:$false repairs without
    asking.

    What Sync-NexusFleet never does: it does not remove an unmanaged node (use Remove-NexusNode for that, on purpose),
    and it cannot repair a host whose preflight fails (unreachable, no sudo); those are reported with an Error.

    .PARAMETER InputObject
    The desired hosts: NexusFleet.Host objects from Import-NexusInventory, usually through the pipeline.

    .PARAMETER RabbitMqUrl
    The broker URL for a repair that recreates an agent, as a SecureString. Default: the stored secret, as in
    Install-NexusNode. Not needed when nothing is repaired.

    .PARAMETER InternalApiToken
    NexusInfra's INTERNAL_API_TOKEN for a repair that recreates an agent, as a SecureString. Default: the stored
    secret, as in Install-NexusNode.

    .PARAMETER ThrottleLimit
    How many hosts are compared, and repaired, at the same time (1-256). Default: Install.ThrottleLimit.

    .EXAMPLE
    Import-NexusInventory ./config/inventory.json | Sync-NexusFleet -WhatIf | Format-Table Host, InSync, Differences

    Reports the drift of every node and changes nothing.

    .EXAMPLE
    Import-NexusInventory ./config/inventory.json | Sync-NexusFleet -Confirm:$false

    Repairs every node that drifted, without asking, and reports per host whether it was repaired.

    .EXAMPLE
    (Import-NexusInventory ./config/inventory.json | Sync-NexusFleet -WhatIf | Where-Object { -not $_.InSync }).Differences

    Shows only the differences, one line each.

    .INPUTS
    NexusFleet.Host
    The hosts from Import-NexusInventory.

    .OUTPUTS
    NexusFleet.SyncResult
    Host, InSync (was it as the inventory wants it), Differences (one line per difference), Repairable, Repaired,
    Success ($false when the comparison or the repair failed) and Error.

    .NOTES
    Needs Connect-NexusInfra first (error NexusFleet.NotConnected otherwise), with a token that has the scopes write
    and admin. A changed agent secret is not drift Sync-NexusFleet can see: the secrets are never read back from a
    host. Use Install-NexusNode -Force after changing one.
    Logs: logs/<RunId>/ for the comparison, and a second run folder for the repair by Install-NexusNode.

    .LINK
    https://github.com/Tombomeke-Studios/NexusFleet/blob/dev/docs/user-guide.md#sync-nexusfleet

    .LINK
    about_NexusFleet

    .LINK
    Install-NexusNode

    .LINK
    Get-NexusFleetStatus
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSTypeName('NexusFleet.Host')]
        [pscustomobject[]]$InputObject,

        [securestring]$RabbitMqUrl,

        [securestring]$InternalApiToken,

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
        $run = Initialize-NexusRunContext -LogRoot $config.Log.Directory -KeepRuns $config.Log.KeepRuns -Secret ([System.Net.NetworkCredential]::new('', $session.Token).Password)
        Write-NexusLog -Context $run -Message "Sync: compare $($hosts.Count) host(s) with the inventory, $ThrottleLimit at a time"

        # 1. Compare: the dry run of the installation for every host. Nothing is changed and no secrets are needed.
        $loop = @{
            InputObject     = @($hosts | ForEach-Object { @{ HostInfo = $_; PlanOnly = $true } })
            FunctionName    = 'Invoke-NexusHostInstall'
            Parameter       = @{ Config = $config; Session = $session; RunContext = $run }
            FailureFunction = 'ConvertTo-NexusInstallFailure'
            ThrottleLimit   = $ThrottleLimit
            Activity        = 'NexusFleet sync: compare'
        }
        $steps = @(Get-NexusStep)
        $results = @(Invoke-NexusHostLoop @loop | ForEach-Object { ConvertTo-NexusSyncResult -Plan $_ -Step $steps })

        # 2. Nodes NexusInfra knows that the inventory does not. A failure here is a warning: the hosts still count.
        $unmanaged = @()
        try {
            $api = Get-NexusApiParameter -Session $session
            $nodes = @(Invoke-NexusApi @api -Method GET -Path '/nodes')
            $unmanaged = @($nodes | Where-Object { $_.id -notin $hosts.Name } | ForEach-Object { ConvertTo-NexusSyncResult -Unmanaged $_.id })
        }
        catch {
            Write-Warning "NexusInfra could not be asked for the nodes, so unmanaged nodes are not reported: $($_.Exception.Message)"
        }

        # 3. Repair: asked per host, with its differences. ShouldProcess is $false under -WhatIf.
        $repair = @(
            foreach ($result in $results | Where-Object Repairable) {
                if ($PSCmdlet.ShouldProcess($result.Host, "Repair: $($result.Differences -join '; ')")) {
                    $hosts | Where-Object Name -EQ $result.Host
                }
            }
        )
        if ($repair.Count -gt 0) {
            Write-NexusLog -Context $run -Message "Sync: repair $($repair.Count) host(s) with Install-NexusNode"
            # Install-NexusNode applies only the steps that are not in order. Asked already, so it must not ask again.
            $install = @{ ThrottleLimit = $ThrottleLimit; Confirm = $false }
            if ($RabbitMqUrl) { $install.RabbitMqUrl = $RabbitMqUrl }
            if ($InternalApiToken) { $install.InternalApiToken = $InternalApiToken }
            $installed = @($repair | Install-NexusNode @install)

            foreach ($outcome in $installed) {
                $result = $results | Where-Object Host -EQ $outcome.Host
                $result.Repaired = $outcome.Success
                $result.Success = $outcome.Success
                $result.Error = $outcome.Error
            }
        }

        $drifted = @($results | Where-Object { -not $_.InSync }).Count
        $repaired = @($results | Where-Object Repaired).Count
        Write-NexusLog -Context $run -Message "Sync done: $drifted of $($hosts.Count) host(s) not in sync, $repaired repaired, $($unmanaged.Count) unmanaged node(s)"
        foreach ($result in $results + $unmanaged) {
            $result
        }
    }
}
