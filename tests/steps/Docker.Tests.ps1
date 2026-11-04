[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester: variables set in BeforeAll/BeforeEach are used in It blocks and mocks; the analyzer does not look across script blocks.')]
param()

BeforeAll {
    $module = Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../../NexusFleet.psd1') -Force -PassThru
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestStepContext.ps1')
    $step = & $module { Get-NexusStep } | Where-Object Name -EQ 'Docker'
}

AfterAll {
    Remove-Module -Name NexusFleet -Force -ErrorAction SilentlyContinue
}

Describe 'Step Docker' {
    BeforeEach {
        $context = Get-TestStepContext -Module $module
    }

    It 'runs first (Order 10)' {
        $step.Order | Should -Be 10
    }

    Context 'Test' {
        It 'is in order when docker exists and the daemon answers with sudo' {
            Mock -ModuleName NexusFleet -CommandName Invoke-NexusHostCommand -MockWith { Get-TestCommandResult -ExitCode 0 }

            & $step.Test $context | Should -BeTrue
            Should -Invoke -ModuleName NexusFleet -CommandName Invoke-NexusHostCommand -Times 1 -Exactly -ParameterFilter {
                $Command -match 'command -v docker' -and $Command -match 'sudo -n docker info'
            }
        }

        It 'is not in order when the check fails' {
            Mock -ModuleName NexusFleet -CommandName Invoke-NexusHostCommand -MockWith { Get-TestCommandResult -ExitCode 1 }

            & $step.Test $context | Should -BeFalse
        }

        It 'throws when the host cannot be reached (nothing is known then)' {
            Mock -ModuleName NexusFleet -CommandName Invoke-NexusHostCommand -MockWith { Get-TestCommandResult -ExitCode 255 -StdErr 'Connection timed out' }

            { & $step.Test $context } | Should -Throw '*ssh to 10.0.0.5 failed*'
        }
    }

    Context 'Apply' {
        It 'installs the configured package without questions, waits for the apt lock, and starts the daemon' {
            Mock -ModuleName NexusFleet -CommandName Invoke-NexusHostCommand -MockWith { Get-TestCommandResult -ExitCode 0 }

            & $step.Apply $context

            Should -Invoke -ModuleName NexusFleet -CommandName Invoke-NexusHostCommand -Times 1 -Exactly -ParameterFilter {
                $Command -match "install -y -q 'docker\.io'" -and $Command -match 'DEBIAN_FRONTEND=noninteractive' -and
                $Command -match 'DPkg::Lock::Timeout=300' -and $Command -match 'systemctl enable --now docker' -and $Command -match '^set -e'
            }
        }

        It 'fails with apt''s reason when the installation fails' {
            Mock -ModuleName NexusFleet -CommandName Invoke-NexusHostCommand -MockWith { Get-TestCommandResult -ExitCode 100 -StdErr 'E: Unable to locate package docker.io' }

            { & $step.Apply $context } | Should -Throw '*Could not install Docker on 10.0.0.5 (exit 100): E: Unable to locate package docker.io*'
        }
    }

    Context 'Rollback' {
        It 'removes the package again' {
            Mock -ModuleName NexusFleet -CommandName Invoke-NexusHostCommand -MockWith { Get-TestCommandResult -ExitCode 0 }

            & $step.Rollback $context

            Should -Invoke -ModuleName NexusFleet -CommandName Invoke-NexusHostCommand -Times 1 -Exactly -ParameterFilter { $Command -match "apt-get remove -y -q 'docker\.io'" }
        }
    }
}
