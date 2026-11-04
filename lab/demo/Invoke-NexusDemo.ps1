<#
.SYNOPSIS
Runs the NexusFleet demo on an inventory and measures it: preflight, dry run, install, second run, status.

.DESCRIPTION
The demo of phase 4, for the lab VMs (see README.md in this folder) and the node lab alike. Needs a connection
(Connect-NexusInfra) and the agent's secrets in SecretManagement (or -RabbitMqUrl / -InternalApiToken).
  1. Test-NexusHost             preflight of every host
  2. Install-NexusNode -WhatIf  the plan
  3. Install-NexusNode          the installation, timed
  4. Install-NexusNode          the second run, timed: must change nothing
  5. Get-NexusFleetStatus       the status, also exported to status.json and status.csv
Then it checks the three "Klaar als" criteria (CLAUDE.md, section 9) on the results and writes everything to
<OutputPath>/<time>/: measurements.json, summary.md, the exports, and the results of every phase (results.json).
Put one host in the inventory that cannot work (a wrong port) to show criterion 3.

.PARAMETER InventoryPath
The inventory of the demo hosts.

.PARAMETER OutputPath
Where the results go. Default: lab/demo/results/ (git-ignored).

.PARAMETER RabbitMqUrl
Passed to Install-NexusNode; default: from SecretManagement.

.PARAMETER InternalApiToken
Passed to Install-NexusNode; default: from SecretManagement.

.PARAMETER ThrottleLimit
Hosts at the same time. Default: the config.

.EXAMPLE
Connect-NexusInfra
./lab/demo/Invoke-NexusDemo.ps1 -InventoryPath ./config/inventory.json
#>
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'A demo script: the person watching sees each phase; the results are returned as objects and files.')]
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -Path $_ -PathType Leaf })]
    [string]$InventoryPath,

    [string]$OutputPath = (Join-Path -Path $PSScriptRoot -ChildPath 'results'),

    [securestring]$RabbitMqUrl,

    [securestring]$InternalApiToken,

    [ValidateRange(1, 256)]
    [int]$ThrottleLimit
)

$ErrorActionPreference = 'Stop'
if (-not (Get-Module -Name NexusFleet)) {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../../NexusFleet.psd1')
}
$folder = (New-Item -Path (Join-Path -Path $OutputPath -ChildPath ([datetime]::UtcNow.ToString('yyyyMMddTHHmmssZ'))) -ItemType Directory).FullName

$installArgs = @{}
if ($RabbitMqUrl) { $installArgs.RabbitMqUrl = $RabbitMqUrl }
if ($InternalApiToken) { $installArgs.InternalApiToken = $InternalApiToken }
if ($ThrottleLimit) { $installArgs.ThrottleLimit = $ThrottleLimit }
$parallel = @{}
if ($ThrottleLimit) { $parallel.ThrottleLimit = $ThrottleLimit }

# Runs one phase, times it, and tells the person watching what happened.
$phases = [System.Collections.Generic.List[object]]::new()
$timed = {
    param([string]$Name, [scriptblock]$Work)
    Write-Host "`n== $Name" -ForegroundColor Cyan
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $output = @(& $Work)
    $clock.Stop()
    $phases.Add([pscustomobject]@{ Phase = $Name; Seconds = [math]::Round($clock.Elapsed.TotalSeconds, 1); Results = $output })
    Write-Host ("   {0:n1} s" -f $clock.Elapsed.TotalSeconds)
    $output
}

$hosts = @(Import-NexusInventory -Path $InventoryPath)
Write-Host "Demo on $($hosts.Count) host(s) from $InventoryPath"

$preflight = & $timed 'Preflight (Test-NexusHost)' { $hosts | Test-NexusHost @parallel }
$preflight | Format-Table Host, Success, Step, Error -AutoSize | Out-Host

$plan = & $timed 'Plan (Install-NexusNode -WhatIf)' { $hosts | Install-NexusNode @parallel -WhatIf }
$plan | ForEach-Object { [pscustomobject]@{ Host = $_.Host; Plan = (($_.Steps | ForEach-Object { "$($_.Step)=$($_.Outcome)" }) -join ', ') } } |
    Format-Table -AutoSize | Out-Host

