BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../src/utils/ConvertFrom-NexusFactLine.ps1')
}

Describe 'ConvertFrom-NexusFactLine' {
    It 'turns key=value lines into a hashtable' {
        $facts = ConvertFrom-NexusFactLine -Text "os=ubuntu`nosversion=24.04`nsudo=yes"

        $facts.os | Should -Be 'ubuntu'
        $facts.osversion | Should -Be '24.04'
        $facts.sudo | Should -Be 'yes'
    }

    It 'keeps an = inside the value, because only the first = separates key and value' {
        (ConvertFrom-NexusFactLine -Text 'agent=running|2026-11-04T07:00:00Z|0|image=x').agent |
            Should -Be 'running|2026-11-04T07:00:00Z|0|image=x'
    }

    It 'trims spaces and the carriage return of Windows line endings' {
        $facts = ConvertFrom-NexusFactLine -Text "docker = Docker version 27.3.1 `r`nsudo=yes`r`n"

        $facts.docker | Should -Be 'Docker version 27.3.1'
        $facts.sudo | Should -Be 'yes'
    }

    It 'gives an empty value for a key without a value, and skips empty lines' {
        $facts = ConvertFrom-NexusFactLine -Text "docker=`n`n`nagent="

        $facts.Keys | Should -HaveCount 2
        $facts.docker | Should -BeExactly ''
        $facts.agent | Should -BeExactly ''
    }

    It 'returns an empty hashtable for no output at all' {
        (ConvertFrom-NexusFactLine -Text $null).Count | Should -Be 0
        (ConvertFrom-NexusFactLine -Text '').Count | Should -Be 0
    }

    It 'lets a later line win when a key appears twice' {
        (ConvertFrom-NexusFactLine -Text "os=debian`nos=ubuntu").os | Should -Be 'ubuntu'
    }
}
