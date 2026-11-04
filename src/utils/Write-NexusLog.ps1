function Write-NexusLog {
    <#
    .SYNOPSIS
    Writes one readable log line for an event of a NexusFleet run, with secrets redacted.

    .DESCRIPTION
    Line format: <UTC time> <LEVEL> run=<RunId> host=<host> step=<step> <message>
    Each host gets its own file in the run's log folder (<host>.log), run-level events go to run.log.
    Because one host is handled by one runspace, two runspaces never write to the same file.
    Known secrets from the run context and NexusInfra API tokens (nxi_...) are replaced before writing.
    The line is also written to the verbose stream, so -Verbose shows the log live.
    When the file cannot be written, a warning says so and the run goes on: logging never fails the work.

    .PARAMETER Context
    The run context from Initialize-NexusRunContext.

    .PARAMETER Message
    What happened. Line breaks are replaced by " | " to keep one line per event.

    .PARAMETER Level
    Info, Warning or Error.

    .PARAMETER HostName
    The host the event is about; "-" (default) for run-level events.

    .PARAMETER Step
    The step the event is about; "-" (default) when not tied to a step.

    .EXAMPLE
    Write-NexusLog -Context $context -HostName 'web01' -Step 'agent' -Message 'Container started'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSTypeName('NexusFleet.RunContext')]
        [pscustomobject]$Context,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Message,

        [ValidateSet('Info', 'Warning', 'Error')]
        [string]$Level = 'Info',

        [ValidateNotNullOrEmpty()]
        [string]$HostName = '-',

        [ValidateNotNullOrEmpty()]
        [string]$Step = '-'
    )

    $text = $Message -replace '\r?\n', ' | '
    foreach ($secret in $Context.Secrets) {
        $text = $text.Replace($secret, '***')
    }
    # Safety net for API tokens that were never registered as a secret (format: nxi_ + base64url).
    $text = $text -replace 'nxi_[A-Za-z0-9_-]+', 'nxi_***'

    $time = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    $line = '{0} {1,-7} run={2} host={3} step={4} {5}' -f $time, $Level.ToUpper(), $Context.RunId, $HostName, $Step, $text

    # Characters such as ':' (IPv6) are not allowed in Windows file names.
    $fileName = if ($HostName -eq '-') { 'run' } else { $HostName -replace '[^A-Za-z0-9._-]', '_' }
    $logFile = Join-Path -Path $Context.LogDirectory -ChildPath "$fileName.log"

    # -WhatIf:$false: a dry run is logged too. A log that cannot be written (a locked file, a full disk) must never make
    # the work itself fail: the host's result would then say "failed" for a host that was installed. So it warns.
    try {
        Add-Content -Path $logFile -Value $line -Encoding utf8 -WhatIf:$false -ErrorAction Stop
    }
    catch {
        Write-Warning -Message "NexusFleet could not write to the log ${logFile}: $($_.Exception.Message)"
    }
    Write-Verbose -Message $line
}
