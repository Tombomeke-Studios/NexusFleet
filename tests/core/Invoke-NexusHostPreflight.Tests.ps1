[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester: variables set in BeforeAll/BeforeEach are used in It blocks and mocks; the analyzer does not look across script blocks.')]
param()

BeforeAll {
    foreach ($file in 'core/ConvertTo-NexusCommandResult', 'transports/Invoke-NexusSshClient', 'transports/Invoke-NexusHostCommand',
        'utils/Initialize-NexusRunContext', 'utils/Write-NexusLog', 'core/Invoke-NexusHostPreflight') {
        . (Join-Path -Path $PSScriptRoot -ChildPath "../../src/$file.ps1")
    }

    $hostInfo = [pscustomobject]@{
        PSTypeName = 'NexusFleet.Host'; Name = 'node-web01'; Address = '10.0.0.5'; Port = 22; User = 'fleet'
        Location = 'home'; Role = $null; KeyFile = $null; AgentUrl = 'http://10.0.0.5:9100'
    }
    $config = @{
        Broker    = @{ Host = 'broker.example.com'; Port = 5672 }
        Ssh       = @{ ConnectTimeoutSeconds = 7; KnownHostsFile = '' }
        Preflight = @{ MinDiskFreeMB = 2048; SupportedOs = @('ubuntu'); ThrottleLimit = 10 }
    }

    # The facts script answers with key=value lines; tests change one fact at a time.
    function Get-FactsResult {
        param([hashtable]$Change = @{})
        $facts = [ordered]@{ os = 'ubuntu'; osversion = '24.04'; sudo = 'yes'; diskfreemb = '20000'; docker = 'Docker version 27.3.1'; broker = 'yes' }
        foreach ($key in $Change.Keys) { $facts[$key] = $Change[$key] }
        ConvertTo-NexusCommandResult -HostName '10.0.0.5' -ExitCode 0 -StdOut ($facts.Keys | ForEach-Object { "$_=$($facts[$_])" })
    }
}

Describe 'Invoke-NexusHostPreflight' {
    BeforeEach {
        $facts = @{}
        Mock -CommandName Invoke-NexusHostCommand -ParameterFilter { $Command -eq 'true' } -MockWith {
            ConvertTo-NexusCommandResult -HostName '10.0.0.5' -ExitCode 0
        }
        Mock -CommandName Invoke-NexusHostCommand -ParameterFilter { $Command -like '*os-release*' } -MockWith { Get-FactsResult -Change $facts }
    }

    It 'passes every check on a ready host and returns one result object' {
        $result = Invoke-NexusHostPreflight -HostInfo $hostInfo -Config $config

        $result.PSObject.TypeNames | Should -Contain 'NexusFleet.PreflightResult'
        $result.Host | Should -Be 'node-web01'
        $result.Address | Should -Be '10.0.0.5'
        $result.Success | Should -BeTrue
        $result.Step | Should -BeNullOrEmpty
        $result.Checks.Name | Should -Be @('Reachable', 'SshAuth', 'OS', 'Sudo', 'DiskSpace', 'Docker', 'Broker')
        $result.Checks.Status | Should -Be @('Pass', 'Pass', 'Pass', 'Pass', 'Pass', 'Pass', 'Pass')
    }

    It 'uses the host''s address, port, user and key and the configured ssh settings' {
        $withKey = $hostInfo.PSObject.Copy()
        $withKey.KeyFile = 'C:\keys\fleet'
        $sshConfig = @{ Broker = $config.Broker; Preflight = $config.Preflight; Ssh = @{ ConnectTimeoutSeconds = 7; KnownHostsFile = 'C:\keys\known_hosts' } }

        $null = Invoke-NexusHostPreflight -HostInfo $withKey -Config $sshConfig

        Should -Invoke -CommandName Invoke-NexusHostCommand -ParameterFilter {
            $HostName -eq '10.0.0.5' -and $Port -eq 22 -and $UserName -eq 'fleet' -and $KeyFile -eq 'C:\keys\fleet' -and
            $KnownHostsFile -eq 'C:\keys\known_hosts' -and $ConnectTimeoutSeconds -eq 7
        }
    }

    It 'checks the configured broker address from the host' {
        $null = Invoke-NexusHostPreflight -HostInfo $hostInfo -Config $config

        Should -Invoke -CommandName Invoke-NexusHostCommand -ParameterFilter { $Command -like '*/dev/tcp/broker.example.com/5672*' }
    }

    It 'only warns when Docker is missing, because the install adds it' {
        $facts = @{ docker = '' }

        $result = Invoke-NexusHostPreflight -HostInfo $hostInfo -Config $config

        $result.Success | Should -BeTrue
        ($result.Checks | Where-Object Name -EQ 'Docker').Status | Should -Be 'Warning'
    }

    Context 'a host that is not ready' {
        It 'stops at Reachable when ssh cannot connect, and runs no other check' {
            Mock -CommandName Invoke-NexusHostCommand -ParameterFilter { $Command -eq 'true' } -MockWith {
                ConvertTo-NexusCommandResult -HostName '10.0.0.5' -ExitCode 255 -StdErr 'ssh: connect to host 10.0.0.5 port 22: Connection timed out'
            }

            $result = Invoke-NexusHostPreflight -HostInfo $hostInfo -Config $config

            $result.Success | Should -BeFalse
            $result.Step | Should -Be 'Reachable'
            $result.Error | Should -Match 'Connection timed out'
            Should -Invoke -CommandName Invoke-NexusHostCommand -ParameterFilter { $Command -like '*os-release*' } -Times 0 -Exactly
        }

        It 'reports SshAuth when the host answers but refuses the key' {
            Mock -CommandName Invoke-NexusHostCommand -ParameterFilter { $Command -eq 'true' } -MockWith {
                ConvertTo-NexusCommandResult -HostName '10.0.0.5' -ExitCode 255 -StdErr 'fleet@10.0.0.5: Permission denied (publickey).'
            }

            $result = Invoke-NexusHostPreflight -HostInfo $hostInfo -Config $config

            $result.Step | Should -Be 'SshAuth'
            ($result.Checks | Where-Object Name -EQ 'Reachable').Status | Should -Be 'Pass'
        }

        It 'fails <Check> when <Fact> is <Value>' -ForEach @(
            @{ Check = 'OS'; Fact = 'os'; Value = 'centos'; Detail = '*centos*ubuntu*' }
            @{ Check = 'Sudo'; Fact = 'sudo'; Value = 'no'; Detail = '*sudo*password*' }
            @{ Check = 'DiskSpace'; Fact = 'diskfreemb'; Value = '500'; Detail = '*500 MB*2048 MB*' }
            @{ Check = 'Broker'; Fact = 'broker'; Value = 'no'; Detail = '*broker.example.com:5672*' }
        ) {
            $facts = @{ $Fact = $Value }

            $result = Invoke-NexusHostPreflight -HostInfo $hostInfo -Config $config

            $result.Success | Should -BeFalse
            $result.Step | Should -Be $Check
            $failed = $result.Checks | Where-Object Name -EQ $Check
            $failed.Status | Should -Be 'Fail'
            $failed.Detail | Should -BeLike $Detail
        }

        It 'reports every failed check, and Step is the first one' {
            $facts = @{ sudo = 'no'; diskfreemb = '100' }

            $result = Invoke-NexusHostPreflight -HostInfo $hostInfo -Config $config

            $result.Step | Should -Be 'Sudo'
            @($result.Checks | Where-Object Status -EQ 'Fail').Name | Should -Be @('Sudo', 'DiskSpace')
        }

        It 'never throws: an unexpected error becomes a failed result' {
            Mock -CommandName Invoke-NexusHostCommand -ParameterFilter { $Command -eq 'true' } -MockWith { throw 'something unexpected' }

            $result = Invoke-NexusHostPreflight -HostInfo $hostInfo -Config $config

            $result.Success | Should -BeFalse
            $result.Step | Should -Be 'Preflight'
            $result.Error | Should -Match 'something unexpected'
        }
    }

    It 'logs every check to the host''s log when a run context is given' {
        $runContext = Initialize-NexusRunContext -LogRoot $TestDrive
        $facts = @{ docker = '' }

        $null = Invoke-NexusHostPreflight -HostInfo $hostInfo -Config $config -RunContext $runContext

        $log = (Get-Content -Path (Join-Path -Path $runContext.LogDirectory -ChildPath 'node-web01.log')) -join "`n"
        $log | Should -Match 'step=OS .*Pass'
        $log | Should -Match 'WARNING .*step=Docker'
    }
}
