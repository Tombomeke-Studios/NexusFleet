function Add-NexusLogSecret {
    <#
    .SYNOPSIS
    Adds a secret to a run context, so the log hides it from then on. Safe from several runspaces at once.

    .DESCRIPTION
    A secret that only appears during the run (the link token NexusInfra mints for an outbound node) is not known
    when Initialize-NexusRunContext starts the run. The hosts of a run share one run context, also in parallel
    runspaces ($using: passes the same object). Reading the list, adding to it and writing it back is then a race:
    two hosts at the same moment both start from the same list, and one of the two secrets is lost. So the change
    happens under a lock on the run context: one runspace at a time.

    The new list replaces the old one in one assignment, so Write-NexusLog, which reads the list once, always sees a
    whole list. Longest first, as Initialize-NexusRunContext keeps it.

    .PARAMETER Context
    The run context (Initialize-NexusRunContext).

    .PARAMETER Secret
    The secret in plain text. An empty one is ignored (it would "match" between every two characters).

    .EXAMPLE
    Add-NexusLogSecret -Context $run -Secret $minted.token
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSTypeName('NexusFleet.RunContext')]
        [pscustomobject]$Context,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Secret
    )

    if ([string]::IsNullOrEmpty($Secret)) {
        return
    }
    [System.Threading.Monitor]::Enter($Context)
    try {
        $Context.Secrets = @(@($Context.Secrets) + $Secret | Sort-Object -Property Length -Descending)
    }
    finally {
        [System.Threading.Monitor]::Exit($Context)
    }
}
