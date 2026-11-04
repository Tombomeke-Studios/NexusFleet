[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester: variables set in BeforeAll/BeforeEach are used in It blocks and mocks; the analyzer does not look across script blocks.')]
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'Test data: a fake secret, never a real one.')]
param()

BeforeAll {
    foreach ($file in 'core/ConvertTo-NexusCommandResult', 'transports/Invoke-NexusSshClient', 'transports/Invoke-NexusHostCommand',
        'core/Invoke-NexusStepCommand') {
        . (Join-Path -Path $PSScriptRoot -ChildPath "../../src/$file.ps1")
    }
    $context = @{ Ssh = @{ HostName = '10.0.0.5'; Port = 22; UserName = 'fleet'; ConnectTimeoutSeconds = 5 } }
}

Describe 'Invoke-NexusStepCommand' {
    It 'runs the command with the ssh settings of the context and returns the result' {
        Mock -CommandName Invoke-NexusHostCommand -MockWith { ConvertTo-NexusCommandResult -HostName $HostName -ExitCode 0 -StdOut 'ok' }

        $result = Invoke-NexusStepCommand -Context $context -Purpose 'say ok' -Command 'echo ok'

        $result.StdOut | Should -Be 'ok'
        Should -Invoke -CommandName Invoke-NexusHostCommand -Times 1 -Exactly -ParameterFilter {
            $HostName -eq '10.0.0.5' -and $UserName -eq 'fleet' -and $ConnectTimeoutSeconds -eq 5 -and $Command -eq 'echo ok'
        }
    }

    It 'throws with the purpose, the exit code and the last stderr lines when the command fails' {
        Mock -CommandName Invoke-NexusHostCommand -MockWith {
            ConvertTo-NexusCommandResult -HostName $HostName -ExitCode 100 -StdErr 'line 1', 'line 2', 'E: Unable to locate package', 'E: done'
        }

        { Invoke-NexusStepCommand -Context $context -Purpose 'install Docker' -Command 'apt-get install x' } |
            Should -Throw "Could not install Docker on 10.0.0.5 (exit 100): line 2 E: Unable to locate package E: done"
    }

    It 'returns a failed command with -AllowFailure (for a Test)' {
        Mock -CommandName Invoke-NexusHostCommand -MockWith { ConvertTo-NexusCommandResult -HostName $HostName -ExitCode 1 }

        $result = Invoke-NexusStepCommand -Context $context -Purpose 'check Docker' -Command 'docker info' -AllowFailure

        $result.ExitCode | Should -Be 1
    }

    It 'throws when ssh itself fails, also with -AllowFailure' {
        Mock -CommandName Invoke-NexusHostCommand -MockWith { ConvertTo-NexusCommandResult -HostName $HostName -ExitCode 255 -StdErr 'Connection timed out' }

        { Invoke-NexusStepCommand -Context $context -Purpose 'check Docker' -Command 'docker info' -AllowFailure } |
            Should -Throw '*ssh to 10.0.0.5 failed while trying to check Docker: Connection timed out*'
    }

    It 'names the host by its inventory name when the context has one' {
        Mock -CommandName Invoke-NexusHostCommand -MockWith { ConvertTo-NexusCommandResult -HostName $HostName -ExitCode 1 -StdErr 'nope' }
        $named = @{ Ssh = $context.Ssh; HostInfo = [pscustomobject]@{ Name = 'node-web01' } }

        { Invoke-NexusStepCommand -Context $named -Purpose 'start' -Command 'x' } | Should -Throw 'Could not start on node-web01 (10.0.0.5) (exit 1): nope'
    }

    It 'passes secrets on to the transport' {
        Mock -CommandName Invoke-NexusHostCommand -MockWith { ConvertTo-NexusCommandResult -HostName $HostName -ExitCode 0 }
        $secret = ConvertTo-SecureString -String 'S3cr3t' -AsPlainText -Force

        $null = Invoke-NexusStepCommand -Context $context -Purpose 'write' -Command 'IFS= read -r s' -Secret $secret, $secret

        Should -Invoke -CommandName Invoke-NexusHostCommand -Times 1 -Exactly -ParameterFilter { $Secret.Count -eq 2 }
    }
}
