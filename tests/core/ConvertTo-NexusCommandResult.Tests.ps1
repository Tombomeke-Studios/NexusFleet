BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../src/core/ConvertTo-NexusCommandResult.ps1')
}

Describe 'ConvertTo-NexusCommandResult' {
    It 'builds the result object of the transport contract' {
        $result = ConvertTo-NexusCommandResult -HostName 'web01' -ExitCode 0 -StdOut 'line 1', 'line 2' -StdErr @()

        $result.PSObject.TypeNames | Should -Contain 'NexusFleet.CommandResult'
        $result.HostName | Should -Be 'web01'
        $result.ExitCode | Should -Be 0
        $result.StdOut | Should -Be "line 1`nline 2"
        $result.StdErr | Should -Be ''
        $result.Succeeded | Should -BeTrue
        $result.TransportFailed | Should -BeFalse
    }

    It 'marks a non-zero exit code as not succeeded' {
        (ConvertTo-NexusCommandResult -HostName 'web01' -ExitCode 7).Succeeded | Should -BeFalse
    }

    It 'marks exit code 255 as a transport failure (ssh itself failed: connection or authentication)' {
        $result = ConvertTo-NexusCommandResult -HostName 'web01' -ExitCode 255 -StdErr 'Permission denied (publickey).'

        $result.TransportFailed | Should -BeTrue
        $result.StdErr | Should -Be 'Permission denied (publickey).'
    }
}
