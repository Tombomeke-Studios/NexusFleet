function Invoke-NexusHostPreflight {
    <#
    .SYNOPSIS
    Checks whether one host is ready to become a node, and returns one NexusFleet.PreflightResult. Never throws.

    .DESCRIPTION
    The per-host work of Test-NexusHost (E3: tested directly, the parallel loop around it stays thin).
      1. One ssh call ('true'): Reachable and SshAuth. Exit 255 with "Permission denied" means the host answered but
         refused the key (SshAuth fails); any other exit 255 means it could not be reached. Then nothing else runs.
      2. One ssh call with a small script that prints key=value facts: OS, sudo, free disk space on /, Docker, and
         whether the broker (config Broker.Host:Port) can be reached from the host.
    Checks: Reachable, SshAuth, OS, Sudo, DiskSpace, Docker, Broker, and for a host with reach "outbound" also
    AgentLink: the control plane must support the agent link, and the host must reach the link's address (the
    host and port of -LinkUrl), because that agent connects to the control plane itself. Each is Pass, Fail or Warning. A missing Docker
    is only a Warning: Install-NexusNode installs it. Success is $true when no check failed; Step is the first
    failed check and Error its detail. Any unexpected error becomes a failed result (Step 'Preflight'), so one bad
    host never stops the others.

    .PARAMETER HostInfo
    A NexusFleet.Host from Import-NexusInventory.

    .PARAMETER Config
    The NexusFleet config (Get-NexusConfig): Broker, Ssh and Preflight are used.

    .PARAMETER LinkUrl
    The agent link URL (Get-NexusAgentLinkUrl), for a host with reach "outbound".

    .PARAMETER LinkUnsupported
    The connected control plane does not list the agent-link feature: an outbound host then fails AgentLink.

    .PARAMETER RunContext
    Optional run context: every check is then logged in the host's log.

    .EXAMPLE
    Invoke-NexusHostPreflight -HostInfo $host -Config (Get-NexusConfig)
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [PSTypeName('NexusFleet.Host')]
        [pscustomobject]$HostInfo,

        [Parameter(Mandatory)]
        [hashtable]$Config,

        [PSTypeName('NexusFleet.RunContext')]
        [pscustomobject]$RunContext,

        [string]$LinkUrl,

        [switch]$LinkUnsupported
    )

    $outbound = $HostInfo.Reach -eq 'outbound'
    # The link's host and port, for the reachability test on the host. Only a plain host name or address is put in
    # the script; anything else would be a way to run something else on the host.
    $link = $null
    if ($outbound -and $LinkUrl) {
        $uri = [uri]$LinkUrl
        if ($uri.DnsSafeHost -match '^[A-Za-z0-9.:-]+$') {
            $link = @{ Host = $uri.DnsSafeHost; Port = $uri.Port }
        }
    }

    $checks = [System.Collections.Generic.List[object]]::new()
    $addCheck = {
        param([string]$Name, [string]$Status, [string]$Detail)
        $checks.Add([pscustomobject]@{ Name = $Name; Status = $Status; Detail = $Detail })
        if ($RunContext) {
            $level = @{ Pass = 'Info'; Warning = 'Warning'; Fail = 'Error' }[$Status]
            Write-NexusLog -Context $RunContext -HostName $HostInfo.Name -Step $Name -Level $level -Message "$Status - $Detail"
        }
    }

    $ssh = Get-NexusSshParameter -HostInfo $HostInfo -Config $Config

    $unexpected = $null
    try {
        # 1. Can we get in?
        $login = Invoke-NexusHostCommand @ssh -Command 'true'
        if ($login.TransportFailed) {
            if ($login.StdErr -match 'Permission denied') {
                & $addCheck 'Reachable' 'Pass' "$($HostInfo.Address):$($HostInfo.Port) answers"
                & $addCheck 'SshAuth' 'Fail' "the host refused the key for user $($HostInfo.User): $($login.StdErr)"
            }
            else {
                & $addCheck 'Reachable' 'Fail' "cannot reach $($HostInfo.Address):$($HostInfo.Port) over ssh: $($login.StdErr)"
            }
        }
        else {
            & $addCheck 'Reachable' 'Pass' "$($HostInfo.Address):$($HostInfo.Port) answers"
            & $addCheck 'SshAuth' 'Pass' "logged in as $($HostInfo.User)"

            # 2. The facts, in one connection. Broker host and port were validated by Get-NexusConfig.
            $script = @'
. /etc/os-release 2>/dev/null; echo "os=${ID:-unknown}"; echo "osversion=${VERSION_ID:-}"
if sudo -n true 2>/dev/null; then echo "sudo=yes"; else echo "sudo=no"; fi
echo "diskfreemb=$(df -Pm / | awk 'NR==2 {print $4}')"
if command -v docker >/dev/null 2>&1; then echo "docker=$(docker --version 2>/dev/null)"; else echo "docker="; fi
if timeout 3 bash -c '</dev/tcp/{BrokerHost}/{BrokerPort}' 2>/dev/null; then echo "broker=yes"; else echo "broker=no"; fi
'@
            $script = $script.Replace('{BrokerHost}', $Config.Broker.Host).Replace('{BrokerPort}', "$($Config.Broker.Port)")
            if ($link) {
                $script += "if timeout 3 bash -c '</dev/tcp/$($link.Host)/$($link.Port)' 2>/dev/null; then echo `"link=yes`"; else echo `"link=no`"; fi`n"
            }
            $answer = Invoke-NexusHostCommand @ssh -Command $script

            $facts = ConvertFrom-NexusFactLine -Text $answer.StdOut

            $supported = @($Config.Preflight.SupportedOs)
            if ($facts.os -in $supported) {
                & $addCheck 'OS' 'Pass' "$($facts.os) $($facts.osversion)"
            }
            else {
                & $addCheck 'OS' 'Fail' "OS '$($facts.os)' is not supported (supported: $($supported -join ', '))"
            }

            if ($facts.sudo -eq 'yes') {
                & $addCheck 'Sudo' 'Pass' "$($HostInfo.User) may use sudo without a password"
            }
            else {
                & $addCheck 'Sudo' 'Fail' "$($HostInfo.User) cannot use sudo without a password (needed to install Docker and the agent)"
            }

            $freeMb = 0
            $minMb = $Config.Preflight.MinDiskFreeMB
            if ([int]::TryParse($facts.diskfreemb, [ref]$freeMb) -and $freeMb -ge $minMb) {
                & $addCheck 'DiskSpace' 'Pass' "$freeMb MB free on /"
            }
            else {
                & $addCheck 'DiskSpace' 'Fail' "$($facts.diskfreemb) MB free on /, at least $minMb MB needed"
            }

            if ($facts.docker) {
                & $addCheck 'Docker' 'Pass' $facts.docker
            }
            else {
                & $addCheck 'Docker' 'Warning' 'Docker is not installed; Install-NexusNode will install it'
            }

            $broker = "$($Config.Broker.Host):$($Config.Broker.Port)"
            if ($facts.broker -eq 'yes') {
                & $addCheck 'Broker' 'Pass' "broker $broker reachable from the host"
            }
            else {
                & $addCheck 'Broker' 'Fail' "broker $broker is not reachable from the host (the agent needs it for heartbeats)"
            }

            if ($outbound) {
                if ($LinkUnsupported) {
                    & $addCheck 'AgentLink' 'Fail' 'the control plane does not support the agent link (it lists no agent-link feature); use reach direct, or a NexusInfra with the agent link'
                }
                elseif (-not $link) {
                    & $addCheck 'AgentLink' 'Fail' "no agent link URL to check (got '$LinkUrl'); set Agent.Link.Url or Api.BaseUrl in the config"
                }
                elseif ($facts.link -eq 'yes') {
                    & $addCheck 'AgentLink' 'Pass' "agent link $($link.Host):$($link.Port) reachable from the host"
                }
                else {
                    & $addCheck 'AgentLink' 'Fail' "agent link $($link.Host):$($link.Port) is not reachable from the host (the agent connects to the control plane there)"
                }
            }
        }
    }
    catch {
        $unexpected = "preflight of $($HostInfo.Name) failed unexpectedly: $($_.Exception.Message)"
        if ($RunContext) {
            Write-NexusLog -Context $RunContext -HostName $HostInfo.Name -Step 'Preflight' -Level Error -Message $unexpected
        }
    }

    $firstFail = $checks | Where-Object Status -EQ 'Fail' | Select-Object -First 1
    [pscustomobject]@{
        PSTypeName = 'NexusFleet.PreflightResult'
        Host       = $HostInfo.Name
        Address    = $HostInfo.Address
        Success    = -not $unexpected -and -not $firstFail
        Step       = if ($unexpected) { 'Preflight' } elseif ($firstFail) { $firstFail.Name } else { $null }
        Error      = if ($unexpected) { $unexpected } elseif ($firstFail) { $firstFail.Detail } else { $null }
        Checks     = @($checks)
    }
}
