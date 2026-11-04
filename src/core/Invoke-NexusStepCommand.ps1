function Invoke-NexusStepCommand {
    <#
    .SYNOPSIS
    Runs a shell command on the host of a step context, and throws when it fails.

    .DESCRIPTION
    The way the installation steps talk to their host. It uses the ssh settings in the step context and turns
    a failure into an exception with a clear message, so the step runner records it and rolls back:
      - ssh itself failed (exit 255: host gone, key refused): always an error, also in a Test, because then
        nothing is known about the host.
      - the command failed (any other non-zero exit): an error, unless -AllowFailure. A Test uses -AllowFailure
        and reads the exit code itself ("not installed" is an answer, not an error).

    .PARAMETER Context
    The step context (Invoke-NexusHostInstall builds it): Ssh holds the arguments for Invoke-NexusHostCommand.

    .PARAMETER Command
    The shell command (bash) to run on the host.

    .PARAMETER Purpose
    A few words for the error message, e.g. 'install Docker'.

    .PARAMETER Secret
    Optional secrets to send on stdin, one line each.

    .PARAMETER AllowFailure
    Return the result also when the command exits with an error (ssh failures still throw).

    .EXAMPLE
    Invoke-NexusStepCommand -Context $Context -Purpose 'check Docker' -Command 'sudo -n docker info' -AllowFailure
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Context,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Command,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Purpose,

        [securestring[]]$Secret,

        [switch]$AllowFailure
    )

    $ssh = $Context.Ssh
    $result = if ($Secret) {
        Invoke-NexusHostCommand @ssh -Command $Command -Secret $Secret
    }
    else {
        Invoke-NexusHostCommand @ssh -Command $Command
    }

    if ($result.TransportFailed) {
        throw "ssh to $($ssh.HostName) failed while trying to $Purpose`: $($result.StdErr)"
    }
    if (-not $result.Succeeded -and -not $AllowFailure) {
        # The last lines of stderr usually say what went wrong (apt and docker print a lot before that).
        $reason = ($result.StdErr -split "`n" | Select-Object -Last 3) -join ' '
        throw "Could not $Purpose on $($ssh.HostName) (exit $($result.ExitCode)): $reason"
    }
    $result
}
