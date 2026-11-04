[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'Test data: a fake token, never a real secret.')]
param()

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../src/utils/Get-NexusApiParameter.ps1')
}

Describe 'Get-NexusApiParameter' {
    It 'takes every connection setting of Invoke-NexusApi from the session' {
        $token = ConvertTo-SecureString -String 'nxi_test' -AsPlainText -Force
        $session = [pscustomobject]@{
            PSTypeName = 'NexusFleet.Session'; BaseUrl = 'https://panel.test'; Token = $token; User = 'admin@example.com'
            TimeoutSeconds = 12; RetryCount = 3; AllowUnencryptedHttp = $true
        }

        $api = Get-NexusApiParameter -Session $session

        $api.BaseUrl | Should -Be 'https://panel.test'
        $api.Token | Should -Be $token
        $api.TimeoutSeconds | Should -Be 12
        $api.RetryCount | Should -Be 3
        $api.AllowUnencryptedHttp | Should -BeTrue
        $api.Keys | Should -HaveCount 5 -Because 'only parameters of Invoke-NexusApi may be in the splat'
    }

    It 'turns a missing AllowUnencryptedHttp into $false' {
        $session = [pscustomobject]@{ PSTypeName = 'NexusFleet.Session'; BaseUrl = 'https://panel.test'; Token = $null; TimeoutSeconds = 5; RetryCount = 0 }

        (Get-NexusApiParameter -Session $session).AllowUnencryptedHttp | Should -BeFalse
    }
}
