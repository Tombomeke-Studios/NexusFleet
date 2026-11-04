# Integration test: Get-NexusFleetStatus against the node lab (./lab/node-lab/Start-NodeLab.ps1). It first makes
# sure both lab hosts are nodes (Install-NexusNode; nothing to do when they already are), then stops the agent on
# one host and checks that the status shows it, from both sides: the host says the container exited, NexusInfra says
# the node is offline. The agent is started again at the end. Skipped when the lab is not running.
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester: variables set in BeforeAll are used in It blocks and mocks; the analyzer does not look across script blocks.')]
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'Lab-only secrets, created by Start-NodeLab.ps1 in the git-ignored .keys folder.')]
param()

BeforeAll {
    $module = Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../../NexusFleet.psd1') -Force -PassThru
    $keys = Join-Path -Path $PSScriptRoot -ChildPath '../../lab/node-lab/.keys'
    $labAvailable = (Test-Path -Path "$keys/api-token") -and (Test-Path -Path "$keys/inventory.lab.json") -and
    (Test-Connection -TargetName '127.0.0.1' -TcpPort 29400 -TimeoutSeconds 2 -Quiet)
    if (-not $labAvailable) {
        return
    }

    $config = & $module { param($Local) Get-NexusConfig -LocalPath $Local } "$keys/nexusinfra.lab.psd1"
    $settings = @{}
    foreach ($line in Get-Content -Path "$keys/.env") {
        $key, $value = $line -split '=', 2
        $settings[$key] = $value
    }
    $token = ConvertTo-SecureString -String (Get-Content -Path "$keys/api-token" -Raw) -AsPlainText -Force
    $rabbitMqUrl = ConvertTo-SecureString -String "amqp://$($settings.RABBITMQ_USER):$($settings.RABBITMQ_PASS)@172.29.50.10:5672" -AsPlainText -Force
    $internalToken = ConvertTo-SecureString -String $settings.INTERNAL_API_TOKEN -AsPlainText -Force
    $labHosts = @(Import-NexusInventory -Path "$keys/inventory.lab.json")

    $onHost = {
        param($HostInfo, [string]$Command)
        $ssh = @{ HostName = $HostInfo.Address; Port = $HostInfo.Port; UserName = $HostInfo.User; KeyFile = $HostInfo.KeyFile; KnownHostsFile = $config.Ssh.KnownHostsFile }
        & $module { param($Ssh, $Command) Invoke-NexusHostCommand @Ssh -Command $Command } $ssh $Command
    }
}

AfterAll {
    if ($labAvailable) {
        $null = & $onHost $labHosts[1] 'sudo -n docker start nexusinfra-node-agent'
    }
    Remove-Module -Name NexusFleet -Force -ErrorAction SilentlyContinue
}

Describe 'Get-NexusFleetStatus against the node lab' -Tag 'Integration' {
    BeforeAll {
        if (-not $labAvailable) {
            return
        }
        Mock -ModuleName NexusFleet -CommandName Get-NexusConfig -MockWith { $config }
        $null = Connect-NexusInfra -Token $token
        $installed = @($labHosts | Install-NexusNode -RabbitMqUrl $rabbitMqUrl -InternalApiToken $internalToken)

        $before = @($labHosts | Get-NexusFleetStatus)

        # Stop the agent on the second host, and wait until NexusInfra notices (offline after 10 s without heartbeat).
        $null = & $onHost $labHosts[1] 'sudo -n docker stop nexusinfra-node-agent'
        Start-Sleep -Seconds ($config.Health.OfflineAfterSeconds + 2)
        $after = @($labHosts | Get-NexusFleetStatus)
    }

    BeforeEach {
        if (-not $labAvailable) {
            Set-ItResult -Skipped -Because 'the node lab is not running (./lab/node-lab/Start-NodeLab.ps1)'
        }
    }

    It 'shows both lab nodes as ok after the installation, with data from NexusInfra and from the host' {
        $installed.Success | Should -Not -Contain $false
        foreach ($status in $before) {
            $status.Ok | Should -BeTrue -Because "$($status.Name): $($status.Problem)"
            $status.Health | Should -Be 'healthy'
            $status.Reachable | Should -BeTrue
            $status.AgentState | Should -Be 'running'
            $status.Docker | Should -Match '^Docker version'
            $status.LastHeartbeat | Should -BeGreaterThan ([datetime]::UtcNow.AddMinutes(-1))
        }
    }

    It 'shows a stopped agent from both sides: exited on the host, offline in NexusInfra' {
        ($after | Where-Object Name -EQ $labHosts[0].Name).Ok | Should -BeTrue
        $stopped = $after | Where-Object Name -EQ $labHosts[1].Name
        $stopped.Ok | Should -BeFalse
        $stopped.AgentState | Should -Be 'exited'
        $stopped.Health | Should -Be 'offline'
        $stopped.Problem | Should -Be 'NexusInfra reports it offline; the agent container is exited'
    }

    It 'exports the status to CSV and JSON' {
        $csv = $after | Export-NexusFleetStatus -Path (Join-Path -Path $TestDrive -ChildPath 'lab.csv')
        $json = $after | Export-NexusFleetStatus -Path (Join-Path -Path $TestDrive -ChildPath 'lab.json')

        @(Import-Csv -Path $csv.FullName).Count | Should -Be 2
        (Get-Content -Path $json.FullName -Raw | ConvertFrom-Json).nodes.Count | Should -Be 2
    }
}
