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

    It 'uses logs/ in the current folder when the log root is empty or not given (the default of Log.Directory)' {
        Push-Location -Path $TestDrive
        try {
            $empty = Initialize-NexusRunContext -LogRoot ''
            $none = Initialize-NexusRunContext -LogRoot $null
        }
        finally {
            Pop-Location
        }

        Split-Path -Path $empty.LogDirectory -Parent | Should -Be (Join-Path -Path $TestDrive -ChildPath 'logs')
        Split-Path -Path $none.LogDirectory -Parent | Should -Be (Join-Path -Path $TestDrive -ChildPath 'logs')
    }

    It 'creates a log root that does not exist yet, also several folders deep' {
        $root = Join-Path -Path $TestDrive -ChildPath 'nexusfleet/runs'

        $context = Initialize-NexusRunContext -LogRoot $root

        Test-Path -Path $context.LogDirectory -PathType Container | Should -BeTrue
    }
    Context 'keeping only the newest runs (-KeepRuns, config Log.KeepRuns)' {
        BeforeEach {
            $root = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
            # Five older runs, oldest first. The names sort by time, as real RunIds do.
            $old = foreach ($day in 1..5) { "2026010${day}T120000Z-abc12$day" }
            foreach ($name in $old) { $null = New-Item -Path (Join-Path -Path $root -ChildPath $name) -ItemType Directory -Force }
        }

        It 'removes the oldest run folders beyond the number to keep, counting the new run' {
            $context = Initialize-NexusRunContext -LogRoot $root -KeepRuns 3

            $left = @(Get-ChildItem -Path $root -Directory).Name | Sort-Object
            $left | Should -Be @($old[3], $old[4], $context.RunId)
        }

        It 'keeps every run with -KeepRuns 0, the default' {
            $null = Initialize-NexusRunContext -LogRoot $root

            @(Get-ChildItem -Path $root -Directory) | Should -HaveCount 6
        }

        It 'never touches a file or folder that is not a run folder' {
            $null = New-Item -Path (Join-Path -Path $root -ChildPath 'notes') -ItemType Directory
            $null = New-Item -Path (Join-Path -Path $root -ChildPath 'README.txt') -ItemType File

            $null = Initialize-NexusRunContext -LogRoot $root -KeepRuns 1

            Test-Path -Path (Join-Path -Path $root -ChildPath 'notes') | Should -BeTrue
            Test-Path -Path (Join-Path -Path $root -ChildPath 'README.txt') | Should -BeTrue
            @(Get-ChildItem -Path $root -Directory | Where-Object Name -Match '^\d{8}T') | Should -HaveCount 1
        }

        It 'removes nothing under -WhatIf: a dry run only adds its own log' {
            $WhatIfPreference = $true
            $null = Initialize-NexusRunContext -LogRoot $root -KeepRuns 2
            $WhatIfPreference = $false

            @(Get-ChildItem -Path $root -Directory) | Should -HaveCount 6
        }
    }
    It 'drops empty secrets, which would otherwise match everywhere' {
        $context = Initialize-NexusRunContext -LogRoot $TestDrive -Secret 'token-1', '', $null

        $context.Secrets | Should -Be @('token-1')
    }
}
