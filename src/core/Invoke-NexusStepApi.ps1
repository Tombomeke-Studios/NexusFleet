function Invoke-NexusStepApi {
    <#
    .SYNOPSIS
    Calls the NexusInfra API with the connection of a step context.

    .DESCRIPTION
    The way the installation steps talk to the panel: Invoke-NexusApi with the base URL, token and settings in
    the step context (from Connect-NexusInfra). In ForEach-Object -Parallel runspaces the session of
    Connect-NexusInfra does not exist, so it travels in the context.

    .PARAMETER Context
    The step context: Api holds the arguments for Invoke-NexusApi.

    .PARAMETER Method
    GET, POST, PATCH, PUT or DELETE.

    .PARAMETER Path
    The API path, e.g. /nodes.

    .PARAMETER Body
    Optional data to send.

    .EXAMPLE
    $nodes = Invoke-NexusStepApi -Context $Context -Method GET -Path '/nodes'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Context,

        [Parameter(Mandatory)]
        [ValidateSet('GET', 'POST', 'PATCH', 'PUT', 'DELETE')]
        [string]$Method,

        [Parameter(Mandatory)]
        [ValidatePattern('^/')]
        [string]$Path,

        [object]$Body
    )

    $api = $Context.Api
    if ($PSBoundParameters.ContainsKey('Body')) {
        Invoke-NexusApi @api -Method $Method -Path $Path -Body $Body
    }
    else {
        Invoke-NexusApi @api -Method $Method -Path $Path
    }
}
