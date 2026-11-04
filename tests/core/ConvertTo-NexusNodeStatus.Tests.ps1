[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester: variables set in BeforeAll/BeforeEach are used in It blocks; the analyzer does not look across script blocks.')]
param()

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../src/core/ConvertTo-NexusNodeStatus.ps1')
    $hostInfo = [pscustomobject]@{ Name = 'node-web01'; Address = '10.0.0.5'; Location = 'home'; AgentUrl = 'http://10.0.0.5:9100' }
    $node = [pscustomobject]@{
        id = 'node-web01'; name = 'node-web01'; location = 'home'; agentUrl = 'http://10.0.0.5:9100'; health = 'healthy'
        maintenance = $false; lastHeartbeat = '2026-11-04T07:35:00.000Z'; cpuPercent = 12.5; ramUsedMb = 900; ramTotalMb = 4000
    }
    $seen = [pscustomobject]@{
        Host = 'node-web01'; Reachable = $true; Error = $null; UptimeSeconds = 3600; DiskFreeMB = 20000
        Docker = 'Docker version 27.3.1'; AgentState = 'running'; AgentRestarts = 0
    }
}

Describe 'ConvertTo-NexusNodeStatus' {
    It 'is Ok when NexusInfra says healthy and the host runs the agent' {
        $status = ConvertTo-NexusNodeStatus -Name 'node-web01' -Node $node -HostInfo $hostInfo -HostStatus $seen

        $status.PSObject.TypeNames | Should -Contain 'NexusFleet.NodeStatus'
        $status.Ok | Should -BeTrue
        $status.Problem | Should -BeNullOrEmpty
        $status.Health | Should -Be 'healthy'
        $status.Registered | Should -BeTrue
        $status.InInventory | Should -BeTrue
        $status.AgentState | Should -Be 'running'
        $status.CpuPercent | Should -Be 12.5
        $status.LastHeartbeat | Should -Be ([datetime]::new(2026, 11, 4, 7, 35, 0, [System.DateTimeKind]::Utc))
    }

    It 'accepts a heartbeat time that is already a [datetime] (as Invoke-RestMethod gives it)' {
        $parsed = $node.PSObject.Copy()
        $parsed.lastHeartbeat = [datetime]::new(2026, 11, 4, 7, 35, 0, [System.DateTimeKind]::Utc)

        (ConvertTo-NexusNodeStatus -Name 'node-web01' -Node $parsed).LastHeartbeat.Hour | Should -Be 7
    }

    It 'reports a node that never sent a heartbeat as never (no 1970 time)' {
        $never = $node.PSObject.Copy()
        $never.lastHeartbeat = '1970-01-01T00:00:00.000Z'
        $never.health = 'offline'

        $status = ConvertTo-NexusNodeStatus -Name 'node-web01' -Node $never

        $status.LastHeartbeat | Should -BeNullOrEmpty
        $status.Problem | Should -Be 'NexusInfra reports it offline'
    }

    It 'names every problem: <Why>' -ForEach @(
        @{ Why = 'not registered'; NodeChange = 'none'; SeenChange = @{}; Expected = 'not registered in NexusInfra' }
        @{ Why = 'degraded'; NodeChange = 'degraded'; SeenChange = @{}; Expected = 'NexusInfra reports it degraded' }
        @{ Why = 'host unreachable'; NodeChange = ''; SeenChange = @{ Reachable = $false; Error = 'cannot reach 10.0.0.5:22 over ssh: timed out' }; Expected = 'cannot reach 10.0.0.5:22 over ssh: timed out' }
        @{ Why = 'agent stopped'; NodeChange = ''; SeenChange = @{ AgentState = 'exited' }; Expected = 'the agent container is exited' }
        @{ Why = 'agent missing'; NodeChange = ''; SeenChange = @{ AgentState = 'missing' }; Expected = 'the agent container is missing' }
    ) {
        $thisNode = $node.PSObject.Copy()
        if ($NodeChange -eq 'none') { $thisNode = $null } elseif ($NodeChange) { $thisNode.health = $NodeChange }
        $thisSeen = $seen.PSObject.Copy()
        foreach ($key in $SeenChange.Keys) { $thisSeen.$key = $SeenChange[$key] }

        $status = ConvertTo-NexusNodeStatus -Name 'node-web01' -Node $thisNode -HostInfo $hostInfo -HostStatus $thisSeen

        $status.Ok | Should -BeFalse
        $status.Problem | Should -Be $Expected
    }

    It 'shows how NexusInfra reaches the node: direct by default, and for outbound whether the link is up' {
        $direct = ConvertTo-NexusNodeStatus -Name 'node-web01' -Node $node -HostInfo $hostInfo -HostStatus $seen
        $direct.Connection | Should -Be 'direct'
        $direct.Linked | Should -BeNullOrEmpty

        $outbound = $node.PSObject.Copy()
        $outbound | Add-Member -NotePropertyName connection -NotePropertyValue 'outbound'
        $outbound | Add-Member -NotePropertyName linked -NotePropertyValue $true
        $linked = ConvertTo-NexusNodeStatus -Name 'node-web01' -Node $outbound -HostInfo $hostInfo -HostStatus $seen
        $linked.Connection | Should -Be 'outbound'
        $linked.Linked | Should -BeTrue
        $linked.Ok | Should -BeTrue
    }

    It 'names a healthy outbound node whose link is down as a problem (NexusInfra hears it but cannot control it)' {
        $outbound = $node.PSObject.Copy()
        $outbound | Add-Member -NotePropertyName connection -NotePropertyValue 'outbound'
        $outbound | Add-Member -NotePropertyName linked -NotePropertyValue $false

        $status = ConvertTo-NexusNodeStatus -Name 'node-web01' -Node $outbound -HostInfo $hostInfo -HostStatus $seen

        $status.Ok | Should -BeFalse
        $status.Problem | Should -BeLike '*agent link is down*'
    }

    It 'lists several problems at once' {
        $offline = $node.PSObject.Copy()
        $offline.health = 'offline'
        $stopped = $seen.PSObject.Copy()
        $stopped.AgentState = 'exited'

        (ConvertTo-NexusNodeStatus -Name 'node-web01' -Node $offline -HostInfo $hostInfo -HostStatus $stopped).Problem |
            Should -Be 'NexusInfra reports it offline; the agent container is exited'
    }

    It 'does not count maintenance as a problem' {
        $drained = $node.PSObject.Copy()
        $drained.maintenance = $true

        $status = ConvertTo-NexusNodeStatus -Name 'node-web01' -Node $drained

        $status.Ok | Should -BeTrue
        $status.Maintenance | Should -BeTrue
    }

    It 'shows a node NexusInfra knows but the inventory does not, without host data' {
        $status = ConvertTo-NexusNodeStatus -Name 'node-web01' -Node $node

        $status.InInventory | Should -BeFalse
        $status.Reachable | Should -BeNullOrEmpty
        $status.Location | Should -Be 'home'
    }

    It 'reports health unknown and registration unknown when NexusInfra could not be asked' {
        $status = ConvertTo-NexusNodeStatus -Name 'node-web01' -HostInfo $hostInfo -HostStatus $seen -PanelError 'NexusInfra is unreachable'

        $status.Health | Should -Be 'unknown'
        $status.Registered | Should -BeNullOrEmpty
        $status.Problem | Should -Be 'NexusInfra could not be asked: NexusInfra is unreachable'
        $status.AgentState | Should -Be 'running'
    }
}
