[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester: variables set in BeforeAll/BeforeEach are used in It blocks and mocks; the analyzer does not look across script blocks.')]
param()

BeforeAll {
    $module = Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../../NexusFleet.psd1') -Force -PassThru
    $config = @{ Agent = @{ Port = 9100 } }

    # Writes an inventory (a hashtable or raw text) to TestDrive and returns its path.
    function Write-TestInventory {
        param([object]$Content, [string]$Name = 'inventory.json')
        $path = Join-Path -Path $TestDrive -ChildPath $Name
        $text = if ($Content -is [string]) { $Content } else { $Content | ConvertTo-Json -Depth 5 }
        Set-Content -Path $path -Value $text
        $path
    }
}

AfterAll {
    Remove-Module -Name NexusFleet -Force -ErrorAction SilentlyContinue
}

Describe 'Import-NexusInventory' {
    BeforeEach {
        $runContext = & $module { param($Root) Initialize-NexusRunContext -LogRoot $Root } $TestDrive
        Mock -ModuleName NexusFleet -CommandName Initialize-NexusRunContext -MockWith { $runContext }
        Mock -ModuleName NexusFleet -CommandName Get-NexusConfig -MockWith { $config }
    }

    Context 'a valid inventory' {
        It 'returns one NexusFleet.Host per host, with the defaults applied' {
            $path = Write-TestInventory @{
                defaults = @{ user = 'fleet'; port = 22; location = 'home' }
                hosts    = @(
                    @{ name = 'node-web01'; address = '10.0.0.5' }
                    @{ name = 'node-web02'; address = 'web02.example.com'; port = 2222; location = 'laptop' }
                )
            }

            $hosts = @(Import-NexusInventory -Path $path)

            $hosts | Should -HaveCount 2
            $hosts[0].PSObject.TypeNames | Should -Contain 'NexusFleet.Host'
            $hosts[0].Name | Should -Be 'node-web01'
            $hosts[0].Address | Should -Be '10.0.0.5'
            $hosts[0].Port | Should -Be 22
            $hosts[0].User | Should -Be 'fleet'
            $hosts[0].Location | Should -Be 'home'
            $hosts[1].Port | Should -Be 2222
            $hosts[1].Location | Should -Be 'laptop'
        }

        It 'builds the agent URL from the address and the configured agent port, unless one is given' {
            $path = Write-TestInventory @{
                hosts = @(
                    @{ name = 'node-a'; address = '10.0.0.5'; user = 'fleet'; location = 'home' }
                    @{ name = 'node-b'; address = '10.0.0.6'; user = 'fleet'; location = 'home'; agentUrl = 'https://agent-b.example.com' }
                )
            }

            $hosts = @(Import-NexusInventory -Path $path)

            $hosts[0].AgentUrl | Should -Be 'http://10.0.0.5:9100'
            $hosts[1].AgentUrl | Should -Be 'https://agent-b.example.com'
        }

        It 'reaches a host directly unless it says otherwise, and an outbound host has no agent URL' {
            $path = Write-TestInventory @{
                defaults = @{ user = 'fleet'; location = 'home' }
                hosts    = @(
                    @{ name = 'node-a'; address = '10.0.0.5' }
                    @{ name = 'node-b'; address = '10.0.0.6'; reach = 'outbound' }
                )
            }

            $hosts = @(Import-NexusInventory -Path $path)

            $hosts[0].Reach | Should -Be 'direct'
            $hosts[0].AgentUrl | Should -Be 'http://10.0.0.5:9100'
            $hosts[1].Reach | Should -Be 'outbound'
            $hosts[1].AgentUrl | Should -BeNullOrEmpty
        }

        It 'takes reach from the defaults' {
            $path = Write-TestInventory @{
                defaults = @{ user = 'fleet'; location = 'home'; reach = 'outbound' }
                hosts    = @(@{ name = 'node-a'; address = '10.0.0.5' })
            }

            (Import-NexusInventory -Path $path).Reach | Should -Be 'outbound'
        }

        It 'reads the example inventory of the repository without problems' {
            $example = Join-Path -Path $PSScriptRoot -ChildPath '../../config/inventory.example.json'

            $hosts = @(Import-NexusInventory -Path $example)

            $hosts.Count | Should -BeGreaterThan 0
        }

        It 'accepts the path from the pipeline' {
            $path = Write-TestInventory @{ hosts = @(@{ name = 'node-a'; address = '10.0.0.5'; user = 'fleet'; location = 'home' }) }

            @($path | Import-NexusInventory) | Should -HaveCount 1
        }
    }

    Context 'problems' {
        It 'fails clearly when the file does not exist' {
            { Import-NexusInventory -Path (Join-Path -Path $TestDrive -ChildPath 'missing.json') } |
                Should -Throw -ErrorId 'NexusFleet.InventoryNotFound*' -ExpectedMessage '*missing.json*'
        }

        It 'fails clearly when the file is not valid JSON' {
            $path = Write-TestInventory '{ "hosts": [ { "name": "node-a", '

            { Import-NexusInventory -Path $path } | Should -Throw -ErrorId 'NexusFleet.InventoryInvalid*' -ExpectedMessage '*not valid JSON*'
        }

        It 'fails when there are no hosts' {
            $path = Write-TestInventory @{ hosts = @() }

            { Import-NexusInventory -Path $path } | Should -Throw -ExpectedMessage '*no hosts*'
        }

        It 'refuses an invalid host address: <Address>' -ForEach @(
            @{ Address = 'web01; rm -rf /' }
            @{ Address = '-oProxyCommand=evil' }
            @{ Address = 'web 01' }
        ) {
            $path = Write-TestInventory @{ hosts = @(@{ name = 'node-a'; address = $Address; user = 'fleet'; location = 'home' }) }

            { Import-NexusInventory -Path $path } | Should -Throw -ErrorId 'NexusFleet.InventoryInvalid*' -ExpectedMessage '*node-a*address*'
        }

        It 'refuses a node name NexusInfra would not accept' {
            $path = Write-TestInventory @{ hosts = @(@{ name = 'Node A!'; address = '10.0.0.5'; user = 'fleet'; location = 'home' }) }

            { Import-NexusInventory -Path $path } | Should -Throw -ExpectedMessage '*host 1*name*Node A!*'
        }

        It 'refuses a port outside 1-65535' {
            $path = Write-TestInventory @{ hosts = @(@{ name = 'node-a'; address = '10.0.0.5'; port = 70000; user = 'fleet'; location = 'home' }) }

            { Import-NexusInventory -Path $path } | Should -Throw -ExpectedMessage '*node-a*port*70000*'
        }

        It 'refuses a user name Linux would not accept' {
            $path = Write-TestInventory @{ hosts = @(@{ name = 'node-a'; address = '10.0.0.5'; user = 'Fleet User'; location = 'home' }) }

            { Import-NexusInventory -Path $path } | Should -Throw -ErrorId 'NexusFleet.InventoryInvalid*' -ExpectedMessage "*node-a*user 'Fleet User' is not a Linux user name*"
        }

        It 'refuses an agentUrl that is not an http(s) URL' {
            $path = Write-TestInventory @{ hosts = @(@{ name = 'node-a'; address = '10.0.0.5'; user = 'fleet'; location = 'home'; agentUrl = 'ftp://10.0.0.5' }) }

            { Import-NexusInventory -Path $path } | Should -Throw -ExpectedMessage "*node-a*agentUrl 'ftp://10.0.0.5' must be an http(s) URL*"
        }

        It 'refuses an unknown reach' {
            $path = Write-TestInventory @{ hosts = @(@{ name = 'node-a'; address = '10.0.0.5'; user = 'fleet'; location = 'home'; reach = 'tunnel' }) }

            { Import-NexusInventory -Path $path } | Should -Throw -ExpectedMessage "*node-a*reach 'tunnel' must be direct or outbound*"
        }

        It 'refuses an agentUrl on an outbound host (it would never be used)' {
            $path = Write-TestInventory @{ hosts = @(@{ name = 'node-a'; address = '10.0.0.5'; user = 'fleet'; location = 'home'; reach = 'outbound'; agentUrl = 'http://10.0.0.5:9100' }) }

            { Import-NexusInventory -Path $path } | Should -Throw -ExpectedMessage '*node-a*agentUrl*outbound*'
        }

        It 'names a host without a usable name by its position' {
            $hosts = @(
                @{ name = 'node-a'; address = '10.0.0.5'; user = 'fleet'; location = 'home' }
                @{ address = '10.0.0.6'; user = 'fleet'; location = 'home' }
            )
            $path = Write-TestInventory @{ hosts = $hosts }

            { Import-NexusInventory -Path $path } | Should -Throw -ExpectedMessage '*host 2: name is missing*'
        }

        It 'names a missing required field' {
            $path = Write-TestInventory @{ hosts = @(@{ name = 'node-a'; address = '10.0.0.5'; location = 'home' }) }

            { Import-NexusInventory -Path $path } | Should -Throw -ExpectedMessage '*node-a*user is missing*'
        }

        It 'refuses a duplicate host name' {
            $path = Write-TestInventory @{
                hosts = @(
                    @{ name = 'node-a'; address = '10.0.0.5'; user = 'fleet'; location = 'home' }
                    @{ name = 'node-a'; address = '10.0.0.6'; user = 'fleet'; location = 'home' }
                )
            }

            { Import-NexusInventory -Path $path } | Should -Throw -ExpectedMessage "*name 'node-a'*more than once*"
        }

        It 'refuses the same address and port twice' {
            $path = Write-TestInventory @{
                hosts = @(
                    @{ name = 'node-a'; address = '10.0.0.5'; user = 'fleet'; location = 'home' }
                    @{ name = 'node-b'; address = '10.0.0.5'; user = 'fleet'; location = 'home' }
                )
            }

            { Import-NexusInventory -Path $path } | Should -Throw -ExpectedMessage "*10.0.0.5:22*more than once*"
        }

        It 'lists every problem at once' {
            $path = Write-TestInventory @{
                hosts = @(
                    @{ name = 'node-a'; address = 'bad address'; user = 'fleet'; location = 'home' }
                    @{ name = 'node-b'; address = '10.0.0.6'; port = 0; user = 'fleet'; location = 'home' }
                )
            }

            $message = try { Import-NexusInventory -Path $path; '' } catch { $_.Exception.Message }

            $message | Should -Match 'node-a.*address'
            $message | Should -Match 'node-b.*port'
        }

        It 'warns about an unknown field (probably a typo) and still imports' {
            $path = Write-TestInventory @{ hosts = @(@{ name = 'node-a'; address = '10.0.0.5'; user = 'fleet'; location = 'home'; adress = 'x' }) }

            $hosts = @(Import-NexusInventory -Path $path -WarningVariable warnings -WarningAction SilentlyContinue)

            $hosts | Should -HaveCount 1
            "$warnings" | Should -Match "node-a.*unknown field 'adress'"
        }
    }
}
