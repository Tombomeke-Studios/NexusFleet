# Shared by the install tests (not a test file itself): a fake fleet that answers like real hosts and a real panel.
# The mocks of Invoke-NexusHostCommand and Invoke-NexusApi call these functions, which read and change a plain
# hashtable ($Fake), so a test can run the real steps through the real step runner, run them twice, make one step
# fail, and then look at what "happened" on the host and in NexusInfra. Nothing here reaches a network.
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'Test data: fake secrets, never real ones.')]
param()

function Get-FakeFleet {
    # Hosts by address: Docker installed? agent container running? FailAt makes one kind of change fail there.
    # Nodes by id, as NexusInfra stores them. Changes lists every changing call, in order.
    @{
        Hosts        = @{}
        Nodes        = @{}
        Heartbeating = @{}
        NeverHealthy = $false
        Unreachable  = [System.Collections.Generic.List[string]]::new()
        FailAt       = $null
        Changes      = [System.Collections.Generic.List[string]]::new()
    }
}

function Add-FakeHost {
    param([hashtable]$Fake, [string]$Address, [switch]$Docker, [switch]$Agent, [string]$NodeId)
    $Fake.Hosts[$Address] = @{ Docker = [bool]$Docker; Agent = [bool]$Agent; NodeId = $NodeId }
    if ($Agent) { $Fake.Heartbeating[$NodeId] = $true }
}

function Get-FakeHostInfo {
    param([string]$Name, [string]$Address)
    [pscustomobject]@{
        PSTypeName = 'NexusFleet.Host'; Name = $Name; Address = $Address; Port = 22; User = 'fleet'
        Location = 'home'; Role = $null; KeyFile = $null; AgentUrl = "http://${Address}:9100"
    }
}

function Get-FakeSession {
    [pscustomobject]@{
        PSTypeName = 'NexusFleet.Session'; BaseUrl = 'http://localhost:9400'
        Token       = (ConvertTo-SecureString -String 'nxi_fake' -AsPlainText -Force)
        User = 'admin@example.com'; PlatformRole = 'owner'; TimeoutSeconds = 5; RetryCount = 0; AllowUnencryptedHttp = $false
        ConnectedAt = [datetime]::UtcNow
    }
}

function Get-FakeSecretSet {
    @{
        RabbitMqUrl      = ConvertTo-SecureString -String 'amqp://fleet:Br0ker-pass@broker:5672' -AsPlainText -Force
        InternalApiToken = ConvertTo-SecureString -String 'internal-T0ken' -AsPlainText -Force
    }
}

function Get-FakeCommandResult {
    param([string]$HostName, [int]$ExitCode = 0, [string[]]$StdOut = @(), [string]$StdErr = '')
    [pscustomobject]@{
        PSTypeName = 'NexusFleet.CommandResult'; HostName = $HostName; ExitCode = $ExitCode; StdOut = $StdOut -join "`n"
        StdErr = $StdErr; Succeeded = $ExitCode -eq 0; TransportFailed = $ExitCode -eq 255
    }
}

