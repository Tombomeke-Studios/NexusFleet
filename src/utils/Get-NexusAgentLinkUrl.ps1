function Get-NexusAgentLinkUrl {
    <#
    .SYNOPSIS
    Returns the WebSocket URL an agent with reach "outbound" dials to reach the control plane.

    .DESCRIPTION
    The agent link goes through the gateway, the same address as the panel's API (docs/agent-link.md). So by
    default the URL is the panel address with http:// turned into ws:// (and https:// into wss://, the encrypted
    form), plus the link's path. When the nodes reach the control plane under another name than this machine
    does, Agent.Link.Url in the config sets the URL itself.

    .PARAMETER Link
    The Agent.Link section of the config: Url (may be empty) and Path.

    .PARAMETER BaseUrl
    The panel address of the connection, e.g. https://nexus.example.com.

    .EXAMPLE
    Get-NexusAgentLinkUrl -Link @{ Url = ''; Path = '/agent-link' } -BaseUrl 'https://nexus.example.com'

    Returns wss://nexus.example.com/agent-link.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Link,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$BaseUrl
    )

    if ($Link.Url) {
        return $Link.Url
    }
    # 'https://' -> 'wss://', 'http://' -> 'ws://': only the start of the address changes.
    $base = $BaseUrl.TrimEnd('/') -replace '^http', 'ws'
    "$base$($Link.Path)"
}
