BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../src/core/ConvertTo-NexusInstallFailure.ps1')
}

Describe 'ConvertTo-NexusInstallFailure' {
    It 'turns an unexpected error into a failed InstallResult that changed nothing' {
        $result = ConvertTo-NexusInstallFailure -HostInfo ([pscustomobject]@{ Name = 'node-web01' }) -Message 'module not found'

        $result.PSObject.TypeNames | Should -Contain 'NexusFleet.InstallResult'
        $result.Host | Should -Be 'node-web01'
        $result.Success | Should -BeFalse
        $result.Changed | Should -BeFalse
        $result.Step | Should -Be 'Install'
        $result.Error | Should -Be 'installation of node-web01 failed unexpectedly: module not found'
        $result.Steps | Should -BeNullOrEmpty
    }

    It 'keeps whether it was a dry run' {
        (ConvertTo-NexusInstallFailure -HostInfo ([pscustomobject]@{ Name = 'a' }) -Message 'x' -PlanOnly).PlanOnly | Should -BeTrue
        (ConvertTo-NexusInstallFailure -HostInfo ([pscustomobject]@{ Name = 'a' }) -Message 'x').PlanOnly | Should -BeFalse
    }
}
