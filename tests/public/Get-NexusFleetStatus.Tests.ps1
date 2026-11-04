# Get-NexusFleetStatus with -ThrottleLimit 1 (one after the other, in this runspace, so the mocks work) and
# Export-NexusFleetStatus. The real parallel path is in Get-NexusFleetStatus.LocalSsh.Tests.ps1.
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester: variables set in BeforeAll/BeforeEach are used in It blocks and mocks; the analyzer does not look across script blocks.')]
param()

BeforeAll {
    $module = Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../../NexusFleet.psd1') -Force -PassThru
    . (Join-Path -Path $PSScriptRoot -ChildPath '../core/FakeFleet.ps1')
    $config = & $module { Get-NexusConfig }

    function Get-TestNode {
        param([string]$Id, [string]$Health = 'healthy')
        [pscustomobject]@{
            id = $Id; name = $Id; location = 'home'; agentUrl = 'http://x:9100'; health = $Health; maintenance = $false
            lastHeartbeat = '2026-11-04T07:35:00.000Z'; cpuPercent = 5; ramUsedMb = 500; ramTotalMb = 2000
        }
    }
    function Get-TestHostStatus {
        param([string]$Name, [bool]$Reachable = $true, [string]$AgentState = 'running')
        [pscustomobject]@{
            PSTypeName = 'NexusFleet.HostStatus'; Host = $Name; Reachable = $Reachable
            Error = $(if (-not $Reachable) { 'cannot reach it over ssh: timed out' }); UptimeSeconds = 100; DiskFreeMB = 9000
            Docker = 'Docker version 27'; AgentState = $(if ($Reachable) { $AgentState }); AgentStartedAt = $null; AgentRestarts = 0; AgentImage = 'img'
        }
    }
}

AfterAll {
    Remove-Module -Name NexusFleet -Force -ErrorAction SilentlyContinue
}

Describe 'Get-NexusFleetStatus' {
    BeforeEach {
        & $module { param($Session) $script:NexusSession = $Session } (Get-FakeSession)
        $hosts = foreach ($i in 1..3) { Get-FakeHostInfo -Name "node-web0$i" -Address "10.0.0.$i" }
        $runContext = & $module { param($Root) Initialize-NexusRunContext -LogRoot $Root } $TestDrive
        Mock -ModuleName NexusFleet -CommandName Initialize-NexusRunContext -MockWith { $runContext }
        Mock -ModuleName NexusFleet -CommandName Get-NexusConfig -MockWith { $config }
        # node-web03 is not registered; node-extra is registered but not in the inventory.
        Mock -ModuleName NexusFleet -CommandName Invoke-NexusApi -MockWith {
            @((Get-TestNode -Id 'node-web01'), (Get-TestNode -Id 'node-web02' -Health 'offline'), (Get-TestNode -Id 'node-extra'))
        }
        Mock -ModuleName NexusFleet -CommandName Get-NexusHostStatus -MockWith {
            switch ($HostInfo.Name) {
                'node-web02' { Get-TestHostStatus -Name $HostInfo.Name -Reachable $false }
                default { Get-TestHostStatus -Name $HostInfo.Name }
            }
        }
    }

    It 'needs Connect-NexusInfra first' {
        & $module { $script:NexusSession = $null }

        { Get-NexusFleetStatus } | Should -Throw -ErrorId 'NexusFleet.NotConnected*'
    }

    It 'without hosts shows NexusInfra''s view only, without ssh' {
        $results = @(Get-NexusFleetStatus)

        $results.Name | Should -Be @('node-extra', 'node-web01', 'node-web02')
        $results.InInventory | Should -Not -Contain $true
        Should -Invoke -ModuleName NexusFleet -CommandName Get-NexusHostStatus -Times 0 -Exactly
        Should -Invoke -ModuleName NexusFleet -CommandName Invoke-NexusApi -Times 1 -Exactly -ParameterFilter { $Method -eq 'GET' -and $Path -eq '/nodes' }
    }

    It 'gives one status per node: the inventory in its order, then the nodes only NexusInfra knows' {
        $results = @($hosts | Get-NexusFleetStatus -ThrottleLimit 1)

        $results.Name | Should -Be @('node-web01', 'node-web02', 'node-web03', 'node-extra')
        $results.InInventory | Should -Be @($true, $true, $true, $false)
    }

    It 'reports offline, unreachable and unregistered nodes as problems, never as an error' {
        $results = @($hosts | Get-NexusFleetStatus -ThrottleLimit 1)

        ($results | Where-Object Name -EQ 'node-web01').Ok | Should -BeTrue
        ($results | Where-Object Name -EQ 'node-web02').Problem | Should -Be 'NexusInfra reports it offline; cannot reach it over ssh: timed out'
        ($results | Where-Object Name -EQ 'node-web03').Problem | Should -Be 'not registered in NexusInfra'
    }

    It 'still checks the hosts when NexusInfra cannot be asked, with a warning' {
        Mock -ModuleName NexusFleet -CommandName Invoke-NexusApi -MockWith { throw [System.InvalidOperationException]::new('NexusInfra is unreachable') }

        $results = @($hosts | Get-NexusFleetStatus -ThrottleLimit 1 -WarningVariable warned -WarningAction SilentlyContinue)

        $results | Should -HaveCount 3
        $results.Health | Should -Be @('unknown', 'unknown', 'unknown')
        ($results | Where-Object Name -EQ 'node-web01').AgentState | Should -Be 'running'
        $warned | Should -Match 'only the hosts are checked'
    }

    It 'logs a summary and keeps the API token out of the log' {
        $null = $hosts | Get-NexusFleetStatus -ThrottleLimit 1

        $log = Get-Content -Path (Join-Path -Path $runContext.LogDirectory -ChildPath 'run.log') -Raw
        $log | Should -Match 'Fleet status: 2 of 4 node\(s\) ok'
        Should -Invoke -ModuleName NexusFleet -CommandName Initialize-NexusRunContext -ParameterFilter { $Secret -contains 'nxi_fake' }
    }

    It 'handles 80 generated hosts, a few unreachable, each with its own status' {
        $many = foreach ($i in 1..80) { Get-FakeHostInfo -Name ('node-{0:d3}' -f $i) -Address "10.2.0.$i" }
        Mock -ModuleName NexusFleet -CommandName Invoke-NexusApi -MockWith { foreach ($i in 1..80) { Get-TestNode -Id ('node-{0:d3}' -f $i) } }
        Mock -ModuleName NexusFleet -CommandName Get-NexusHostStatus -MockWith {
            Get-TestHostStatus -Name $HostInfo.Name -Reachable ($HostInfo.Name -notin 'node-013', 'node-042', 'node-077')
        }

        $results = @($many | Get-NexusFleetStatus -ThrottleLimit 1)

        $results | Should -HaveCount 80
        @($results | Where-Object { -not $_.Ok }).Name | Should -Be @('node-013', 'node-042', 'node-077')
    }
}

