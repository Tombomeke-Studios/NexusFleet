# The connection made by Connect-NexusInfra lives here, in the module scope, for the other cmdlets.
$script:NexusSession = $null

function Get-NexusSession {
    <#
    .SYNOPSIS
    Returns the current NexusInfra session, or tells you to connect first.

    .DESCRIPTION
    Every cmdlet that needs the panel calls this. The session holds the base URL, the token (SecureString),
    the user and the API settings. In ForEach-Object -Parallel runspaces the module variable does not exist,
    so callers pass the session in with $using:.

    .EXAMPLE
    $session = Get-NexusSession
    Invoke-NexusApi -BaseUrl $session.BaseUrl -Token $session.Token -Method GET -Path '/nodes'
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    if ($null -eq $script:NexusSession) {
        $exception = [System.InvalidOperationException]::new('NexusFleet is not connected to a NexusInfra panel. Run Connect-NexusInfra first.')
        $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                $exception, 'NexusFleet.NotConnected', 'ConnectionError', $null))
    }
    $script:NexusSession
}
