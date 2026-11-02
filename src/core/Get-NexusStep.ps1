function Get-NexusStep {
    <#
    .SYNOPSIS
    Returns the registered installation steps, sorted by Order.

    .DESCRIPTION
    The steps registered by the files in src/steps/ (see Register-NexusStep), in the order they run.

    .EXAMPLE
    Get-NexusStep | Select-Object Order, Name, Description
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $script:NexusStepRegistry.Values | Sort-Object -Property Order
}
