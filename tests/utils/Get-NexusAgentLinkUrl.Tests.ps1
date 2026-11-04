BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../src/utils/Get-NexusAgentLinkUrl.ps1')
}

Describe 'Get-NexusAgentLinkUrl' {
    It 'derives wss:// from an https:// panel address, plus the path' {
        Get-NexusAgentLinkUrl -Link @{ Url = ''; Path = '/agent-link' } -BaseUrl 'https://nexus.example.com' |
            Should -BeExactly 'wss://nexus.example.com/agent-link'
    }

    It 'derives ws:// from an http:// panel address, keeping the port and dropping a trailing slash' {
        Get-NexusAgentLinkUrl -Link @{ Url = ''; Path = '/agent-link' } -BaseUrl 'http://127.0.0.1:29400/' |
            Should -BeExactly 'ws://127.0.0.1:29400/agent-link'
    }

    It 'uses Link.Url as it is when set (the nodes reach the panel under another name)' {
        Get-NexusAgentLinkUrl -Link @{ Url = 'wss://link.example.com/agent-link'; Path = '/agent-link' } -BaseUrl 'http://192.168.0.6:9400' |
            Should -BeExactly 'wss://link.example.com/agent-link'
    }
}
