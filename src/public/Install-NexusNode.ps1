function Install-NexusNode {
    <#
    .SYNOPSIS
    Turns Linux hosts into healthy NexusInfra nodes, in parallel, idempotent, with rollback per host.

    .DESCRIPTION
    For every host from Import-NexusInventory:
      1. Preflight (the checks of Test-NexusHost). A host that is not ready is not touched.
      2. The installation steps, each only when its Test says it is needed:
           Docker          install Docker Engine (Ubuntu package) when it is missing
           RegisterNode    POST /nodes with id, name, location and agentUrl
           AgentContainer  the node agent container, with the restart policy, the port, the backups volume, the
                           Docker socket and the host-gateway mapping; secrets in an env file with mode 600
           VerifyHealthy   wait until NexusInfra reports the node healthy (Health.VerifyTimeoutSeconds)
    When a step fails, everything this run changed on that host is rolled back, in reverse order. What was already
    in order before the run is left alone. A second run on a finished host changes nothing (Changed = $false).

    Hosts run at the same time, at most -ThrottleLimit at once (default Install.ThrottleLimit). One failing host
    never stops the others: every host gets its own NexusFleet.InstallResult.

    -WhatIf is the dry run: per host only the checks run, and the result says per step AlreadyDone or WouldApply.
    Nothing on the hosts or in NexusInfra changes, and no secrets are needed. With -Confirm you are asked per host;
    a host you decline only gets the plan.

    Needs Connect-NexusInfra first. The agent's secrets come from the parameters, or else from SecretManagement
    (config Agent.SecretNames). They go to the hosts over the ssh stdin, never on a command line, and are redacted
    from the logs (logs/<RunId>/<host>.log and run.log).

    .PARAMETER InputObject
    The hosts: NexusFleet.Host objects from Import-NexusInventory, usually through the pipeline.

    .PARAMETER RabbitMqUrl
    The broker URL for the agents (amqp://user:password@broker:5672) as a SecureString. Default: the secret named
    in Agent.SecretNames.RabbitMqUrl.

    .PARAMETER InternalApiToken
    NexusInfra's INTERNAL_API_TOKEN (shared by the orchestrator and the agents) as a SecureString. Default: the
    secret named in Agent.SecretNames.InternalApiToken.

    .PARAMETER Force
    Recreate the agent container on every host, even when it looks in order. Needed after a change of RABBITMQ_URL
    or INTERNAL_API_TOKEN: the check never reads the secrets back from a host, so it cannot see that they changed.

    .PARAMETER ThrottleLimit
    How many hosts are installed at the same time. Default: Install.ThrottleLimit from the config. 1 = one after
    the other, in order.

    .EXAMPLE
    Import-NexusInventory ./config/inventory.json | Install-NexusNode -WhatIf

    Shows per host what would be done, and changes nothing.

    .EXAMPLE
    Import-NexusInventory ./config/inventory.json | Install-NexusNode | Format-Table Host, Success, Changed, Step, Error

    Installs every host and shows one line per host. Run it again: every host then reports Changed = False.

    .EXAMPLE
    Set-Secret -Name NexusFleet-RabbitMqUrl -Secret (Read-Host -AsSecureString 'RABBITMQ_URL')
    Set-Secret -Name NexusFleet-InternalApiToken -Secret (Read-Host -AsSecureString 'INTERNAL_API_TOKEN')

    Stores the agent's secrets once, so Install-NexusNode finds them without parameters.

    .EXAMPLE
    (Import-NexusInventory ./config/inventory.json | Install-NexusNode -ThrottleLimit 1 | Where-Object Host -EQ 'node-home01').Steps

    Installs the hosts one by one and shows what happened in every step of one host.

    .EXAMPLE
    Import-NexusInventory ./config/inventory.json | Install-NexusNode -Force

    After changing the broker password: recreates the agent on every host with the new secrets.

    .OUTPUTS
    NexusFleet.InstallResult: Host, Success, PlanOnly, Changed, Step (where it failed), Error, Steps (Step, Outcome,
    Rollback, Error), Preflight.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSTypeName('NexusFleet.Host')]
        [pscustomobject[]]$InputObject,

        [securestring]$RabbitMqUrl,

        [securestring]$InternalApiToken,

        [switch]$Force,

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
            [pscustomobject]@{
                HostInfo = $hostInfo
                PlanOnly = -not $PSCmdlet.ShouldProcess($hostInfo.Name, 'Turn into a NexusInfra node (Docker, register, agent, verify healthy)')
            }
        }

        # The agent's secrets, only when something will really be installed (a dry run needs none).
        $secrets = $null
        if (@($work | Where-Object { -not $_.PlanOnly }).Count -gt 0) {
            $names = $config.Agent.SecretNames
            if (-not $RabbitMqUrl) {
                $RabbitMqUrl = Get-NexusStoredToken -SecretName $names.RabbitMqUrl -Label 'RABBITMQ_URL' `
                    -StoreHint "Set-Secret -Name $($names.RabbitMqUrl) -Secret (Read-Host -AsSecureString 'RABBITMQ_URL'), or pass -RabbitMqUrl"
            }
            if (-not $InternalApiToken) {
                $InternalApiToken = Get-NexusStoredToken -SecretName $names.InternalApiToken -Label 'INTERNAL_API_TOKEN' `
                    -StoreHint "Set-Secret -Name $($names.InternalApiToken) -Secret (Read-Host -AsSecureString 'INTERNAL_API_TOKEN'), or pass -InternalApiToken"
            }
            $secrets = @{ RabbitMqUrl = $RabbitMqUrl; InternalApiToken = $InternalApiToken }
        }

        # Every secret of this run is redacted from its logs.
        $plain = foreach ($secure in $session.Token, $RabbitMqUrl, $InternalApiToken) {
            if ($secure) { [System.Net.NetworkCredential]::new('', $secure).Password }
        }
        $run = Initialize-NexusRunContext -Secret $plain
        $planCount = @($work | Where-Object PlanOnly).Count
        Write-NexusLog -Context $run -Message ("Install on $($hosts.Count) host(s), $ThrottleLimit at a time" +
            $(if ($planCount) { "; $planCount host(s) plan only" } else { '' }))

        # Progress bar, updated for every finished host (also while the parallel loop is still running).
        $done = 0
        $showProgress = {
            process {
                $done++
                Write-Progress -Activity 'NexusFleet install' -Status "$done of $($hosts.Count) hosts done" `
                    -PercentComplete ([math]::Floor(100 * $done / [math]::Max(1, $hosts.Count)))
                $_
            }
        }

        if ($ThrottleLimit -eq 1) {
            # One after the other, in this runspace.
            $results = foreach ($item in $work) {
                try {
                    Invoke-NexusHostInstall -HostInfo $item.HostInfo -Config $config -Session $session -Secrets $secrets `
                        -PlanOnly:$item.PlanOnly -Force:$Force -RunContext $run
                }
                catch {
                    ConvertTo-NexusInstallFailure -HostInfo $item.HostInfo -Message $_.Exception.Message -PlanOnly:$item.PlanOnly
                }
            }
            $results = $results | & $showProgress
        }
        else {
            # Each runspace starts empty: import the module by path (that also registers the steps there) and run the
            # internal per-host function in the module's scope. Everything else comes in with $using:.
            $manifest = Join-Path -Path $PSScriptRoot -ChildPath '../../NexusFleet.psd1'
            $results = $work | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
                $module = Import-Module -Name $using:manifest -PassThru
                & $module {
                    param($Item, $Config, $Session, $Secrets, $Run, $Force)
                    try {
                        Invoke-NexusHostInstall -HostInfo $Item.HostInfo -Config $Config -Session $Session -Secrets $Secrets `
                            -PlanOnly:$Item.PlanOnly -Force:$Force -RunContext $Run
                    }
                    catch {
                        ConvertTo-NexusInstallFailure -HostInfo $Item.HostInfo -Message $_.Exception.Message -PlanOnly:$Item.PlanOnly
                    }
                } $_ $using:config $using:session $using:secrets $using:run ([bool]$using:Force)
            } | & $showProgress
        }
        Write-Progress -Activity 'NexusFleet install' -Completed

        $succeeded = @($results | Where-Object Success).Count
        $changed = @($results | Where-Object Changed).Count
        Write-NexusLog -Context $run -Message "Install done: $succeeded of $($hosts.Count) host(s) succeeded, $changed changed"
        foreach ($result in $results) {
            $result
        }
    }
}
