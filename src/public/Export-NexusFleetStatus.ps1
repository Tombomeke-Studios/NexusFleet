function Export-NexusFleetStatus {
    <#
    .SYNOPSIS
    Writes the fleet status from Get-NexusFleetStatus to a JSON or CSV file.

    .DESCRIPTION
    Collects the NexusFleet.NodeStatus objects from the pipeline and writes them in one go:
      JSON  { "generatedAt": "<UTC time>", "nodes": [ ... ] }, every field of every node
      CSV   one row per node, a header with the field names; times as ISO-8601 UTC, so a spreadsheet sorts them
    The format comes from -Format, or else from the extension of -Path (.json or .csv). An existing file is
    replaced. Returns the file.

    .PARAMETER InputObject
    The status objects, through the pipeline.

    .PARAMETER Path
    The file to write.

    .PARAMETER Format
    Json or Csv. Default: from the extension of -Path.

    .EXAMPLE
    Import-NexusInventory ./config/inventory.json | Get-NexusFleetStatus | Export-NexusFleetStatus -Path ./status.json

    .EXAMPLE
    Get-NexusFleetStatus | Export-NexusFleetStatus -Path ./reports/fleet.txt -Format Csv

    .OUTPUTS
    System.IO.FileInfo: the written file.
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
