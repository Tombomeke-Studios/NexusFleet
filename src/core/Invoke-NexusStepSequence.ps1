function Invoke-NexusStepSequence {
    <#
    .SYNOPSIS
    Runs the installation steps for one host: applies what is missing, rolls back on failure.

    .DESCRIPTION
    For each step, in Order:
      1. Test. $true means the host is already in order for this step: nothing to do (AlreadyDone).
      2. Otherwise Apply (Applied), or with -PlanOnly only note that it would be applied (WouldApply).
    When a Test or Apply fails, the run stops there. The failed step and every step this run applied are
    rolled back, in reverse order. Steps that were already in order are left alone: NexusFleet does not
    undo what it did not do. Steps after the failure are NotRun.

    -PlanOnly is the dry run: only Test runs. It is a switch and not ShouldProcess, because this function
    also runs inside ForEach-Object -Parallel, where ShouldProcess is not available; the public cmdlet
    turns its own -WhatIf into -PlanOnly.

    Returns one NexusFleet.StepRunResult: Host, Success, PlanOnly, Step (the failed step), Error, and Steps
    (per step: Step, Outcome, Rollback, Error).

    .PARAMETER HostName
    The host, for the result and the log.

    .PARAMETER Step
    The steps to run (see Get-NexusStep). They are sorted by Order here.

    .PARAMETER Context
    Passed to every Test, Apply and Rollback script block (host, config, transport settings).

    .PARAMETER PlanOnly
    Only run Test and return the plan.

    .PARAMETER RunContext
    Optional run context (Initialize-NexusRunContext): then every step outcome is logged for this host.

    .EXAMPLE
    Invoke-NexusStepSequence -HostName 'web01' -Step (Get-NexusStep) -Context $stepContext -RunContext $run
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$HostName,

        [Parameter(Mandatory)]
        [PSTypeName('NexusFleet.Step')]
        [pscustomobject[]]$Step,

        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$Context,

        [switch]$PlanOnly,

        [PSTypeName('NexusFleet.RunContext')]
        [pscustomobject]$RunContext
    )

    # Logs only when a run context was given. The run context is passed in explicitly, so it is clear
    # (also to PSScriptAnalyzer) where it is used.
    $log = {
        param($Run, [string]$StepName, [string]$Message, [string]$Level = 'Info')
        if ($Run) {
            Write-NexusLog -Context $Run -HostName $HostName -Step $StepName -Level $Level -Message $Message
        }
    }

    $ordered = @($Step | Sort-Object -Property Order)
    $outcomes = foreach ($item in $ordered) {
        [pscustomobject]@{ Step = $item.Name; Outcome = 'NotRun'; Detail = $null; Rollback = $null; Error = $null }
    }
    $failedIndex = -1
    $failedPhase = $null
    $failure = $null

    for ($i = 0; $i -lt $ordered.Count; $i++) {
        $current = $ordered[$i]
        $phase = 'Test'
        try {
            $answer = & $current.Test $Context
            if ($answer -isnot [bool]) {
                throw "Test of step '$($current.Name)' must return `$true or `$false, not '$answer'."
            }
            if ($answer) {
                $outcomes[$i].Outcome = 'AlreadyDone'
                & $log $RunContext $current.Name 'already in order, nothing to do'
                continue
            }
            # A Test may say what is not in order (State.Detail), for the plan and for Sync-NexusFleet.
            if ($Context.State -and $Context.State.Detail) {
                $outcomes[$i].Detail = $Context.State.Detail
                $Context.State.Remove('Detail')
            }
            if ($PlanOnly) {
                $outcomes[$i].Outcome = 'WouldApply'
                & $log $RunContext $current.Name 'would apply (plan only)'
                continue
            }
            $phase = 'Apply'
            # $null = : output of a step must not end up next to the result object.
            $null = & $current.Apply $Context
            $outcomes[$i].Outcome = 'Applied'
            & $log $RunContext $current.Name 'applied'
        }
        catch {
            $failedIndex = $i
            $failedPhase = $phase
            $failure = "$phase of step '$($current.Name)' failed: $($_.Exception.Message)"
            $outcomes[$i].Outcome = 'Failed'
            $outcomes[$i].Error = $failure
            & $log $RunContext $current.Name $failure 'Error'
            break
        }
    }

    # Roll back the failed step (its Apply may have half happened) and every step this run applied.
    if ($failedIndex -ge 0 -and -not $PlanOnly) {
        for ($i = $failedIndex; $i -ge 0; $i--) {
            # The failed step only when its Apply started (a failed Test changed nothing).
            $wasTouched = ($i -eq $failedIndex -and $failedPhase -eq 'Apply') -or $outcomes[$i].Outcome -eq 'Applied'
            if (-not $wasTouched) {
                continue
            }
            try {
                $null = & $ordered[$i].Rollback $Context
                $outcomes[$i].Rollback = 'Done'
                & $log $RunContext $ordered[$i].Name 'rolled back'
            }
            catch {
                # Keep rolling back the other steps; report this one. The failed step already has an error (why its
                # Apply failed): the rollback's error is added to it, so neither is lost.
                $outcomes[$i].Rollback = 'Failed'
                $rollbackError = "Rollback of step '$($ordered[$i].Name)' failed: $($_.Exception.Message)"
                $outcomes[$i].Error = (@($outcomes[$i].Error, $rollbackError) | Where-Object { $_ }) -join '; '
                & $log $RunContext $ordered[$i].Name $rollbackError 'Error'
            }
        }
    }

    [pscustomobject]@{
        PSTypeName = 'NexusFleet.StepRunResult'
        Host       = $HostName
        Success    = $failedIndex -lt 0
        PlanOnly   = [bool]$PlanOnly
        Step       = if ($failedIndex -ge 0) { $ordered[$failedIndex].Name } else { $null }
        Error      = $failure
        Steps      = @($outcomes)
    }
}
