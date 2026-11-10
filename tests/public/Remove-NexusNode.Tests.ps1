# Remove-NexusNode with -ThrottleLimit 1 (one after the other, in this runspace, so the mocks work) against the fake
# fleet of tests/core/FakeFleet.ps1. The per-host work itself is tested in tests/core/Invoke-NexusHostRemoval.Tests.ps1.
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester: variables set in BeforeAll/BeforeEach are used in It blocks and mocks; the analyzer does not look across script blocks.')]
param()

BeforeAll {
    $module = Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../../NexusFleet.psd1') -Force -PassThru
    . (Join-Path -Path $PSScriptRoot -ChildPath '../core/FakeFleet.ps1')
    $config = & $module { Get-NexusConfig }

    $connect = { & $module { param($Session) $script:NexusSession = $Session } (Get-FakeSession) }
    $disconnect = { & $module { $script:NexusSession = $null } }
}

AfterAll {
    Remove-Module -Name NexusFleet -Force -ErrorAction SilentlyContinue
}

Describe 'Remove-NexusNode' {
    BeforeEach {
        & $connect
        # Three installed nodes.
        $fake = Get-FakeFleet
        $hosts = foreach ($i in 1..3) {
            Add-FakeHost -Fake $fake -Address "10.0.0.$i" -Docker -Agent -NodeId "node-web0$i"
            $fake.Nodes["node-web0$i"] = @{ id = "node-web0$i"; name = "node-web0$i"; location = 'home'; connection = 'direct' }
            Get-FakeHostInfo -Name "node-web0$i" -Address "10.0.0.$i"
        }
        $runContext = & $module { param($Root) Initialize-NexusRunContext -LogRoot $Root } $TestDrive
        Mock -ModuleName NexusFleet -CommandName Initialize-NexusRunContext -MockWith { $runContext }
        Mock -ModuleName NexusFleet -CommandName Get-NexusConfig -MockWith { $config }
        Mock -ModuleName NexusFleet -CommandName Invoke-NexusHostCommand -MockWith { Invoke-FakeHostCommand -Fake $fake -HostName $HostName -Command $Command }
        Mock -ModuleName NexusFleet -CommandName Invoke-NexusApi -MockWith { Invoke-FakeApi -Fake $fake -Method $Method -Path $Path -Body $Body }
    }

    It 'needs Connect-NexusInfra first' {
        & $disconnect

        { $hosts | Remove-NexusNode -ThrottleLimit 1 -Confirm:$false } | Should -Throw -ErrorId 'NexusFleet.NotConnected*'
    }

    It 'removes every node, one result per host, in the order of the inventory' {
        $results = @($hosts | Remove-NexusNode -ThrottleLimit 1 -Confirm:$false)

        $results | Should -HaveCount 3
        $results.Host | Should -Be @('node-web01', 'node-web02', 'node-web03')
        $results.Success | Should -Not -Contain $false
        $results.Changed | Should -Not -Contain $false
        $fake.Nodes.Count | Should -Be 0
        @($fake.Hosts.Values | Where-Object Agent) | Should -HaveCount 0
    }

    It 'changes nothing on a second run' {
        $null = $hosts | Remove-NexusNode -ThrottleLimit 1 -Confirm:$false
        $fake.Changes.Clear()

        $second = @($hosts | Remove-NexusNode -ThrottleLimit 1 -Confirm:$false)

        $second.Success | Should -Not -Contain $false
        $second.Changed | Should -Not -Contain $true
        $fake.Changes | Should -BeNullOrEmpty
    }

    It 'with -WhatIf reports the plan per host and changes nothing' {
        $results = @($hosts | Remove-NexusNode -ThrottleLimit 1 -WhatIf)

        $results | Should -HaveCount 3
        $results.PlanOnly | Should -Not -Contain $false
        $results.Node | Should -Be @('WouldRemove', 'WouldRemove', 'WouldRemove')
        $fake.Changes | Should -BeNullOrEmpty
        $fake.Nodes.Count | Should -Be 3
    }

    It 'does not let one failing host stop the others' {
        $fake.Busy.Add('node-web02')

        $results = @($hosts | Remove-NexusNode -ThrottleLimit 1 -Confirm:$false)

        $results.Success | Should -Be @($true, $false, $true)
        $results[1].Error | Should -Match 'still hosts a running server'
        $fake.Hosts['10.0.0.2'].Agent | Should -BeTrue
        $fake.Nodes.Keys | Should -Be @('node-web02')
    }

    It 'deregisters a machine that is gone only with -IgnoreUnreachableHost' {
        $fake.Hosts.Remove('10.0.0.3')
        $fake.Heartbeating.Remove('node-web03')

        $without = @($hosts[2] | Remove-NexusNode -ThrottleLimit 1 -Confirm:$false)
        $with = @($hosts[2] | Remove-NexusNode -ThrottleLimit 1 -Confirm:$false -IgnoreUnreachableHost)

        $without.Success | Should -BeFalse
        $with.Success | Should -BeTrue
        $fake.Nodes.Keys | Should -Not -Contain 'node-web03'
    }

    It 'uses Install.ThrottleLimit when none is given' {
        Mock -ModuleName NexusFleet -CommandName Invoke-NexusHostLoop -MockWith { }

        $null = $hosts | Remove-NexusNode -Confirm:$false

        Should -Invoke -ModuleName NexusFleet -CommandName Invoke-NexusHostLoop -Times 1 -Exactly -ParameterFilter {
            $ThrottleLimit -eq $config.Install.ThrottleLimit -and $FunctionName -eq 'Invoke-NexusHostRemoval'
        }
    }

    It 'logs the run, with the API token redacted' {
        $null = $hosts | Remove-NexusNode -ThrottleLimit 1 -Confirm:$false

        $log = Get-Content -Path (Join-Path -Path $runContext.LogDirectory -ChildPath 'run.log') -Raw
        $log | Should -Match 'Remove 3 node\(s\), 1 at a time'
        $log | Should -Match 'Remove done: 3 of 3 host\(s\) succeeded, 3 changed'
    }
}
