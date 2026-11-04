# Integration test: the three "Klaar als" criteria of the MVP, end to end, against the node lab
# (./lab/node-lab/Start-NodeLab.ps1: a real NexusInfra control plane and two fresh Ubuntu hosts in Docker).
#   1. one command turns the hosts into healthy nodes,
#   2. a second run changes nothing,
#   3. one failing host does not stop the others.
# Everything is real: Connect-NexusInfra with the lab's API token, ssh, the parallel runspaces, apt, docker, the API.
# It starts by undoing an earlier run (agent, env file, Docker, node records), so it can be run again.
# Skipped when the lab is not running. Takes one to three minutes.
# Run: Invoke-Pester -Path ./tests/public/Install-NexusNode.Integration.Tests.ps1 -TagFilter Integration -Output Detailed
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
    # A third host on a closed port: it must fail on its own.
    $broken = $labHosts[0].PSObject.Copy()
    $broken.Name = 'node-lab-broken'
    $broken.Port = 2239
    $allHosts = $labHosts + $broken

    $api = @{ BaseUrl = $config.Api.BaseUrl; Token = $token }
    $getNodes = { @(& $module { param($Api) Invoke-NexusApi @Api -Method GET -Path '/nodes' } $api) }
}

AfterAll {
    Remove-Module -Name NexusFleet -Force -ErrorAction SilentlyContinue
}

Describe 'Install-NexusNode against the node lab' -Tag 'Integration' {
    BeforeAll {
        if (-not $labAvailable) {
            return
        }
        Mock -ModuleName NexusFleet -CommandName Get-NexusConfig -MockWith { $config }
        $null = Connect-NexusInfra -Token $token

        # Undo an earlier run: the hosts become fresh again (the Docker image cache stays, which keeps this fast).
        foreach ($hostInfo in $labHosts) {
            $ssh = @{ HostName = $hostInfo.Address; Port = $hostInfo.Port; UserName = $hostInfo.User; KeyFile = $hostInfo.KeyFile; KnownHostsFile = $config.Ssh.KnownHostsFile }
            $null = & $module { param($Ssh) Invoke-NexusHostCommand @Ssh -Command (
                    'sudo -n docker rm -f nexusinfra-node-agent >/dev/null 2>&1; sudo -n rm -f /etc/nexusinfra/agent.env; ' +
                    'sudo -n env DEBIAN_FRONTEND=noninteractive apt-get remove -y -q docker.io >/dev/null 2>&1; true') } $ssh
            if ((& $getNodes).id -contains $hostInfo.Name) {
                $null = & $module { param($Api, $Id) Invoke-NexusApi @Api -Method DELETE -Path "/nodes/$Id" } $api $hostInfo.Name
            }
        }

        $plan = @($allHosts | Install-NexusNode -WhatIf -ThrottleLimit 3)
        $nodesAfterPlan = & $getNodes
        $first = @($allHosts | Install-NexusNode -ThrottleLimit 3 -RabbitMqUrl $rabbitMqUrl -InternalApiToken $internalToken)
        $second = @($labHosts | Install-NexusNode -ThrottleLimit 3 -RabbitMqUrl $rabbitMqUrl -InternalApiToken $internalToken)
        $nodesAtEnd = & $getNodes
    }

    BeforeEach {
        if (-not $labAvailable) {
            Set-ItResult -Skipped -Because 'the node lab is not running (./lab/node-lab/Start-NodeLab.ps1)'
        }
    }

    It '-WhatIf plans every step on the fresh hosts and changes nothing' {
        foreach ($name in $labHosts.Name) {
            ($plan | Where-Object Host -EQ $name).Steps.Outcome | Should -Be @('WouldApply', 'WouldApply', 'WouldApply', 'WouldApply')
        }
        $nodesAfterPlan.id | Should -Not -Contain $labHosts[0].Name
    }

    It '1. one command turns the lab hosts into healthy nodes' {
        foreach ($name in $labHosts.Name) {
            $result = $first | Where-Object Host -EQ $name
            $result.Success | Should -BeTrue -Because "$name should succeed: $($result.Error)"
            $result.Steps.Outcome | Should -Be @('Applied', 'Applied', 'Applied', 'Applied')
            ($nodesAtEnd | Where-Object id -EQ $name).health | Should -Be 'healthy'
        }
    }

    It '2. a second run changes nothing' {
        $second.Changed | Should -Not -Contain $true
        $second.Success | Should -Not -Contain $false
        foreach ($result in $second) {
            $result.Steps.Outcome | Should -Be @('AlreadyDone', 'AlreadyDone', 'AlreadyDone', 'AlreadyDone')
        }
    }

    It '3. one failing host does not stop the others, and gets its own error' {
        $first | Should -HaveCount 3
        $failed = $first | Where-Object Host -EQ 'node-lab-broken'
        $failed.Success | Should -BeFalse
        $failed.Step | Should -Be 'Reachable'
        $failed.Changed | Should -BeFalse
    }
}
