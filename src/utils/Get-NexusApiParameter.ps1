function Get-NexusApiParameter {
    <#
    .SYNOPSIS
    Returns the connection parameters for Invoke-NexusApi from a session, as a hashtable to splat.

    .DESCRIPTION
    Install and status both call the API with the settings of the connection made by Connect-NexusInfra. They cannot
    read the module's session directly in a parallel runspace, so the session is passed in and turned into this
    hashtable. Only the parameters of Invoke-NexusApi are copied: the session's User and PlatformRole are not.

    .PARAMETER Session
    The connection from Connect-NexusInfra (Get-NexusSession).

    .EXAMPLE
    $api = Get-NexusApiParameter -Session (Get-NexusSession)
    Invoke-NexusApi @api -Method GET -Path '/nodes'

    Lists the nodes with the connection's address, token, time-out and retries.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [PSTypeName('NexusFleet.Session')]
        [pscustomobject]$Session
    )

    @{
        BaseUrl              = $Session.BaseUrl
        Token                = $Session.Token
        TimeoutSeconds       = $Session.TimeoutSeconds
        RetryCount           = $Session.RetryCount
        AllowUnencryptedHttp = [bool]$Session.AllowUnencryptedHttp
    }
}
