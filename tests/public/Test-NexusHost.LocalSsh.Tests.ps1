# The real parallel path of Test-NexusHost: real ForEach-Object -Parallel runspaces and the real ssh client, no mocks
# on that path. The hosts point at free (closed) ports on this machine, so every ssh fails at once with "Connection
# refused": no network and no lab needed, so this runs in CI. It proves that every host gets its own result, that
# nothing crashes, and that logging from the runspaces works.
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester: variables set in BeforeAll are used in It blocks and mocks; the analyzer does not look across script blocks.')]
param()

BeforeAll {
    $module = Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../../NexusFleet.psd1') -Force -PassThru

    # Twelve free ports: let the system pick them, then release them, so nothing listens there.
    $ports = foreach ($i in 1..12) {
        $probe = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
        $probe.Start(); $probe.LocalEndpoint.Port; $probe.Stop()
    }
    $hosts = for ($i = 0; $i -lt $ports.Count; $i++) {
        [pscustomobject]@{
            PSTypeName = 'NexusFleet.Host'; Name = 'node-closed{0:d2}' -f ($i + 1); Address = '127.0.0.1'; Port = $ports[$i]
            User = 'fleet'; Location = 'lab'; Role = $null; KeyFile = $null; AgentUrl = $null
        }
    }
    $config = @{
        Broker    = @{ Host = 'localhost'; Port = 5672 }
        Ssh       = @{ ConnectTimeoutSeconds = 5; KnownHostsFile = '' }
        Preflight = @{ MinDiskFreeMB = 2048; SupportedOs = @('ubuntu'); ThrottleLimit = 4 }
    }
}

AfterAll {
    Remove-Module -Name NexusFleet -Force -ErrorAction SilentlyContinue
}

Describe 'Test-NexusHost in parallel with the real ssh client' -Tag 'LocalSsh' {
    BeforeAll {
        # Read in the main runspace and passed into the runspaces with $using:, so these replacements reach them.
        $runContext = & $module { param($Root) Initialize-NexusRunContext -LogRoot $Root } $TestDrive
        Mock -ModuleName NexusFleet -CommandName Initialize-NexusRunContext -MockWith { $runContext }
        Mock -ModuleName NexusFleet -CommandName Get-NexusConfig -MockWith { $config }

        $results = @($hosts | Test-NexusHost -ThrottleLimit 4)
    }

    It 'returns exactly one result for every host' {
        $results | Should -HaveCount 12
        @($results.Host | Sort-Object -Unique) | Should -Be @($hosts.Name | Sort-Object)
    }

    It 'reports every closed port as not reachable, with ssh''s reason' {
        $results.Success | Should -Not -Contain $true
        @($results.Step | Sort-Object -Unique) | Should -Be @('Reachable')
        $results[0].Error | Should -Match 'refused|connect'
    }

    It 'logged every host from inside its runspace, in its own file' {
        foreach ($name in $hosts.Name) {
            Get-Content -Path (Join-Path -Path $runContext.LogDirectory -ChildPath "$name.log") -Raw | Should -Match 'step=Reachable'
        }
        Get-Content -Path (Join-Path -Path $runContext.LogDirectory -ChildPath 'run.log') -Raw | Should -Match 'Preflight done: 0 of 12'
    }
}
