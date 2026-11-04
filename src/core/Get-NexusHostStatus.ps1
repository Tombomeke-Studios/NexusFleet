function Get-NexusHostStatus {
    <#
    .SYNOPSIS
    Looks at one host over ssh: uptime, free disk, Docker and the agent container. Changes nothing, never throws.

    .DESCRIPTION
    The per-host work of Get-NexusFleetStatus (E3: tested directly, the parallel loop around it stays thin). One ssh
    call with a small script that prints key=value facts:
      uptime      seconds since the host started
      diskfreemb  free MB on /
      docker      the Docker version, empty when Docker is missing
      agent       state|started|restarts|image of the agent container (Agent.ContainerName), empty when missing
    A host that cannot be reached gets Reachable = $false and the reason in Error; any unexpected error is reported
    the same way, so one bad host never stops the others.

    .PARAMETER HostInfo
    A NexusFleet.Host from Import-NexusInventory.

    .PARAMETER Config
    The NexusFleet config (Get-NexusConfig): Ssh and Agent.ContainerName are used.

    .PARAMETER RunContext
    Optional run context: the outcome is then logged in the host's log.

    .EXAMPLE
    Get-NexusHostStatus -HostInfo $host -Config (Get-NexusConfig)

    .OUTPUTS
    NexusFleet.HostStatus: Host, Reachable, Error, UptimeSeconds, DiskFreeMB, Docker, AgentState (running, exited, ...,
    or missing), AgentStartedAt, AgentRestarts, AgentImage.
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
        [pscustomobject]$RunContext
    )

    $status = [pscustomobject]@{
        PSTypeName     = 'NexusFleet.HostStatus'
        Host           = $HostInfo.Name
        Reachable      = $false
        Error          = $null
        UptimeSeconds  = $null
        DiskFreeMB     = $null
        Docker         = $null
        AgentState     = $null
        AgentStartedAt = $null
        AgentRestarts  = $null
        AgentImage     = $null
    }

    $ssh = Get-NexusSshParameter -HostInfo $HostInfo -Config $Config

    try {
        # One connection for every fact, printed as key=value lines (as the preflight does). Nothing is changed:
        # docker inspect only reads. Without the container, inspect fails and 'agent=' stays empty.
        $script = @'
echo "uptime=$(cut -d. -f1 /proc/uptime)"
echo "diskfreemb=$(df -Pm / | awk 'NR==2 {print $4}')"
if command -v docker >/dev/null 2>&1; then echo "docker=$(docker --version 2>/dev/null)"; else echo "docker="; fi
if a=$(sudo -n docker inspect --format '{{.State.Status}}|{{.State.StartedAt}}|{{.RestartCount}}|{{.Config.Image}}' {Name} 2>/dev/null); then echo "agent=$a"; else echo "agent="; fi
'@
        $script = $script.Replace('{Name}', (ConvertTo-NexusShellArgument -Value $Config.Agent.ContainerName))
        $answer = Invoke-NexusHostCommand @ssh -Command $script

        # Exit 255 is ssh itself failing (host down, key refused): then nothing is known about the host. Any other
        # exit code still came from the host, so the facts it printed count.
        if ($answer.TransportFailed) {
            $status.Error = "cannot reach $($HostInfo.Address):$($HostInfo.Port) over ssh: $($answer.StdErr)"
        }
        else {
            $facts = @{}
            foreach ($line in $answer.StdOut -split "`n") {
                $key, $value = $line -split '=', 2
                if ($key) { $facts[$key.Trim()] = "$value".Trim() }
            }
            $status.Reachable = $true
            # A fact that is not a number (an old df, an empty line) stays $null instead of failing the whole status.
            $number = 0
            if ([int]::TryParse($facts.uptime, [ref]$number)) { $status.UptimeSeconds = $number }
            if ([int]::TryParse($facts.diskfreemb, [ref]$number)) { $status.DiskFreeMB = $number }
            $status.Docker = if ($facts.docker) { $facts.docker } else { $null }

            # docker inspect printed state|started|restarts|image in one line; split it back into its four parts.
            if ($facts.agent) {
                $state, $started, $restarts, $image = $facts.agent -split '\|', 4
                $status.AgentState = $state
                $status.AgentStartedAt = $started
                if ([int]::TryParse($restarts, [ref]$number)) { $status.AgentRestarts = $number }
                $status.AgentImage = $image
            }
            else {
                $status.AgentState = 'missing'
            }
        }
    }
    catch {
        # Never throw: one host that misbehaves must not stop the status of the others.
        $status.Reachable = $false
        $status.Error = "status of $($HostInfo.Name) failed unexpectedly: $($_.Exception.Message)"
    }

    if ($RunContext) {
        $message = if ($status.Reachable) { "reachable, agent $($status.AgentState)" } else { $status.Error }
        $level = if ($status.Reachable) { 'Info' } else { 'Warning' }
        Write-NexusLog -Context $RunContext -HostName $HostInfo.Name -Step 'Status' -Level $level -Message $message
    }
    $status
}
