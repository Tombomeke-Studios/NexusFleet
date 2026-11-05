# Integration test: a host with reach "outbound" (docs/agent-link.md) against the node lab
# (./lab/node-lab/Start-NodeLab.ps1, host node-lab3 in .keys/inventory.outbound.json).
# Which part runs depends on the lab's control plane, decided when Pester discovers the tests:
#   - it lists the agent-link feature (GET /config): Install-NexusNode makes node-lab3 a healthy node whose agent
#     publishes no port, NexusInfra controls it over the link (AgentReachable), and a second run changes nothing;
#   - it does not (NexusInfra 0.4.0): Test-NexusHost refuses the outbound host with a clear AgentLink failure.
# So the test proves something with every NexusInfra version, and never skips while the lab runs.
# Skipped when the lab is not running.
# Run: Invoke-Pester -Path ./tests/public/Install-NexusNode.Outbound.Integration.Tests.ps1 -TagFilter Integration -Output Detailed
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester: variables set in BeforeAll are used in It blocks and mocks; the analyzer does not look across script blocks.')]
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'Lab-only secrets, created by Start-NodeLab.ps1 in the git-ignored .keys folder.')]
param()

BeforeDiscovery {
    # Does the lab's control plane support the agent link? Asked once, before the tests are defined.
    $keys = Join-Path -Path $PSScriptRoot -ChildPath '../../lab/node-lab/.keys'
    $linkSupported = $false
    if ((Test-Path -Path "$keys/api-token") -and (Test-Connection -TargetName '127.0.0.1' -TcpPort 29400 -TimeoutSeconds 2 -Quiet)) {
        try {
            $headers = @{ Authorization = "Bearer $(Get-Content -Path "$keys/api-token" -Raw)" }
            $features = (Invoke-RestMethod -Uri 'http://127.0.0.1:29400/config' -Headers $headers -TimeoutSec 5).features
            $linkSupported = @($features) -contains 'agent-link'
        }
        catch {
            $linkSupported = $false
        }
    }
}

BeforeAll {
    $module = Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../../NexusFleet.psd1') -Force -PassThru
    $keys = Join-Path -Path $PSScriptRoot -ChildPath '../../lab/node-lab/.keys'
    $labAvailable = (Test-Path -Path "$keys/api-token") -and (Test-Path -Path "$keys/inventory.outbound.json") -and
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

    $outboundHost = Import-NexusInventory -Path "$keys/inventory.outbound.json"
    $api = @{ BaseUrl = $config.Api.BaseUrl; Token = $token }
    $getNodes = { @(& $module { param($Api) Invoke-NexusApi @Api -Method GET -Path '/nodes' } $api) }
    $ssh = @{
        HostName = $outboundHost.Address; Port = $outboundHost.Port; UserName = $outboundHost.User
        KeyFile = $outboundHost.KeyFile; KnownHostsFile = $config.Ssh.KnownHostsFile
    }
    $onHost = { param([string]$Command) & $module { param($Ssh, $Command) Invoke-NexusHostCommand @Ssh -Command $Command } $ssh $Command }
}

AfterAll {
    Remove-Module -Name NexusFleet -Force -ErrorAction SilentlyContinue
}

Describe 'An outbound host in the node lab' -Tag 'Integration' {
    BeforeAll {
        if ($labAvailable) {
            Mock -ModuleName NexusFleet -CommandName Get-NexusConfig -MockWith { $config }
            $null = Connect-NexusInfra -Token $token
        }
    }

    BeforeEach {
        if (-not $labAvailable) {
            Set-ItResult -Skipped -Because 'the node lab is not running (./lab/node-lab/Start-NodeLab.ps1)'
        }
    }

    if ($linkSupported) {
        Context 'with a control plane that has the agent link' {
            BeforeAll {
                if (-not $labAvailable) {
                    return
                }
                # Undo an earlier run: node-lab3 becomes a fresh host again.
                $null = & $onHost ('sudo -n docker rm -f nexusinfra-node-agent >/dev/null 2>&1; sudo -n rm -f /etc/nexusinfra/agent.env; ' +
                    'sudo -n env DEBIAN_FRONTEND=noninteractive apt-get remove -y -q docker.io >/dev/null 2>&1; true')
                if ((& $getNodes).id -contains $outboundHost.Name) {
                    $null = & $module { param($Api, $Id) Invoke-NexusApi @Api -Method DELETE -Path "/nodes/$Id" } $api $outboundHost.Name
                }

                $first = $outboundHost | Install-NexusNode -RabbitMqUrl $rabbitMqUrl -InternalApiToken $internalToken
                $second = $outboundHost | Install-NexusNode -RabbitMqUrl $rabbitMqUrl -InternalApiToken $internalToken
                $node = & $getNodes | Where-Object id -EQ $outboundHost.Name
                $ports = & $onHost 'sudo -n docker port nexusinfra-node-agent'
                $envNames = & $onHost "sudo -n cut -d= -f1 /etc/nexusinfra/agent.env"
                # The status also lists nodes only NexusInfra knows (the direct lab hosts): keep this host's row.
                $status = $outboundHost | Get-NexusFleetStatus | Where-Object Name -EQ $outboundHost.Name
            }

            It 'one command makes it a healthy node that NexusInfra can control' {
                $first.Success | Should -BeTrue -Because "the install should succeed: $($first.Error)"
                # The last step, AgentReachable, calls the agent through NexusInfra: over the link, since no port is open.
                $first.Steps.Outcome | Should -Be @('Applied', 'Applied', 'Applied', 'Applied', 'AlreadyDone')
                $node.health | Should -Be 'healthy'
                $node.connection | Should -Be 'outbound'
                $node.linked | Should -BeTrue
            }

            It 'its agent publishes no port, and its env file holds the link and no agent URL' {
                "$($ports.StdOut)".Trim() | Should -BeNullOrEmpty
                $envNames.StdOut -split "`n" | Should -Contain 'AGENT_LINK_URL'
                $envNames.StdOut -split "`n" | Should -Contain 'AGENT_LINK_TOKEN'
                $envNames.StdOut -split "`n" | Should -Not -Contain 'AGENT_URL'
            }

            It 'a second run changes nothing' {
                $second.Changed | Should -BeFalse
                $second.Steps.Outcome | Should -Be @('AlreadyDone', 'AlreadyDone', 'AlreadyDone', 'AlreadyDone', 'AlreadyDone')
            }

            It 'the fleet status shows it as an outbound node with its link up' {
                $status.Connection | Should -Be 'outbound'
                $status.Linked | Should -BeTrue
                $status.Ok | Should -BeTrue -Because "there should be no problem: $($status.Problem)"
            }
        }
    }
    else {
        Context 'with a control plane without the agent link (NexusInfra 0.4.0)' {
            BeforeAll {
                if ($labAvailable) {
                    $result = $outboundHost | Test-NexusHost
                }
            }

            It 'Test-NexusHost refuses the outbound host on AgentLink, with the reason' {
                $result.Success | Should -BeFalse
                $link = $result.Checks | Where-Object Name -EQ 'AgentLink'
                $link.Status | Should -Be 'Fail'
                $link.Detail | Should -Match 'does not support the agent link'
            }

            It 'still checks the host itself: login and the broker pass' {
                foreach ($name in 'Reachable', 'SshAuth', 'Broker') {
                    ($result.Checks | Where-Object Name -EQ $name).Status | Should -Be 'Pass' -Because "$name should pass"
                }
            }
        }
    }
}
