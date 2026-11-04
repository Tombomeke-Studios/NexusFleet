[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester: variables set in BeforeAll/BeforeEach are used in It blocks and mocks; the analyzer does not look across script blocks.')]
param()

BeforeAll {
    $module = Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../../NexusFleet.psd1') -Force -PassThru
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestStepContext.ps1')
    $step = & $module { Get-NexusStep } | Where-Object Name -EQ 'VerifyHealthy'
    function Get-TestNode { param([string]$Health) [pscustomobject]@{ id = 'node-web01'; name = 'node-web01'; health = $Health } }
}

AfterAll {
    Remove-Module -Name NexusFleet -Force -ErrorAction SilentlyContinue
}

Describe 'Step VerifyHealthy' {
    BeforeEach {
        $context = Get-TestStepContext -Module $module
        $context.Config.Health.VerifyTimeoutSeconds = 10
        $context.Config.Health.PollIntervalSeconds = 2
        Mock -ModuleName NexusFleet -CommandName Start-Sleep -MockWith { }
    }

    It 'runs last (Order 40)' {
        $step.Order | Should -Be 40
        (& $module { Get-NexusStep } | Select-Object -Last 1).Name | Should -Be 'VerifyHealthy'
    }

    Context 'Test' {
        It 'is in order when NexusInfra reports the node healthy' {
            Mock -ModuleName NexusFleet -CommandName Invoke-NexusApi -MockWith { Get-TestNode -Health 'healthy' }

            & $step.Test $context | Should -BeTrue
        }

        It 'is not in order when the node is <Health>' -ForEach @(@{ Health = 'degraded' }, @{ Health = 'offline' }) {
            Mock -ModuleName NexusFleet -CommandName Invoke-NexusApi -MockWith { Get-TestNode -Health $Health }

            & $step.Test $context | Should -BeFalse
        }

        It 'is not in order when the node is not registered' {
            Mock -ModuleName NexusFleet -CommandName Invoke-NexusApi -MockWith { @() }

            & $step.Test $context | Should -BeFalse
        }
    }

    Context 'Apply' {
        It 'polls GET /nodes until the node is healthy, pausing PollIntervalSeconds between checks' {
            $answers = [System.Collections.Generic.Queue[string]]::new([string[]]@('offline', 'degraded', 'healthy'))
            Mock -ModuleName NexusFleet -CommandName Invoke-NexusApi -MockWith { Get-TestNode -Health $answers.Dequeue() }

            & $step.Apply $context

            Should -Invoke -ModuleName NexusFleet -CommandName Invoke-NexusApi -Times 3 -Exactly
            Should -Invoke -ModuleName NexusFleet -CommandName Start-Sleep -Times 2 -Exactly -ParameterFilter { $Seconds -eq 2 }
        }

        It 'gives up after VerifyTimeoutSeconds / PollIntervalSeconds checks, with the last health and a hint' {
            Mock -ModuleName NexusFleet -CommandName Invoke-NexusApi -MockWith { Get-TestNode -Health 'offline' }

            { & $step.Apply $context } | Should -Throw '*node-web01 did not become healthy within 10 s (last health: offline)*docker logs nexusinfra-node-agent*'
            Should -Invoke -ModuleName NexusFleet -CommandName Invoke-NexusApi -Times 5 -Exactly
            Should -Invoke -ModuleName NexusFleet -CommandName Start-Sleep -Times 4 -Exactly
        }

        It 'says when the node never showed up' {
            Mock -ModuleName NexusFleet -CommandName Invoke-NexusApi -MockWith { @() }

            { & $step.Apply $context } | Should -Throw '*last health: not registered*'
        }
    }
}
