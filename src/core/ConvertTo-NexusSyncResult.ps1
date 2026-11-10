function ConvertTo-NexusSyncResult {
    <#
    .SYNOPSIS
    Turns the install plan of one host into a NexusFleet.SyncResult: is the host as the inventory wants it?

    .DESCRIPTION
    Sync-NexusFleet finds drift with the dry run of the installation (Invoke-NexusHostInstall -PlanOnly): every step
    checks whether the host is in order for it. This function reads that plan:
      - every step that would be applied is one difference: the step, and what its check found (Detail), or else the
        step's description;
      - a failed preflight (the host does not answer, sudo is gone) is a difference that cannot be repaired from here,
        so the result has an Error and Repairable is $false;
      - no differences means InSync.
    With -Unmanaged it builds the result of a node NexusInfra knows but the inventory does not.

    .PARAMETER Plan
    A NexusFleet.InstallResult of a dry run (PlanOnly).

    .PARAMETER Step
    The registered steps (Get-NexusStep), for their descriptions.

    .PARAMETER Unmanaged
    The id of a node that NexusInfra knows and the inventory does not.

    .EXAMPLE
    ConvertTo-NexusSyncResult -Plan $plan -Step (Get-NexusStep)

    .EXAMPLE
    ConvertTo-NexusSyncResult -Unmanaged 'node-old'
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Plan')]
        [pscustomobject]$Plan,

        [Parameter(ParameterSetName = 'Plan')]
        [object[]]$Step = @(),

        [Parameter(Mandatory, ParameterSetName = 'Unmanaged')]
        [string]$Unmanaged
    )

    $result = [pscustomobject]@{
        PSTypeName  = 'NexusFleet.SyncResult'
        Host        = $null
        InSync      = $false
        Differences = @()
        Repairable  = $false
        Repaired    = $false
        Success     = $true
        Error       = $null
    }

    if ($Unmanaged) {
        $result.Host = $Unmanaged
        $result.Differences = @('Unmanaged: NexusInfra knows this node, the inventory does not')
        return $result
    }

    $result.Host = $Plan.Host
    if (-not $Plan.Success) {
        # The plan itself failed: the preflight, or a check that could not be done. Nothing is known for sure.
        $result.Differences = @("$($Plan.Step): $($Plan.Error)")
        $result.Success = $false
        $result.Error = $Plan.Error
        return $result
    }

    $result.Differences = @(
        foreach ($outcome in $Plan.Steps | Where-Object Outcome -EQ 'WouldApply') {
            $detail = $outcome.Detail
            if (-not $detail) {
                $detail = 'not in order: ' + ($Step | Where-Object Name -EQ $outcome.Step).Description
            }
            "$($outcome.Step): $detail"
        }
    )
    $result.InSync = $result.Differences.Count -eq 0
    $result.Repairable = -not $result.InSync
    $result
}
