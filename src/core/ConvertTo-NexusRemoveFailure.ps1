function ConvertTo-NexusRemoveFailure {
    <#
    .SYNOPSIS
    Turns an unexpected error during the removal of one node into a failed NexusFleet.RemoveResult.

    .DESCRIPTION
    Remove-NexusNode catches anything that escapes the per-host work (Invoke-NexusHostRemoval never throws, but for
    example loading the module in a parallel runspace can fail), so that one host can never stop the others, and
    reports it with this function as a normal, failed result.

    .PARAMETER HostInfo
    The host the error belongs to.

    .PARAMETER Message
    What went wrong.

    .PARAMETER PlanOnly
    Whether it was a dry run.

    .EXAMPLE
    ConvertTo-NexusRemoveFailure -HostInfo $host -Message $_.Exception.Message
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$HostInfo,

        [Parameter(Mandatory)]
        [string]$Message,

        [switch]$PlanOnly
    )

    [pscustomobject]@{
        PSTypeName = 'NexusFleet.RemoveResult'
        Host       = $HostInfo.Name
        Success    = $false
        PlanOnly   = [bool]$PlanOnly
        Changed    = $false
        Step       = 'Remove'
        Error      = "removal of $($HostInfo.Name) failed unexpectedly: $Message"
        Node       = 'Unknown'
        Agent      = 'Unknown'
    }
}