$first = & $timed 'Install (Install-NexusNode)' { $hosts | Install-NexusNode @installArgs }
$first | Format-Table Host, Success, Changed, Step, Error -AutoSize | Out-Host

$second = & $timed 'Second run (Install-NexusNode)' { $hosts | Install-NexusNode @installArgs }
$second | Format-Table Host, Success, Changed, Step, Error -AutoSize | Out-Host

$status = & $timed 'Status (Get-NexusFleetStatus)' { $hosts | Get-NexusFleetStatus @parallel }
$status | Format-Table Name, Ok, Health, AgentState, Problem -AutoSize | Out-Host
$null = $status | Export-NexusFleetStatus -Path (Join-Path -Path $folder -ChildPath 'status.json')
$null = $status | Export-NexusFleetStatus -Path (Join-Path -Path $folder -ChildPath 'status.csv')

# The three criteria, on the results. Hosts that failed the first run are the "failing host" of criterion 3.
$succeeded = @($first | Where-Object Success)
$failed = @($first | Where-Object { -not $_.Success })
$healthy = @($status | Where-Object { $_.Health -eq 'healthy' }).Name
$criteria = @(
    [pscustomobject]@{
        Criterion = '1. one command turns the hosts into healthy nodes'
        Holds     = $succeeded.Count -gt 0 -and @($succeeded.Host | Where-Object { $_ -notin $healthy }).Count -eq 0
        Detail    = "$($succeeded.Count) of $($hosts.Count) host(s) installed; healthy now: $($healthy -join ', ')"
    }
    [pscustomobject]@{
        Criterion = '2. a second run changes nothing'
        Holds     = @($second | Where-Object { $_.Success -and $_.Changed }).Count -eq 0 -and
        @($second | Where-Object Host -In $succeeded.Host | Where-Object { -not $_.Success }).Count -eq 0
        Detail    = "changed in the second run: $(@($second | Where-Object Changed).Host -join ', ')"
    }
    [pscustomobject]@{
        Criterion = '3. one failing host does not stop the others'
        Holds     = if ($failed.Count -eq 0) { $null } else { $succeeded.Count -gt 0 -and $first.Count -eq $hosts.Count }
        Detail    = if ($failed.Count -eq 0) { 'no host failed in this run; add a broken host to the inventory to show it' }
        else { "failed on their own: $(($failed | ForEach-Object { "$($_.Host) ($($_.Step))" }) -join ', ')" }
    }
)
Write-Host "`n== Klaar als" -ForegroundColor Cyan
$criteria | Format-Table -AutoSize -Wrap | Out-Host

$measurements = [ordered]@{
    generatedAt = [datetime]::UtcNow.ToString('o')
    inventory   = (Resolve-Path -Path $InventoryPath).Path
    hosts       = $hosts.Count
    phases      = @($phases | Select-Object Phase, Seconds)
    criteria    = @($criteria)
}
$measurements | ConvertTo-Json -Depth 4 | Set-Content -Path (Join-Path -Path $folder -ChildPath 'measurements.json')
[ordered]@{ preflight = $preflight; plan = $plan; first = $first; second = $second } |
    ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path -Path $folder -ChildPath 'results.json')

$summary = @(
    "# NexusFleet demo, $($measurements.generatedAt)"
    ''
    "$($hosts.Count) host(s) from ``$InventoryPath``."
    ''
    '| Phase | Seconds |'
    '|---|---|'
    ($phases | ForEach-Object { "| $($_.Phase) | $($_.Seconds) |" })
    ''
    '| Klaar als | Holds | Detail |'
    '|---|---|---|'
    ($criteria | ForEach-Object { "| $($_.Criterion) | $(if ($null -eq $_.Holds) { 'not shown' } else { $_.Holds }) | $($_.Detail) |" })
)
Set-Content -Path (Join-Path -Path $folder -ChildPath 'summary.md') -Value $summary
Write-Host "Results: $folder"

[pscustomobject]@{
    Folder   = $folder
    Phases   = @($phases | Select-Object Phase, Seconds)
    Criteria = $criteria
}
