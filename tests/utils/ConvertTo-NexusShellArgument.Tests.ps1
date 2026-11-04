BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../src/utils/ConvertTo-NexusShellArgument.ps1')
}

Describe 'ConvertTo-NexusShellArgument' {
    It 'wraps a plain value in single quotes' {
        ConvertTo-NexusShellArgument -Value 'node-a' | Should -BeExactly "'node-a'"
    }

    It 'leaves $, backticks, spaces and ; as plain text' {
        ConvertTo-NexusShellArgument -Value 'a $(rm -rf /); `b` c' | Should -BeExactly "'a `$(rm -rf /); ``b`` c'"
    }

    It 'turns a single quote into an escaped one' {
        ConvertTo-NexusShellArgument -Value "it's" | Should -BeExactly "'it'\''s'"
    }

    It 'quotes an empty value as an empty word' {
        ConvertTo-NexusShellArgument -Value '' | Should -BeExactly "''"
    }
}