function Invoke-FakeHostCommand {
    param([hashtable]$Fake, [string]$HostName, [string]$Command)
    $state = $Fake.Hosts[$HostName]
    if (-not $state) {
        return Get-FakeCommandResult -HostName $HostName -ExitCode 255 -StdErr 'Connection timed out'
    }
    $fail = { param($Kind) $Fake.FailAt -eq $Kind -or $Fake.FailAt -eq "$Kind@$HostName" }

    switch -Regex ($Command) {
        'command -v docker' {
            return Get-FakeCommandResult -HostName $HostName -ExitCode $(if ($state.Docker) { 0 } else { 1 })
        }
        'apt-get .*install' {
            $Fake.Changes.Add("$HostName install docker")
            if (& $fail 'Docker') { return Get-FakeCommandResult -HostName $HostName -ExitCode 100 -StdErr 'E: Unable to locate package docker.io' }
            $state.Docker = $true
            return Get-FakeCommandResult -HostName $HostName
        }
        'apt-get remove' {
            $Fake.Changes.Add("$HostName remove docker")
            $state.Docker = $false
            return Get-FakeCommandResult -HostName $HostName
        }
        'docker inspect' {
            if (-not $state.Agent) { return Get-FakeCommandResult -HostName $HostName -StdOut 'exists=no' }
            return Get-FakeCommandResult -HostName $HostName -StdOut @(
                'exists=yes', 'image=ghcr.io/tombomeke-studios/nexusinfra/node-agent:community', 'running=true', 'restart=unless-stopped',
                'port=9100->9100/tcp', 'mount=/var/run/docker.sock:/var/run/docker.sock', 'mount=nexusinfra-backups:/var/lib/nexusinfra/backups',
                'host=host.docker.internal:host-gateway', "env=NODE_ID=$($state.NodeId)", "env=AGENT_URL=http://${HostName}:9100")
        }
        'docker run' {
            $Fake.Changes.Add("$HostName start agent")
            if (& $fail 'AgentContainer') { return Get-FakeCommandResult -HostName $HostName -ExitCode 125 -StdErr 'docker: port is already allocated.' }
            $state.Agent = $true
            $state.NodeId = [regex]::Match($Command, "'NODE_ID' '([^']+)'").Groups[1].Value
            # Like a real agent, the first heartbeat arrives a moment later: the next GET /nodes still says offline.
            if (-not $Fake.NeverHealthy) { $Fake.Heartbeating[$state.NodeId] = 'soon' }
            return Get-FakeCommandResult -HostName $HostName
        }
        'docker rm -f' {
            $Fake.Changes.Add("$HostName remove agent")
            $state.Agent = $false
            if ($state.NodeId) { $Fake.Heartbeating.Remove($state.NodeId) }
            return Get-FakeCommandResult -HostName $HostName
        }
    }
    throw "the fake host does not know this command: $Command"
}

function Invoke-FakeApi {
    param([hashtable]$Fake, [string]$Method, [string]$Path, [object]$Body)
    switch ($Method) {
        'GET' {
            # GET /nodes/<id>/disk: NexusInfra asks the agent itself. Unreachable lists agents it cannot call.
            if ($Path -match '^/nodes/([^/]+)/disk$') {
                $id = $Matches[1]
                if (-not $Fake.Heartbeating[$id] -or $Fake.Unreachable -contains $id) {
                    throw [System.InvalidOperationException]::new('NexusInfra API GET /nodes/x/disk failed 502. NexusInfra says: fetch failed')
                }
                return [pscustomobject]@{ measuredAt = '2026-11-04T10:00:00Z'; deployments = @() }
            }
            return @($Fake.Nodes.Values | ForEach-Object {
                    $node = $_.Clone()
                    $beat = $Fake.Heartbeating[$node.id]
                    $node.health = if ($beat -eq $true) { 'healthy' } else { 'offline' }
                    if ($beat -eq 'soon') { $Fake.Heartbeating[$node.id] = $true }
                    [pscustomobject]$node
                })
        }
        'POST' {
            $Fake.Changes.Add("POST /nodes $($Body.id)")
            if ($Fake.FailAt -eq 'RegisterNode' -or $Fake.FailAt -eq "RegisterNode@$($Body.id)") {
                throw [System.InvalidOperationException]::new('NexusInfra answered 403 Forbidden.')
            }
            $Fake.Nodes[$Body.id] = @{ id = $Body.id; name = $Body.name; location = $Body.location; agentUrl = $Body.agentUrl }
            return [pscustomobject]$Fake.Nodes[$Body.id]
        }
        'DELETE' {
            $id = $Path -replace '^/nodes/', ''
            $Fake.Changes.Add("DELETE /nodes/$id")
            $Fake.Nodes.Remove($id)
            return
        }
    }
    throw "the fake panel does not know: $Method $Path"
}

# A preflight that passes, without ssh (the preflight itself is tested in Invoke-NexusHostPreflight.Tests.ps1).
function Get-FakePreflight {
    param([pscustomobject]$HostInfo, [string]$FailStep)
    [pscustomobject]@{
        PSTypeName = 'NexusFleet.PreflightResult'; Host = $HostInfo.Name; Address = $HostInfo.Address
        Success = -not $FailStep; Step = $(if ($FailStep) { $FailStep }); Error = $(if ($FailStep) { "$FailStep failed" })
        Checks = @([pscustomobject]@{ Name = 'Reachable'; Status = 'Pass'; Detail = 'answers' })
    }
}
