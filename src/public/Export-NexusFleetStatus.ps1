function Export-NexusFleetStatus {
    <#
    .SYNOPSIS
    Writes the fleet status from Get-NexusFleetStatus to a JSON or CSV file.

    .DESCRIPTION
    Collects the NexusFleet.NodeStatus objects from the pipeline and writes them to one file:

      JSON  { "generatedAt": "<UTC time>", "nodes": [ ... ] } with every field of every node, for scripts and tools
      CSV   one row per node and a header with the field names, for a spreadsheet

    Times (LastHeartbeat) are written as ISO-8601 in UTC, e.g. 2026-11-04T07:35:00.0000000Z: the same on every
    machine and in every language setting, and sortable. The format comes from -Format, or else from the extension of
    -Path (.json or .csv). A missing folder is created; an existing file is replaced. Supports -WhatIf.

    .PARAMETER InputObject
    The status objects from Get-NexusFleetStatus, through the pipeline.

    .PARAMETER Path
    The file to write, e.g. ./status.csv. A relative path is relative to the current folder.

    .PARAMETER Format
    Json or Csv. Default: from the extension of -Path; needed when the extension is neither .json nor .csv.

    .EXAMPLE
    Import-NexusInventory ./config/inventory.json | Get-NexusFleetStatus | Export-NexusFleetStatus -Path ./status.json

    Writes the status of every host of the inventory as JSON.

    .EXAMPLE
    Get-NexusFleetStatus | Export-NexusFleetStatus -Path ./reports/fleet.txt -Format Csv

    Writes NexusInfra's view of all nodes as CSV to a file with another extension; the folder is created.

    .INPUTS
    NexusFleet.NodeStatus
    The statuses from Get-NexusFleetStatus.

    .OUTPUTS
    System.IO.FileInfo
    The written file.

    .NOTES
    Error id NexusFleet.UnknownExportFormat when the format cannot be told from the extension and -Format is not
    given. The file holds no secrets: a status has none.

    .LINK
    https://github.com/Tombomeke-Studios/NexusFleet/blob/dev/docs/user-guide.md#export-nexusfleetstatus

    .LINK
    about_NexusFleet

    .LINK
    Get-NexusFleetStatus
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSTypeName('NexusFleet.NodeStatus')]
        [pscustomobject[]]$InputObject,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [ValidateSet('Json', 'Csv')]
        [string]$Format
    )

    begin {
        $statuses = [System.Collections.Generic.List[object]]::new()
    }

    process {
        foreach ($item in $InputObject) {
            $statuses.Add($item)
        }
    }

    end {
        if (-not $Format) {
            $Format = switch ([System.IO.Path]::GetExtension($Path).ToLowerInvariant()) {
                '.json' { 'Json' }
                '.csv' { 'Csv' }
                default {
                    $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                            [System.ArgumentException]::new("Cannot tell the format from '$Path'; use a .json or .csv file, or -Format."),
                            'NexusFleet.UnknownExportFormat', 'InvalidArgument', $Path))
                }
            }
        }

        # Times as ISO-8601 UTC text: the same in every culture, and sortable.
        $rows = foreach ($status in $statuses) {
            $row = [ordered]@{}
            foreach ($property in $status.PSObject.Properties) {
                $row[$property.Name] = if ($property.Value -is [datetime]) { $property.Value.ToUniversalTime().ToString('o') } else { $property.Value }
            }
            [pscustomobject]$row
        }

        $fullPath = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($Path)
        if (-not $PSCmdlet.ShouldProcess($fullPath, "Write the status of $($statuses.Count) node(s) as $Format")) {
            return
        }
        $folder = Split-Path -Path $fullPath -Parent
        if ($folder -and -not (Test-Path -Path $folder)) {
            New-Item -Path $folder -ItemType Directory | Out-Null
        }

        if ($Format -eq 'Json') {
            $document = [ordered]@{ generatedAt = [datetime]::UtcNow.ToString('o'); nodes = @($rows) }
            $document | ConvertTo-Json -Depth 4 | Set-Content -Path $fullPath -Encoding utf8
        }
        else {
            @($rows) | Export-Csv -Path $fullPath -NoTypeInformation -Encoding utf8
        }
        Get-Item -Path $fullPath
    }
}
