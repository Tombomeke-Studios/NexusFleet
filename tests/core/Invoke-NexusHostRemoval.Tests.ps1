# Invoke-NexusHostRemoval against a fake host and a fake panel (FakeFleet.ps1): what is removed, in which order, and
# what stays untouched when NexusInfra refuses or the host does not answer.
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester: variables set in BeforeAll/BeforeEach are used in It blocks and mocks; the analyzer does not look across script blocks.')]
param()

BeforeAll {
    $module = Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../../NexusFleet.psd1') -Force -PassThru
    . (Join-Path -Path $PSScriptRoot -ChildPath 'FakeFleet.ps1')
    $config = & $module { Get-NexusConfig }
    $session = Get-FakeSession
    $hostInfo = Get-FakeHostInfo -Name 'node-web01' -Address '10.0.0.5'

    $remove = {
        param([switch]$PlanOnly, [switch]$IgnoreUnreachableHost, $RunContext)
        & $module {
            param($HostInfo, $Config, $Session, $PlanOnly, $Ignore, $RunContext)
            Invoke-NexusHostRemoval -HostInfo $HostInfo -Config $Config -Session $Session -PlanOnly:$PlanOnly `
                -IgnoreUnreachableHost:$Ignore -RunContext $RunContext
        } $hostInfo $config $session $PlanOnly $IgnoreUnreachableHost $RunContext
    }
}

AfterAll {
    Remove-Module -Name NexusFleet -Force -ErrorAction SilentlyContinue
}

Describe 'Invoke-NexusHostRemoval' {
    BeforeEach {
        # An installed node: the agent runs and sends heartbeats, and NexusInfra knows the node.
        $fake = Get-FakeFleet
        Add-FakeHost -Fake $fake -Address '10.0.0.5' -Docker -Agent -NodeId 'node-web01'
        $fake.Nodes['node-web01'] = @{ id = 'node-web01'; name = 'node-web01'; location = 'home'; connection = 'direct' }
        Mock -ModuleName NexusFleet -CommandName Invoke-NexusHostCommand -MockWith { Invoke-FakeHostCommand -Fake $fake -HostName $HostName -Command $Command }
        Mock -ModuleName NexusFleet -CommandName Invoke-NexusApi -MockWith { Invoke-FakeApi -Fake $fake -Method $Method -Path $Path -Body $Body }
    }

    Context 'an installed node' {
        It 'deregisters the node and removes the agent' {
            $result = & $remove

            $result.PSObject.TypeNames | Should -Contain 'NexusFleet.RemoveResult'
            $result.Success | Should -BeTrue
            $result.Changed | Should -BeTrue
            $result.Node | Should -Be 'Removed'
            $result.Agent | Should -Be 'Removed'
            $result.Step | Should -BeNullOrEmpty
            $fake.Hosts['10.0.0.5'].Agent | Should -BeFalse
            $fake.Hosts['10.0.0.5'].Docker | Should -BeTrue
        }

        It 'deletes the node again after the agent stopped, because a heartbeat brought it back' {
            $null = & $remove

            $fake.Changes | Should -Be @('DELETE /nodes/node-web01', '10.0.0.5 remove agent', 'DELETE /nodes/node-web01')
            $fake.Nodes.Keys | Should -Not -Contain 'node-web01'
        }

        It 'removes the env file with the secrets, and never the backups volume or Docker' {
            $null = & $remove

            Should -Invoke -ModuleName NexusFleet -CommandName Invoke-NexusHostCommand -Times 1 -Exactly -ParameterFilter {
                $Command -match 'docker rm -f' -and $Command -match "rm -f '/etc/nexusinfra/agent.env'"
            }
            Should -Invoke -ModuleName NexusFleet -CommandName Invoke-NexusHostCommand -Times 0 -Exactly -ParameterFilter {
                $Command -match 'volume|apt-get'
            }
        }

        It 'changes nothing on a second run' {
            $null = & $remove
            $fake.Changes.Clear()

            $second = & $remove

            $second.Success | Should -BeTrue
            $second.Changed | Should -BeFalse
            $second.Node | Should -Be 'Absent'
            $second.Agent | Should -Be 'Absent'
            $fake.Changes | Should -BeNullOrEmpty
        }
    }

    Context 'a dry run (-PlanOnly)' {
        It 'reports what would be removed and changes nothing' {
            $result = & $remove -PlanOnly

            $result.Success | Should -BeTrue
            $result.PlanOnly | Should -BeTrue
            $result.Changed | Should -BeFalse
            $result.Node | Should -Be 'WouldRemove'
            $result.Agent | Should -Be 'WouldRemove'
            $fake.Changes | Should -BeNullOrEmpty
        }
    }

    Context 'a node that still hosts a running server' {
        It 'fails at Node with a clear error and leaves the host alone' {
            $fake.Busy.Add('node-web01')

            $result = & $remove

            $result.Success | Should -BeFalse
            $result.Changed | Should -BeFalse
            $result.Step | Should -Be 'Node'
            $result.Error | Should -Match 'still hosts a running server, nothing was changed'
            $result.Node | Should -Be 'Present'
            $fake.Hosts['10.0.0.5'].Agent | Should -BeTrue
            $fake.Changes | Should -Be @('DELETE /nodes/node-web01')
        }
    }

    Context 'half-removed states' {
        It 'removes an agent whose node is not registered' {
            $fake.Nodes.Clear()
            $fake.Heartbeating.Clear()

            $result = & $remove

            $result.Success | Should -BeTrue
            $result.Node | Should -Be 'Absent'
            $result.Agent | Should -Be 'Removed'
            $fake.Changes | Should -Be @('10.0.0.5 remove agent')
        }

        It 'deregisters a node whose host has no agent' {
            $fake.Hosts['10.0.0.5'].Agent = $false
            $fake.Heartbeating.Clear()

            $result = & $remove

            $result.Success | Should -BeTrue
            $result.Node | Should -Be 'Removed'
            $result.Agent | Should -Be 'Absent'
            $fake.Changes | Should -Be @('DELETE /nodes/node-web01')
        }
    }

    Context 'a host that does not answer' {
        BeforeEach {
            $fake.Hosts.Remove('10.0.0.5')
            $fake.Heartbeating.Clear()
        }

        It 'fails at Host and keeps the node registered' {
            $result = & $remove

            $result.Success | Should -BeFalse
            $result.Step | Should -Be 'Host'
            $result.Error | Should -Match 'cannot reach 10\.0\.0\.5:22 over ssh, nothing was changed: Connection timed out'
            $result.Agent | Should -Be 'Unknown'
            $fake.Nodes.Keys | Should -Contain 'node-web01'
            $fake.Changes | Should -BeNullOrEmpty
        }

        It 'deregisters the node anyway with -IgnoreUnreachableHost' {
            $result = & $remove -IgnoreUnreachableHost

            $result.Success | Should -BeTrue
            $result.Node | Should -Be 'Removed'
            $result.Agent | Should -Be 'Unknown'
            $fake.Nodes.Keys | Should -Not -Contain 'node-web01'
        }
    }

    Context 'failures' {
        It 'fails at Agent when the container cannot be removed, and says the node is already gone' {
            $fake.FailAt = 'RemoveAgent'

            $result = & $remove

            $result.Success | Should -BeFalse
            $result.Step | Should -Be 'Agent'
            $result.Error | Should -Match 'could not remove the agent from node-web01 \(exit 1\): .*removal in progress'
            $result.Node | Should -Be 'Removed'
            $result.Changed | Should -BeTrue
        }

        It 'fails at Node when NexusInfra cannot be asked, before anything is changed' {
            Mock -ModuleName NexusFleet -CommandName Invoke-NexusApi -MockWith { throw 'NexusInfra is not reachable' }

            $result = & $remove

            $result.Success | Should -BeFalse
            $result.Step | Should -Be 'Node'
            $result.Error | Should -Match 'not reachable'
            $fake.Changes | Should -BeNullOrEmpty
        }

        It 'passes on another API error of the delete as it is' {
            Mock -ModuleName NexusFleet -CommandName Invoke-NexusApi -ParameterFilter { $Method -eq 'DELETE' } -MockWith { throw 'NexusInfra answered 403 Forbidden.' }

            $result = & $remove

            $result.Step | Should -Be 'Node'
            $result.Error | Should -Be 'NexusInfra answered 403 Forbidden.'
            $fake.Hosts['10.0.0.5'].Agent | Should -BeTrue
        }
    }

    Context 'logging' {
        It 'writes the outcome to the log of the host' {
            $run = & $module { param($Root) Initialize-NexusRunContext -LogRoot $Root } $TestDrive

            $null = & $remove -RunContext $run

            $log = Get-Content -Path (Join-Path -Path $run.LogDirectory -ChildPath 'node-web01.log') -Raw
            $log | Should -Match 'Remove.*node Removed, agent Removed'
        }

        It 'writes a failure as an error' {
            $fake.Busy.Add('node-web01')
            $run = & $module { param($Root) Initialize-NexusRunContext -LogRoot $Root } $TestDrive

            $null = & $remove -RunContext $run

            $log = Get-Content -Path (Join-Path -Path $run.LogDirectory -ChildPath 'node-web01.log') -Raw
            $log | Should -Match 'Error.*still hosts a running server'
        }
    }
}

Describe 'ConvertTo-NexusRemoveFailure' {
    It 'builds a failed result for the host' {
        $result = & $module { param($HostInfo) ConvertTo-NexusRemoveFailure -HostInfo $HostInfo -Message 'boom' -PlanOnly } $hostInfo

        $result.PSObject.TypeNames | Should -Contain 'NexusFleet.RemoveResult'
        $result.Host | Should -Be 'node-web01'
        $result.Success | Should -BeFalse
        $result.PlanOnly | Should -BeTrue
        $result.Step | Should -Be 'Remove'
        $result.Error | Should -Be 'removal of node-web01 failed unexpectedly: boom'
    }
}
