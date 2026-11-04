# Shared by the step tests (not a test file itself): a step context like Invoke-NexusHostInstall builds one, with
# the real config, a fake host, a fake connection and fake secrets. Nothing here reaches a network.
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'Test data: fake secrets, never real ones.')]
param()

function Get-TestStepContext {
    # -Outbound: a host with reach outbound, whose agent connects to the control plane (docs/agent-link.md).
    param([object]$Module, [switch]$WithoutSecrets, [switch]$Outbound)
    $hostInfo = [pscustomobject]@{
        PSTypeName = 'NexusFleet.Host'; Name = 'node-web01'; Address = '10.0.0.5'; Port = 22; User = 'fleet'
        Location = 'home'; Role = $null; KeyFile = $null
        Reach = if ($Outbound) { 'outbound' } else { 'direct' }
        AgentUrl = if ($Outbound) { $null } else { 'http://10.0.0.5:9100' }
    }
    @{
        HostInfo   = $hostInfo
        LinkUrl    = if ($Outbound) { 'wss://nexus.example.com/agent-link' } else { $null }
        Config     = & $Module { Get-NexusConfig }
        Ssh        = @{ HostName = '10.0.0.5'; Port = 22; UserName = 'fleet'; ConnectTimeoutSeconds = 5 }
        Api        = @{
            BaseUrl = 'http://localhost:9400'; Token = (ConvertTo-SecureString -String 'nxi_fake' -AsPlainText -Force)
            TimeoutSeconds = 5; RetryCount = 0; AllowUnencryptedHttp = $false
        }
        Secrets    = if ($WithoutSecrets) { $null } else {
            @{
                RabbitMqUrl      = ConvertTo-SecureString -String 'amqp://fleet:Br0ker-pass@broker:5672' -AsPlainText -Force
                InternalApiToken = ConvertTo-SecureString -String 'internal-T0ken' -AsPlainText -Force
            }
        }
        RunContext = $null
        State      = @{}
    }
}

# A result as Invoke-NexusHostCommand returns it.
function Get-TestCommandResult {
    param([int]$ExitCode = 0, [string[]]$StdOut = @(), [string[]]$StdErr = @())
    [pscustomobject]@{
        PSTypeName = 'NexusFleet.CommandResult'; HostName = '10.0.0.5'; ExitCode = $ExitCode
        StdOut = $StdOut -join "`n"; StdErr = $StdErr -join "`n"; Succeeded = $ExitCode -eq 0; TransportFailed = $ExitCode -eq 255
    }
}
