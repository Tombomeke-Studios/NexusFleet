# Mini-module for experiment E3. It copies the NexusFleet pattern: the work for one host lives in
# its own function, and the fleet function is a thin wrapper that runs it per host.
# No Export-ModuleMember: without it every function is exported, and it triggers the
# PSScriptAnalyzer race described in docs/ontwerpkeuzes.md (K2).

function Get-DemoAnswer {
    <#
    .SYNOPSIS
    Stands in for anything that touches the outside world (SSH, REST API). Tests mock this.
    #>
    param([string]$Name)
    "real:$Name"
}

function Invoke-DemoHostWork {
    <#
    .SYNOPSIS
    The work for one host.
    #>
    param([string]$Name)
    Get-DemoAnswer -Name $Name
}

function Invoke-DemoFleetWorkSequential {
    <#
    .SYNOPSIS
    Thin wrapper: one host after the other, in the current runspace.
    #>
    param([string[]]$Name)
    $Name | ForEach-Object { Invoke-DemoHostWork -Name $_ }
}

function Invoke-DemoFleetWorkParallel {
    <#
    .SYNOPSIS
    Thin wrapper: hosts in parallel. Each runspace starts empty, so it imports this module by path.
    #>
    param([string[]]$Name, [int]$ThrottleLimit = 4)
    $modulePath = $PSCommandPath
    $Name | ForEach-Object -Parallel {
        Import-Module -Name $using:modulePath
        Invoke-DemoHostWork -Name $_
    } -ThrottleLimit $ThrottleLimit
}
