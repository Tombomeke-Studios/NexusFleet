function Invoke-NexusHostRemoval {
    <#
    .SYNOPSIS
    Removes one node: deregisters it in NexusInfra and removes the agent from its host. Never throws.

    .DESCRIPTION
    The per-host work of Remove-NexusNode (E3: tested directly, the parallel loop around it stays thin).
      1. Host   one ssh call: is the agent container there, and its env file? Nothing is changed.
      2. Node   GET /nodes: is the node registered?
      3. Node   DELETE /nodes/<name>. NexusInfra refuses (409) while the node hosts a running server; the host is
                then left alone, so a refused removal changes nothing.
      4. Agent  removes the agent container and its env file (it holds the secrets) from the host.
      5. Node   a heartbeat the agent sent just before it stopped makes NexusInfra create the node again, so the
                node is looked up once more and deleted again when it is back.
    Only what is there is removed, so a second run changes nothing (Changed = $false). Docker and the backups volume
    stay: Docker may have been on the host before NexusFleet, and the volume is data.

    With -PlanOnly only 1 and 2 run (the dry run of -WhatIf). A dry run cannot see whether NexusInfra would refuse
    the node: only the DELETE itself answers that.

    Returns one NexusFleet.RemoveResult: Host, Success, PlanOnly, Changed, Step (where it failed), Error, Node and
    Agent (Absent, Present, Removed, WouldRemove, or Unknown for a host that was not reached).

    .PARAMETER HostInfo
    A NexusFleet.Host from Import-NexusInventory.

    .PARAMETER Config
    The NexusFleet config (Get-NexusConfig).

    .PARAMETER Session
    The connection from Connect-NexusInfra (passed in: in a parallel runspace the module's session does not exist).

    .PARAMETER PlanOnly
    Only check and report what would be removed.

    .PARAMETER IgnoreUnreachableHost
    Deregister the node even when its host cannot be reached over ssh (a machine that is gone). Without it an
    unreachable host is a failure and nothing is changed.

    .PARAMETER RunContext
    Optional run context: the outcome is then logged in the host's log.

    .EXAMPLE
    Invoke-NexusHostRemoval -HostInfo $host -Config (Get-NexusConfig) -Session (Get-NexusSession)
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [PSTypeName('NexusFleet.Host')]
        [pscustomobject]$HostInfo,

        [Parameter(Mandatory)]
        [hashtable]$Config,

        [Parameter(Mandatory)]
        [PSTypeName('NexusFleet.Session')]
        [pscustomobject]$Session,

        [switch]$PlanOnly,

        [switch]$IgnoreUnreachableHost,

        [PSTypeName('NexusFleet.RunContext')]
        [pscustomobject]$RunContext
    )

    $result = [pscustomobject]@{
        PSTypeName = 'NexusFleet.RemoveResult'
        Host       = $HostInfo.Name
        Success    = $false
        PlanOnly   = [bool]$PlanOnly
        Changed    = $false
        Step       = $null
        Error      = $null
        Node       = 'Unknown'
        Agent      = 'Unknown'
    }
    $name = $HostInfo.Name

    try {
        $ssh = Get-NexusSshParameter -HostInfo $HostInfo -Config $Config
        $api = Get-NexusApiParameter -Session $Session
        $container = ConvertTo-NexusShellArgument -Value $Config.Agent.ContainerName
        $envFile = ConvertTo-NexusShellArgument -Value $Config.Agent.EnvFile

        # 1. What is on the host? Printed as key=value lines; nothing is changed.
        $result.Step = 'Host'
        $look = "if sudo -n docker inspect $container >/dev/null 2>&1; then echo exists=yes; else echo exists=no; fi; " +
        "if sudo -n test -e $envFile; then echo envfile=yes; else echo envfile=no; fi"
        $answer = Invoke-NexusHostCommand @ssh -Command $look
        $reachable = -not $answer.TransportFailed
        if (-not $reachable -and -not $IgnoreUnreachableHost) {
            throw "cannot reach $($HostInfo.Address):$($HostInfo.Port) over ssh, nothing was changed: $($answer.StdErr)"
        }
        $facts = ConvertFrom-NexusFactLine -Text $answer.StdOut
        $containerThere = $facts.exists -eq 'yes'
        $agentThere = $containerThere -or $facts.envfile -eq 'yes'
        if ($reachable) {
            $result.Agent = if ($agentThere) { 'Present' } else { 'Absent' }
        }

        # 2. Is the node registered?
        $result.Step = 'Node'
        $nodes = @(Invoke-NexusApi @api -Method GET -Path '/nodes')
        $nodeThere = [bool]($nodes | Where-Object id -EQ $name)
        $result.Node = if ($nodeThere) { 'Present' } else { 'Absent' }

        if ($PlanOnly) {
            if ($nodeThere) { $result.Node = 'WouldRemove' }
            if ($agentThere) { $result.Agent = 'WouldRemove' }
        }
        else {
            # 3. Deregister first: NexusInfra refuses a node with running servers, and then the host stays as it is.
            if ($nodeThere) {
                try {
                    $null = Invoke-NexusApi @api -Method DELETE -Path "/nodes/$name"
                }
                catch {
                    if ($_.FullyQualifiedErrorId -like 'NexusApi.Conflict*') {
                        throw "node $name still hosts a running server, nothing was changed. Stop or move its servers first."
                    }
                    throw
                }
                $result.Node = 'Removed'
                $result.Changed = $true
            }

            # 4. The agent container and its env file. Only what step 1 saw, so a missing one is not an error.
            if ($agentThere) {
                $result.Step = 'Agent'
                $remove = "sudo -n rm -f $envFile"
                if ($containerThere) {
                    $remove = "sudo -n docker rm -f $container >/dev/null && $remove"
                }
                $removed = Invoke-NexusHostCommand @ssh -Command $remove
                if (-not $removed.Succeeded) {
                    throw "could not remove the agent from $name (exit $($removed.ExitCode)): $($removed.StdErr)"
                }
                $result.Agent = 'Removed'
                $result.Changed = $true
            }

            # 5. A last heartbeat of the agent that just stopped creates the node again in NexusInfra.
            if ($nodeThere -and $containerThere) {
                $result.Step = 'Node'
                $nodes = @(Invoke-NexusApi @api -Method GET -Path '/nodes')
                if ($nodes | Where-Object id -EQ $name) {
                    $null = Invoke-NexusApi @api -Method DELETE -Path "/nodes/$name"
                }
            }
        }
        $result.Success = $true
        $result.Step = $null
    }
    catch {
        $result.Error = $_.Exception.Message
    }

    if ($RunContext) {
        $message = if ($result.Success) { "node $($result.Node), agent $($result.Agent)" } else { $result.Error }
        $level = if ($result.Success) { 'Info' } else { 'Error' }
        Write-NexusLog -Context $RunContext -HostName $name -Step 'Remove' -Level $level -Message $message
    }
    $result
}
