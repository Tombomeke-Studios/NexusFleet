[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester: variables set in BeforeAll/BeforeEach are used in It blocks and mocks; the analyzer does not look across script blocks.')]
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'Test data: a fake token, never a real one.')]
param()

BeforeAll {
    foreach ($file in 'api/Invoke-NexusApi', 'core/Invoke-NexusStepApi') {
        . (Join-Path -Path $PSScriptRoot -ChildPath "../../src/$file.ps1")
    }
    $token = ConvertTo-SecureString -String 'nxi_fake' -AsPlainText -Force
    $context = @{ Api = @{ BaseUrl = 'http://localhost:9400'; Token = $token; TimeoutSeconds = 5; RetryCount = 1; AllowUnencryptedHttp = $false } }
}

Describe 'Invoke-NexusStepApi' {
    It 'calls Invoke-NexusApi with the connection of the context' {
        Mock -CommandName Invoke-NexusApi -MockWith { @() }

        $null = Invoke-NexusStepApi -Context $context -Method GET -Path '/nodes'

        Should -Invoke -CommandName Invoke-NexusApi -Times 1 -Exactly -ParameterFilter {
            $BaseUrl -eq 'http://localhost:9400' -and $Token -eq $token -and $TimeoutSeconds -eq 5 -and $RetryCount -eq 1 -and
            $Method -eq 'GET' -and $Path -eq '/nodes' -and $null -eq $Body
        }
    }

    It 'sends a body when one is given' {
        Mock -CommandName Invoke-NexusApi -MockWith { [pscustomobject]@{ id = 'node-a' } }

        $answer = Invoke-NexusStepApi -Context $context -Method POST -Path '/nodes' -Body @{ id = 'node-a' }

        $answer.id | Should -Be 'node-a'
        Should -Invoke -CommandName Invoke-NexusApi -Times 1 -Exactly -ParameterFilter { $Method -eq 'POST' -and $Body.id -eq 'node-a' }
    }
}
