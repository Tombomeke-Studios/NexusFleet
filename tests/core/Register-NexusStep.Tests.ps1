Describe 'Register-NexusStep and Get-NexusStep' {
    BeforeEach {
        # Loading the file starts an empty registry, like loading the module does.
        . (Join-Path -Path $PSScriptRoot -ChildPath '../../src/core/Register-NexusStep.ps1')
        . (Join-Path -Path $PSScriptRoot -ChildPath '../../src/core/Get-NexusStep.ps1')
    }

    It 'returns the registered steps sorted by Order, whatever the registration order' {
        Register-NexusStep -Name 'Agent' -Order 20 -Test { $true } -Apply { }
        Register-NexusStep -Name 'Docker' -Order 10 -Test { $true } -Apply { }
        Register-NexusStep -Name 'Verify' -Order 40 -Test { $true } -Apply { }

        (Get-NexusStep).Name | Should -Be @('Docker', 'Agent', 'Verify')
    }

    It 'builds a NexusFleet.Step object' {
        Register-NexusStep -Name 'Docker' -Order 10 -Description 'Install Docker' -Test { $true } -Apply { } -Rollback { }

        $step = Get-NexusStep
        $step.PSObject.TypeNames | Should -Contain 'NexusFleet.Step'
        $step.Description | Should -Be 'Install Docker'
        $step.Test | Should -BeOfType [scriptblock]
    }

    It 'gives a step without Rollback an empty one (nothing to undo)' {
        Register-NexusStep -Name 'Verify' -Order 40 -Test { $true } -Apply { }

        (Get-NexusStep).Rollback | Should -BeOfType [scriptblock]
    }

    It 'refuses a second step with the same name' {
        Register-NexusStep -Name 'Docker' -Order 10 -Test { $true } -Apply { }

        { Register-NexusStep -Name 'Docker' -Order 11 -Test { $true } -Apply { } } | Should -Throw -ExpectedMessage "*'Docker'*already registered*"
    }

    It 'refuses a second step with the same Order, because the order would be ambiguous' {
        Register-NexusStep -Name 'Docker' -Order 10 -Test { $true } -Apply { }

        { Register-NexusStep -Name 'Other' -Order 10 -Test { $true } -Apply { } } | Should -Throw -ExpectedMessage "*Order 10*'Docker'*"
    }

    It 'refuses a step name with spaces or odd characters' {
        { Register-NexusStep -Name 'my step' -Order 10 -Test { $true } -Apply { } } | Should -Throw
    }
}
