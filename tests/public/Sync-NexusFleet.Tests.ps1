# Sync-NexusFleet with -ThrottleLimit 1 (in this runspace, so the mocks work) against the fake fleet of
# tests/core/FakeFleet.ps1: installed nodes that drift in different ways, the report, and the repair.
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester: variables set in BeforeAll/BeforeEach are used in It blocks and mocks; the analyzer does not look across script blocks.')]
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'Test data: fake secrets, never real ones.')]
param()

BeforeAll {
    $module = Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../../NexusFleet.psd1') -Force -PassThru
    . (Join-Path -Path $PSScriptRoot -ChildPath '../core/FakeFleet.ps1')
    $config = & $module { Get-NexusConfig }
    $config.Health.VerifyTimeoutSeconds = 4
    $config.Health.PollIntervalSeconds = 2

    $connect = { & $module { param($Session) $script:NexusSession = $Session } (Get-FakeSession) }
    $disconnect = { & $module { $script:NexusSession = $null } }
    # The install in BeforeEach reads the two agent secrets once; Sync-NexusFleet itself must add no call to that.
    $setupSecretCalls = 2
}

AfterAll {
    Remove-Module -Name NexusFleet -Force -ErrorAction SilentlyContinue
}

Describe 'Sync-NexusFleet' {
    BeforeEach {
        & $connect
        $fake = Get-FakeFleet
        $hosts = foreach ($i in 1..3) {
            Add-FakeHost -Fake $fake -Address "10.0.0.$i"
            Get-FakeHostInfo -Name "node-web0$i" -Address "10.0.0.$i"
        }
        $runContext = & $module { param($Root) Initialize-NexusRunContext -LogRoot $Root } $TestDrive
        Mock -ModuleName NexusFleet -CommandName Initialize-NexusRunContext -MockWith { $runContext }
        Mock -ModuleName NexusFleet -CommandName Get-NexusConfig -MockWith { $config }
        Mock -ModuleName NexusFleet -CommandName Invoke-NexusHostPreflight -MockWith { Get-FakePreflight -HostInfo $HostInfo }
        Mock -ModuleName NexusFleet -CommandName Invoke-NexusHostCommand -MockWith { Invoke-FakeHostCommand -Fake $fake -HostName $HostName -Command $Command }
        Mock -ModuleName NexusFleet -CommandName Invoke-NexusApi -MockWith { Invoke-FakeApi -Fake $fake -Method $Method -Path $Path -Body $Body }
        Mock -ModuleName NexusFleet -CommandName Start-Sleep -MockWith { }
        Mock -ModuleName NexusFleet -CommandName Get-NexusStoredToken -MockWith {
            ConvertTo-SecureString -String "stored-$SecretName" -AsPlainText -Force
        }
        # The starting point of every test: three healthy nodes, exactly as the inventory wants them.
        $null = $hosts | Install-NexusNode -ThrottleLimit 1
        $fake.Changes.Clear()
    }

    It 'needs Connect-NexusInfra first' {
        & $disconnect

        { $hosts | Sync-NexusFleet -ThrottleLimit 1 -WhatIf } | Should -Throw -ErrorId 'NexusFleet.NotConnected*'
    }

    Context 'a fleet without drift' {
        It 'reports every host in sync and changes nothing' {
            $results = @($hosts | Sync-NexusFleet -ThrottleLimit 1 -Confirm:$false)

            $results | Should -HaveCount 3
            $results[0].PSObject.TypeNames | Should -Contain 'NexusFleet.SyncResult'
            $results.Host | Should -Be @('node-web01', 'node-web02', 'node-web03')
            $results.InSync | Should -Not -Contain $false
            $results.Repaired | Should -Not -Contain $true
            $results.Success | Should -Not -Contain $false
            $fake.Changes | Should -BeNullOrEmpty
        }

        It 'asks for no secrets' {
            $null = $hosts | Sync-NexusFleet -ThrottleLimit 1 -Confirm:$false

            Should -Invoke -ModuleName NexusFleet -CommandName Get-NexusStoredToken -Times $setupSecretCalls -Exactly
        }
    }

    Context 'a label changed in the panel' {
        BeforeEach {
            $fake.Nodes['node-web02'].location = 'somewhere else'
        }

        It 'with -WhatIf reports the difference in words and changes nothing' {
            $results = @($hosts | Sync-NexusFleet -ThrottleLimit 1 -WhatIf)

            $drifted = $results | Where-Object Host -EQ 'node-web02'
            $drifted.InSync | Should -BeFalse
            $drifted.Repairable | Should -BeTrue
            $drifted.Repaired | Should -BeFalse
            $drifted.Differences | Should -Be @("RegisterNode: location is 'somewhere else', not 'home'")
            @($results | Where-Object InSync).Host | Should -Be @('node-web01', 'node-web03')
            $fake.Changes | Should -BeNullOrEmpty
            Should -Invoke -ModuleName NexusFleet -CommandName Get-NexusStoredToken -Times $setupSecretCalls -Exactly
        }

        It 'repairs only that host, and only the step that was not in order' {
            $results = @($hosts | Sync-NexusFleet -ThrottleLimit 1 -Confirm:$false)

            $drifted = $results | Where-Object Host -EQ 'node-web02'
            $drifted.InSync | Should -BeFalse
            $drifted.Repaired | Should -BeTrue
            $drifted.Success | Should -BeTrue
            $fake.Changes | Should -Be @('POST /nodes node-web02')
            $fake.Nodes['node-web02'].location | Should -Be 'home'
        }

        It 'finds nothing on the run after the repair' {
            $null = $hosts | Sync-NexusFleet -ThrottleLimit 1 -Confirm:$false

            $again = @($hosts | Sync-NexusFleet -ThrottleLimit 1 -Confirm:$false)

            $again.InSync | Should -Not -Contain $false
        }
    }

    Context 'an agent container that is gone' {
        BeforeEach {
            $fake.Hosts['10.0.0.3'].Agent = $false
            $fake.Heartbeating.Remove('node-web03')
        }

        It 'reports the missing agent and the node that is not healthy' {
            $results = @($hosts | Sync-NexusFleet -ThrottleLimit 1 -WhatIf)

            $drifted = $results | Where-Object Host -EQ 'node-web03'
            $drifted.Differences | Should -Contain 'AgentContainer: there is no agent container'
            $drifted.Differences | Should -Contain 'VerifyHealthy: NexusInfra reports the node offline'
        }

        It 'starts the agent again with the secrets given, and the node is healthy' {
            $secrets = Get-FakeSecretSet

            $results = @($hosts | Sync-NexusFleet -ThrottleLimit 1 -Confirm:$false -RabbitMqUrl $secrets.RabbitMqUrl -InternalApiToken $secrets.InternalApiToken)

            ($results | Where-Object Host -EQ 'node-web03').Repaired | Should -BeTrue
            $fake.Changes | Should -Be @('10.0.0.3 start agent')
            $fake.Heartbeating['node-web03'] | Should -BeTrue
            Should -Invoke -ModuleName NexusFleet -CommandName Get-NexusStoredToken -Times $setupSecretCalls -Exactly
        }

        It 'reports a repair that fails, with the error of the installation' {
            $fake.FailAt = 'AgentContainer'

            $results = @($hosts | Sync-NexusFleet -ThrottleLimit 1 -Confirm:$false)

            $failed = $results | Where-Object Host -EQ 'node-web03'
            $failed.Repaired | Should -BeFalse
            $failed.Success | Should -BeFalse
            $failed.Error | Should -Match 'port is already allocated'
        }
    }

    Context 'a host that cannot be compared' {
        It 'reports the failed preflight as an error and does not try to repair it' {
            Mock -ModuleName NexusFleet -CommandName Invoke-NexusHostPreflight -MockWith {
                Get-FakePreflight -HostInfo $HostInfo -FailStep $(if ($HostInfo.Name -eq 'node-web01') { 'Reachable' })
            }

            $results = @($hosts | Sync-NexusFleet -ThrottleLimit 1 -Confirm:$false)

            $failed = $results | Where-Object Host -EQ 'node-web01'
            $failed.InSync | Should -BeFalse
            $failed.Repairable | Should -BeFalse
            $failed.Success | Should -BeFalse
            $failed.Error | Should -Match 'preflight failed'
            @($results | Where-Object InSync).Host | Should -Be @('node-web02', 'node-web03')
            $fake.Changes | Should -BeNullOrEmpty
        }
    }

    Context 'a node the inventory does not know' {
        BeforeEach {
            $fake.Nodes['node-old'] = @{ id = 'node-old'; name = 'node-old'; location = 'attic'; connection = 'direct' }
        }

        It 'reports it as unmanaged, after the hosts, and never removes it' {
            $results = @($hosts | Sync-NexusFleet -ThrottleLimit 1 -Confirm:$false)

            $results | Should -HaveCount 4
            $results[3].Host | Should -Be 'node-old'
            $results[3].InSync | Should -BeFalse
            $results[3].Repairable | Should -BeFalse
            $results[3].Differences | Should -Match '^Unmanaged'
            $fake.Nodes.Keys | Should -Contain 'node-old'
            $fake.Changes | Should -BeNullOrEmpty
        }
    }

    It 'warns and still reports the hosts when the node list cannot be read' {
        Mock -ModuleName NexusFleet -CommandName ConvertTo-NexusSyncResult -ParameterFilter { $Unmanaged } -MockWith { throw 'the node list is broken' }
        $fake.Nodes['node-old'] = @{ id = 'node-old'; name = 'node-old' }

        $results = @($hosts | Sync-NexusFleet -ThrottleLimit 1 -Confirm:$false -WarningVariable warnings -WarningAction SilentlyContinue)

        $results | Should -HaveCount 3
        $warnings | Should -Match 'unmanaged nodes are not reported: the node list is broken'
    }

    It 'installs a host that is not a node yet' {
        Add-FakeHost -Fake $fake -Address '10.0.0.9'
        $new = Get-FakeHostInfo -Name 'node-new' -Address '10.0.0.9'

        $results = @($new | Sync-NexusFleet -ThrottleLimit 1 -Confirm:$false)

        $results[0].InSync | Should -BeFalse
        $results[0].Repaired | Should -BeTrue
        $results[0].Differences[1] | Should -Be 'RegisterNode: the node is not registered'
        $fake.Heartbeating['node-new'] | Should -BeTrue
    }

    It 'logs the comparison and the repair' {
        $fake.Nodes['node-web02'].location = 'somewhere else'

        $null = $hosts | Sync-NexusFleet -ThrottleLimit 1 -Confirm:$false

        $log = Get-Content -Path (Join-Path -Path $runContext.LogDirectory -ChildPath 'run.log') -Raw
        $log | Should -Match 'Sync: compare 3 host\(s\)'
        $log | Should -Match 'Sync: repair 1 host\(s\) with Install-NexusNode'
        $log | Should -Match 'Sync done: 1 of 3 host\(s\) not in sync, 1 repaired, 0 unmanaged node\(s\)'
    }
}

Describe 'ConvertTo-NexusSyncResult' {
    It 'uses the description of the step when its check gave no detail' {
        $plan = [pscustomobject]@{
            Host = 'node-web01'; Success = $true; Step = $null; Error = $null
            Steps = @(
                [pscustomobject]@{ Step = 'Docker'; Outcome = 'WouldApply'; Detail = $null }
                [pscustomobject]@{ Step = 'RegisterNode'; Outcome = 'AlreadyDone'; Detail = $null }
            )
        }
        $steps = @([pscustomobject]@{ Name = 'Docker'; Description = 'Docker Engine installed and running' })

        $result = & $module { param($Plan, $Step) ConvertTo-NexusSyncResult -Plan $Plan -Step $Step } $plan $steps

        $result.InSync | Should -BeFalse
        $result.Differences | Should -Be @('Docker: not in order: Docker Engine installed and running')
    }
}
