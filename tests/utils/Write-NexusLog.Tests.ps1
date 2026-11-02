[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester: variables set in BeforeEach are used in It blocks; the analyzer does not look across script blocks.')]
param()

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../src/utils/Initialize-NexusRunContext.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../src/utils/Write-NexusLog.ps1')
}

Describe 'Write-NexusLog' {
    BeforeEach {
        $context = Initialize-NexusRunContext -LogRoot $TestDrive -Secret 'S3cr3t-value'
    }

    It 'writes one line with UTC time, level, RunId, host, step and message' {
        Write-NexusLog -Context $context -HostName 'web01' -Step 'agent' -Message 'Container started'

        $line = Get-Content -Path (Join-Path -Path $context.LogDirectory -ChildPath 'web01.log')
        $line | Should -HaveCount 1
        $line | Should -Match ('^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z INFO    run=' + [regex]::Escape($context.RunId) + ' host=web01 step=agent Container started$')
    }

    It 'writes run-level events (no host) to run.log' {
        Write-NexusLog -Context $context -Message 'Run started'

        Get-Content -Path (Join-Path -Path $context.LogDirectory -ChildPath 'run.log') | Should -Match 'host=- step=- Run started$'
    }

    It 'keeps one file per host, so parallel hosts never write to the same file' {
        Write-NexusLog -Context $context -HostName 'web01' -Message 'one'
        Write-NexusLog -Context $context -HostName 'web02' -Message 'two'
        Write-NexusLog -Context $context -HostName 'web01' -Message 'three'

        Get-Content -Path (Join-Path -Path $context.LogDirectory -ChildPath 'web01.log') | Should -HaveCount 2
        Get-Content -Path (Join-Path -Path $context.LogDirectory -ChildPath 'web02.log') | Should -HaveCount 1
    }

    It 'writes the level in capitals' {
        Write-NexusLog -Context $context -Level Error -Message 'boom'

        Get-Content -Path (Join-Path -Path $context.LogDirectory -ChildPath 'run.log') | Should -Match 'Z ERROR   run='
    }

    It 'redacts every occurrence of a known secret' {
        Write-NexusLog -Context $context -Message 'token S3cr3t-value sent, again S3cr3t-value'

        $line = Get-Content -Path (Join-Path -Path $context.LogDirectory -ChildPath 'run.log')
        $line | Should -Not -Match 'S3cr3t-value'
        $line | Should -Match 'token \*\*\* sent, again \*\*\*$'
    }

    It 'redacts NexusInfra API tokens (nxi_...) even when they were not registered' {
        Write-NexusLog -Context $context -Message 'Authorization: Bearer nxi_Ab-9_xYz0123'

        Get-Content -Path (Join-Path -Path $context.LogDirectory -ChildPath 'run.log') | Should -Match 'Bearer nxi_\*\*\*$'
    }

    It 'keeps one line per event when the message has line breaks' {
        Write-NexusLog -Context $context -Message "first line`r`nsecond line`nthird"

        $lines = Get-Content -Path (Join-Path -Path $context.LogDirectory -ChildPath 'run.log')
        $lines | Should -HaveCount 1
        $lines | Should -Match 'first line \| second line \| third$'
    }

    It 'turns characters that are not allowed in a file name into _' {
        Write-NexusLog -Context $context -HostName 'fe80::1' -Message 'IPv6 host'

        Test-Path -Path (Join-Path -Path $context.LogDirectory -ChildPath 'fe80__1.log') | Should -BeTrue
    }

    It 'still writes under -WhatIf, because a dry run is logged too' {
        $WhatIfPreference = $true
        Write-NexusLog -Context $context -Message 'dry run'
        $WhatIfPreference = $false

        Get-Content -Path (Join-Path -Path $context.LogDirectory -ChildPath 'run.log') | Should -Match 'dry run$'
    }

    It 'refuses an object that is not a run context' {
        { Write-NexusLog -Context ([pscustomobject]@{ RunId = 'x' }) -Message 'm' } | Should -Throw
    }

    It 'works from ForEach-Object -Parallel: context via $using:, function called in the module scope' {
        # Write-NexusLog is internal (not exported), so a runspace cannot call it after Import-Module.
        # Running a script block *in the module's scope* (& $module { }) can.
        $manifest = Join-Path -Path $PSScriptRoot -ChildPath '../../NexusFleet.psd1'

        'web01', 'web02', 'web03' | ForEach-Object -Parallel {
            $module = Import-Module -Name $using:manifest -PassThru -Force
            & $module { param($Context, $HostName) Write-NexusLog -Context $Context -HostName $HostName -Message 'from a runspace' } $using:context $_
        } -ThrottleLimit 3

        foreach ($name in 'web01', 'web02', 'web03') {
            Get-Content -Path (Join-Path -Path $context.LogDirectory -ChildPath "$name.log") | Should -Match "host=$name step=- from a runspace$"
        }
    }
}
