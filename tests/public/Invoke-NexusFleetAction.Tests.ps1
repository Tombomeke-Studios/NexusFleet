# Invoke-NexusFleetAction against a mocked Invoke-NexusApi that answers like NexusInfra's POST /deployments/bulk:
# always one result per server, also for the ones that fail.
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester: variables set in BeforeAll/BeforeEach are used in It blocks and mocks; the analyzer does not look across script blocks.')]
param()

BeforeAll {
    $module = Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../../NexusFleet.psd1') -Force -PassThru
    . (Join-Path -Path $PSScriptRoot -ChildPath '../core/FakeFleet.ps1')
    $config = & $module { Get-NexusConfig }

    $connect = { & $module { param($Session) $script:NexusSession = $Session } (Get-FakeSession) }
    $disconnect = { & $module { $script:NexusSession = $null } }
}

AfterAll {
    Remove-Module -Name NexusFleet -Force -ErrorAction SilentlyContinue
}

Describe 'Invoke-NexusFleetAction' {
    BeforeEach {
        & $connect
        # Every request the cmdlet sends, and the ids NexusInfra refuses (their server is not found).
        $requests = [System.Collections.Generic.List[object]]::new()
        $unknown = @()
        $failBatch = 0
        $runContext = & $module { param($Root) Initialize-NexusRunContext -LogRoot $Root } $TestDrive
        Mock -ModuleName NexusFleet -CommandName Initialize-NexusRunContext -MockWith { $runContext }
        Mock -ModuleName NexusFleet -CommandName Get-NexusConfig -MockWith { $config }
        Mock -ModuleName NexusFleet -CommandName Invoke-NexusApi -MockWith {
            $requests.Add([pscustomobject]@{ Method = $Method; Path = $Path; Action = $Body.action; Ids = @($Body.ids) })
            if ($requests.Count -eq $failBatch) {
                throw 'NexusInfra is not reachable'
            }
            $results = foreach ($id in $Body.ids) {
                if ($unknown -contains $id) {
                    [pscustomobject]@{ id = $id; ok = $false; status = 404; error = 'deployment not found' }
                }
                else {
                    [pscustomobject]@{ id = $id; name = "server $id"; ok = $true; status = 200 }
                }
            }
            [pscustomobject]@{ action = $Body.action; results = @($results) }
        }
    }

    It 'needs Connect-NexusInfra first' {
        & $disconnect

        { Invoke-NexusFleetAction -Action stop -Id 'srv-1' } | Should -Throw -ErrorId 'NexusFleet.NotConnected*'
    }

    It 'sends one request with the action and the ids, and returns a result per server' {
        $results = @(Invoke-NexusFleetAction -Action stop -Id 'srv-1', 'srv-2')

        $requests | Should -HaveCount 1
        $requests[0].Method | Should -Be 'POST'
        $requests[0].Path | Should -Be '/deployments/bulk'
        $requests[0].Action | Should -Be 'stop'
        $requests[0].Ids | Should -Be @('srv-1', 'srv-2')
        $results | Should -HaveCount 2
        $results[0].PSObject.TypeNames | Should -Contain 'NexusFleet.ActionResult'
        $results.Id | Should -Be @('srv-1', 'srv-2')
        $results[0].Name | Should -Be 'server srv-1'
        $results[0].Action | Should -Be 'stop'
        $results[0].Status | Should -Be 200
        $results.Success | Should -Not -Contain $false
        $results.PlanOnly | Should -Not -Contain $true
    }

    It 'takes the servers of Get-NexusServer from the pipeline' {
        $servers = 1..3 | ForEach-Object { [pscustomobject]@{ PSTypeName = 'NexusFleet.Server'; Id = "srv-$_"; Name = "server $_" } }

        $results = @($servers | Invoke-NexusFleetAction -Action restart)

        $results.Id | Should -Be @('srv-1', 'srv-2', 'srv-3')
        $requests[0].Ids | Should -Be @('srv-1', 'srv-2', 'srv-3')
    }

    It 'takes plain ids from the pipeline and sends a double id once' {
        $results = @('srv-1', 'srv-2', 'srv-1' | Invoke-NexusFleetAction -Action start)

        $results.Id | Should -Be @('srv-1', 'srv-2')
        $requests[0].Ids | Should -Be @('srv-1', 'srv-2')
    }

    It 'sends the action in lower case' {
        $null = Invoke-NexusFleetAction -Action STOP -Id 'srv-1'

        $requests[0].Action | Should -BeExactly 'stop'
    }

    It 'sends more than BulkMaxIds servers in batches' {
        $ids = 1..250 | ForEach-Object { "srv-$_" }

        $results = @($ids | Invoke-NexusFleetAction -Action stop)

        $requests | Should -HaveCount 3
        $requests[0].Ids | Should -HaveCount 100
        $requests[1].Ids | Should -HaveCount 100
        $requests[2].Ids | Should -HaveCount 50
        $requests[2].Ids[0] | Should -Be 'srv-201'
        $results | Should -HaveCount 250
        $results.Id | Should -Be $ids
    }

    It 'gives a server that NexusInfra refuses its own failed result' {
        $unknown = @('srv-2')

        $results = @(Invoke-NexusFleetAction -Action stop -Id 'srv-1', 'srv-2', 'srv-3')

        $results.Success | Should -Be @($true, $false, $true)
        $results[1].Status | Should -Be 404
        $results[1].Error | Should -Be 'deployment not found'
    }

    It 'gives the servers of a failed batch that error, and still sends the next batch' {
        $failBatch = 1
        $ids = 1..150 | ForEach-Object { "srv-$_" }

        $results = @($ids | Invoke-NexusFleetAction -Action stop)

        $requests | Should -HaveCount 2
        @($results | Where-Object { -not $_.Success }) | Should -HaveCount 100
        $results[0].Error | Should -Be 'NexusInfra is not reachable'
        @($results | Where-Object Success).Id | Should -Be ($ids | Select-Object -Skip 100)
    }

    It 'reports a server NexusInfra left out of its answer' {
        Mock -ModuleName NexusFleet -CommandName Invoke-NexusApi -MockWith { [pscustomobject]@{ results = @() } }

        $results = @(Invoke-NexusFleetAction -Action stop -Id 'srv-1')

        $results[0].Success | Should -BeFalse
        $results[0].Error | Should -Be 'NexusInfra gave no result for this server'
    }

    It 'with -WhatIf sends nothing and returns the plan' {
        $results = @(Invoke-NexusFleetAction -Action kill -Id 'srv-1', 'srv-2' -WhatIf)

        $requests | Should -HaveCount 0
        $results | Should -HaveCount 2
        $results.PlanOnly | Should -Not -Contain $false
        $results.Action | Should -Be @('kill', 'kill')
    }

    It 'refuses an action NexusInfra does not know' {
        { Invoke-NexusFleetAction -Action delete -Id 'srv-1' } | Should -Throw
    }

    It 'logs the run and every failed server' {
        $unknown = @('srv-2')

        $null = Invoke-NexusFleetAction -Action stop -Id 'srv-1', 'srv-2'

        $log = Get-Content -Path (Join-Path -Path $runContext.LogDirectory -ChildPath 'run.log') -Raw
        $log | Should -Match 'Action stop on 2 server\(s\)'
        $log | Should -Match 'stop srv-2 failed: deployment not found'
        $log | Should -Match 'Action stop done: 1 of 2 server\(s\) succeeded'
    }
}
