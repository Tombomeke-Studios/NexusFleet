# Integration test: Invoke-NexusHostCommand with the real ssh client against the E1 lab container
# (start it with ./lab/E1-transport/Start-LabTarget.ps1). Skipped when the lab target is not there.
# Run: Invoke-Pester -Path ./tests/transports -TagFilter Integration -Output Detailed
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester: variables set in BeforeAll are used in It blocks; the analyzer does not look across script blocks.')]
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'Test data: a fake secret, never a real one.')]
param()

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../src/core/ConvertTo-NexusCommandResult.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../src/transports/Invoke-NexusSshClient.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../src/transports/Invoke-NexusHostCommand.ps1')

    $keyFolder = Join-Path -Path $PSScriptRoot -ChildPath '../../lab/E1-transport/.keys'
    $lab = @{
        HostName       = '127.0.0.1'
        Port           = 2222
        UserName       = 'fleet'
        KeyFile        = Join-Path -Path $keyFolder -ChildPath 'id_ed25519'
        KnownHostsFile = Join-Path -Path $keyFolder -ChildPath 'known_hosts'
    }
    $labAvailable = (Test-Path -Path $lab.KeyFile) -and
    (Test-Connection -TargetName '127.0.0.1' -TcpPort 2222 -TimeoutSeconds 2 -Quiet)
}

Describe 'Invoke-NexusHostCommand against the lab container' -Tag 'Integration' {
    BeforeEach {
        if (-not $labAvailable) {
            Set-ItResult -Skipped -Because 'the E1 lab target is not running (./lab/E1-transport/Start-LabTarget.ps1)'
        }
    }

    It 'runs a command and returns its output and exit code 0' {
        $result = Invoke-NexusHostCommand @lab -Command 'uname -s'

        $result.ExitCode | Should -Be 0
        $result.StdOut | Should -Be 'Linux'
        $result.Succeeded | Should -BeTrue
    }

    It 'returns the exit code and the error output of a failing command' {
        $result = Invoke-NexusHostCommand @lab -Command 'echo broken >&2; exit 7'

        $result.ExitCode | Should -Be 7
        $result.StdErr | Should -Be 'broken'
        $result.TransportFailed | Should -BeFalse
    }

    It 'may use sudo without a password (target-host requirement)' {
        (Invoke-NexusHostCommand @lab -Command 'sudo -n true').ExitCode | Should -Be 0
    }

    It 'delivers a secret on stdin exactly, without CR or LF' {
        $secret = ConvertTo-SecureString -String 'S3cr3t-value' -AsPlainText -Force

        $result = Invoke-NexusHostCommand @lab -Command 'IFS= read -r s; printf %s "$s" | od -An -c | tr -s " "' -Secret $secret

        $result.StdOut.Trim() | Should -Be 'S 3 c r 3 t - v a l u e'
    }

    It 'reports a key the host does not accept as a transport failure, without waiting for input' {
        $wrong = $lab.Clone()
        $wrong.KeyFile = Join-Path -Path $keyFolder -ChildPath 'wrong_ed25519'

        $result = Invoke-NexusHostCommand @wrong -Command 'true'

        $result.TransportFailed | Should -BeTrue
        $result.StdErr | Should -Match 'Permission denied'
    }
}
