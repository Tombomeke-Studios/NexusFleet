[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester: variables set in BeforeAll/BeforeEach are used in It blocks and mocks; the analyzer does not look across script blocks.')]
param()

# Mocks do not reach ForEach-Object -Parallel runspaces (E3), so these tests use -ThrottleLimit 1, which runs the
# hosts one after the other in this runspace. The parallel path is tested for real in Test-NexusHost.LocalSsh.Tests.ps1.
BeforeAll {
    $module = Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../../NexusFleet.psd1') -Force -PassThru
    $config = @{
        Broker    = @{ Host = 'broker.example.com'; Port = 5672 }
        Ssh       = @{ ConnectTimeoutSeconds = 5; KnownHostsFile = '' }
        Preflight = @{ MinDiskFreeMB = 2048; SupportedOs = @('ubuntu'); ThrottleLimit = 10 }
    }

    function Get-TestHost {
        param([int]$Number)
        [pscustomobject]@{
            PSTypeName = 'NexusFleet.Host'; Name = 'node-{0:d3}' -f $Number; Address = "10.0.$([math]::Floor($Number / 250)).$($Number % 250 + 1)"
            Port = 22; User = 'fleet'; Location = 'lab'; Role = $null; KeyFile = $null; AgentUrl = $null
        }
    }
}

AfterAll {
    Remove-Module -Name NexusFleet -Force -ErrorAction SilentlyContinue
}

Describe 'Test-NexusHost' {
    BeforeEach {
        $runContext = & $module { param($Root) Initialize-NexusRunContext -LogRoot $Root } $TestDrive
        Mock -ModuleName NexusFleet -CommandName Initialize-NexusRunContext -MockWith { $runContext }
        Mock -ModuleName NexusFleet -CommandName Get-NexusConfig -MockWith { $config }
        Mock -ModuleName NexusFleet -CommandName Invoke-NexusHostPreflight -MockWith {
            [pscustomobject]@{ PSTypeName = 'NexusFleet.PreflightResult'; Host = $HostInfo.Name; Address = $HostInfo.Address; Success = $true; Step = $null; Error = $null; Checks = @() }
        }
    }

    It 'returns one result per host, in inventory order, from pipeline input' {
        $hosts = 1..3 | ForEach-Object { Get-TestHost -Number $_ }

        $results = @($hosts | Test-NexusHost -ThrottleLimit 1)

        $results | Should -HaveCount 3
        $results.Host | Should -Be @('node-001', 'node-002', 'node-003')
        Should -Invoke -ModuleName NexusFleet -CommandName Invoke-NexusHostPreflight -Times 3 -Exactly
    }

    It 'passes the config and the run context to the per-host check' {
        $null = Get-TestHost -Number 1 | Test-NexusHost -ThrottleLimit 1

        Should -Invoke -ModuleName NexusFleet -CommandName Invoke-NexusHostPreflight -ParameterFilter {
            $Config.Broker.Host -eq 'broker.example.com' -and $RunContext.RunId -eq $runContext.RunId
        }
    }

    It 'keeps going when one host throws, and gives that host a failed result' {
        Mock -ModuleName NexusFleet -CommandName Invoke-NexusHostPreflight -ParameterFilter { $HostInfo.Name -eq 'node-002' } -MockWith { throw 'kaboom' }
        $hosts = 1..3 | ForEach-Object { Get-TestHost -Number $_ }

        $results = @($hosts | Test-NexusHost -ThrottleLimit 1)

        $results | Should -HaveCount 3
        $failed = $results | Where-Object Host -EQ 'node-002'
        $failed.Success | Should -BeFalse
        $failed.Error | Should -Match 'kaboom'
        ($results | Where-Object Host -NE 'node-002').Success | Should -Be @($true, $true)
    }

    It 'gives every host of a generated inventory of 100 its own correct result, with a few failing' {
        $failing = 'node-007', 'node-042', 'node-077', 'node-099'
        Mock -ModuleName NexusFleet -CommandName Invoke-NexusHostPreflight -MockWith {
            $ok = $HostInfo.Name -notin $failing
            [pscustomobject]@{
                PSTypeName = 'NexusFleet.PreflightResult'; Host = $HostInfo.Name; Address = $HostInfo.Address
                Success = $ok; Step = if ($ok) { $null } else { 'Reachable' }; Error = $null; Checks = @()
            }
        }
        $hosts = 1..100 | ForEach-Object { Get-TestHost -Number $_ }

        $results = @($hosts | Test-NexusHost -ThrottleLimit 1)

        $results | Should -HaveCount 100
        @($results.Host | Sort-Object -Unique) | Should -HaveCount 100
        @($results | Where-Object { -not $_.Success }).Host | Should -Be $failing
    }

    It 'writes a summary to run.log' {
        $null = 1..2 | ForEach-Object { Get-TestHost -Number $_ } | Test-NexusHost -ThrottleLimit 1

        Get-Content -Path (Join-Path -Path $runContext.LogDirectory -ChildPath 'run.log') -Raw | Should -Match 'Preflight done: 2 of 2 host\(s\) ready'
    }

    It 'refuses input that is not a NexusFleet.Host' {
        # A wrong pipeline object is a non-terminating error per object; -ErrorAction Stop makes it stop.
        { [pscustomobject]@{ Name = 'x' } | Test-NexusHost -ThrottleLimit 1 -ErrorAction Stop } | Should -Throw
    }
}
