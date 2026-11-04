[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester: variables set in BeforeAll/BeforeEach are used in It blocks and mocks; the analyzer does not look across script blocks.')]
param()

BeforeAll {
    foreach ($file in 'core/ConvertTo-NexusCommandResult', 'transports/Invoke-NexusSshClient', 'transports/Invoke-NexusHostCommand',
        'utils/ConvertTo-NexusShellArgument', 'utils/Initialize-NexusRunContext', 'utils/Write-NexusLog', 'utils/Get-NexusSshParameter', 'utils/ConvertFrom-NexusFactLine', 'core/Get-NexusHostStatus') {
        . (Join-Path -Path $PSScriptRoot -ChildPath "../../src/$file.ps1")
    }
    $hostInfo = [pscustomobject]@{
        PSTypeName = 'NexusFleet.Host'; Name = 'node-web01'; Address = '10.0.0.5'; Port = 22; User = 'fleet'
        Location = 'home'; Role = $null; KeyFile = $null; AgentUrl = 'http://10.0.0.5:9100'
    }
    $config = @{ Ssh = @{ ConnectTimeoutSeconds = 7; KnownHostsFile = '' }; Agent = @{ ContainerName = 'nexusinfra-node-agent' } }

    function Get-FactsResult {
        param([hashtable]$Change = @{})
        $facts = [ordered]@{
            uptime = '86400'; diskfreemb = '20000'; docker = 'Docker version 27.3.1'
            agent = 'running|2026-11-04T07:34:06.72Z|0|ghcr.io/tombomeke-studios/nexusinfra/node-agent:community'
        }
        foreach ($key in $Change.Keys) { $facts[$key] = $Change[$key] }
        ConvertTo-NexusCommandResult -HostName '10.0.0.5' -ExitCode 0 -StdOut ($facts.Keys | ForEach-Object { "$_=$($facts[$_])" })
    }
}

Describe 'Get-NexusHostStatus' {
    It 'reads uptime, free disk, Docker and the agent container in one ssh call' {
        Mock -CommandName Invoke-NexusHostCommand -MockWith { Get-FactsResult }

        $status = Get-NexusHostStatus -HostInfo $hostInfo -Config $config

        $status.PSObject.TypeNames | Should -Contain 'NexusFleet.HostStatus'
        $status.Reachable | Should -BeTrue
        $status.UptimeSeconds | Should -Be 86400
        $status.DiskFreeMB | Should -Be 20000
        $status.Docker | Should -Be 'Docker version 27.3.1'
        $status.AgentState | Should -Be 'running'
        $status.AgentRestarts | Should -Be 0
        $status.AgentImage | Should -Match 'node-agent:community$'
        Should -Invoke -CommandName Invoke-NexusHostCommand -Times 1 -Exactly -ParameterFilter {
            $HostName -eq '10.0.0.5' -and $Command -match "docker inspect .* 'nexusinfra-node-agent'"
        }
    }

    It 'uses the host''s key file and the configured known_hosts file' {
        Mock -CommandName Invoke-NexusHostCommand -MockWith { Get-FactsResult }
        $withKey = $hostInfo.PSObject.Copy()
        $withKey.KeyFile = 'C:/keys/fleet'
        $sshConfig = @{ Ssh = @{ ConnectTimeoutSeconds = 7; KnownHostsFile = 'C:/keys/known_hosts' }; Agent = $config.Agent }

        $null = Get-NexusHostStatus -HostInfo $withKey -Config $sshConfig

        Should -Invoke -CommandName Invoke-NexusHostCommand -Times 1 -Exactly -ParameterFilter {
            $KeyFile -eq 'C:/keys/fleet' -and $KnownHostsFile -eq 'C:/keys/known_hosts' -and $ConnectTimeoutSeconds -eq 7
        }
    }
    It 'reports a missing agent container as missing' {
        Mock -CommandName Invoke-NexusHostCommand -MockWith { Get-FactsResult -Change @{ agent = '' } }

        (Get-NexusHostStatus -HostInfo $hostInfo -Config $config).AgentState | Should -Be 'missing'
    }

    It 'reports a stopped agent with its state and restart count' {
        Mock -CommandName Invoke-NexusHostCommand -MockWith { Get-FactsResult -Change @{ agent = 'exited|2026-11-04T07:00:00Z|5|img' } }

        $status = Get-NexusHostStatus -HostInfo $hostInfo -Config $config

        $status.AgentState | Should -Be 'exited'
        $status.AgentRestarts | Should -Be 5
    }

    It 'reports a host without Docker' {
        Mock -CommandName Invoke-NexusHostCommand -MockWith { Get-FactsResult -Change @{ docker = ''; agent = '' } }

        $status = Get-NexusHostStatus -HostInfo $hostInfo -Config $config

        $status.Docker | Should -BeNullOrEmpty
        $status.AgentState | Should -Be 'missing'
    }

    It 'reports an unreachable host with ssh''s reason, without throwing' {
        Mock -CommandName Invoke-NexusHostCommand -MockWith { ConvertTo-NexusCommandResult -HostName '10.0.0.5' -ExitCode 255 -StdErr 'Connection timed out' }

        $status = Get-NexusHostStatus -HostInfo $hostInfo -Config $config

        $status.Reachable | Should -BeFalse
        $status.Error | Should -Match 'cannot reach 10.0.0.5:22 over ssh: Connection timed out'
        $status.AgentState | Should -BeNullOrEmpty
    }

    It 'turns an unexpected error into an unreachable status' {
        Mock -CommandName Invoke-NexusHostCommand -MockWith { throw 'boom' }

        $status = Get-NexusHostStatus -HostInfo $hostInfo -Config $config

        $status.Reachable | Should -BeFalse
        $status.Error | Should -Match 'failed unexpectedly: boom'
    }

    It 'logs the outcome in the host''s log' {
        Mock -CommandName Invoke-NexusHostCommand -MockWith { Get-FactsResult }
        $run = Initialize-NexusRunContext -LogRoot $TestDrive

        $null = Get-NexusHostStatus -HostInfo $hostInfo -Config $config -RunContext $run

        Get-Content -Path (Join-Path -Path $run.LogDirectory -ChildPath 'node-web01.log') -Raw | Should -Match 'step=Status.*reachable, agent running'
    }
}
