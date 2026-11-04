# Scale: generated inventories of 50 and 100 hosts for the three cmdlets that work per host, with a few hosts that
# cannot be reached and a few that fail. Every host must get exactly one correct result and nothing may crash.
# One after the other (-ThrottleLimit 1) so the mocks work; the parallel path is proven in the *.LocalSsh tests.
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester: variables set in BeforeAll/BeforeEach are used in It blocks and mocks; the analyzer does not look across script blocks.')]
param()

BeforeAll {
    $module = Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../../NexusFleet.psd1') -Force -PassThru
    . (Join-Path -Path $PSScriptRoot -ChildPath '../core/FakeFleet.ps1')
    $config = & $module { Get-NexusConfig }
    $config.Health.VerifyTimeoutSeconds = 4
    $config.Health.PollIntervalSeconds = 2

    # Every 17th host cannot be reached, every 23rd fails while the agent starts.
    $newFleet = {
        param([int]$Count)
        $fake = Get-FakeFleet
        $hosts = foreach ($i in 1..$Count) {
            $address = '10.{0}.{1}.{2}' -f $Count, [math]::Floor($i / 250), ($i % 250 + 1)
            if ($i % 17 -ne 0) { Add-FakeHost -Fake $fake -Address $address -Docker:($i % 2 -eq 0) }
            Get-FakeHostInfo -Name ('node-{0:d3}' -f $i) -Address $address
        }
        $unreachable = @(foreach ($i in 1..$Count) { if ($i % 17 -eq 0) { 'node-{0:d3}' -f $i } })
        $failing = @(foreach ($i in 1..$Count) { if ($i % 23 -eq 0 -and $i % 17 -ne 0) { 'node-{0:d3}' -f $i } })
        @{ Fake = $fake; Hosts = @($hosts); Unreachable = $unreachable; Failing = $failing }
    }
}

AfterAll {
    Remove-Module -Name NexusFleet -Force -ErrorAction SilentlyContinue
}

Describe 'Scale: <Count> generated hosts' -ForEach @(@{ Count = 50 }, @{ Count = 100 }) {
    BeforeEach {
        & $module { param($Session) $script:NexusSession = $Session } (Get-FakeSession)
        $fleet = & $newFleet $Count
        $fake = $fleet.Fake
        $runContext = & $module { param($Root) Initialize-NexusRunContext -LogRoot $Root } $TestDrive
        Mock -ModuleName NexusFleet -CommandName Initialize-NexusRunContext -MockWith { $runContext }
        Mock -ModuleName NexusFleet -CommandName Get-NexusConfig -MockWith { $config }
        Mock -ModuleName NexusFleet -CommandName Invoke-NexusHostCommand -MockWith { Invoke-FakeHostCommand -Fake $fake -HostName $HostName -Command $Command }
        Mock -ModuleName NexusFleet -CommandName Invoke-NexusApi -MockWith { Invoke-FakeApi -Fake $fake -Method $Method -Path $Path -Body $Body }
        Mock -ModuleName NexusFleet -CommandName Start-Sleep -MockWith { }
    }

    It 'Test-NexusHost: one result per host; exactly the unreachable ones fail at Reachable' {
        # The preflight facts script is not part of the fake fleet: answer it as a ready Ubuntu host.
        Mock -ModuleName NexusFleet -CommandName Invoke-NexusHostCommand -ParameterFilter { $Command -eq 'true' -or $Command -like '*os-release*' } -MockWith {
            if (-not $fake.Hosts[$HostName]) { return Get-FakeCommandResult -HostName $HostName -ExitCode 255 -StdErr 'Connection timed out' }
            Get-FakeCommandResult -HostName $HostName -StdOut 'os=ubuntu', 'osversion=24.04', 'sudo=yes', 'diskfreemb=20000', 'docker=', 'broker=yes'
        }

        $results = @($fleet.Hosts | Test-NexusHost -ThrottleLimit 1)

        $results | Should -HaveCount $Count
        @($results.Host | Sort-Object -Unique) | Should -HaveCount $Count
        @($results | Where-Object { -not $_.Success }).Host | Should -Be $fleet.Unreachable
        @($results | Where-Object { -not $_.Success }).Step | Sort-Object -Unique | Should -Be 'Reachable'
    }

    It 'Install-NexusNode: one result per host; unreachable and failing hosts are reported and rolled back, the rest is healthy' {
        Mock -ModuleName NexusFleet -CommandName Invoke-NexusHostPreflight -MockWith { Get-FakePreflight -HostInfo $HostInfo }
        $failingAddresses = @($fleet.Hosts | Where-Object Name -In $fleet.Failing | ForEach-Object Address)
        # FailAt in the fake fails one host; here several fail, so POST /nodes is refused for each of them.
        Mock -ModuleName NexusFleet -CommandName Invoke-NexusApi -ParameterFilter { $Method -eq 'POST' -and $Body.id -in $fleet.Failing } -MockWith {
            $fake.Changes.Add("POST /nodes $($Body.id)")
            throw [System.InvalidOperationException]::new('NexusInfra answered 409 Conflict.')
        }

        $results = @($fleet.Hosts | Install-NexusNode -ThrottleLimit 1 -RabbitMqUrl (Get-FakeSecretSet).RabbitMqUrl -InternalApiToken (Get-FakeSecretSet).InternalApiToken)

        $results | Should -HaveCount $Count
        @($results.Host | Sort-Object -Unique) | Should -HaveCount $Count
        $failed = @($results | Where-Object { -not $_.Success })
        @($failed.Host | Sort-Object) | Should -Be @(($fleet.Unreachable + $fleet.Failing) | Sort-Object)
        ($failed | Where-Object Host -In $fleet.Failing).Step | Sort-Object -Unique | Should -Be 'RegisterNode'
        $fake.Heartbeating.Count | Should -Be ($Count - $fleet.Unreachable.Count - $fleet.Failing.Count)
        foreach ($address in $failingAddresses) {
            $fake.Hosts[$address].Agent | Should -BeFalse
        }
    }

    It 'Get-NexusFleetStatus: one status per host; exactly the unreachable ones have a problem after the install' {
        Mock -ModuleName NexusFleet -CommandName Invoke-NexusHostPreflight -MockWith { Get-FakePreflight -HostInfo $HostInfo }
        $null = $fleet.Hosts | Install-NexusNode -ThrottleLimit 1 -RabbitMqUrl (Get-FakeSecretSet).RabbitMqUrl -InternalApiToken (Get-FakeSecretSet).InternalApiToken
        # The status script is not part of the fake fleet: answer it from the fake host's state.
        Mock -ModuleName NexusFleet -CommandName Invoke-NexusHostCommand -ParameterFilter { $Command -like '*/proc/uptime*' } -MockWith {
            $state = $fake.Hosts[$HostName]
            if (-not $state) { return Get-FakeCommandResult -HostName $HostName -ExitCode 255 -StdErr 'Connection timed out' }
            $agent = if ($state.Agent) { 'running|2026-11-04T07:00:00Z|0|img' } else { '' }
            Get-FakeCommandResult -HostName $HostName -StdOut 'uptime=100', 'diskfreemb=9000', 'docker=Docker version 27', "agent=$agent"
        }

        $statuses = @($fleet.Hosts | Get-NexusFleetStatus -ThrottleLimit 1)

        $statuses | Should -HaveCount $Count
        $statuses.Name | Should -Be $fleet.Hosts.Name
        @($statuses | Where-Object { -not $_.Ok }).Name | Should -Be $fleet.Unreachable
    }
}
