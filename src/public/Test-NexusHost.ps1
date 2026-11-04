function Test-NexusHost {
    <#
    .SYNOPSIS
    Checks in parallel whether hosts are ready to become NexusInfra nodes (preflight); changes nothing.

    .DESCRIPTION
    For every host from Import-NexusInventory, Test-NexusHost logs in over SSH and checks, in this order:

      Reachable  the host answers on its SSH port within Ssh.ConnectTimeoutSeconds
      SshAuth    the host accepts the key for the inventory's user
      OS         the operating system is supported (Preflight.SupportedOs, e.g. ubuntu)
      Sudo       the user may use sudo without a password (needed to install Docker and the agent)
      DiskSpace  at least Preflight.MinDiskFreeMB free on /
      Docker     Docker is installed; only a warning when it is not, because Install-NexusNode installs it
      Broker     the broker (Broker.Host:Broker.Port) can be reached from the host itself, as the agent will need it

    When the host cannot be reached or refuses the key, the other checks are not run. A host is ready (Success) when
    no check failed; Step names the first failed check and Error says why, in plain words.

    Hosts are checked at the same time, at most -ThrottleLimit at once. One host that fails or misbehaves never stops
    the others: every host gets its own result. With more than one host at a time the results appear as hosts
    finish, so the order can differ from the inventory; with -ThrottleLimit 1 they run one after the other, in order.
    Nothing on the hosts changes. Every check is logged per host in logs/<RunId>/<host>.log.

    .PARAMETER InputObject
    The hosts to check: NexusFleet.Host objects from Import-NexusInventory, usually through the pipeline.

    .PARAMETER ThrottleLimit
    How many hosts are checked at the same time (1-256). Default: Preflight.ThrottleLimit from the config.
    1 checks them one after the other, in the order of the inventory.

    .EXAMPLE
    Import-NexusInventory ./config/inventory.json | Test-NexusHost

    Checks all hosts and shows one result per host.

    .EXAMPLE
    Import-NexusInventory ./config/inventory.json | Test-NexusHost | Where-Object { -not $_.Success } | Format-Table Host, Step, Error

    Shows only the hosts that are not ready, with the first failed check and why.

    .EXAMPLE
    (Import-NexusInventory ./config/inventory.json | Test-NexusHost -ThrottleLimit 1)[0].Checks

    Checks the hosts one by one and shows every check of the first host.

    .INPUTS
    NexusFleet.Host
    The hosts from Import-NexusInventory.

    .OUTPUTS
    NexusFleet.PreflightResult
    Host, Address, Success, Step (the first failed check), Error, Checks (Name, Status Pass/Fail/Warning, Detail).

    .NOTES
    Needs the OpenSSH client (ssh) and a key the hosts accept; ssh never asks for a password (BatchMode). Does not
    need Connect-NexusInfra: it only talks to the hosts. A new host key is accepted and remembered once; a changed
    host key is refused (StrictHostKeyChecking=accept-new).

    .LINK
    https://github.com/Tombomeke-Studios/NexusFleet/blob/dev/docs/user-guide.md#test-nexushost

    .LINK
    about_NexusFleet

    .LINK
    Import-NexusInventory

    .LINK
    Install-NexusNode
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
