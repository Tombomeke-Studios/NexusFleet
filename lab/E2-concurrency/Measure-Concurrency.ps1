<#
.SYNOPSIS
Experiment E2: compares ForEach-Object -Parallel, Start-ThreadJob and Start-Job (and a sequential baseline).

.DESCRIPTION
Every target gets the same simulated work: a sleep that stands in for waiting on SSH, plus a small
CPU loop. Each measurement runs in a fresh pwsh process, so the memory of one run never leaks into
the next. The script calls itself with -Method for every single measurement.

Memory is the peak working set of the measuring process. For Start-Job the child processes are
sampled every 100 ms while the jobs run, and their largest total is added.

.EXAMPLE
./lab/E2-concurrency/Measure-Concurrency.ps1
Runs all methods for 10 and 50 targets, three times each, and prints a summary table.

.EXAMPLE
./lab/E2-concurrency/Measure-Concurrency.ps1 -TargetCount 100 -Repeat 1
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 1000)]
    [int[]]$TargetCount = @(10, 50),

    [ValidateRange(0, 60000)]
    [int]$WorkMilliseconds = 500,

    [ValidateRange(1, 256)]
    [int]$ThrottleLimit = 10,

    [ValidateRange(1, 20)]
    [int]$Repeat = 3,

    # Internal: when set, run one measurement and print it as JSON.
    [ValidateSet('Sequential', 'ForEachParallel', 'ThreadJob', 'Job')]
    [string]$Method
)

if ($Method) {
    $count = $TargetCount[0]
    $self = [System.Diagnostics.Process]::GetCurrentProcess()
    $pwshBefore = @(Get-Process -Name pwsh).Id
    $childPeakBytes = 0
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    switch ($Method) {
        'Sequential' {
            $null = 1..$count | ForEach-Object {
                Start-Sleep -Milliseconds $WorkMilliseconds
                $sum = 0; foreach ($i in 1..20000) { $sum += $i }
                $sum
            }
        }
        'ForEachParallel' {
            $null = 1..$count | ForEach-Object -Parallel {
                Start-Sleep -Milliseconds $using:WorkMilliseconds
                $sum = 0; foreach ($i in 1..20000) { $sum += $i }
                $sum
            } -ThrottleLimit $ThrottleLimit
        }
        'ThreadJob' {
            $jobs = 1..$count | ForEach-Object {
                Start-ThreadJob -ThrottleLimit $ThrottleLimit -ScriptBlock {
                    Start-Sleep -Milliseconds $using:WorkMilliseconds
                    $sum = 0; foreach ($i in 1..20000) { $sum += $i }
                    $sum
                }
            }
            $null = $jobs | Wait-Job | Receive-Job
            $jobs | Remove-Job
        }
        'Job' {
            # Start-Job has no throttle: every job is its own pwsh process, all started at once.
            $jobs = 1..$count | ForEach-Object {
                Start-Job -ScriptBlock {
                    Start-Sleep -Milliseconds $using:WorkMilliseconds
                    $sum = 0; foreach ($i in 1..20000) { $sum += $i }
                    $sum
                }
            }
            while ($jobs.State -contains 'Running' -or $jobs.State -contains 'NotStarted') {
                $children = Get-Process -Name pwsh | Where-Object { $_.Id -notin $pwshBefore -and $_.Id -ne $self.Id }
                $childBytes = ($children | Measure-Object -Property WorkingSet64 -Sum).Sum
                if ($childBytes -gt $childPeakBytes) { $childPeakBytes = $childBytes }
                Start-Sleep -Milliseconds 100
            }
            $null = $jobs | Receive-Job
            $jobs | Remove-Job
        }
    }

    $stopwatch.Stop()
    $self.Refresh()
    [pscustomobject]@{
        Method   = $Method
        Targets  = $count
        Seconds  = [math]::Round($stopwatch.Elapsed.TotalSeconds, 2)
        MemoryMB = [math]::Round(($self.PeakWorkingSet64 + $childPeakBytes) / 1MB)
    } | ConvertTo-Json -Compress
    return
}

$methods = 'Sequential', 'ForEachParallel', 'ThreadJob', 'Job'
$runs = foreach ($count in $TargetCount) {
    foreach ($name in $methods) {
        foreach ($round in 1..$Repeat) {
            Write-Verbose "Measuring $name with $count targets (round $round of $Repeat)"
            $json = pwsh -NoProfile -File $PSCommandPath -Method $name -TargetCount $count `
                -WorkMilliseconds $WorkMilliseconds -ThrottleLimit $ThrottleLimit
            $json | ConvertFrom-Json
        }
    }
}

# One line per method and target count: the median of the rounds.
$runs | Group-Object -Property Method, Targets | ForEach-Object {
    $seconds = @($_.Group.Seconds | Sort-Object)
    $memory = @($_.Group.MemoryMB | Sort-Object)
    [pscustomobject]@{
        Method         = $_.Group[0].Method
        Targets        = $_.Group[0].Targets
        ThrottleLimit  = $ThrottleLimit
        MedianSeconds  = $seconds[[math]::Floor($seconds.Count / 2)]
        MedianMemoryMB = $memory[[math]::Floor($memory.Count / 2)]
        Rounds         = $_.Count
    }
}
