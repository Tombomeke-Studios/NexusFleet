[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester: variables set in BeforeAll/BeforeEach are used in It blocks and mocks; the analyzer does not look across script blocks.')]
param()

BeforeAll {
    $module = Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../../NexusFleet.psd1') -Force -PassThru
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestStepContext.ps1')
    $step = & $module { Get-NexusStep } | Where-Object Name -EQ 'AgentContainer'

    # What the inspect script prints for a container that is exactly right; tests change or drop one line.
    function Get-InspectResult {
        param([hashtable]$Replace = @{}, [string[]]$Drop = @())
        $lines = [ordered]@{
            exists  = 'exists=yes'
            image   = 'image=ghcr.io/tombomeke-studios/nexusinfra/node-agent:community'
            running = 'running=true'
            restart = 'restart=unless-stopped'
            port    = 'port=9100->9100/tcp'
            socket  = 'mount=/var/run/docker.sock:/var/run/docker.sock'
            backups = 'mount=nexusinfra-backups:/var/lib/nexusinfra/backups'
            gateway = 'host=host.docker.internal:host-gateway'
            nodeId  = 'env=NODE_ID=node-web01'
            url     = 'env=AGENT_URL=http://10.0.0.5:9100'
        }
        foreach ($key in $Replace.Keys) { $lines[$key] = $Replace[$key] }
        foreach ($key in $Drop) { $lines.Remove($key) }
        Get-TestCommandResult -StdOut @($lines.Values)
    }
}

AfterAll {
    Remove-Module -Name NexusFleet -Force -ErrorAction SilentlyContinue
}

Describe 'Step AgentContainer' {
    BeforeEach {
        $context = Get-TestStepContext -Module $module
    }

    It 'runs after the node is registered (Order 30)' {
        $step.Order | Should -Be 30
    }

    Context 'Test' {
        It 'is in order when the container runs with every required setting' {
            Mock -ModuleName NexusFleet -CommandName Invoke-NexusHostCommand -MockWith { Get-InspectResult }

            & $step.Test $context | Should -BeTrue
        }

        It 'never asks the host for the secret variables' {
            Mock -ModuleName NexusFleet -CommandName Invoke-NexusHostCommand -MockWith { Get-InspectResult }

            $null = & $step.Test $context

            Should -Invoke -ModuleName NexusFleet -CommandName Invoke-NexusHostCommand -Times 1 -Exactly -ParameterFilter {
                $Command -match "grep -E '\^\(NODE_ID\|AGENT_URL\|AGENT_LINK_URL\)='" -and $Command -notmatch 'RABBITMQ_URL|INTERNAL_API_TOKEN|AGENT_LINK_TOKEN'
            }
        }

        It 'is not in order when the container does not exist' {
            Mock -ModuleName NexusFleet -CommandName Invoke-NexusHostCommand -MockWith { Get-TestCommandResult -StdOut 'exists=no' }

            & $step.Test $context | Should -BeFalse
        }

        It 'is not in order when <Why>' -ForEach @(
            @{ Why = 'it is stopped'; Replace = @{ running = 'running=false' }; Drop = @() }
            @{ Why = 'it runs another image'; Replace = @{ image = 'image=ghcr.io/tombomeke-studios/nexusinfra/node-agent:old' }; Drop = @() }
            @{ Why = 'the restart policy is missing (fails silently)'; Replace = @{ restart = 'restart=no' }; Drop = @() }
            @{ Why = 'the port is not published (fails silently)'; Replace = @{}; Drop = @('port') }
            @{ Why = 'the backups volume is missing (fails silently)'; Replace = @{}; Drop = @('backups') }
            @{ Why = 'the Docker socket is not mounted'; Replace = @{}; Drop = @('socket') }
            @{ Why = 'the host-gateway mapping is missing'; Replace = @{}; Drop = @('gateway') }
            @{ Why = 'NODE_ID is another node'; Replace = @{ nodeId = 'env=NODE_ID=node-other' }; Drop = @() }
            @{ Why = 'AGENT_URL differs'; Replace = @{ url = 'env=AGENT_URL=http://10.9.9.9:9100' }; Drop = @() }
        ) {
            Mock -ModuleName NexusFleet -CommandName Invoke-NexusHostCommand -MockWith { Get-InspectResult -Replace $Replace -Drop $Drop }

            & $step.Test $context | Should -BeFalse
        }

        It 'is not in order with Force, even when everything is right (to apply a changed secret)' {
            Mock -ModuleName NexusFleet -CommandName Invoke-NexusHostCommand -MockWith { Get-InspectResult }
            $context.Force = $true

            & $step.Test $context | Should -BeFalse
        }

        It 'logs what is wrong with an existing container' {
            Mock -ModuleName NexusFleet -CommandName Invoke-NexusHostCommand -MockWith { Get-InspectResult -Replace @{ restart = 'restart=no' } -Drop 'port' }
            $context.RunContext = & $module { param($Root) Initialize-NexusRunContext -LogRoot $Root } $TestDrive

            $null = & $step.Test $context

            $log = Get-Content -Path (Join-Path -Path $context.RunContext.LogDirectory -ChildPath 'node-web01.log') -Raw
            $log | Should -Match 'not as it should be: restart policy unless-stopped; port 9100 is published'
        }
    }

    Context 'Apply' {
        BeforeEach {
            Mock -ModuleName NexusFleet -CommandName Invoke-NexusHostCommand -MockWith { Get-TestCommandResult }
            & $step.Apply $context
        }

        It 'remembers that it started the agent, for VerifyHealthy' {
            $context.State.AgentStarted | Should -BeTrue
        }

        It 'sends the two secrets on stdin, in order, and never in the command' {
            Should -Invoke -ModuleName NexusFleet -CommandName Invoke-NexusHostCommand -Times 1 -Exactly -ParameterFilter {
                $Secret.Count -eq 2 -and
                [System.Net.NetworkCredential]::new('', $Secret[0]).Password -eq 'amqp://fleet:Br0ker-pass@broker:5672' -and
                [System.Net.NetworkCredential]::new('', $Secret[1]).Password -eq 'internal-T0ken' -and
                $Command -notmatch 'Br0ker-pass|internal-T0ken'
            }
        }

        It 'writes the env file with mode 600 and passes it to docker run' {
            Should -Invoke -ModuleName NexusFleet -CommandName Invoke-NexusHostCommand -ParameterFilter {
                $Command -match 'IFS= read -r rabbitmq_url' -and $Command -match 'IFS= read -r internal_token' -and
                $Command -match "install -d -m 700 '/etc/nexusinfra'" -and $Command -match "chmod 600 '/etc/nexusinfra/agent.env'" -and
                $Command -match "--env-file '/etc/nexusinfra/agent.env'"
            }
        }

        It 'always sets the three options that fail silently: restart policy, port and backups volume' {
            Should -Invoke -ModuleName NexusFleet -CommandName Invoke-NexusHostCommand -ParameterFilter {
                $Command -match "--restart 'unless-stopped'" -and $Command -match '-p 9100:9100' -and
                $Command -match "-v 'nexusinfra-backups:/var/lib/nexusinfra/backups'"
            }
        }

        It 'mounts the Docker socket, maps the host gateway and runs the configured image under the configured name' {
            Should -Invoke -ModuleName NexusFleet -CommandName Invoke-NexusHostCommand -ParameterFilter {
                $Command -match "-v '/var/run/docker.sock:/var/run/docker.sock'" -and
                $Command -match "--add-host='host.docker.internal:host-gateway'" -and
                $Command -match "docker run -d --name 'nexusinfra-node-agent'" -and
                $Command -match "'ghcr.io/tombomeke-studios/nexusinfra/node-agent:community' >/dev/null"
            }
        }

        It 'puts NODE_ID and AGENT_URL of this host in the env file' {
            Should -Invoke -ModuleName NexusFleet -CommandName Invoke-NexusHostCommand -ParameterFilter {
                $Command -match "'NODE_ID' 'node-web01'" -and $Command -match "'AGENT_URL' 'http://10.0.0.5:9100'"
            }
        }
    }

    Context 'a host with reach outbound' {
        BeforeEach {
            $context = Get-TestStepContext -Module $module -Outbound
            $outboundLines = @{ url = 'env=AGENT_LINK_URL=wss://nexus.example.com/agent-link' }
        }

        It 'is in order without a published port and with the link URL' {
            Mock -ModuleName NexusFleet -CommandName Invoke-NexusHostCommand -MockWith { Get-InspectResult -Replace $outboundLines -Drop 'port' }

            & $step.Test $context | Should -BeTrue
        }

        It 'is not in order when <Why>' -ForEach @(
            @{ Why = 'the agent port is still published (nothing should be open)'; Drop = @() ; Replace = @{ url = 'env=AGENT_LINK_URL=wss://nexus.example.com/agent-link' } }
            @{ Why = 'the link URL differs'; Drop = @('port'); Replace = @{ url = 'env=AGENT_LINK_URL=wss://old.example.com/agent-link' } }
            @{ Why = 'the agent has no link (a direct agent)'; Drop = @('port'); Replace = @{ url = 'env=AGENT_URL=http://10.0.0.5:9100' } }
        ) {
            Mock -ModuleName NexusFleet -CommandName Invoke-NexusHostCommand -MockWith { Get-InspectResult -Replace $Replace -Drop $Drop }

            & $step.Test $context | Should -BeFalse
        }

        Context 'Apply' {
            BeforeEach {
                Mock -ModuleName NexusFleet -CommandName Invoke-NexusHostCommand -MockWith { Get-TestCommandResult }
                Mock -ModuleName NexusFleet -CommandName Invoke-NexusApi -MockWith { [pscustomobject]@{ token = 'link-T0ken' } }
            }

            It 'mints a link token for this node and sends it on stdin as the third secret, never in the command' {
                & $step.Apply $context

                Should -Invoke -ModuleName NexusFleet -CommandName Invoke-NexusApi -Times 1 -Exactly -ParameterFilter {
                    $Method -eq 'POST' -and $Path -eq '/nodes/node-web01/link-token'
                }
                Should -Invoke -ModuleName NexusFleet -CommandName Invoke-NexusHostCommand -Times 1 -Exactly -ParameterFilter {
                    $Secret.Count -eq 3 -and [System.Net.NetworkCredential]::new('', $Secret[2]).Password -eq 'link-T0ken' -and
                    $Command -match 'IFS= read -r link_token' -and $Command -notmatch 'link-T0ken'
                }
            }

            It 'writes the link URL and token to the env file, publishes no port and sets no AGENT_URL' {
                & $step.Apply $context

                Should -Invoke -ModuleName NexusFleet -CommandName Invoke-NexusHostCommand -ParameterFilter {
                    $Command -match "'AGENT_LINK_URL' 'wss://nexus.example.com/agent-link'" -and
                    $Command -match "'AGENT_LINK_TOKEN' `"\`$link_token`"" -and
                    $Command -notmatch '-p 9100' -and $Command -notmatch 'AGENT_URL' -and $Command -notmatch 'AGENT_LINK_ALLOW_INSECURE'
                }
            }

            It 'refuses a ws:// link (no TLS) unless Api.AllowUnencryptedHttp is set, before it touches anything' {
                $context.LinkUrl = 'ws://192.168.0.6:9400/agent-link'

                { & $step.Apply $context } | Should -Throw '*ws://*not encrypted*AllowUnencryptedHttp*'
                Should -Invoke -ModuleName NexusFleet -CommandName Invoke-NexusApi -Times 0 -Exactly
                Should -Invoke -ModuleName NexusFleet -CommandName Invoke-NexusHostCommand -Times 0 -Exactly
            }

            It 'allows a ws:// link in a lab with Api.AllowUnencryptedHttp, and tells the agent so' {
                $context.LinkUrl = 'ws://172.29.50.1:9400/agent-link'
                $context.Config.Api.AllowUnencryptedHttp = $true

                & $step.Apply $context

                Should -Invoke -ModuleName NexusFleet -CommandName Invoke-NexusHostCommand -ParameterFilter {
                    $Command -match "'AGENT_LINK_ALLOW_INSECURE' 'true'"
                }
            }
        }
    }

    Context 'Apply without secrets' {
        It 'refuses, before it touches the host' {
            Mock -ModuleName NexusFleet -CommandName Invoke-NexusHostCommand -MockWith { Get-TestCommandResult }
            $context = Get-TestStepContext -Module $module -WithoutSecrets

            { & $step.Apply $context } | Should -Throw '*needs RABBITMQ_URL and INTERNAL_API_TOKEN*'
            Should -Invoke -ModuleName NexusFleet -CommandName Invoke-NexusHostCommand -Times 0 -Exactly
        }
    }

    Context 'Rollback' {
        It 'removes the container and the env file, never the backups volume' {
            Mock -ModuleName NexusFleet -CommandName Invoke-NexusHostCommand -MockWith { Get-TestCommandResult }

            & $step.Rollback $context

            Should -Invoke -ModuleName NexusFleet -CommandName Invoke-NexusHostCommand -Times 1 -Exactly -ParameterFilter {
                $Command -match "docker rm -f 'nexusinfra-node-agent'" -and $Command -match "rm -f '/etc/nexusinfra/agent.env'" -and
                $Command -notmatch 'volume'
            }
        }
    }
}
