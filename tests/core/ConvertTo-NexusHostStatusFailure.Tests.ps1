BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../src/core/ConvertTo-NexusHostStatusFailure.ps1')
}

Describe 'ConvertTo-NexusHostStatusFailure' {
    It 'reports the host as unreachable, with the error' {
        $status = ConvertTo-NexusHostStatusFailure -HostInfo ([pscustomobject]@{ Name = 'node-web01' }) -Message 'module not found'

        $status.PSObject.TypeNames | Should -Contain 'NexusFleet.HostStatus'
        $status.Host | Should -Be 'node-web01'
        $status.Reachable | Should -BeFalse
        $status.Error | Should -Be 'status of node-web01 failed unexpectedly: module not found'
        $status.AgentState | Should -BeNullOrEmpty
    }

    It 'has the same properties as a status from Get-NexusHostStatus, so ConvertTo-NexusNodeStatus merges both the same way' {
        $status = ConvertTo-NexusHostStatusFailure -HostInfo ([pscustomobject]@{ Name = 'a' }) -Message 'x'

        $status.PSObject.Properties.Name | Should -Be 'Host', 'Reachable', 'Error', 'UptimeSeconds', 'DiskFreeMB', 'Docker',
        'AgentState', 'AgentStartedAt', 'AgentRestarts', 'AgentImage'
    }
}
