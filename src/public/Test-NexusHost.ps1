function Test-NexusHost {
    <#
    .SYNOPSIS
    Checks in parallel whether hosts are ready to become NexusInfra nodes (preflight). Changes nothing.

    .DESCRIPTION
    For every host from Import-NexusInventory, checks over ssh: Reachable, SshAuth, OS (supported list in the
    config), Sudo (without a password), DiskSpace (Preflight.MinDiskFreeMB), Docker (only a warning when missing:
    Install-NexusNode installs it) and Broker (Broker.Host:Port reachable from the host).

    Hosts are checked at the same time, at most -ThrottleLimit at once (default Preflight.ThrottleLimit). One host
    that fails or misbehaves never stops the others: every host gets its own NexusFleet.PreflightResult. Results
    appear as hosts finish, so with more than one at a time the order can differ from the inventory; with
    -ThrottleLimit 1 the hosts run one after the other, in order (useful when looking for a problem).

    Every check is logged per host in logs/<RunId>/<host>.log, the summary in run.log.

    .PARAMETER InputObject
    The hosts: NexusFleet.Host objects from Import-NexusInventory, usually through the pipeline.

    .PARAMETER ThrottleLimit
    How many hosts are checked at the same time. Default: Preflight.ThrottleLimit from the config. 1 = one after
    the other.

    .EXAMPLE
    Import-NexusInventory ./config/inventory.json | Test-NexusHost

    Checks all hosts and shows one result per host.

    .EXAMPLE
    Import-NexusInventory ./config/inventory.json | Test-NexusHost | Where-Object { -not $_.Success } | Format-Table Host, Step, Error

    Shows only the hosts that are not ready, with the first failed check and why.

    .EXAMPLE
    (Import-NexusInventory ./config/inventory.json | Test-NexusHost -ThrottleLimit 1)[0].Checks

    Checks the hosts one by one and shows every check of the first host.

    .OUTPUTS
    NexusFleet.PreflightResult: Host, Address, Success, Step (first failed check), Error, Checks (Name, Status, Detail).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSTypeName('NexusFleet.Host')]
        [pscustomobject[]]$InputObject,

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
        $config = Get-NexusConfig
        if (-not $PSBoundParameters.ContainsKey('ThrottleLimit')) {
            $ThrottleLimit = $config.Preflight.ThrottleLimit
        }
        $run = Initialize-NexusRunContext
        Write-NexusLog -Context $run -Message "Preflight of $($hosts.Count) host(s), $ThrottleLimit at a time"

        # Progress bar, updated for every finished host (also while the parallel loop is still running).
        $done = 0
        $showProgress = {
            process {
                $done++
                Write-Progress -Activity 'NexusFleet preflight' -Status "$done of $($hosts.Count) hosts checked" `
                    -PercentComplete ([math]::Floor(100 * $done / [math]::Max(1, $hosts.Count)))
                $_
            }
        }

        if ($ThrottleLimit -eq 1) {
            # One after the other, in this runspace.
            $results = foreach ($hostInfo in $hosts) {
                try {
                    Invoke-NexusHostPreflight -HostInfo $hostInfo -Config $config -RunContext $run
                }
                catch {
                    ConvertTo-NexusPreflightFailure -HostInfo $hostInfo -Message $_.Exception.Message
                }
            }
            $results = $results | & $showProgress
        }
        else {
            # Each runspace starts empty: import the module by path and run the internal per-host function in the
            # module's scope (& $module { }). Config and run context come in with $using:.
            $manifest = Join-Path -Path $PSScriptRoot -ChildPath '../../NexusFleet.psd1'
            $results = $hosts | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
                $module = Import-Module -Name $using:manifest -PassThru
                & $module {
                    param($HostInfo, $Config, $Run)
                    try {
                        Invoke-NexusHostPreflight -HostInfo $HostInfo -Config $Config -RunContext $Run
                    }
                    catch {
                        ConvertTo-NexusPreflightFailure -HostInfo $HostInfo -Message $_.Exception.Message
                    }
                } $_ $using:config $using:run
            } | & $showProgress
        }
        Write-Progress -Activity 'NexusFleet preflight' -Completed

        $ready = @($results | Where-Object Success).Count
        Write-NexusLog -Context $run -Message "Preflight done: $ready of $($hosts.Count) host(s) ready"
        foreach ($result in $results) {
            $result
        }
    }
}
