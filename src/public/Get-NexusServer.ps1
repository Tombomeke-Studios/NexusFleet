function Get-NexusServer {
    <#
    .SYNOPSIS
    Lists the servers (deployments) NexusInfra runs, optionally only those of one node, status or name.

    .DESCRIPTION
    Asks NexusInfra for its servers (GET /deployments) and returns one object per server. NexusInfra answers in
    pages; Get-NexusServer reads every page (Servers.PageSize per request), so you always get the whole list.

    The filters are applied by NexusInfra itself: -Node (the node the server runs on), -Status (for example running)
    and -Name (a part of the name). Without filters you get every server your token may see.

    The result goes straight into Invoke-NexusFleetAction: that is how you start, stop or restart a group of
    servers, for example every server of one node before the node is removed.

    Nothing is changed.

    .PARAMETER Node
    Only the servers on this node (its name in the inventory, which is its id in NexusInfra).

    .PARAMETER Status
    Only the servers with exactly this status, for example running or stopped.

    .PARAMETER Name
    Only the servers whose name contains this text (upper and lower case do not matter).

    .EXAMPLE
    Get-NexusServer | Format-Table Name, Status, Node

    Shows every server with its status and node.

    .EXAMPLE
    Get-NexusServer -Node node-home01 -Status running

    The running servers on one node.

    .EXAMPLE
    Get-NexusServer -Name minecraft | Invoke-NexusFleetAction -Action restart

    Restarts every server with minecraft in its name.

    .INPUTS
    None
    Get-NexusServer takes no pipeline input.

    .OUTPUTS
    NexusFleet.Server
    Id, Name, Status, Node (the id of the node, empty when the server has none yet) and Type.

    .NOTES
    Needs Connect-NexusInfra first (error NexusFleet.NotConnected otherwise).

    .LINK
    https://github.com/Tombomeke-Studios/NexusFleet/blob/dev/docs/user-guide.md#get-nexusserver

    .LINK
    about_NexusFleet

    .LINK
    Invoke-NexusFleetAction
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [ValidatePattern('^[a-z][a-z0-9-]{0,62}$')]
        [string]$Node,

        [ValidatePattern('^[a-z]+$')]
        [string]$Status,

        [ValidateNotNullOrEmpty()]
        [string]$Name
    )

    $session = Get-NexusSession
    $config = Get-NexusConfig
    $api = Get-NexusApiParameter -Session $session
    $pageSize = $config.Servers.PageSize

    # The filters as NexusInfra names them, escaped so a space or & in a name cannot break the query.
    $filter = ''
    if ($Node) { $filter += "&nodeId=$([uri]::EscapeDataString($Node))" }
    if ($Status) { $filter += "&status=$([uri]::EscapeDataString($Status))" }
    if ($Name) { $filter += "&q=$([uri]::EscapeDataString($Name))" }

    # Page after page, until every server NexusInfra counted (total) has been read.
    $offset = 0
    do {
        $page = Invoke-NexusApi @api -Method GET -Path "/deployments?limit=$pageSize&offset=$offset$filter"
        $items = @($page.items)
        foreach ($item in $items) {
            [pscustomobject]@{
                PSTypeName = 'NexusFleet.Server'
                Id         = $item.id
                Name       = $item.name
                Status     = $item.status
                Node       = $item.nodeId
                Type       = $item.type
            }
        }
        $offset += $items.Count
    } while ($items.Count -gt 0 -and $offset -lt $page.total)
}
