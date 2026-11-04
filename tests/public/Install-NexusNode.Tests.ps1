# Install-NexusNode with -ThrottleLimit 1 (one after the other, in this runspace, so the mocks work) against the fake
# fleet of tests/core/FakeFleet.ps1. The real parallel path is in Install-NexusNode.LocalSsh.Tests.ps1.
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester: variables set in BeforeAll/BeforeEach are used in It blocks and mocks; the analyzer does not look across script blocks.')]
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'Test data: fake secrets, never real ones.')]
param()

BeforeAll {
    $module = Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../../NexusFleet.psd1') -Force -PassThru
    . (Join-Path -Path $PSScriptRoot -ChildPath '../core/FakeFleet.ps1')
    $config = & $module { Get-NexusConfig }
    $config.Health.VerifyTimeoutSeconds = 4
    $config.Health.PollIntervalSeconds = 2

    $connect = { & $module { param($Session) $script:NexusSession = $Session } (Get-FakeSession) }
    $disconnect = { & $module { $script:NexusSession = $null } }
}

AfterAll {
    Remove-Module -Name NexusFleet -Force -ErrorAction SilentlyContinue
}

Describe 'Install-NexusNode' {
    BeforeEach {
        & $connect
        $fake = Get-FakeFleet
        $hosts = foreach ($i in 1..3) {
            Add-FakeHost -Fake $fake -Address "10.0.0.$i"
            Get-FakeHostInfo -Name "node-web0$i" -Address "10.0.0.$i"
        }
        $runContext = & $module { param($Root) Initialize-NexusRunContext -LogRoot $Root } $TestDrive
        Mock -ModuleName NexusFleet -CommandName Initialize-NexusRunContext -MockWith { $runContext }
        Mock -ModuleName NexusFleet -CommandName Get-NexusConfig -MockWith { $config }
        Mock -ModuleName NexusFleet -CommandName Invoke-NexusHostPreflight -MockWith { Get-FakePreflight -HostInfo $HostInfo }
        Mock -ModuleName NexusFleet -CommandName Invoke-NexusHostCommand -MockWith { Invoke-FakeHostCommand -Fake $fake -HostName $HostName -Command $Command }
        Mock -ModuleName NexusFleet -CommandName Invoke-NexusApi -MockWith { Invoke-FakeApi -Fake $fake -Method $Method -Path $Path -Body $Body }
        Mock -ModuleName NexusFleet -CommandName Start-Sleep -MockWith { }
        Mock -ModuleName NexusFleet -CommandName Get-NexusStoredToken -MockWith {
            ConvertTo-SecureString -String "stored-$SecretName" -AsPlainText -Force
        }
    }

    It 'needs Connect-NexusInfra first' {
        & $disconnect

        { $hosts | Install-NexusNode -ThrottleLimit 1 } | Should -Throw -ErrorId 'NexusFleet.NotConnected*'
    }

    It 'turns every host into a healthy node, one result per host' {
        $results = @($hosts | Install-NexusNode -ThrottleLimit 1 -RabbitMqUrl (Get-FakeSecretSet).RabbitMqUrl -InternalApiToken (Get-FakeSecretSet).InternalApiToken)

        $results | Should -HaveCount 3
        $results.Host | Should -Be @('node-web01', 'node-web02', 'node-web03')
        $results.Success | Should -Not -Contain $false
        $results.Changed | Should -Not -Contain $false
        @($fake.Heartbeating.Keys | Sort-Object) | Should -Be @('node-web01', 'node-web02', 'node-web03')
    }

    It 'changes nothing on a second run' {
        $null = $hosts | Install-NexusNode -ThrottleLimit 1
        $fake.Changes.Clear()

        $second = @($hosts | Install-NexusNode -ThrottleLimit 1)

        $second.Success | Should -Not -Contain $false
        $second.Changed | Should -Not -Contain $true
        $fake.Changes | Should -BeNullOrEmpty
    }

    It 'gives a failing host its own error and rolls it back, while the others finish' {
        $fake.FailAt = 'AgentContainer@10.0.0.2'

        $results = @($hosts | Install-NexusNode -ThrottleLimit 1)

        $results | Should -HaveCount 3
        ($results | Where-Object Host -EQ 'node-web02').Step | Should -Be 'AgentContainer'
        ($results | Where-Object Host -NE 'node-web02').Success | Should -Not -Contain $false
        $fake.Nodes.Keys | Should -Not -Contain 'node-web02'
        $fake.Hosts['10.0.0.2'].Docker | Should -BeFalse
    }

    Context 'secrets' {
        It 'reads the agent secrets from SecretManagement when they are not passed' {
            $null = $hosts | Install-NexusNode -ThrottleLimit 1

            Should -Invoke -ModuleName NexusFleet -CommandName Get-NexusStoredToken -Times 1 -Exactly -ParameterFilter { $SecretName -eq 'NexusFleet-RabbitMqUrl' }
            Should -Invoke -ModuleName NexusFleet -CommandName Get-NexusStoredToken -Times 1 -Exactly -ParameterFilter { $SecretName -eq 'NexusFleet-InternalApiToken' }
            Should -Invoke -ModuleName NexusFleet -CommandName Invoke-NexusHostCommand -ParameterFilter {
                $Secret.Count -eq 2 -and [System.Net.NetworkCredential]::new('', $Secret[0]).Password -eq 'stored-NexusFleet-RabbitMqUrl'
            }
        }

        It 'uses the parameters before SecretManagement' {
            $secrets = Get-FakeSecretSet

            $null = $hosts | Install-NexusNode -ThrottleLimit 1 -RabbitMqUrl $secrets.RabbitMqUrl -InternalApiToken $secrets.InternalApiToken

            Should -Invoke -ModuleName NexusFleet -CommandName Get-NexusStoredToken -Times 0 -Exactly
        }

        It 'keeps every secret out of the logs' {
            # This run context keeps the secrets Install-NexusNode passes in, so Write-NexusLog really redacts them.
            $logDir = (New-Item -Path (Join-Path -Path $TestDrive -ChildPath 'redaction') -ItemType Directory -Force).FullName
            Mock -ModuleName NexusFleet -CommandName Initialize-NexusRunContext -MockWith {
                [pscustomobject]@{ PSTypeName = 'NexusFleet.RunContext'; RunId = 'test'; LogDirectory = $logDir; Secrets = @($Secret) }
            }
            $secrets = Get-FakeSecretSet
            $fake.FailAt = 'AgentContainer@10.0.0.1'

            $null = $hosts | Install-NexusNode -ThrottleLimit 1 -RabbitMqUrl $secrets.RabbitMqUrl -InternalApiToken $secrets.InternalApiToken

            Should -Invoke -ModuleName NexusFleet -CommandName Initialize-NexusRunContext -Times 1 -Exactly -ParameterFilter {
                $Secret -contains 'amqp://fleet:Br0ker-pass@broker:5672' -and $Secret -contains 'internal-T0ken' -and $Secret -contains 'nxi_fake'
            }
            $logs = Get-ChildItem -Path $logDir -Filter '*.log' | Get-Content -Raw
            $logs | Should -Not -BeNullOrEmpty
            ($logs -join "`n") | Should -Not -Match 'Br0ker-pass|internal-T0ken|nxi_fake'
        }
    }

    Context '-WhatIf' {
        It 'returns the plan per host, makes no changing call and needs no secrets' {
            $results = @($hosts | Install-NexusNode -ThrottleLimit 1 -WhatIf)

            $results | Should -HaveCount 3
            $results.PlanOnly | Should -Not -Contain $false
            $results[0].Steps.Outcome | Should -Be @('WouldApply', 'WouldApply', 'WouldApply', 'WouldApply')
            $fake.Changes | Should -BeNullOrEmpty
            Should -Invoke -ModuleName NexusFleet -CommandName Get-NexusStoredToken -Times 0 -Exactly
            Should -Invoke -ModuleName NexusFleet -CommandName Invoke-NexusApi -Times 0 -ParameterFilter { $Method -ne 'GET' }
        }

        It 'logs the dry run' {
            $null = $hosts | Install-NexusNode -ThrottleLimit 1 -WhatIf

            Get-Content -Path (Join-Path -Path $runContext.LogDirectory -ChildPath 'run.log') -Raw | Should -Match '3 host\(s\) plan only'
        }
    }

    Context 'scale' {
        It 'gives each of 60 generated hosts its own correct result; 3 unreachable and 2 failing ones do not stop the rest' {
            $fake = Get-FakeFleet
            $many = foreach ($i in 1..60) {
                $address = "10.1.0.$i"
                if ($i -notin 7, 30, 59) { Add-FakeHost -Fake $fake -Address $address }
                Get-FakeHostInfo -Name ('node-{0:d3}' -f $i) -Address $address
            }
            $fake.FailAt = 'RegisterNode@node-020'
            $broken = 'node-007', 'node-030', 'node-059', 'node-020'

            $results = @($many | Install-NexusNode -ThrottleLimit 1)

            $results | Should -HaveCount 60
            @($results.Host | Sort-Object -Unique) | Should -HaveCount 60
            @($results | Where-Object { -not $_.Success }).Host | Sort-Object | Should -Be @($broken | Sort-Object)
            ($results | Where-Object Host -EQ 'node-030').Error | Should -Match 'ssh to 10.1.0.30 failed'
            ($results | Where-Object Host -EQ 'node-020').Step | Should -Be 'RegisterNode'
            $fake.Heartbeating.Count | Should -Be 56
        }
    }
}
