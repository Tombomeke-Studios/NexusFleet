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

    .PARAMETER KeepRuns
    How many run folders to keep in the log root, this run included (config Log.KeepRuns). Older ones are removed.
    0 keeps every run. Under -WhatIf nothing is removed.

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

        [ValidateRange(0, 10000)]
        [int]$KeepRuns = 0,

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

    # Keep only the newest runs. Only folders named like a RunId are looked at, so nothing else in the folder is ever
    # removed. The names start with the time, so sorting by name sorts by age. A dry run removes nothing.
    if ($KeepRuns -gt 0 -and -not $WhatIfPreference) {
        $runFolders = Get-ChildItem -Path $LogRoot -Directory | Where-Object Name -Match '^\d{8}T\d{6}Z-[0-9a-f]{6}$' |
            Sort-Object -Property Name -Descending
        foreach ($folder in $runFolders | Select-Object -Skip $KeepRuns) {
            try {
                Remove-Item -LiteralPath $folder.FullName -Recurse -Force -ErrorAction Stop
            }
            catch {
                # An old log that cannot be removed (a file still open) is no reason to stop a run.
                Write-Warning -Message "NexusFleet could not remove the old log folder $($folder.FullName): $($_.Exception.Message)"
            }
        }
    }

    [pscustomobject]@{
        PSTypeName   = 'NexusFleet.RunContext'
        RunId        = $runId
        LogDirectory = $logDirectory
        # An empty string would "match" between every two characters, so it is dropped. Longest first: when one secret
        # is part of another (the broker password in the broker URL), the longer one is then replaced as a whole.
        Secrets      = @($Secret | Where-Object { -not [string]::IsNullOrEmpty($_) } | Sort-Object -Property Length -Descending)
    }
}
