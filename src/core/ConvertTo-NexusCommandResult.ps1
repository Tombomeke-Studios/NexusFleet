function ConvertTo-NexusCommandResult {
    <#
    .SYNOPSIS
    Builds the result object of the transport contract: what running one command on one host returned.

    .DESCRIPTION
    The transport contract: every transport (today only SSH, src/transports/) runs one command on one
    host and returns exactly this object, whatever the technique. Steps only look at these properties:
      HostName        the host the command ran on
      ExitCode        the command's exit code
      StdOut, StdErr  the output, lines joined with a newline
      Succeeded       ExitCode is 0
      TransportFailed the transport itself failed (for ssh: exit code 255, connection or authentication)

    .PARAMETER HostName
    The host the command ran on.

    .PARAMETER ExitCode
    The exit code.

    .PARAMETER StdOut
    The output lines.

    .PARAMETER StdErr
    The error output lines.

    .EXAMPLE
    ConvertTo-NexusCommandResult -HostName 'web01' -ExitCode 0 -StdOut 'Docker version 27.3.1'
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$HostName,

        [Parameter(Mandatory)]
        [int]$ExitCode,

        [AllowEmptyCollection()]
        [string[]]$StdOut = @(),

        [AllowEmptyCollection()]
        [string[]]$StdErr = @()
    )

    [pscustomobject]@{
        PSTypeName      = 'NexusFleet.CommandResult'
        HostName        = $HostName
        ExitCode        = $ExitCode
        StdOut          = $StdOut -join "`n"
        StdErr          = $StdErr -join "`n"
        Succeeded       = $ExitCode -eq 0
        TransportFailed = $ExitCode -eq 255
    }
}
