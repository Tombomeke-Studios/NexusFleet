[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester: variables set in BeforeAll/BeforeEach are used in It blocks and mocks; the analyzer does not look across script blocks.')]
param()

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../src/utils/Get-NexusSshParameter.ps1')

    $config = @{ Ssh = @{ ConnectTimeoutSeconds = 7; KnownHostsFile = $null } }
    $hostInfo = [pscustomobject]@{ Name = 'node-a'; Address = '10.0.0.5'; Port = 2222; User = 'fleet'; KeyFile = $null }
}

Describe 'Get-NexusSshParameter' {
    It 'takes address, port and user from the host and the time-out from the config' {
        $ssh = Get-NexusSshParameter -HostInfo $hostInfo -Config $config

        $ssh.HostName | Should -Be '10.0.0.5'
        $ssh.Port | Should -Be 2222
        $ssh.UserName | Should -Be 'fleet'
        $ssh.ConnectTimeoutSeconds | Should -Be 7
    }

    It 'leaves out the key and known_hosts file when neither is set, so ssh uses its defaults' {
        $ssh = Get-NexusSshParameter -HostInfo $hostInfo -Config $config

        $ssh.Keys | Should -Not -Contain 'KeyFile'
        $ssh.Keys | Should -Not -Contain 'KnownHostsFile'
    }

    It 'passes the key of the host and the known_hosts file of the config when they are set' {
        $withKey = $hostInfo.PSObject.Copy()
        $withKey.KeyFile = '/keys/node-a'
        $withKnownHosts = @{ Ssh = @{ ConnectTimeoutSeconds = 7; KnownHostsFile = '/keys/known_hosts' } }

        $ssh = Get-NexusSshParameter -HostInfo $withKey -Config $withKnownHosts

        $ssh.KeyFile | Should -Be '/keys/node-a'
        $ssh.KnownHostsFile | Should -Be '/keys/known_hosts'
    }
}
