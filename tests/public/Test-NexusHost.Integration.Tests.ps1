# Integration test: Test-NexusHost in parallel against the E1 lab container (a fresh Ubuntu 24.04 with sshd and a
# sudo user, ./lab/E1-transport/Start-LabTarget.ps1). Skipped when the lab target is not running.
# There is no broker and no Docker in the container, so Broker fails and Docker is a warning.
# Run: Invoke-Pester -Path ./tests/public -TagFilter Integration -Output Detailed
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester: variables set in BeforeAll are used in It blocks and mocks; the analyzer does not look across script blocks.')]
param()

BeforeAll {
    $module = Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../../NexusFleet.psd1') -Force -PassThru
    $keyFolder = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '../../lab/E1-transport') -ErrorAction SilentlyContinue).Path
    $labAvailable = $keyFolder -and (Test-Path -Path "$keyFolder/.keys/id_ed25519") -and
    (Test-Connection -TargetName '127.0.0.1' -TcpPort 2222 -TimeoutSeconds 2 -Quiet)

    $newHost = {
        param([string]$Name, [string]$Key)
        [pscustomobject]@{
            PSTypeName = 'NexusFleet.Host'; Name = $Name; Address = '127.0.0.1'; Port = 2222; User = 'fleet'
            Location = 'lab'; Role = $null; KeyFile = "$keyFolder/.keys/$Key"; AgentUrl = $null
        }
    }
    $config = @{
        Broker    = @{ Host = '127.0.0.1'; Port = 5672 }
        Ssh       = @{ ConnectTimeoutSeconds = 5; KnownHostsFile = "$keyFolder/.keys/known_hosts" }
        Preflight = @{ MinDiskFreeMB = 100; SupportedOs = @('ubuntu'); ThrottleLimit = 2 }
    }
}

AfterAll {
    Remove-Module -Name NexusFleet -Force -ErrorAction SilentlyContinue
}

Describe 'Test-NexusHost against the lab container' -Tag 'Integration' {
    BeforeAll {
        if ($labAvailable) {
            $runContext = & $module { param($Root) Initialize-NexusRunContext -LogRoot $Root } $TestDrive
            Mock -ModuleName NexusFleet -CommandName Initialize-NexusRunContext -MockWith { $runContext }
            Mock -ModuleName NexusFleet -CommandName Get-NexusConfig -MockWith { $config }
            $results = @((& $newHost 'node-lab' 'id_ed25519'), (& $newHost 'node-wrongkey' 'wrong_ed25519') | Test-NexusHost -ThrottleLimit 2)
        }
    }

    BeforeEach {
        if (-not $labAvailable) {
            Set-ItResult -Skipped -Because 'the E1 lab target is not running (./lab/E1-transport/Start-LabTarget.ps1)'
        }
    }

    It 'passes reachability, login, OS, sudo and disk on the fresh Ubuntu' {
        $lab = $results | Where-Object Host -EQ 'node-lab'
        foreach ($name in 'Reachable', 'SshAuth', 'OS', 'Sudo', 'DiskSpace') {
            ($lab.Checks | Where-Object Name -EQ $name).Status | Should -Be 'Pass' -Because "$name should pass"
        }
        ($lab.Checks | Where-Object Name -EQ 'OS').Detail | Should -Match '^ubuntu 24\.04'
    }

    It 'warns that Docker is missing and fails on the missing broker' {
        $lab = $results | Where-Object Host -EQ 'node-lab'
        ($lab.Checks | Where-Object Name -EQ 'Docker').Status | Should -Be 'Warning'
        $lab.Success | Should -BeFalse
        $lab.Step | Should -Be 'Broker'
    }

    It 'reports a refused key as SshAuth, in the same run' {
        $wrong = $results | Where-Object Host -EQ 'node-wrongkey'
        $wrong.Step | Should -Be 'SshAuth'
    }
}
