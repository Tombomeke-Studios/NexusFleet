BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../src/utils/Get-NexusSession.ps1')
}

Describe 'Get-NexusSession' {
    It 'tells you to connect first when there is no session' {
        $script:NexusSession = $null

        { Get-NexusSession } | Should -Throw -ErrorId 'NexusFleet.NotConnected*' -ExpectedMessage '*Connect-NexusInfra*'
    }

    It 'returns the session when connected' {
        $script:NexusSession = [pscustomobject]@{ PSTypeName = 'NexusFleet.Session'; BaseUrl = 'https://panel.test' }

        (Get-NexusSession).BaseUrl | Should -Be 'https://panel.test'
    }
}
