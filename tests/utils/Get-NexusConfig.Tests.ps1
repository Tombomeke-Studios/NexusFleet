BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../src/utils/Merge-NexusHashtable.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../src/utils/Get-NexusConfig.ps1')
    $repoConfig = Join-Path -Path $PSScriptRoot -ChildPath '../../config/nexusinfra.psd1'

    # Writes the repository config to TestDrive with one value replaced, and returns its path.
    function Write-TestConfig {
        param([string]$Find, [string]$Replace)
        $path = Join-Path -Path $TestDrive -ChildPath 'nexusinfra.psd1'
        $text = Get-Content -Path $repoConfig -Raw
        if ($Find) { $text = $text.Replace($Find, $Replace) }
        Set-Content -Path $path -Value $text
        $path
    }
}

Describe 'Get-NexusConfig' {
    AfterEach {
        Remove-Item -Path (Join-Path -Path $TestDrive -ChildPath '*.psd1') -ErrorAction SilentlyContinue
    }

    It 'loads the repository config and finds it valid' {
        $config = Get-NexusConfig -Path $repoConfig -LocalPath (Join-Path -Path $TestDrive -ChildPath 'none.psd1')

        $config.Agent.Port | Should -Be 9100
        $config.Agent.RestartPolicy | Should -Be 'unless-stopped'
        $config.Agent.EnvNames.NodeId | Should -Be 'NODE_ID'
        $config.Health.OfflineAfterSeconds | Should -Be 10
    }

    It 'uses values from the local file and keeps the rest' {
        $path = Write-TestConfig
        $localPath = Join-Path -Path $TestDrive -ChildPath 'nexusinfra.local.psd1'
        Set-Content -Path $localPath -Value "@{ Api = @{ BaseUrl = 'https://panel.example.com' } }"

        $config = Get-NexusConfig -Path $path -LocalPath $localPath

        $config.Api.BaseUrl | Should -Be 'https://panel.example.com'
        $config.Api.TimeoutSeconds | Should -Be 30
    }

    It 'fails clearly when the config file is missing' {
        { Get-NexusConfig -Path (Join-Path -Path $TestDrive -ChildPath 'missing.psd1') } |
            Should -Throw -ExpectedMessage '*config file*not found*missing.psd1*'
    }

    It 'fails clearly when the config file is not valid PowerShell data' {
        $path = Join-Path -Path $TestDrive -ChildPath 'nexusinfra.psd1'
        Set-Content -Path $path -Value '@{ Api = @{ BaseUrl = '

        { Get-NexusConfig -Path $path } | Should -Throw -ExpectedMessage '*cannot read*nexusinfra.psd1*'
    }

    It 'names a missing key' {
        $path = Write-TestConfig -Find "        ContainerName   = 'nexusinfra-node-agent'" -Replace ''

        { Get-NexusConfig -Path $path } | Should -Throw -ExpectedMessage '*Agent.ContainerName is missing*'
    }

    It 'names a value of the wrong type or out of range' {
        $path = Write-TestConfig -Find 'Port            = 9100' -Replace 'Port            = 70000'

        { Get-NexusConfig -Path $path } | Should -Throw -ExpectedMessage '*Agent.Port must be*1-65535*70000*'
    }

    It 'refuses a restart policy that does not survive a reboot' {
        $path = Write-TestConfig -Find "RestartPolicy   = 'unless-stopped'" -Replace "RestartPolicy   = 'no'"

        { Get-NexusConfig -Path $path } | Should -Throw -ExpectedMessage '*Agent.RestartPolicy*unless-stopped*always*'
    }

    It 'checks that offline comes after degraded' {
        $path = Write-TestConfig -Find 'OfflineAfterSeconds  = 10' -Replace 'OfflineAfterSeconds  = 2'

        { Get-NexusConfig -Path $path } | Should -Throw -ExpectedMessage '*Health.OfflineAfterSeconds*greater than*DegradedAfterSeconds*'
    }

    It 'lists every problem at once, not only the first' {
        $path = Write-TestConfig -Find 'Port            = 9100' -Replace "Port            = 'abc'"
        $text = (Get-Content -Path $path -Raw).Replace("BaseUrl        = 'http://localhost:9400'", "BaseUrl        = 'localhost'")
        Set-Content -Path $path -Value $text

        $message = try { Get-NexusConfig -Path $path; '' } catch { $_.Exception.Message }

        $message | Should -Match 'Api\.BaseUrl'
        $message | Should -Match 'Agent\.Port'
    }
}
