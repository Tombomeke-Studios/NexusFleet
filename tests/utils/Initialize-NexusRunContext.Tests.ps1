BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../src/utils/Initialize-NexusRunContext.ps1')
}

Describe 'Initialize-NexusRunContext' {
    It 'returns a run context with a RunId, a log folder and the secrets' {
        $context = Initialize-NexusRunContext -LogRoot $TestDrive -Secret 'token-1'

        $context.PSObject.TypeNames | Should -Contain 'NexusFleet.RunContext'
        $context.RunId | Should -Match '^\d{8}T\d{6}Z-[0-9a-f]{6}$'
        $context.LogDirectory | Should -Be (Join-Path -Path $TestDrive -ChildPath $context.RunId)
        $context.Secrets | Should -Be @('token-1')
    }

    It 'creates the log folder' {
        $context = Initialize-NexusRunContext -LogRoot $TestDrive

        Test-Path -Path $context.LogDirectory -PathType Container | Should -BeTrue
    }

    It 'creates the log folder under -WhatIf too, because a dry run is logged as well' {
        $WhatIfPreference = $true
        $context = Initialize-NexusRunContext -LogRoot $TestDrive
        $WhatIfPreference = $false

        Test-Path -Path $context.LogDirectory -PathType Container | Should -BeTrue
    }

    It 'gives every run its own RunId' {
        $first = Initialize-NexusRunContext -LogRoot $TestDrive
        $second = Initialize-NexusRunContext -LogRoot $TestDrive

        $first.RunId | Should -Not -Be $second.RunId
    }

    It 'drops empty secrets, which would otherwise match everywhere' {
        $context = Initialize-NexusRunContext -LogRoot $TestDrive -Secret 'token-1', '', $null

        $context.Secrets | Should -Be @('token-1')
    }
}
