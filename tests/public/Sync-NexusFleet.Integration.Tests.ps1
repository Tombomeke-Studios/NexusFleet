# Integration test: Sync-NexusFleet against the node lab (./lab/node-lab/Start-NodeLab.ps1). Everything is real.
# It installs the lab hosts, then makes them drift the way real nodes do:
#   - node-lab1: its location is changed in NexusInfra (a label edited in the panel),
#   - node-lab2: its agent container is removed on the host.
# Then: -WhatIf reports both differences and changes nothing, one command repairs both, and the next run finds nothing.
# Skipped when the lab is not running. Takes about a minute.
# Run: Invoke-Pester -Path ./tests/public/Sync-NexusFleet.Integration.Tests.ps1 -TagFilter Integration -Output Detailed
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
    $secrets = @{ RabbitMqUrl = $rabbitMqUrl; InternalApiToken = $internalToken }

    $labHosts = @(Import-NexusInventory -Path "$keys/inventory.lab.json")
    $api = @{ BaseUrl = $config.Api.BaseUrl; Token = $token }
    $getNodes = { @(& $module { param($Api) Invoke-NexusApi @Api -Method GET -Path '/nodes' } $api) }
}

AfterAll {
    Remove-Module -Name NexusFleet -Force -ErrorAction SilentlyContinue
}

Describe 'Sync-NexusFleet against the node lab' -Tag 'Integration' {
    BeforeAll {
        if (-not $labAvailable) {
            return
        }
        Mock -ModuleName NexusFleet -CommandName Get-NexusConfig -MockWith { $config }
        $null = Connect-NexusInfra -Token $token

        $installed = @($labHosts | Install-NexusNode -ThrottleLimit 3 @secrets)
        $clean = @($labHosts | Sync-NexusFleet -ThrottleLimit 3 -WhatIf)

        # Drift 1: a label edited in the panel.
        $first = $labHosts[0]
        $null = & $module { param($Api, $Body) Invoke-NexusApi @Api -Method POST -Path '/nodes' -Body $Body } $api @{
            id = $first.Name; name = $first.Name; location = 'moved-by-hand'; agentUrl = $first.AgentUrl
        }
        # Drift 2: an agent container removed on the host.
        $second = $labHosts[1]
        $ssh = @{ HostName = $second.Address; Port = $second.Port; UserName = $second.User; KeyFile = $second.KeyFile; KnownHostsFile = $config.Ssh.KnownHostsFile }
        $null = & $module { param($Ssh) Invoke-NexusHostCommand @Ssh -Command 'sudo -n docker rm -f nexusinfra-node-agent' } $ssh

        $report = @($labHosts | Sync-NexusFleet -ThrottleLimit 3 -WhatIf)
        $nodesAfterReport = & $getNodes
        $repair = @($labHosts | Sync-NexusFleet -ThrottleLimit 3 -Confirm:$false @secrets)
        $nodesAfterRepair = & $getNodes
        $again = @($labHosts | Sync-NexusFleet -ThrottleLimit 3 -WhatIf)
    }

    BeforeEach {
        if (-not $labAvailable) {
            Set-ItResult -Skipped -Because 'the node lab is not running (./lab/node-lab/Start-NodeLab.ps1)'
        }
    }

    It 'finds no drift right after an install' {
        $installed.Success | Should -Not -Contain $false -Because ($installed.Error -join '; ')
        foreach ($name in $labHosts.Name) {
            ($clean | Where-Object Host -EQ $name).InSync | Should -BeTrue -Because (($clean | Where-Object Host -EQ $name).Differences -join '; ')
        }
    }

    It '-WhatIf reports the changed label in words and changes nothing' {
        $result = $report | Where-Object Host -EQ $labHosts[0].Name
        $result.InSync | Should -BeFalse
        $result.Differences | Should -Be @("RegisterNode: location is 'moved-by-hand', not '$($labHosts[0].Location)'")
        ($nodesAfterReport | Where-Object id -EQ $labHosts[0].Name).location | Should -Be 'moved-by-hand'
    }

    It '-WhatIf reports the agent container that is gone' {
        $result = $report | Where-Object Host -EQ $labHosts[1].Name
        $result.InSync | Should -BeFalse
        $result.Differences | Should -Contain 'AgentContainer: there is no agent container'
    }

    It 'one command repairs both nodes' {
        foreach ($name in $labHosts.Name) {
            $result = $repair | Where-Object Host -EQ $name
            $result.Repaired | Should -BeTrue -Because "$name should be repaired: $($result.Error)"
            ($nodesAfterRepair | Where-Object id -EQ $name).health | Should -Be 'healthy'
        }
        ($nodesAfterRepair | Where-Object id -EQ $labHosts[0].Name).location | Should -Be $labHosts[0].Location
    }

    It 'the run after the repair finds no drift' {
        foreach ($name in $labHosts.Name) {
            ($again | Where-Object Host -EQ $name).InSync | Should -BeTrue -Because (($again | Where-Object Host -EQ $name).Differences -join '; ')
        }
    }
}
