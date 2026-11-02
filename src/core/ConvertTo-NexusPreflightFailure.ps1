function ConvertTo-NexusPreflightFailure {
    <#
    .SYNOPSIS
    Turns an unexpected error during the preflight of one host into a failed NexusFleet.PreflightResult.

    .DESCRIPTION
    Test-NexusHost catches anything that escapes the per-host check, so that one host can never stop the others,
    and reports it with this function as a normal, failed result.

    .PARAMETER HostInfo
    The host the error belongs to.

    .PARAMETER Message
    What went wrong.

    .EXAMPLE
    ConvertTo-NexusPreflightFailure -HostInfo $host -Message $_.Exception.Message
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
        PSTypeName = 'NexusFleet.PreflightResult'
        Host       = $HostInfo.Name
        Address    = $HostInfo.Address
        Success    = $false
        Step       = 'Preflight'
        Error      = "preflight of $($HostInfo.Name) failed unexpectedly: $Message"
        Checks     = @()
    }
}
