function Invoke-NexusSshClient {
    <#
    .SYNOPSIS
    Starts the native ssh client with the given arguments and optional stdin bytes; returns its raw output.

    .DESCRIPTION
    The smallest possible wrapper around the ssh program, so that Invoke-NexusHostCommand can be unit
    tested: Pester cannot see what is piped into a mocked external program, but it can see the
    -InputBytes parameter of this function. This wrapper itself is covered by the integration test
    against the lab container (tests/transports/Invoke-NexusHostCommand.Integration.Tests.ps1).

    .PARAMETER ArgumentList
    The arguments for ssh.

    .PARAMETER InputBytes
    Optional bytes to send on ssh's stdin.

    .EXAMPLE
    Invoke-NexusSshClient -ArgumentList '-o', 'BatchMode=yes', 'fleet@web01', 'uname -a'
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string[]]$ArgumentList,

        [byte[]]$InputBytes
    )

    # ssh's error output must be collected, never stop this function (callers may use ErrorAction Stop).
    $ErrorActionPreference = 'Continue'

    # 2>&1: stderr lines come back as ErrorRecord objects between the stdout strings.
    if ($InputBytes) {
        $output = $InputBytes | & ssh @ArgumentList 2>&1
    }
    else {
        $output = & ssh @ArgumentList 2>&1
    }

    [pscustomobject]@{
        Output   = @($output)
        ExitCode = $LASTEXITCODE
    }
}
