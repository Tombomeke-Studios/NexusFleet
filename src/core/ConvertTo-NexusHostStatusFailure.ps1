function ConvertTo-NexusHostStatusFailure {
    <#
    .SYNOPSIS
    Turns an unexpected error while looking at one host into an unreachable NexusFleet.HostStatus.

    .DESCRIPTION
    Get-NexusHostStatus never throws by itself, but its parallel runspace can still fail (for example when the module
    cannot be loaded there). Get-NexusFleetStatus then reports the host with this function: not reachable, with the
    reason as its Error, so the fleet status still names the problem instead of leaving the host out.

    .PARAMETER HostInfo
    The host the error belongs to.

    .PARAMETER Message
    What went wrong.

    .EXAMPLE
    ConvertTo-NexusHostStatusFailure -HostInfo $host -Message $_.Exception.Message
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$HostInfo,

        [Parameter(Mandatory)]
        [string]$Message
    )

    [pscustomobject]@{
        PSTypeName     = 'NexusFleet.HostStatus'
        Host           = $HostInfo.Name
        Reachable      = $false
        Error          = "status of $($HostInfo.Name) failed unexpectedly: $Message"
        UptimeSeconds  = $null
        DiskFreeMB     = $null
        Docker         = $null
        AgentState     = $null
        AgentStartedAt = $null
        AgentRestarts  = $null
        AgentImage     = $null
    }
}
