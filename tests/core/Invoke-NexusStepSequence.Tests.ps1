[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester: variables set in BeforeAll/BeforeEach are used in It blocks and step script blocks; the analyzer does not look across script blocks.')]
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '',
    Justification = 'Fake steps follow the step contract (param($Context)) without needing the context; closure parameters are used inside GetNewClosure() script blocks, which the analyzer does not follow.')]
param()

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../src/utils/Initialize-NexusRunContext.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../src/utils/Write-NexusLog.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../src/core/Invoke-NexusStepSequence.ps1')

    # A fake step. $Done says whether its Test reports "already in order"; every call is written to $calls.
    function Get-FakeStep {
        param([string]$Name, [int]$Order, [bool]$Done = $false, [switch]$ApplyFails, [switch]$RollbackFails)
        $calls = $script:calls
        [pscustomobject]@{
            PSTypeName = 'NexusFleet.Step'
            Name       = $Name
            Order      = $Order
            Test       = { param($Context) $calls.Add("test:$Name"); $Done }.GetNewClosure()
            Apply      = { param($Context) $calls.Add("apply:$Name"); if ($ApplyFails) { throw "apply of $Name broke" } }.GetNewClosure()
            Rollback   = { param($Context) $calls.Add("rollback:$Name"); if ($RollbackFails) { throw "rollback of $Name broke" } }.GetNewClosure()
        }
    }
}

