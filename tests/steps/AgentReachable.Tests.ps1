[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester: variables set in BeforeAll/BeforeEach are used in It blocks and mocks; the analyzer does not look across script blocks.')]
param()

BeforeAll {
    $module = Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../../NexusFleet.psd1') -Force -PassThru
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestStepContext.ps1')
    $step = & $module { Get-NexusStep } | Where-Object Name -EQ 'AgentReachable'
}

AfterAll {
    Remove-Module -Name NexusFleet -Force -ErrorAction SilentlyContinue
}

Describe 'Step AgentReachable' {
    BeforeEach {
        $context = Get-TestStepContext -Module $module
    }

    It 'runs last (Order 50), after the node is healthy' {
        $step.Order | Should -Be 50
        (& $module { Get-NexusStep } | Select-Object -Last 1).Name | Should -Be 'AgentReachable'
    }

    Context 'Test' {
        It 'is in order when NexusInfra reaches the agent (GET /nodes/<id>/disk answers)' {
            Mock -ModuleName NexusFleet -CommandName Invoke-NexusApi -MockWith { [pscustomobject]@{ measuredAt = '2026-11-04T10:00:00Z'; deployments = @() } }

            & $step.Test $context | Should -BeTrue
            Should -Invoke -ModuleName NexusFleet -CommandName Invoke-NexusApi -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'GET' -and $Path -eq '/nodes/node-web01/disk'
            }
        }

        It 'is not in order when NexusInfra cannot reach the agent (502), even though the node is healthy' {
            # Heartbeats go from the node to the broker; this call goes the other way, like deploying does.
            Mock -ModuleName NexusFleet -CommandName Invoke-NexusApi -MockWith { throw 'NexusInfra API GET /nodes/node-web01/disk failed 502: ... NexusInfra says: fetch failed' }

            & $step.Test $context | Should -BeFalse
        }
    }

    Context 'Apply' {
        It 'changes nothing and succeeds when the agent is reachable now' {
            Mock -ModuleName NexusFleet -CommandName Invoke-NexusApi -MockWith { [pscustomobject]@{ deployments = @() } }
            Mock -ModuleName NexusFleet -CommandName Invoke-NexusHostCommand -MockWith { }

            { & $step.Apply $context } | Should -Not -Throw
            Should -Invoke -ModuleName NexusFleet -CommandName Invoke-NexusHostCommand -Times 0 -Exactly
        }

        It 'fails with the agentUrl, NexusInfra''s reason and what to check' {
            Mock -ModuleName NexusFleet -CommandName Invoke-NexusApi -MockWith { throw 'NexusInfra says: the node answered 401' }

            { & $step.Apply $context } | Should -Throw -ExpectedMessage "*cannot reach the agent of node-web01 at $($context.HostInfo.AgentUrl)*the node answered 401*port 9100*INTERNAL_API_TOKEN*"
        }

        It 'points an outbound host at its agent link, not at a port (#114)' {
            $context = Get-TestStepContext -Module $module -Outbound
            Mock -ModuleName NexusFleet -CommandName Invoke-NexusApi -MockWith { throw 'NexusInfra says: the node has no agent link' }

            $message = { & $step.Apply $context } | Should -Throw -PassThru | ForEach-Object { $_.Exception.Message }
            $message | Should -BeLike "*cannot reach the agent of node-web01 over its agent link*no agent link*wss://nexus.example.com/agent-link*"
            $message | Should -Not -BeLike '*port forwarding*'
        }
    }
}
