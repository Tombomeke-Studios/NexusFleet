[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester: variables set in BeforeAll/BeforeEach are used in It blocks and mocks; the analyzer does not look across script blocks.')]
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'Test data: a fake secret, never a real one.')]
param()

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../src/core/ConvertTo-NexusCommandResult.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../src/transports/Invoke-NexusSshClient.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../src/transports/Invoke-NexusHostCommand.ps1')

    # A fake stderr line, as ssh's 2>&1 output contains them.
    function Get-StdErrLine { param([string]$Text) [System.Management.Automation.ErrorRecord]::new([System.Exception]::new($Text), 'NativeCommandError', 'NotSpecified', $null) }

    $target = @{ HostName = '10.0.0.5'; Port = 2222; UserName = 'fleet' }
}

Describe 'Invoke-NexusHostCommand' {
    BeforeEach {
        # What the fake ssh client received: its arguments and the stdin bytes.
        # Invoke-NexusSshClient is mocked, not ssh itself: Pester cannot see what is piped into a mocked program.
        $seen = @{ Args = @(); Input = $null }
    }

    Context 'the ssh call' {
        It 'never waits for input: BatchMode, a connect time-out, accept-new host keys, quiet log level' {
            Mock -CommandName Invoke-NexusSshClient -MockWith { $seen.Args = $ArgumentList; [pscustomobject]@{ Output = @(); ExitCode = 0 } }

            $null = Invoke-NexusHostCommand @target -Command 'uname -a' -ConnectTimeoutSeconds 7

            $joined = $seen.Args -join ' '
            $joined | Should -Match '-o BatchMode=yes'
            $joined | Should -Match '-o ConnectTimeout=7'
            $joined | Should -Match '-o StrictHostKeyChecking=accept-new'
            $joined | Should -Match '-o LogLevel=ERROR'
            $joined | Should -Match '-p 2222'
        }

        It 'puts user@host and then the command last' {
            Mock -CommandName Invoke-NexusSshClient -MockWith { $seen.Args = $ArgumentList; [pscustomobject]@{ Output = @(); ExitCode = 0 } }

            $null = Invoke-NexusHostCommand @target -Command 'uname -a'

            $seen.Args[-2] | Should -Be 'fleet@10.0.0.5'
            $seen.Args[-1] | Should -Be 'uname -a'
        }

        It 'closes stdin (-n) when there is nothing to send, so a remote command cannot wait for input' {
            Mock -CommandName Invoke-NexusSshClient -MockWith { $seen.Args = $ArgumentList; [pscustomobject]@{ Output = @(); ExitCode = 0 } }

            $null = Invoke-NexusHostCommand @target -Command 'cat'

            $seen.Args | Should -Contain '-n'
        }

        It 'uses the key file and the known_hosts file when given' {
            Mock -CommandName Invoke-NexusSshClient -MockWith { $seen.Args = $ArgumentList; [pscustomobject]@{ Output = @(); ExitCode = 0 } }

            $null = Invoke-NexusHostCommand @target -Command 'true' -KeyFile 'C:\keys\fleet' -KnownHostsFile 'C:\keys\known_hosts'

            ($seen.Args -join ' ') | Should -Match '-i C:\\keys\\fleet'
            ($seen.Args -join ' ') | Should -Match '-o UserKnownHostsFile=C:\\keys\\known_hosts'
        }
    }

    Context 'the result' {
        It 'separates stdout and stderr and returns the exit code' {
            Mock -CommandName Invoke-NexusSshClient -MockWith {
                [pscustomobject]@{ Output = @('out 1', 'out 2', (Get-StdErrLine -Text 'err 1')); ExitCode = 3 }
            }

            $result = Invoke-NexusHostCommand @target -Command 'something'

            $result.PSObject.TypeNames | Should -Contain 'NexusFleet.CommandResult'
            $result.HostName | Should -Be '10.0.0.5'
            $result.ExitCode | Should -Be 3
            $result.StdOut | Should -Be "out 1`nout 2"
            $result.StdErr | Should -Be 'err 1'
            $result.Succeeded | Should -BeFalse
        }

        It 'reports exit code 255 as a transport failure' {
            Mock -CommandName Invoke-NexusSshClient -MockWith { [pscustomobject]@{ Output = @(Get-StdErrLine -Text 'Permission denied (publickey).'); ExitCode = 255 } }

            $result = Invoke-NexusHostCommand @target -Command 'true'

            $result.TransportFailed | Should -BeTrue
        }
    }

    Context 'secrets' {
        It 'sends a secret on stdin as bytes, as one line ending in LF only, and never as an argument' {
            # Copy the bytes: the function clears its own array after the call.
            Mock -CommandName Invoke-NexusSshClient -MockWith { $seen.Args = $ArgumentList; $seen.Input = [byte[]]$InputBytes.Clone(); [pscustomobject]@{ Output = @(); ExitCode = 0 } }
            $secret = ConvertTo-SecureString -String 'S3cr3t-value' -AsPlainText -Force

            $null = Invoke-NexusHostCommand @target -Command 'IFS= read -r s' -Secret $secret

            [System.Text.Encoding]::UTF8.GetString($seen.Input) | Should -BeExactly "S3cr3t-value`n"
            ($seen.Args -join ' ') | Should -Not -Match 'S3cr3t-value'
            $seen.Args | Should -Not -Contain '-n'
        }

        It 'sends several secrets as one line each, in order' {
            Mock -CommandName Invoke-NexusSshClient -MockWith { $seen.Input = [byte[]]$InputBytes.Clone(); [pscustomobject]@{ Output = @(); ExitCode = 0 } }
            $first = ConvertTo-SecureString -String 'amqp://u:p@broker:5672' -AsPlainText -Force
            $second = ConvertTo-SecureString -String 'token-2' -AsPlainText -Force

            $null = Invoke-NexusHostCommand @target -Command 'IFS= read -r a; IFS= read -r b' -Secret $first, $second

            [System.Text.Encoding]::UTF8.GetString($seen.Input) | Should -BeExactly "amqp://u:p@broker:5672`ntoken-2`n"
        }

        It 'refuses a secret that contains a line break (it would split into two lines)' {
            Mock -CommandName Invoke-NexusSshClient -MockWith { [pscustomobject]@{ Output = @(); ExitCode = 0 } }
            $secret = ConvertTo-SecureString -String "two`nlines" -AsPlainText -Force

            { Invoke-NexusHostCommand @target -Command 'true' -Secret $secret } | Should -Throw '*line break*'
            Should -Invoke -CommandName Invoke-NexusSshClient -Times 0 -Exactly
        }
    }

    Context 'parameter validation' {
        It 'refuses a host name with characters a host name cannot have: <HostName>' -ForEach @(
            @{ HostName = 'web01; rm -rf /' }
            @{ HostName = '-oProxyCommand=evil' }
            @{ HostName = 'web 01' }
        ) {
            { Invoke-NexusHostCommand -HostName $HostName -UserName 'fleet' -Command 'true' } | Should -Throw
        }

        It 'accepts names, IPv4 and IPv6 addresses: <HostName>' -ForEach @(
            @{ HostName = 'web01.example.com' }
            @{ HostName = '192.168.1.20' }
            @{ HostName = 'fe80::1' }
        ) {
            Mock -CommandName Invoke-NexusSshClient -MockWith { [pscustomobject]@{ Output = @(); ExitCode = 0 } }

            { Invoke-NexusHostCommand -HostName $HostName -UserName 'fleet' -Command 'true' } | Should -Not -Throw
        }

        It 'refuses a port outside 1-65535' {
            { Invoke-NexusHostCommand -HostName 'web01' -Port 70000 -UserName 'fleet' -Command 'true' } | Should -Throw
        }

        It 'refuses a user name that is not a Linux user name' {
            { Invoke-NexusHostCommand -HostName 'web01' -UserName 'fleet;id' -Command 'true' } | Should -Throw
        }
    }
}
