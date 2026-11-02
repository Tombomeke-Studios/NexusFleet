# The step registry: every file in src/steps/ calls Register-NexusStep once when the module loads.
# The loader loads src/core before src/steps, so this function exists by then.
$script:NexusStepRegistry = @{}

function Register-NexusStep {
    <#
    .SYNOPSIS
    Registers one installation step: its name, its place in the order, and its Test / Apply / Rollback.

    .DESCRIPTION
    The step contract. Each step answers three questions about one host, each a script block that gets
    the step context (host, config, transport settings) as its only argument:
      Test     is the host already in the desired state for this step?  Must return $true or $false.
      Apply    bring the host into that state.
      Rollback undo what Apply did. Must be safe to run when Apply only half succeeded.
    Adding a step is adding a file in src/steps/ that calls this function; nothing else changes.

    .PARAMETER Name
    A short, unique name (letters, digits, dashes), e.g. Docker.

    .PARAMETER Order
    Where the step runs: lower first. Unique, so the order is never ambiguous. Leave gaps (10, 20, 30)
    so a step can be put in between later.

    .PARAMETER Description
    One line for logs and plans.

    .PARAMETER Test
    Returns $true when nothing needs to be done.

    .PARAMETER Apply
    Makes the change.

    .PARAMETER Rollback
    Undoes the change. Default: nothing to undo.

    .EXAMPLE
    Register-NexusStep -Name 'Docker' -Order 10 -Description 'Install Docker Engine' `
        -Test { param($Context) ... } -Apply { param($Context) ... } -Rollback { param($Context) ... }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z][A-Za-z0-9-]*$')]
        [string]$Name,

        [Parameter(Mandatory)]
        [ValidateRange(1, 10000)]
        [int]$Order,

        [string]$Description = '',

        [Parameter(Mandatory)]
        [scriptblock]$Test,

        [Parameter(Mandatory)]
        [scriptblock]$Apply,

        [scriptblock]$Rollback = { }
    )

    if ($script:NexusStepRegistry.ContainsKey($Name)) {
        throw "Step '$Name' is already registered; step names must be unique."
    }
    $sameOrder = $script:NexusStepRegistry.Values | Where-Object { $_.Order -eq $Order }
    if ($sameOrder) {
        throw "Step '$Name' uses Order $Order, which step '$($sameOrder.Name)' already has; give each step its own Order."
    }

    $script:NexusStepRegistry[$Name] = [pscustomobject]@{
        PSTypeName  = 'NexusFleet.Step'
        Name        = $Name
        Order       = $Order
        Description = $Description
        Test        = $Test
        Apply       = $Apply
        Rollback    = $Rollback
    }
}
