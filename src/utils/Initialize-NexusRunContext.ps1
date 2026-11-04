function Initialize-NexusRunContext {
    <#
    .SYNOPSIS
    Creates the context of one NexusFleet run: a RunId, the log folder and the secrets to redact.

    .DESCRIPTION
    Every public cmdlet calls this once at the start of a run and passes the result to Write-NexusLog.
    The context is a plain object, so it can go into ForEach-Object -Parallel runspaces with $using:
    (module variables do not exist there). The log folder is created even under -WhatIf, because a dry
    run is logged too.

    .PARAMETER LogRoot
    The folder that holds one subfolder per run (config Log.Directory). Empty or not given: logs/ in the current
    folder. It is created when it does not exist yet.

    .PARAMETER Secret
    Values that must never appear in a log, such as the API token. Empty values are ignored.

    .EXAMPLE
    $context = Initialize-NexusRunContext -Secret $apiToken
    Write-NexusLog -Context $context -Message 'Run started'
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$LogRoot,

        [AllowNull()]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Secret = @()
    )

    # Empty (the default of Log.Directory) means logs/ in the current folder.
    if ([string]::IsNullOrWhiteSpace($LogRoot)) {
        $LogRoot = Join-Path -Path (Get-Location).Path -ChildPath 'logs'
    }

    # Sortable by time, and unique even when two runs start in the same second.
    $runId = '{0}-{1}' -f [datetime]::UtcNow.ToString('yyyyMMddTHHmmssZ'), [guid]::NewGuid().ToString('N').Substring(0, 6)
    $logDirectory = Join-Path -Path $LogRoot -ChildPath $runId

    # -WhatIf:$false: a caller's -WhatIf must not stop the log folder from being created.
    New-Item -Path $logDirectory -ItemType Directory -Force -WhatIf:$false | Out-Null

    [pscustomobject]@{
        PSTypeName   = 'NexusFleet.RunContext'
        RunId        = $runId
        LogDirectory = $logDirectory
        # An empty string would "match" between every two characters, so it is dropped.
        Secrets      = @($Secret | Where-Object { -not [string]::IsNullOrEmpty($_) })
    }
}
