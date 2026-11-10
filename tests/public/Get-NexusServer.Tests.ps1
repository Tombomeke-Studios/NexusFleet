# Get-NexusServer against a mocked Invoke-NexusApi that answers in pages, as NexusInfra's GET /deployments does.
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester: variables set in BeforeAll/BeforeEach are used in It blocks and mocks; the analyzer does not look across script blocks.')]
param()

BeforeAll {
    $module = Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../../NexusFleet.psd1') -Force -PassThru
    . (Join-Path -Path $PSScriptRoot -ChildPath '../core/FakeFleet.ps1')
    $config = & $module { Get-NexusConfig }
    $config.Servers.PageSize = 2

    $connect = { & $module { param($Session) $script:NexusSession = $Session } (Get-FakeSession) }
    $disconnect = { & $module { $script:NexusSession = $null } }
}

AfterAll {
    Remove-Module -Name NexusFleet -Force -ErrorAction SilentlyContinue
}

Describe 'Get-NexusServer' {
    BeforeEach {
        & $connect
        # Five servers; the mock cuts pages out of them by the limit and offset in the path.
        $servers = foreach ($i in 1..5) {
            [pscustomobject]@{ id = "srv-$i"; name = "server $i"; status = 'running'; nodeId = 'node-web01'; type = 'minecraft' }
        }
        $paths = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName NexusFleet -CommandName Get-NexusConfig -MockWith { $config }
        Mock -ModuleName NexusFleet -CommandName Invoke-NexusApi -MockWith {
            $paths.Add($Path)
            $limit = [int][regex]::Match($Path, 'limit=(\d+)').Groups[1].Value
            $offset = [int][regex]::Match($Path, 'offset=(\d+)').Groups[1].Value
            [pscustomobject]@{
                items  = @($servers | Select-Object -Skip $offset -First $limit)
                total  = @($servers).Count
                limit  = $limit
                offset = $offset
            }
        }
    }

    It 'needs Connect-NexusInfra first' {
        & $disconnect

        { Get-NexusServer } | Should -Throw -ErrorId 'NexusFleet.NotConnected*'
    }

    It 'reads every page and returns one object per server' {
        $result = @(Get-NexusServer)

        $result | Should -HaveCount 5
        $result[0].PSObject.TypeNames | Should -Contain 'NexusFleet.Server'
        $result.Id | Should -Be @('srv-1', 'srv-2', 'srv-3', 'srv-4', 'srv-5')
        $result[0].Name | Should -Be 'server 1'
        $result[0].Status | Should -Be 'running'
        $result[0].Node | Should -Be 'node-web01'
        $result[0].Type | Should -Be 'minecraft'
        $paths | Should -Be @(
            '/deployments?limit=2&offset=0'
            '/deployments?limit=2&offset=2'
            '/deployments?limit=2&offset=4'
        )
    }

    It 'stops after one request when everything fits in one page' {
        $servers = @($servers | Select-Object -First 2)

        @(Get-NexusServer) | Should -HaveCount 2
        $paths | Should -HaveCount 1
    }

    It 'returns nothing when there are no servers' {
        $servers = @()

        @(Get-NexusServer) | Should -HaveCount 0
        $paths | Should -HaveCount 1
    }

    It 'sends the filters to NexusInfra, escaped' {
        $null = Get-NexusServer -Node 'node-web01' -Status 'running' -Name 'my server&co'

        $paths[0] | Should -Be '/deployments?limit=2&offset=0&nodeId=node-web01&status=running&q=my%20server%26co'
    }

    It 'only reads' {
        $null = Get-NexusServer

        Should -Invoke -ModuleName NexusFleet -CommandName Invoke-NexusApi -Times 0 -Exactly -ParameterFilter { $Method -ne 'GET' }
    }

    It 'refuses a node name that cannot be one' {
        { Get-NexusServer -Node 'Not A Node' } | Should -Throw
    }
}
