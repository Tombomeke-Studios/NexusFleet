[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester: variables set in BeforeAll/BeforeEach are used in It blocks and mocks; the analyzer does not look across script blocks.')]
param()

# The loop is internal, so it runs in the module's scope (& $module { }). With -ThrottleLimit 1 the mocks work (E3).
# The parallel path is tested with real runspaces and a real module function that needs no network.
BeforeAll {
    $module = Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../../NexusFleet.psd1') -Force -PassThru

    function Get-TestItem {
        param([int]$Number)
        @{ HostInfo = [pscustomobject]@{ PSTypeName = 'NexusFleet.Host'; Name = "node-$Number"; Address = "10.0.0.$Number"; Port = 22; User = 'fleet' } }
    }
}

AfterAll {
    Remove-Module -Name NexusFleet -Force -ErrorAction SilentlyContinue
}

Describe 'Invoke-NexusHostLoop one after the other' {
    BeforeEach {
        Mock -ModuleName NexusFleet -CommandName Invoke-NexusHostPreflight -MockWith {
            [pscustomobject]@{ Host = $HostInfo.Name; Config = $Config }
        }
    }

    It 'returns one result per host, in input order, with the shared and the host parameters' {
        $items = 1..3 | ForEach-Object { Get-TestItem -Number $_ }

        $results = @(& $module {
                param($Items)
                Invoke-NexusHostLoop -InputObject $Items -FunctionName Invoke-NexusHostPreflight -Parameter @{ Config = @{ Name = 'shared' } } `
                    -FailureFunction ConvertTo-NexusPreflightFailure -ThrottleLimit 1 -Activity 'test'
            } $items)

        $results.Host | Should -Be 'node-1', 'node-2', 'node-3'
        $results.Config.Name | Should -Be 'shared', 'shared', 'shared'
    }

    It 'gives a host whose work throws a failure result, and keeps going with the others' {
        Mock -ModuleName NexusFleet -CommandName Invoke-NexusHostPreflight -ParameterFilter { $HostInfo.Name -eq 'node-2' } -MockWith { throw 'kaboom' }
        $items = 1..3 | ForEach-Object { Get-TestItem -Number $_ }

        $results = @(& $module {
                param($Items)
                Invoke-NexusHostLoop -InputObject $Items -FunctionName Invoke-NexusHostPreflight -Parameter @{ Config = @{} } `
                    -FailureFunction ConvertTo-NexusPreflightFailure -ThrottleLimit 1 -Activity 'test'
            } $items)

        $results | Should -HaveCount 3
        $failed = $results | Where-Object Host -EQ 'node-2'
        $failed.Success | Should -BeFalse
        $failed.Error | Should -BeLike '*kaboom*'
        $failed.PSObject.TypeNames | Should -Contain 'NexusFleet.PreflightResult'
        $failed.PSObject.TypeNames | Should -Not -Contain 'NexusFleet.HostLoopFailure' -Because 'the internal marker never reaches the caller'
    }

    It 'passes the failure function only the host parameters it declares' {
        Mock -ModuleName NexusFleet -CommandName Invoke-NexusHostInstall -MockWith { throw 'kaboom' }
        $item = Get-TestItem -Number 1
        $item.PlanOnly = $true

        $result = & $module {
            param($Item)
            $session = [pscustomobject]@{ PSTypeName = 'NexusFleet.Session' }
            Invoke-NexusHostLoop -InputObject $Item -FunctionName Invoke-NexusHostInstall -Parameter @{ Config = @{}; Session = $session } `
                -FailureFunction ConvertTo-NexusInstallFailure -ThrottleLimit 1 -Activity 'test'
        } $item

        $result.PlanOnly | Should -BeTrue -Because 'PlanOnly is a parameter of ConvertTo-NexusInstallFailure'
        $result.Error | Should -BeLike '*kaboom*'
    }

    It 'returns nothing and calls nothing for no hosts' {
        $results = @(& $module {
                Invoke-NexusHostLoop -InputObject @() -FunctionName Invoke-NexusHostPreflight -FailureFunction ConvertTo-NexusPreflightFailure `
                    -ThrottleLimit 1 -Activity 'test'
            })

        $results | Should -HaveCount 0
        Should -Invoke -ModuleName NexusFleet -CommandName Invoke-NexusHostPreflight -Times 0 -Exactly
    }
}

Describe 'Invoke-NexusHostLoop in parallel' -Tag 'LocalSsh' {
    It 'runs an internal module function in real runspaces and returns one result per host' {
        $items = 1..6 | ForEach-Object { Get-TestItem -Number $_ }

        $results = @(& $module {
                param($Items)
                Invoke-NexusHostLoop -InputObject $Items -FunctionName Get-NexusSshParameter -Parameter @{ Config = @{ Ssh = @{ ConnectTimeoutSeconds = 3 } } } `
                    -FailureFunction ConvertTo-NexusPreflightFailure -ThrottleLimit 3 -Activity 'test'
            } $items)

        $results | Should -HaveCount 6
        ($results.HostName | Sort-Object) | Should -Be ('10.0.0.1', '10.0.0.2', '10.0.0.3', '10.0.0.4', '10.0.0.5', '10.0.0.6')
    }

    It 'gives every host a failure result when the work throws inside its runspace' {
        $items = 1..4 | ForEach-Object { Get-TestItem -Number $_ }

        $results = @(& $module {
                param($Items)
                # Config must be a hashtable: the parameter binding fails in every runspace.
                Invoke-NexusHostLoop -InputObject $Items -FunctionName Get-NexusSshParameter -Parameter @{ Config = 'not a hashtable' } `
                    -FailureFunction ConvertTo-NexusPreflightFailure -ThrottleLimit 2 -Activity 'test'
            } $items)

        $results | Should -HaveCount 4
        ($results.Host | Sort-Object) | Should -Be 'node-1', 'node-2', 'node-3', 'node-4'
        $results.Success | Should -Not -Contain $true
        $results[0].Error | Should -BeLike '*Config*'
    }
}
