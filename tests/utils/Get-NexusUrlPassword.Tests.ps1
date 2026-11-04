BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../src/utils/Get-NexusUrlPassword.ps1')
}

Describe 'Get-NexusUrlPassword' {
    It 'returns the password of a URL with user:password' {
        Get-NexusUrlPassword -Url 'amqp://fleet:Br0ker-pass@broker:5672' | Should -BeExactly 'Br0ker-pass'
    }

    It 'decodes a password with escaped characters, as it would appear in an error message' {
        Get-NexusUrlPassword -Url 'amqp://fleet:p%40ss%3Aword@broker:5672' | Should -BeExactly 'p@ss:word'
    }

    It 'returns nothing for a URL without a password' {
        Get-NexusUrlPassword -Url 'amqp://fleet@broker:5672' | Should -BeNullOrEmpty
        Get-NexusUrlPassword -Url 'amqp://broker:5672' | Should -BeNullOrEmpty
    }

    It 'returns nothing, without an error, for a text that is not a URL' {
        Get-NexusUrlPassword -Url 'not a url' -ErrorAction Stop | Should -BeNullOrEmpty
        Get-NexusUrlPassword -Url '' -ErrorAction Stop | Should -BeNullOrEmpty
    }
}
