function Invoke-NexusFleetAction {
    <#
    .SYNOPSIS
    Starts, stops, restarts or kills a group of servers in one go, with a result per server.

    .DESCRIPTION
    Sends one action for many servers to NexusInfra (POST /deployments/bulk). The servers usually come from
    Get-NexusServer through the pipeline; their ids can also be given with -Id.

    NexusInfra accepts at most Servers.BulkMaxIds (100) servers per request, so a larger group is sent in batches of
    that size, one after the other. An id that appears twice is sent once.

    Every server gets its own result. NexusInfra handles the servers one by one and reports each: a server that
    fails (not found, not allowed, already stopped) does not stop the others. When a whole request fails, for example
    because NexusInfra is unreachable, the servers of that batch get a failed result with that error, and the next
    batch is still tried.

    -WhatIf is the dry run: nothing is sent, and every server gets a result with PlanOnly = $true. -Confirm asks
    once for the whole group.

    .PARAMETER Action
    What to do: start, stop, restart or kill. Stop asks the server to shut down; kill ends it at once.

    .PARAMETER Id
    The ids of the servers. Through the pipeline: the objects of Get-NexusServer (their Id is used), or plain ids.

    .EXAMPLE
    Get-NexusServer -Node node-home01 -Status running | Invoke-NexusFleetAction -Action stop -WhatIf

    Shows which servers would be stopped, and sends nothing.

    .EXAMPLE
    Get-NexusServer -Node node-home01 -Status running | Invoke-NexusFleetAction -Action stop

    Stops every running server on one node, for example before Remove-NexusNode.

    .EXAMPLE
    Get-NexusServer | Invoke-NexusFleetAction -Action restart | Where-Object { -not $_.Success } | Format-Table Name, Status, Error

    Restarts every server and shows only the ones that failed, with the reason.

    .INPUTS
    NexusFleet.Server
    The servers from Get-NexusServer, or their ids as strings.

    .OUTPUTS
    NexusFleet.ActionResult
    Id, Name, Action, Success, PlanOnly (a -WhatIf result), Status (the HTTP status NexusInfra gives that server,
    for example 200, 403, 404 or 409) and Error.

    .NOTES
    Needs Connect-NexusInfra first (error NexusFleet.NotConnected otherwise), with a token that has the scope write.
    Logs: logs/<RunId>/run.log.

    .LINK
    https://github.com/Tombomeke-Studios/NexusFleet/blob/dev/docs/user-guide.md#invoke-nexusfleetaction

    .LINK
    about_NexusFleet

    .LINK
    Get-NexusServer

    .LINK
    Remove-NexusNode
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('start', 'stop', 'restart', 'kill')]
        [string]$Action,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Id
    )

    begin {
        $ids = [System.Collections.Generic.List[string]]::new()
    }

    process {
        # Only collect here; the batches are made in end, when every id is known.
        foreach ($item in $Id) {
            if (-not $ids.Contains($item)) {
                $ids.Add($item)
            }
        }
    }

    end {
        $session = Get-NexusSession
        $config = Get-NexusConfig
        $api = Get-NexusApiParameter -Session $session
        $batchSize = $config.Servers.BulkMaxIds
        # NexusInfra uses lower case; ValidateSet also accepts Stop or STOP.
        $Action = $Action.ToLower()

        $run = Initialize-NexusRunContext -LogRoot $config.Log.Directory -KeepRuns $config.Log.KeepRuns -Secret ([System.Net.NetworkCredential]::new('', $session.Token).Password)
        $planOnly = -not $PSCmdlet.ShouldProcess("$($ids.Count) server(s)", $Action)
        Write-NexusLog -Context $run -Message ("Action $Action on $($ids.Count) server(s)" + $(if ($planOnly) { ', plan only' } else { '' }))

        $failed = 0
        for ($start = 0; $start -lt $ids.Count; $start += $batchSize) {
            $batch = @($ids.GetRange($start, [math]::Min($batchSize, $ids.Count - $start)))

            # What NexusInfra says per server, or one error for the whole batch.
            $answers = @()
            $batchError = $null
            if (-not $planOnly) {
                try {
                    $response = Invoke-NexusApi @api -Method POST -Path '/deployments/bulk' -Body @{ action = $Action; ids = $batch }
                    $answers = @($response.results)
                }
                catch {
                    $batchError = $_.Exception.Message
                    Write-NexusLog -Context $run -Level Error -Message "Action $Action failed for a batch of $($batch.Count) server(s): $batchError"
                }
            }

            foreach ($serverId in $batch) {
                $answer = $answers | Where-Object id -EQ $serverId | Select-Object -First 1
                $result = [pscustomobject]@{
                    PSTypeName = 'NexusFleet.ActionResult'
                    Id         = $serverId
                    Name       = $null
                    Action     = $Action
                    Success    = $false
                    PlanOnly   = $planOnly
                    Status     = $null
                    Error      = $null
                }
                if ($planOnly) {
                    $result.Success = $true
                }
                elseif ($answer) {
                    $result.Name = $answer.name
                    $result.Success = [bool]$answer.ok
                    $result.Status = $answer.status
                    $result.Error = $answer.error
                }
                else {
                    $result.Error = if ($batchError) { $batchError } else { 'NexusInfra gave no result for this server' }
                }
                if (-not $result.Success) {
                    $failed++
                    Write-NexusLog -Context $run -Level Warning -Message "$Action $serverId failed: $($result.Error)"
                }
                $result
            }
        }
        Write-NexusLog -Context $run -Message "Action $Action done: $($ids.Count - $failed) of $($ids.Count) server(s) succeeded"
    }
}
