# Integration test: Remove-NexusNode, Get-NexusServer and Invoke-NexusFleetAction against the node lab
# (./lab/node-lab/Start-NodeLab.ps1). Everything is real: ssh, the parallel runspaces, docker, the API.
# It first installs the lab hosts (nothing happens when they are nodes already), then removes them:
#   - -WhatIf reports the plan and changes nothing,
#   - one command deregisters the nodes and removes their agents, and the nodes stay gone (no heartbeat brings one back),
#   - a second run changes nothing,
#   - one failing host does not stop the others.
# Skipped when the lab is not running. Takes about a minute.
# Run: Invoke-Pester -Path ./tests/public/Remove-NexusNode.Integration.Tests.ps1 -TagFilter Integration -Output Detailed
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

Describe 'Remove-NexusNode against the node lab' -Tag 'Integration' {
    BeforeAll {
        if (-not $labAvailable) {
            return
        }
        Mock -ModuleName NexusFleet -CommandName Get-NexusConfig -MockWith { $config }
        $null = Connect-NexusInfra -Token $token

        $installed = @($labHosts | Install-NexusNode -ThrottleLimit 3 -RabbitMqUrl $rabbitMqUrl -InternalApiToken $internalToken)
        $servers = @(Get-NexusServer)
        $action = @(Invoke-NexusFleetAction -Action stop -Id 'no-such-server')

        $plan = @($allHosts | Remove-NexusNode -WhatIf -ThrottleLimit 3)
        $nodesAfterPlan = & $getNodes
        $first = @($allHosts | Remove-NexusNode -ThrottleLimit 3 -Confirm:$false)
        # Long enough for a heartbeat that was still on its way to arrive: the nodes must stay gone.
        Start-Sleep -Seconds 5
        $nodesAfterRemove = & $getNodes
        $second = @($labHosts | Remove-NexusNode -ThrottleLimit 3 -Confirm:$false)
    }

    BeforeEach {
        if (-not $labAvailable) {
            Set-ItResult -Skipped -Because 'the node lab is not running (./lab/node-lab/Start-NodeLab.ps1)'
        }
    }

    It 'starts from installed nodes' {
        $installed.Success | Should -Not -Contain $false -Because ($installed.Error -join '; ')
    }

    It 'Get-NexusServer reads the server list of a real NexusInfra (the lab runs none)' {
        $servers | Should -HaveCount 0
    }

    It 'Invoke-NexusFleetAction gets a result per server from a real NexusInfra' {
        $action | Should -HaveCount 1
        $action[0].Success | Should -BeFalse
        $action[0].Status | Should -Be 404
    }

    It '-WhatIf plans the removal and changes nothing' {
        foreach ($name in $labHosts.Name) {
            $result = $plan | Where-Object Host -EQ $name
            $result.Node | Should -Be 'WouldRemove'
            $result.Agent | Should -Be 'WouldRemove'
            $nodesAfterPlan.id | Should -Contain $name
        }
    }

    It 'one command deregisters the nodes and removes their agents, and they stay gone' {
        foreach ($name in $labHosts.Name) {
            $result = $first | Where-Object Host -EQ $name
            $result.Success | Should -BeTrue -Because "$name should succeed: $($result.Error)"
            $result.Node | Should -Be 'Removed'
            $result.Agent | Should -Be 'Removed'
            $nodesAfterRemove.id | Should -Not -Contain $name
        }
    }

    It 'a second run changes nothing' {
        $second.Success | Should -Not -Contain $false
        $second.Changed | Should -Not -Contain $true
        $second.Node | Should -Be @('Absent', 'Absent')
        $second.Agent | Should -Be @('Absent', 'Absent')
    }

    It 'one failing host does not stop the others, and gets its own error' {
        $first | Should -HaveCount 3
        $failed = $first | Where-Object Host -EQ 'node-lab-broken'
        $failed.Success | Should -BeFalse
        $failed.Step | Should -Be 'Host'
        $failed.Changed | Should -BeFalse
    }
}
