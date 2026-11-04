# The real parallel path of Get-NexusFleetStatus: real ForEach-Object -Parallel runspaces and the real ssh client to
# free (closed) ports on this machine, so every host is unreachable at once. NexusInfra's answer is mocked: it is read
# in the main runspace, before the parallel loop. Runs in CI: it proves one status per host from real runspaces, with
# every unreachable host reported and nothing crashing.
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester: variables set in BeforeAll are used in It blocks and mocks; the analyzer does not look across script blocks.')]
param()

BeforeAll {
    $module = Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../../NexusFleet.psd1') -Force -PassThru
    . (Join-Path -Path $PSScriptRoot -ChildPath '../core/FakeFleet.ps1')

    $ports = foreach ($i in 1..8) {
        $probe = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
        $probe.Start(); $probe.LocalEndpoint.Port; $probe.Stop()
    }
    $hosts = for ($i = 0; $i -lt $ports.Count; $i++) {
        $hostInfo = Get-FakeHostInfo -Name ('node-closed{0:d2}' -f ($i + 1)) -Address '127.0.0.1'
        $hostInfo.Port = $ports[$i]
        $hostInfo
    }
    $config = & $module { Get-NexusConfig }
    $config.Ssh.KnownHostsFile = ''
}

AfterAll {
    Remove-Module -Name NexusFleet -Force -ErrorAction SilentlyContinue
}

Describe 'Get-NexusFleetStatus in parallel with the real ssh client' -Tag 'LocalSsh' {
    BeforeAll {
        & $module { param($Session) $script:NexusSession = $Session } (Get-FakeSession)
        $runContext = & $module { param($Root) Initialize-NexusRunContext -LogRoot $Root } $TestDrive
        Mock -ModuleName NexusFleet -CommandName Initialize-NexusRunContext -MockWith { $runContext }
        Mock -ModuleName NexusFleet -CommandName Get-NexusConfig -MockWith { $config }
        Mock -ModuleName NexusFleet -CommandName Invoke-NexusApi -MockWith {
            [pscustomobject]@{ id = 'node-closed01'; name = 'node-closed01'; health = 'healthy'; maintenance = $false; lastHeartbeat = '2026-11-04T07:35:00Z' }
        }

        $results = @($hosts | Get-NexusFleetStatus -ThrottleLimit 4)
    }

    It 'returns one status per host, in the order of the inventory' {
        $results.Name | Should -Be @($hosts.Name)
    }

    It 'reports every host as unreachable, with ssh''s reason, and merges NexusInfra''s view' {
        $results.Reachable | Should -Not -Contain $true
        $results[0].Health | Should -Be 'healthy'
        $results[0].Problem | Should -Match 'cannot reach 127.0.0.1:\d+ over ssh: .*(refused|connect)'
        $results[1].Problem | Should -Match '^not registered in NexusInfra; cannot reach'
    }

    It 'logged every host from inside its runspace' {
        foreach ($name in $hosts.Name) {
            Get-Content -Path (Join-Path -Path $runContext.LogDirectory -ChildPath "$name.log") -Raw | Should -Match 'step=Status'
        }
    }
}
