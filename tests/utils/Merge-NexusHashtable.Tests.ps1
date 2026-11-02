BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../src/utils/Merge-NexusHashtable.ps1')
}

Describe 'Merge-NexusHashtable' {
    It 'replaces only the keys given in the override, also in nested tables' {
        $base = @{ Api = @{ BaseUrl = 'http://a'; TimeoutSeconds = 30 }; Agent = @{ Port = 9100 } }
        $override = @{ Api = @{ BaseUrl = 'https://b' } }

        $merged = Merge-NexusHashtable -Base $base -Override $override

        $merged.Api.BaseUrl | Should -Be 'https://b'
        $merged.Api.TimeoutSeconds | Should -Be 30
        $merged.Agent.Port | Should -Be 9100
    }

    It 'does not change the base table' {
        $base = @{ Api = @{ BaseUrl = 'http://a' } }

        $null = Merge-NexusHashtable -Base $base -Override @{ Api = @{ BaseUrl = 'https://b' } }

        $base.Api.BaseUrl | Should -Be 'http://a'
    }

    It 'warns about a key that does not exist in the base (probably a typo) and still adds it' {
        $merged = Merge-NexusHashtable -Base @{ Api = @{ BaseUrl = 'http://a' } } -Override @{ Api = @{ BaseUlr = 'x' } } -WarningVariable warnings -WarningAction SilentlyContinue

        $warnings | Should -HaveCount 1
        "$($warnings[0])" | Should -Match "Api\.BaseUlr"
        $merged.Api.BaseUlr | Should -Be 'x'
    }
}
