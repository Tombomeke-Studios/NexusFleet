# The real parallel path of Install-NexusNode: real ForEach-Object -Parallel runspaces and the real ssh client, no
# mocks on that path. The hosts point at free (closed) ports on this machine, so every preflight fails at once with
# "Connection refused" and nothing is installed: no network and no lab needed, so this runs in CI. It proves that
# the module, the session and the secrets reach the runspaces, that every host gets its own result, and that
# nothing crashes. The full installation is proven against the lab (Install-NexusNode.Integration.Tests.ps1).
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester: variables set in BeforeAll are used in It blocks and mocks; the analyzer does not look across script blocks.')]
param()

BeforeAll {
    $module = Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../../NexusFleet.psd1') -Force -PassThru
    . (Join-Path -Path $PSScriptRoot -ChildPath '../core/FakeFleet.ps1')

    # Ten free ports: let the system pick them, then release them, so nothing listens there.
    $ports = foreach ($i in 1..10) {
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
    $secrets = Get-FakeSecretSet
}

AfterAll {
    Remove-Module -Name NexusFleet -Force -ErrorAction SilentlyContinue
}

Describe 'Install-NexusNode in parallel with the real ssh client' -Tag 'LocalSsh' {
    BeforeAll {
        & $module { param($Session) $script:NexusSession = $Session } (Get-FakeSession)
        # Read in the main runspace and passed into the runspaces with $using:, so these replacements reach them.
        $runContext = & $module { param($Root) Initialize-NexusRunContext -LogRoot $Root } $TestDrive
        Mock -ModuleName NexusFleet -CommandName Initialize-NexusRunContext -MockWith { $runContext }
        Mock -ModuleName NexusFleet -CommandName Get-NexusConfig -MockWith { $config }

        $results = @($hosts | Install-NexusNode -ThrottleLimit 4 -RabbitMqUrl $secrets.RabbitMqUrl -InternalApiToken $secrets.InternalApiToken)
    }

    It 'returns exactly one InstallResult for every host' {
        $results | Should -HaveCount 10
        @($results.Host | Sort-Object -Unique) | Should -Be @($hosts.Name | Sort-Object)
        $results[0].PSObject.TypeNames | Should -Contain 'NexusFleet.InstallResult'
    }

    It 'stops every unreachable host at the preflight, changing nothing' {
        $results.Success | Should -Not -Contain $true
        $results.Changed | Should -Not -Contain $true
        @($results.Step | Sort-Object -Unique) | Should -Be @('Reachable')
        $results[0].Error | Should -Match '^preflight failed, nothing was changed'
    }

    It 'logged every host from inside its runspace, and the summary' {
        foreach ($name in $hosts.Name) {
            Get-Content -Path (Join-Path -Path $runContext.LogDirectory -ChildPath "$name.log") -Raw | Should -Match 'step=Reachable'
        }
        Get-Content -Path (Join-Path -Path $runContext.LogDirectory -ChildPath 'run.log') -Raw | Should -Match 'Install done: 0 of 10'
    }
}
