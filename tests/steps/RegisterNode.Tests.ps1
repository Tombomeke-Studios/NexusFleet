[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester: variables set in BeforeAll/BeforeEach are used in It blocks and mocks; the analyzer does not look across script blocks.')]
param()

BeforeAll {
    $module = Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../../NexusFleet.psd1') -Force -PassThru
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestStepContext.ps1')
    $step = & $module { Get-NexusStep } | Where-Object Name -EQ 'RegisterNode'
    $sameNode = [pscustomobject]@{ id = 'node-web01'; name = 'node-web01'; location = 'home'; agentUrl = 'http://10.0.0.5:9100'; health = 'offline' }
    $otherNode = [pscustomobject]@{ id = 'node-other'; name = 'node-other'; location = 'vps'; agentUrl = 'http://10.0.0.9:9100'; health = 'healthy' }
}

AfterAll {
    Remove-Module -Name NexusFleet -Force -ErrorAction SilentlyContinue
}

Describe 'Step RegisterNode' {
    BeforeEach {
        $context = Get-TestStepContext -Module $module
    }

    It 'runs after Docker and before the agent (Order 20)' {
        $step.Order | Should -Be 20
    }

    Context 'Test' {
        It 'is in order when GET /nodes has the node with the same name, location and agentUrl' {
            Mock -ModuleName NexusFleet -CommandName Invoke-NexusApi -MockWith { @($otherNode, $sameNode) }

            & $step.Test $context | Should -BeTrue
            $context.State.NodeExisted | Should -BeTrue
            Should -Invoke -ModuleName NexusFleet -CommandName Invoke-NexusApi -Times 1 -Exactly -ParameterFilter { $Method -eq 'GET' -and $Path -eq '/nodes' }
        }

        It 'is not in order when the node is not registered, and remembers that' {
            Mock -ModuleName NexusFleet -CommandName Invoke-NexusApi -MockWith { @($otherNode) }

            & $step.Test $context | Should -BeFalse
            $context.State.NodeExisted | Should -BeFalse
        }

        It 'is not in order when the panel has no nodes at all' {
            Mock -ModuleName NexusFleet -CommandName Invoke-NexusApi -MockWith { @() }

            & $step.Test $context | Should -BeFalse
        }

        It 'is not in order when a label differs (<Field>)' -ForEach @(
            @{ Field = 'name' }, @{ Field = 'location' }, @{ Field = 'agentUrl' }
        ) {
            $changed = $sameNode.PSObject.Copy()
            $changed.$Field = 'something else'
            Mock -ModuleName NexusFleet -CommandName Invoke-NexusApi -MockWith { @($changed) }

            & $step.Test $context | Should -BeFalse
            $context.State.NodeExisted | Should -BeTrue
        }
    }

    Context 'Apply' {
        It 'sends POST /nodes with id, name, location and agentUrl from the inventory' {
            Mock -ModuleName NexusFleet -CommandName Invoke-NexusApi -MockWith { $sameNode }

            & $step.Apply $context

            Should -Invoke -ModuleName NexusFleet -CommandName Invoke-NexusApi -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Path -eq '/nodes' -and $Body.id -eq 'node-web01' -and $Body.name -eq 'node-web01' -and
                $Body.location -eq 'home' -and $Body.agentUrl -eq 'http://10.0.0.5:9100'
            }
        }
    }

    Context 'a host with reach outbound' {
        BeforeEach {
            $context = Get-TestStepContext -Module $module -Outbound
            $outboundNode = [pscustomobject]@{ id = 'node-web01'; name = 'node-web01'; location = 'home'; agentUrl = $null; connection = 'outbound'; linked = $false }
        }

        It 'is in order when the node is registered as outbound, whatever its agentUrl' {
            Mock -ModuleName NexusFleet -CommandName Invoke-NexusApi -MockWith { @($outboundNode) }

            & $step.Test $context | Should -BeTrue
        }

        It 'is not in order when the node is registered as direct' {
            $direct = $outboundNode.PSObject.Copy()
            $direct.connection = 'direct'
            Mock -ModuleName NexusFleet -CommandName Invoke-NexusApi -MockWith { @($direct) }

            & $step.Test $context | Should -BeFalse
        }

        It 'sends POST /nodes with connection outbound and no agentUrl' {
            Mock -ModuleName NexusFleet -CommandName Invoke-NexusApi -MockWith { $outboundNode }

            & $step.Apply $context

            Should -Invoke -ModuleName NexusFleet -CommandName Invoke-NexusApi -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Path -eq '/nodes' -and $Body.connection -eq 'outbound' -and -not $Body.ContainsKey('agentUrl')
            }
        }
    }

    Context 'Rollback' {
        It 'deletes the node when this run created it' {
            Mock -ModuleName NexusFleet -CommandName Invoke-NexusApi -MockWith { }
            $context.State.NodeExisted = $false

            & $step.Rollback $context

            Should -Invoke -ModuleName NexusFleet -CommandName Invoke-NexusApi -Times 1 -Exactly -ParameterFilter { $Method -eq 'DELETE' -and $Path -eq '/nodes/node-web01' }
        }

        It 'leaves a node alone that existed before this run' {
            Mock -ModuleName NexusFleet -CommandName Invoke-NexusApi -MockWith { }
            $context.State.NodeExisted = $true

            & $step.Rollback $context

            Should -Invoke -ModuleName NexusFleet -CommandName Invoke-NexusApi -Times 0 -Exactly
        }
    }
}