Describe 'Invoke-NexusStepSequence' {
    BeforeEach {
        $script:calls = [System.Collections.Generic.List[string]]::new()
    }

    It 'does nothing when every step is already in order (idempotent: a second run changes nothing)' {
        $steps = (Get-FakeStep -Name 'a' -Order 10 -Done $true), (Get-FakeStep -Name 'b' -Order 20 -Done $true)

        $result = Invoke-NexusStepSequence -HostName 'web01' -Step $steps -Context @{}

        $result.Success | Should -BeTrue
        $result.Steps.Outcome | Should -Be @('AlreadyDone', 'AlreadyDone')
        $script:calls | Should -Not -Contain 'apply:a'
        $script:calls | Should -Not -Contain 'apply:b'
    }

    It 'applies only the steps whose Test says they are missing, in Order' {
        $steps = (Get-FakeStep -Name 'c' -Order 30), (Get-FakeStep -Name 'a' -Order 10 -Done $true), (Get-FakeStep -Name 'b' -Order 20)

        $result = Invoke-NexusStepSequence -HostName 'web01' -Step $steps -Context @{}

        $result.PSObject.TypeNames | Should -Contain 'NexusFleet.StepRunResult'
        $result.Host | Should -Be 'web01'
        $result.Success | Should -BeTrue
        $result.Steps.Step | Should -Be @('a', 'b', 'c')
        $result.Steps.Outcome | Should -Be @('AlreadyDone', 'Applied', 'Applied')
        $script:calls -join ' ' | Should -Be 'test:a test:b apply:b test:c apply:c'
    }

    It 'returns only the result object, even when a step writes output' {
        $chatty = Get-FakeStep -Name 'a' -Order 10
        $chatty.Apply = { param($Context) 'output of apply' }
        $chatty.Rollback = { param($Context) 'output of rollback' }
        $broken = Get-FakeStep -Name 'b' -Order 20 -ApplyFails

        $output = @(Invoke-NexusStepSequence -HostName 'web01' -Step $chatty, $broken -Context @{})

        $output | Should -HaveCount 1
        $output[0].PSObject.TypeNames | Should -Contain 'NexusFleet.StepRunResult'
    }

    It 'passes the context to Test, Apply and Rollback' {
        $seen = [System.Collections.Generic.List[string]]::new()
        $step = [pscustomobject]@{
            PSTypeName = 'NexusFleet.Step'
            Name       = 'ctx'
            Order      = 10
            Test       = { param($Context) $seen.Add("test:$($Context.HostName)"); $false }.GetNewClosure()
            Apply      = { param($Context) $seen.Add("apply:$($Context.HostName)"); throw 'stop' }.GetNewClosure()
            Rollback   = { param($Context) $seen.Add("rollback:$($Context.HostName)") }.GetNewClosure()
        }

        $null = Invoke-NexusStepSequence -HostName 'web01' -Step $step -Context @{ HostName = 'web01' }

        $seen | Should -Be @('test:web01', 'apply:web01', 'rollback:web01')
    }

    It 'rolls back the failed step and the steps it applied, in reverse order, and not what was already there' {
        $steps = (Get-FakeStep -Name 'a' -Order 10 -Done $true), (Get-FakeStep -Name 'b' -Order 20),
        (Get-FakeStep -Name 'c' -Order 30 -ApplyFails), (Get-FakeStep -Name 'd' -Order 40)

        $result = Invoke-NexusStepSequence -HostName 'web01' -Step $steps -Context @{}

        $result.Success | Should -BeFalse
        $result.Step | Should -Be 'c'
        $result.Error | Should -Match 'apply of c broke'
        $result.Steps.Outcome | Should -Be @('AlreadyDone', 'Applied', 'Failed', 'NotRun')
        $result.Steps.Rollback | Should -Be @($null, 'Done', 'Done', $null)
        $script:calls -join ' ' | Should -Be 'test:a test:b apply:b test:c apply:c rollback:c rollback:b'
    }

    It 'keeps rolling back the other steps when one rollback fails, and reports it' {
        $steps = (Get-FakeStep -Name 'a' -Order 10), (Get-FakeStep -Name 'b' -Order 20 -RollbackFails), (Get-FakeStep -Name 'c' -Order 30 -ApplyFails)

        $result = Invoke-NexusStepSequence -HostName 'web01' -Step $steps -Context @{}

        $result.Steps.Rollback | Should -Be @('Done', 'Failed', 'Done')
        $result.Steps[1].Error | Should -Match 'rollback of b broke'
        $script:calls | Should -Contain 'rollback:a'
    }

    It 'keeps why the Apply failed when the rollback of that step fails too (#118)' {
        $steps = (Get-FakeStep -Name 'a' -Order 10), (Get-FakeStep -Name 'b' -Order 20 -ApplyFails -RollbackFails)

        $result = Invoke-NexusStepSequence -HostName 'web01' -Step $steps -Context @{}

        $result.Steps[1].Outcome | Should -Be 'Failed'
        $result.Steps[1].Rollback | Should -Be 'Failed'
        $result.Steps[1].Error | Should -BeLike "Apply of step 'b' failed*; Rollback of step 'b' failed*rollback of b broke*"
    }

    It 'treats a Test that throws as a failure and rolls back what was applied' {
        $broken = Get-FakeStep -Name 'b' -Order 20
        $broken.Test = { param($Context) throw 'cannot check' }

        $result = Invoke-NexusStepSequence -HostName 'web01' -Step (Get-FakeStep -Name 'a' -Order 10), $broken -Context @{}

        $result.Success | Should -BeFalse
        $result.Step | Should -Be 'b'
        $result.Error | Should -Match 'cannot check'
        $script:calls | Should -Contain 'rollback:a'
    }

    It 'refuses a Test that does not answer $true or $false' {
        $vague = Get-FakeStep -Name 'a' -Order 10
        $vague.Test = { param($Context) 'yes' }

        $result = Invoke-NexusStepSequence -HostName 'web01' -Step $vague -Context @{}

        $result.Success | Should -BeFalse
        $result.Error | Should -Match 'Test of step ''a'' must return \$true or \$false'
    }

    Context 'plan only (dry run)' {
        It 'runs every Test, never Apply, and returns the plan' {
            $steps = (Get-FakeStep -Name 'a' -Order 10 -Done $true), (Get-FakeStep -Name 'b' -Order 20), (Get-FakeStep -Name 'c' -Order 30)

            $result = Invoke-NexusStepSequence -HostName 'web01' -Step $steps -Context @{} -PlanOnly

            $result.PlanOnly | Should -BeTrue
            $result.Success | Should -BeTrue
            $result.Steps.Outcome | Should -Be @('AlreadyDone', 'WouldApply', 'WouldApply')
            ($script:calls | Where-Object { $_ -like 'apply:*' }) | Should -BeNullOrEmpty
        }
    }

    Context 'what a Test found (Detail)' {
        It 'puts the detail a Test left in State on that step only, in a plan and in a real run' {
            $explains = Get-FakeStep -Name 'a' -Order 10
            $explains.Test = { param($Context) $Context.State.Detail = 'the label differs'; $false }
            $silent = Get-FakeStep -Name 'b' -Order 20

            $plan = Invoke-NexusStepSequence -HostName 'web01' -Step $explains, $silent -Context @{ State = @{} } -PlanOnly
            $real = Invoke-NexusStepSequence -HostName 'web01' -Step $explains, $silent -Context @{ State = @{} }

            $plan.Steps.Detail | Should -Be @('the label differs', $null)
            $real.Steps.Detail | Should -Be @('the label differs', $null)
        }
    }

    Context 'logging' {
        It 'writes one line per step to the host''s log when a run context is given' {
            $runContext = Initialize-NexusRunContext -LogRoot $TestDrive
            $steps = (Get-FakeStep -Name 'a' -Order 10 -Done $true), (Get-FakeStep -Name 'b' -Order 20 -ApplyFails)

            $null = Invoke-NexusStepSequence -HostName 'web01' -Step $steps -Context @{} -RunContext $runContext

            # One string with all lines, so each -Match looks at the whole log.
            $log = (Get-Content -Path (Join-Path -Path $runContext.LogDirectory -ChildPath 'web01.log')) -join "`n"
            $log | Should -Match 'step=a .*already in order'
            $log | Should -Match 'ERROR .*step=b .*apply of b broke'
            $log | Should -Match 'step=b .*rolled back'
        }
    }
}
