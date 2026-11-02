function Invoke-NexusHostCommand {
    <#
    .SYNOPSIS
    Runs one shell command on one Linux host over native ssh and returns a NexusFleet.CommandResult.

    .DESCRIPTION
    The SSH transport (choice from experiment E1). ssh never waits for input: BatchMode=yes (no password
    prompts), a connect time-out, and stdin closed (-n) when nothing is sent. A new host key is accepted
    once (StrictHostKeyChecking=accept-new); a changed key is refused.

    A secret (for example the agent's INTERNAL_API_TOKEN) is sent on stdin as bytes, so it never appears on
    a command line or in the process list of the host, and arrives without the CR/LF PowerShell would add
    to a string. The remote command reads it, e.g. with: IFS= read -r token

    The command is run by the remote shell as given: never build it from untrusted text.

    .PARAMETER HostName
    Host name, IPv4 or IPv6 address.

    .PARAMETER Port
    SSH port.

    .PARAMETER UserName
    The (sudo-capable) user to log in as.

    .PARAMETER Command
    The shell command to run on the host.

    .PARAMETER Secret
    Optional secret to send on stdin.

    .PARAMETER KeyFile
    Optional private key file (otherwise ssh uses its defaults and the agent).

    .PARAMETER KnownHostsFile
    Optional known_hosts file (otherwise ~/.ssh/known_hosts).

    .PARAMETER ConnectTimeoutSeconds
    How long ssh waits for the connection.

    .EXAMPLE
    Invoke-NexusHostCommand -HostName '10.0.0.5' -UserName 'fleet' -Command 'docker --version'

    .EXAMPLE
    Invoke-NexusHostCommand -HostName 'web01' -UserName 'fleet' -Command 'IFS= read -r t; echo ${#t}' -Secret $token
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        # Letters, digits, dots and dashes, not starting with a dash (that would be an ssh option); or IPv6.
        [Parameter(Mandatory)]
        [ValidatePattern('^([A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?|[0-9A-Fa-f]*:[0-9A-Fa-f:]*)$')]
        [string]$HostName,

        [ValidateRange(1, 65535)]
        [int]$Port = 22,

        [Parameter(Mandatory)]
        [ValidatePattern('^[a-z_][a-z0-9_-]{0,31}$')]
        [string]$UserName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Command,

        [securestring]$Secret,

        [ValidateNotNullOrEmpty()]
        [string]$KeyFile,

        [ValidateNotNullOrEmpty()]
        [string]$KnownHostsFile,

        [ValidateRange(1, 300)]
        [int]$ConnectTimeoutSeconds = 10
    )

    $sshArgs = [System.Collections.Generic.List[string]]::new()
    $sshArgs.AddRange([string[]]@(
            '-o', 'BatchMode=yes',
            '-o', "ConnectTimeout=$ConnectTimeoutSeconds",
            '-o', 'StrictHostKeyChecking=accept-new',
            '-o', 'LogLevel=ERROR',
            '-p', "$Port"))
    if ($KeyFile) { $sshArgs.AddRange([string[]]@('-i', $KeyFile)) }
    if ($KnownHostsFile) { $sshArgs.AddRange([string[]]@('-o', "UserKnownHostsFile=$KnownHostsFile")) }
    if (-not $Secret) { $sshArgs.Add('-n') }
    $sshArgs.Add("$UserName@$HostName")
    $sshArgs.Add($Command)

    $inputBytes = $null
    if ($Secret) {
        # Bytes, not a string: a string piped to a native command gets CR/LF appended on Windows (E1).
        $inputBytes = [System.Text.Encoding]::UTF8.GetBytes([System.Net.NetworkCredential]::new('', $Secret).Password)
    }

    $raw = Invoke-NexusSshClient -ArgumentList $sshArgs -InputBytes $inputBytes
    if ($inputBytes) {
        [array]::Clear($inputBytes, 0, $inputBytes.Length)   # do not leave the secret in memory longer than needed
    }

    # stderr lines are ErrorRecord objects, stdout lines are strings.
    $stdOut = @($raw.Output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] } | ForEach-Object { "$_" })
    $stdErr = @($raw.Output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object { "$_" })

    ConvertTo-NexusCommandResult -HostName $HostName -ExitCode $raw.ExitCode -StdOut $stdOut -StdErr $stdErr
}
