function Get-NexusSshParameter {
    <#
    .SYNOPSIS
    Returns the parameters for Invoke-NexusHostCommand that reach one host, as a hashtable to splat.

    .DESCRIPTION
    Preflight, install and status all talk to a host the same way: the address, port and user come from the inventory
    host, the time-out and the known_hosts file from the config. Building that hashtable in one place keeps the three
    in step: a new ssh setting is added here once.

    KeyFile and KnownHostsFile are only added when they are set. Left out, ssh uses its own defaults
    (~/.ssh/id_* and ~/.ssh/known_hosts) instead of an empty path.

    .PARAMETER HostInfo
    A NexusFleet.Host from Import-NexusInventory.

    .PARAMETER Config
    The NexusFleet config (Get-NexusConfig); only Ssh is read.

    .EXAMPLE
    $ssh = Get-NexusSshParameter -HostInfo $hostInfo -Config (Get-NexusConfig)
    Invoke-NexusHostCommand @ssh -Command 'uptime'

    Runs uptime on the host with the settings of the inventory and the config.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$HostInfo,

        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    $ssh = @{
        HostName              = $HostInfo.Address
        Port                  = $HostInfo.Port
        UserName              = $HostInfo.User
        ConnectTimeoutSeconds = $Config.Ssh.ConnectTimeoutSeconds
    }
    if ($HostInfo.KeyFile) { $ssh.KeyFile = $HostInfo.KeyFile }
    if ($Config.Ssh.KnownHostsFile) { $ssh.KnownHostsFile = $Config.Ssh.KnownHostsFile }
    $ssh
}
