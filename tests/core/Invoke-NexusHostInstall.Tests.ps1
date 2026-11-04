# Invoke-NexusHostInstall with the real steps and the real step runner, against a fake host and a fake panel
# (FakeFleet.ps1). These tests carry the three "Klaar als" criteria for one host: it becomes healthy, a second run
# changes nothing, and a failure is rolled back. The parallel part is tested in tests/public/Install-NexusNode*.
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester: variables set in BeforeAll/BeforeEach are used in It blocks and mocks; the analyzer does not look across script blocks.')]
param()

BeforeAll {
    $module = Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../../NexusFleet.psd1') -Force -PassThru
    . (Join-Path -Path $PSScriptRoot -ChildPath 'FakeFleet.ps1')
    $config = & $module { Get-NexusConfig }
    $config.Health.VerifyTimeoutSeconds = 6
    $config.Health.PollIntervalSeconds = 2
    $session = Get-FakeSession
    $hostInfo = Get-FakeHostInfo -Name 'node-web01' -Address '10.0.0.5'

    $install = {
        param([switch]$PlanOnly, [switch]$NoSecrets, [switch]$Force)
        $secrets = if ($NoSecrets) { $null } else { Get-FakeSecretSet }
        & $module {
            param($HostInfo, $Config, $Session, $Secrets, $PlanOnly, $Force)
            Invoke-NexusHostInstall -HostInfo $HostInfo -Config $Config -Session $Session -Secrets $Secrets -PlanOnly:$PlanOnly -Force:$Force
        } $hostInfo $config $session $secrets $PlanOnly $Force
    }
}

AfterAll {
    Remove-Module -Name NexusFleet -Force -ErrorAction SilentlyContinue
}