Describe 'Export-NexusFleetStatus' {
    BeforeAll {
        $statuses = & $module {
            ConvertTo-NexusNodeStatus -Name 'node-web01' -Node ([pscustomobject]@{
                    id = 'node-web01'; health = 'healthy'; maintenance = $false; lastHeartbeat = '2026-11-04T07:35:00.000Z'; location = 'home'; agentUrl = 'http://x:9100'
                })
            ConvertTo-NexusNodeStatus -Name 'node-web02'
        }
    }

    It 'writes JSON with the time it was made and every node' {
        $file = $statuses | Export-NexusFleetStatus -Path (Join-Path -Path $TestDrive -ChildPath 'status.json')

        $file | Should -BeOfType [System.IO.FileInfo]
        $document = Get-Content -Path $file.FullName -Raw | ConvertFrom-Json
        $document.generatedAt | Should -Not -BeNullOrEmpty
        $document.nodes.Name | Should -Be @('node-web01', 'node-web02')
        $document.nodes[1].Problem | Should -Be 'not registered in NexusInfra'
    }

    It 'writes CSV with one row per node and times as ISO-8601 UTC' {
        $path = Join-Path -Path $TestDrive -ChildPath 'reports/status.csv'

        $null = $statuses | Export-NexusFleetStatus -Path $path

        $rows = Import-Csv -Path $path
        $rows | Should -HaveCount 2
        $rows[0].Name | Should -Be 'node-web01'
        $rows[0].LastHeartbeat | Should -Be '2026-11-04T07:35:00.0000000Z'
        $rows[0].PSObject.Properties.Name | Should -Contain 'AgentState'
    }

    It 'uses -Format over the extension' {
        $path = Join-Path -Path $TestDrive -ChildPath 'status.txt'

        $null = $statuses | Export-NexusFleetStatus -Path $path -Format Csv

        (Get-Content -Path $path -TotalCount 1) | Should -Match '^"Name","Ok","Health"'
    }

    It 'refuses a file whose format it cannot tell' {
        { $statuses | Export-NexusFleetStatus -Path (Join-Path -Path $TestDrive -ChildPath 'status.xml') } |
            Should -Throw -ErrorId 'NexusFleet.UnknownExportFormat*'
    }

    It 'writes nothing with -WhatIf' {
        $path = Join-Path -Path $TestDrive -ChildPath 'whatif.json'

        $null = $statuses | Export-NexusFleetStatus -Path $path -WhatIf

        Test-Path -Path $path | Should -BeFalse
    }
}