Describe 'Invoke-NexusHostInstall' {
    BeforeEach {
        $fake = Get-FakeFleet
        Add-FakeHost -Fake $fake -Address '10.0.0.5'
        $preflightFails = $null
        Mock -ModuleName NexusFleet -CommandName Invoke-NexusHostPreflight -MockWith { Get-FakePreflight -HostInfo $HostInfo -FailStep $preflightFails }
        Mock -ModuleName NexusFleet -CommandName Invoke-NexusHostCommand -MockWith { Invoke-FakeHostCommand -Fake $fake -HostName $HostName -Command $Command }
        Mock -ModuleName NexusFleet -CommandName Invoke-NexusApi -MockWith { Invoke-FakeApi -Fake $fake -Method $Method -Path $Path -Body $Body }
        Mock -ModuleName NexusFleet -CommandName Start-Sleep -MockWith { }
    }

    Context 'a fresh host' {
        It 'applies every step in order and ends with a healthy node' {
            $result = & $install

            $result.PSObject.TypeNames | Should -Contain 'NexusFleet.InstallResult'
            $result.Success | Should -BeTrue
            $result.Changed | Should -BeTrue
            $result.Steps.Step | Should -Be @('Docker', 'RegisterNode', 'AgentContainer', 'VerifyHealthy', 'AgentReachable')
            $result.Steps.Outcome | Should -Be @('Applied', 'Applied', 'Applied', 'Applied', 'AlreadyDone')
            $fake.Changes | Should -Be @('10.0.0.5 install docker', 'POST /nodes node-web01', '10.0.0.5 start agent')
            $fake.Heartbeating['node-web01'] | Should -BeTrue
            # VerifyHealthy Applied: its Test still saw offline (no heartbeat yet), its Apply polled until healthy.
            # AgentReachable changes nothing: once NexusInfra reaches the agent, its Test is already in order.
        }

        It 'keeps the preflight checks in the result' {
            (& $install).Preflight.Checks.Name | Should -Contain 'Reachable'
        }
    }

    Context 'a second run (idempotency)' {
        It 'changes nothing on a host that is already a healthy node' {
            $null = & $install
            $fake.Changes.Clear()

            $second = & $install

            $second.Success | Should -BeTrue
            $second.Changed | Should -BeFalse
            $second.Steps.Outcome | Should -Be @('AlreadyDone', 'AlreadyDone', 'AlreadyDone', 'AlreadyDone', 'AlreadyDone')
            $fake.Changes | Should -BeNullOrEmpty
        }

        It 'with -Force recreates only the agent on a finished host (to apply a changed secret)' {
            $null = & $install
            $fake.Changes.Clear()

            $forced = & $install -Force

            $forced.Success | Should -BeTrue
            $forced.Changed | Should -BeTrue
            $forced.Steps.Outcome | Should -Be @('AlreadyDone', 'AlreadyDone', 'Applied', 'Applied', 'AlreadyDone')
            $fake.Changes | Should -Be @('10.0.0.5 start agent')
        }

        It 'only does what is missing: Docker present, node and agent not' {
            $fake.Hosts['10.0.0.5'].Docker = $true

            $result = & $install

            $result.Steps.Outcome | Should -Be @('AlreadyDone', 'Applied', 'Applied', 'Applied', 'AlreadyDone')
            $fake.Changes | Should -Not -Contain '10.0.0.5 install docker'
        }
    }

    Context 'plan only (-WhatIf)' {
        It 'makes no changing call and reports what would be applied, without secrets' {
            $result = & $install -PlanOnly -NoSecrets

            $result.Success | Should -BeTrue
            $result.PlanOnly | Should -BeTrue
            $result.Changed | Should -BeFalse
            $result.Steps.Outcome | Should -Be @('WouldApply', 'WouldApply', 'WouldApply', 'WouldApply', 'WouldApply')
            $fake.Changes | Should -BeNullOrEmpty
            Should -Invoke -ModuleName NexusFleet -CommandName Invoke-NexusApi -Times 0 -ParameterFilter { $Method -ne 'GET' }
        }

        It 'reports AlreadyDone for a finished host' {
            $null = & $install
            $fake.Changes.Clear()

            (& $install -PlanOnly -NoSecrets).Steps.Outcome | Should -Be @('AlreadyDone', 'AlreadyDone', 'AlreadyDone', 'AlreadyDone', 'AlreadyDone')
        }
    }

    Context 'rollback, with a failure in each step' {
        It 'Docker fails: nothing else runs, nothing to undo' {
            $fake.FailAt = 'Docker'

            $result = & $install

            $result.Success | Should -BeFalse
            $result.Step | Should -Be 'Docker'
            $result.Error | Should -Match 'Unable to locate package'
            $result.Steps.Outcome | Should -Be @('Failed', 'NotRun', 'NotRun', 'NotRun', 'NotRun')
            # The failed Apply is rolled back too: it may have half installed the package.
            $fake.Changes | Should -Be @('10.0.0.5 install docker', '10.0.0.5 remove docker')
        }

        It 'RegisterNode fails: Docker, installed by this run, is removed again' {
            $fake.FailAt = 'RegisterNode'

            $result = & $install

            $result.Step | Should -Be 'RegisterNode'
            $result.Steps.Rollback | Should -Be @('Done', 'Done', $null, $null, $null)
            $fake.Changes[-1] | Should -Be '10.0.0.5 remove docker'
            $fake.Hosts['10.0.0.5'].Docker | Should -BeFalse
            $fake.Nodes.Count | Should -Be 0
        }

        It 'AgentContainer fails: the new node record is deleted and Docker removed, in reverse order' {
            $fake.FailAt = 'AgentContainer'

            $result = & $install

            $result.Step | Should -Be 'AgentContainer'
            $result.Error | Should -Match 'port is already allocated'
            $fake.Changes | Should -Be @('10.0.0.5 install docker', 'POST /nodes node-web01', '10.0.0.5 start agent',
                '10.0.0.5 remove agent', 'DELETE /nodes/node-web01', '10.0.0.5 remove docker')
        }

        It 'VerifyHealthy times out: everything this run did is undone, and the error says why' {
            $fake.NeverHealthy = $true

            $result = & $install

            $result.Step | Should -Be 'VerifyHealthy'
            $result.Error | Should -Match 'did not become healthy within 6 s \(last health: offline\)'
            $result.Changed | Should -BeTrue
            $fake.Hosts['10.0.0.5'].Agent | Should -BeFalse
            $fake.Nodes.Count | Should -Be 0
            $fake.Hosts['10.0.0.5'].Docker | Should -BeFalse
        }

        It 'AgentReachable fails (healthy, but NexusInfra cannot call the agent): everything this run did is undone' {
            $fake.Unreachable.Add('node-web01')

            $result = & $install

            $result.Success | Should -BeFalse
            $result.Step | Should -Be 'AgentReachable'
            $result.Error | Should -Match 'cannot reach the agent of node-web01 at http://10\.0\.0\.5:9100'
            $fake.Hosts['10.0.0.5'].Agent | Should -BeFalse
            $fake.Nodes.Count | Should -Be 0
            $fake.Hosts['10.0.0.5'].Docker | Should -BeFalse
        }

        It 'leaves alone what was there before the run (Docker and an existing node record)' {
            $fake.Hosts['10.0.0.5'].Docker = $true
            $fake.Nodes['node-web01'] = @{ id = 'node-web01'; name = 'old name'; location = 'home'; agentUrl = 'http://10.0.0.5:9100' }
            $fake.FailAt = 'AgentContainer'

            $null = & $install

            $fake.Changes | Should -Not -Contain '10.0.0.5 remove docker'
            $fake.Changes | Should -Not -Contain 'DELETE /nodes/node-web01'
            $fake.Nodes.ContainsKey('node-web01') | Should -BeTrue
        }
    }

    Context 'ssh settings' {
        It 'uses the host''s key file and the configured known_hosts file for every step' {
            $withKey = $hostInfo.PSObject.Copy()
            $withKey.KeyFile = 'C:/keys/fleet'
            $sshConfig = & $module { Get-NexusConfig }
            $sshConfig.Ssh.KnownHostsFile = 'C:/keys/known_hosts'

            $null = & $module { param($HostInfo, $Config, $Session, $Secrets) Invoke-NexusHostInstall -HostInfo $HostInfo -Config $Config -Session $Session -Secrets $Secrets } $withKey $sshConfig $session (Get-FakeSecretSet)

            Should -Invoke -ModuleName NexusFleet -CommandName Invoke-NexusHostCommand -ParameterFilter { $KeyFile -ne 'C:/keys/fleet' -or $KnownHostsFile -ne 'C:/keys/known_hosts' } -Times 0 -Exactly
            Should -Invoke -ModuleName NexusFleet -CommandName Invoke-NexusHostCommand -ParameterFilter { $KeyFile -eq 'C:/keys/fleet' }
        }
    }

    Context 'a host that is not ready' {
        It 'touches nothing when the preflight fails, and names the check' {
            $preflightFails = 'Sudo'

            $result = & $install

            $result.Success | Should -BeFalse
            $result.Step | Should -Be 'Sudo'
            $result.Error | Should -Match '^preflight failed, nothing was changed'
            $result.Steps | Should -BeNullOrEmpty
            Should -Invoke -ModuleName NexusFleet -CommandName Invoke-NexusHostCommand -Times 0
            Should -Invoke -ModuleName NexusFleet -CommandName Invoke-NexusApi -Times 0
        }

        It 'turns an unreachable host during the steps into a failed result, never an exception' {
            $fake.Hosts.Remove('10.0.0.5')

            $result = & $install

            $result.Success | Should -BeFalse
            $result.Step | Should -Be 'Docker'
            $result.Error | Should -Match 'ssh to node-web01 \(10\.0\.0\.5\) failed'
        }

        It 'logs an unexpected error in the host''s log' {
            Mock -ModuleName NexusFleet -CommandName Invoke-NexusHostPreflight -MockWith { throw 'boom' }
            $run = & $module { param($Root) Initialize-NexusRunContext -LogRoot $Root } $TestDrive

            $null = & $module { param($HostInfo, $Config, $Session, $Run) Invoke-NexusHostInstall -HostInfo $HostInfo -Config $Config -Session $Session -RunContext $Run } $hostInfo $config $session $run

            Get-Content -Path (Join-Path -Path $run.LogDirectory -ChildPath 'node-web01.log') -Raw | Should -Match 'ERROR.*step=Install.*failed unexpectedly: boom'
        }
        It 'turns an unexpected error into a failed result' {
            Mock -ModuleName NexusFleet -CommandName Invoke-NexusHostPreflight -MockWith { throw 'boom' }

            $result = & $install

            $result.Success | Should -BeFalse
            $result.Step | Should -Be 'Install'
            $result.Error | Should -Match 'failed unexpectedly: boom'
        }
    }
}
