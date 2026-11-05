<#
.SYNOPSIS
Starts the node lab: a local NexusInfra control plane and three fresh Ubuntu hosts, for Install-NexusNode end to end.

.DESCRIPTION
A lab on this machine that needs nothing but Docker (see docker-compose.yml for the layout):
  1. Creates lab/node-lab/.keys/ (git-ignored): an SSH key pair, an empty known_hosts, and .env with random
     secrets for this lab (broker user, JWT secret, INTERNAL_API_TOKEN, admin password).
  2. Builds the host image and starts the stack (docker compose).
  3. Waits for the panel, signs in as the lab admin and creates an API token with the scopes write and admin.
  4. Writes for NexusFleet: .keys/api-token, .keys/nexusinfra.lab.psd1 (config override: panel, broker address
     as the hosts see it, the agent link URL, known_hosts), .keys/inventory.lab.json (the two direct hosts) and
     .keys/inventory.outbound.json (node-lab3, reach "outbound": its agent connects to the gateway over the agent
     link, docs/agent-link.md).
Every secret here is a lab-only value, created by this script and kept in the git-ignored .keys folder.

.PARAMETER Remove
Stops the lab and deletes its containers and volumes (the .keys folder stays; delete it by hand for new secrets).

.PARAMETER Version
The NexusInfra image tag, for the control plane and the agents alike. Default: 0.4.1-community, the published
images of NexusInfra v0.4.1 (the first release with the agent link) on ghcr.io, so any machine and CI can pull them.
0.4.0-community is the nexusfleet-baseline release, without the agent link.

.PARAMETER BuildFrom
A NexusInfra checkout to build the images from, under the tag -Version, instead of pulling published ones: for a
NexusInfra change that is not released yet (for example NexusInfra dev). The hosts cannot see this machine's
images (they run their own Docker), so the agent image also goes into the lab's registry (172.29.50.30:5000), and
the lab config points Agent.Image there.

.EXAMPLE
./lab/node-lab/Start-NodeLab.ps1

.EXAMPLE
./lab/node-lab/Start-NodeLab.ps1 -Remove

.EXAMPLE
./lab/node-lab/Start-NodeLab.ps1 -Version agentlink-community -BuildFrom ../NexusInfra
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Remove,

    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string]$Version = '0.4.1-community',

    [ValidateScript({ Test-Path -Path (Join-Path -Path $_ -ChildPath 'services/node-agent/Dockerfile') })]
    [string]$BuildFrom
)
$imageRoot = 'ghcr.io/tombomeke-studios/nexusinfra'

$keyFolder = Join-Path -Path $PSScriptRoot -ChildPath '.keys'
$envFile = Join-Path -Path $keyFolder -ChildPath '.env'
$compose = @('compose', '--project-directory', $PSScriptRoot, '--env-file', $envFile)

if ($Remove) {
    if ($PSCmdlet.ShouldProcess('nexusfleet-node-lab', 'Remove the lab containers and volumes')) {
        docker @compose down --volumes --remove-orphans
    }
    return
}

# 1. Keys and secrets (kept between runs, so a restarted lab keeps the same token and broker password).
if (-not (Test-Path -Path $keyFolder)) {
    New-Item -Path $keyFolder -ItemType Directory | Out-Null
}
$keyPath = Join-Path -Path $keyFolder -ChildPath 'id_ed25519'
if (-not (Test-Path -Path $keyPath)) {
    ssh-keygen -t ed25519 -N '' -C 'nexusfleet-node-lab' -f $keyPath -q
    if ($LASTEXITCODE -ne 0) { throw 'ssh-keygen failed' }
}
$knownHosts = Join-Path -Path $keyFolder -ChildPath 'known_hosts'
if (-not (Test-Path -Path $knownHosts)) {
    New-Item -Path $knownHosts -ItemType File | Out-Null
}
if (-not (Test-Path -Path $envFile)) {
    $random = { [Convert]::ToHexString([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(24)).ToLower() }
    $lines = @(
        "NEXUSINFRA_VERSION=$Version"
        'RABBITMQ_USER=fleet'
        "RABBITMQ_PASS=$(& $random)"
        "JWT_SECRET=$(& $random)"
        "INTERNAL_API_TOKEN=$(& $random)"
        "ADMIN_PASSWORD=$(& $random)"
        "LAB_PUBKEY=$((Get-Content -Path "$keyPath.pub" -Raw).Trim())"
    )
    Set-Content -Path $envFile -Value $lines
}
# The version follows -Version on every start; the secrets stay.
$lines = @(Get-Content -Path $envFile | Where-Object { $_ -notlike 'NEXUSINFRA_VERSION=*' }) + "NEXUSINFRA_VERSION=$Version"
Set-Content -Path $envFile -Value $lines
$settings = @{}
foreach ($line in Get-Content -Path $envFile) {
    $key, $value = $line -split '=', 2
    $settings[$key] = $value
}

# 2. The stack.
if (-not $PSCmdlet.ShouldProcess('nexusfleet-node-lab', 'Build and start the lab')) {
    return
}
if ($BuildFrom) {
    # Every Dockerfile of NexusInfra builds from the root of the checkout. Under the published names, so the
    # compose file uses them as they are (compose pulls only an image that is missing).
    foreach ($service in 'orchestrator', 'gateway', 'control-room', 'node-agent') {
        docker build --file (Join-Path -Path $BuildFrom -ChildPath "services/$service/Dockerfile") `
            --build-arg NEXUS_EDITION=community --build-arg "APP_VERSION=0.0.0-$Version" --tag "$imageRoot/${service}:$Version" $BuildFrom
        if ($LASTEXITCODE -ne 0) { throw "docker build of $service failed" }
    }
}
docker @compose up --detach --build
if ($LASTEXITCODE -ne 0) { throw 'docker compose up failed' }

# The agent image as the hosts pull it: published on ghcr.io, or built here and pushed into the lab registry.
$agentImage = "$imageRoot/node-agent:$Version"
if ($BuildFrom) {
    $pushed = "127.0.0.1:29500/nexusinfra/node-agent:$Version"
    docker tag $agentImage $pushed
    docker push --quiet $pushed
    if ($LASTEXITCODE -ne 0) { throw 'docker push of the agent image into the lab registry failed' }
    $agentImage = "172.29.50.30:5000/nexusinfra/node-agent:$Version"
}

# 3. Wait for the panel, then sign in and create the API token for NexusFleet.
$baseUrl = 'http://127.0.0.1:29400'
$login = @{ email = 'admin@lab.local'; password = $settings.ADMIN_PASSWORD } | ConvertTo-Json
$jwt = $null
foreach ($attempt in 1..60) {
    try {
        $jwt = (Invoke-RestMethod -Method Post -Uri "$baseUrl/auth/login" -Body $login -ContentType 'application/json' -TimeoutSec 5).token
        break
    }
    catch {
        Start-Sleep -Seconds 2
    }
}
if (-not $jwt) { throw "The lab panel at $baseUrl did not answer within 2 minutes; see: docker @compose logs orchestrator" }

# The panel can answer before RabbitMQ accepts connections. Wait until the broker is reachable from the hosts
# themselves (that is the path the agents take, and what Test-NexusHost checks), so a test never meets a lab that is
# still starting.
$brokerUp = $false
foreach ($attempt in 1..60) {
    docker @compose exec -T node1 bash -c 'timeout 2 bash -c "</dev/tcp/172.29.50.10/5672"' 2>$null
    if ($LASTEXITCODE -eq 0) {
        $brokerUp = $true
        break
    }
    Start-Sleep -Seconds 2
}
if (-not $brokerUp) { throw 'The lab broker did not accept connections from the hosts within 2 minutes; see: docker compose logs rabbitmq' }

$tokenFile = Join-Path -Path $keyFolder -ChildPath 'api-token'
# A kept token only counts when this panel still knows it: the panel's database lives in its container, so a
# recreated lab has forgotten every token.
$tokenValid = $false
if (Test-Path -Path $tokenFile) {
    try {
        $null = Invoke-RestMethod -Uri "$baseUrl/me" -Headers @{ Authorization = "Bearer $(Get-Content -Path $tokenFile -Raw)" } -TimeoutSec 5
        $tokenValid = $true
    }
    catch {
        Write-Verbose "The kept API token is no longer valid; creating a new one."
    }
}
if (-not $tokenValid) {
    $headers = @{ Authorization = "Bearer $jwt" }
    $body = @{ name = 'nexusfleet-lab'; scopes = @('write', 'admin') } | ConvertTo-Json
    $created = Invoke-RestMethod -Method Post -Uri "$baseUrl/me/tokens" -Headers $headers -Body $body -ContentType 'application/json'
    Set-Content -Path $tokenFile -Value $created.secret -NoNewline
}

# 4. What NexusFleet needs for this lab.
$labConfig = @"
# Written by lab/node-lab/Start-NodeLab.ps1: NexusFleet config override for the node lab.
# The agent link goes to the gateway on the lab network, without TLS (ws://): allowed only because this is a lab
# (AllowUnencryptedHttp). The API itself stays on 127.0.0.1, so its token never leaves this machine.
@{
    Api    = @{ BaseUrl = '$baseUrl'; AllowUnencryptedHttp = `$true }
    Broker = @{ Host = '172.29.50.10'; Port = 5672 }
    Agent  = @{
        Image = '$agentImage'
        Link  = @{ Url = 'ws://172.29.50.12:9400/agent-link' }
    }
    Ssh    = @{ KnownHostsFile = '$($knownHosts.Replace('\', '/'))' }
    Health = @{ VerifyTimeoutSeconds = 120 }
}
"@
Set-Content -Path (Join-Path -Path $keyFolder -ChildPath 'nexusinfra.lab.psd1') -Value $labConfig

$inventory = [ordered]@{
    defaults = [ordered]@{ user = 'fleet'; location = 'lab'; keyFile = $keyPath.Replace('\', '/') }
    hosts    = @(
        [ordered]@{ name = 'node-lab1'; address = '127.0.0.1'; port = 2231; agentUrl = 'http://172.29.50.21:9100' }
        [ordered]@{ name = 'node-lab2'; address = '127.0.0.1'; port = 2232; agentUrl = 'http://172.29.50.22:9100' }
    )
}
$inventory | ConvertTo-Json -Depth 4 | Set-Content -Path (Join-Path -Path $keyFolder -ChildPath 'inventory.lab.json')

# The outbound host in its own inventory: it needs a NexusInfra with the agent link (0.4.1 or later).
$outbound = [ordered]@{
    defaults = $inventory.defaults
    hosts    = @([ordered]@{ name = 'node-lab3'; address = '127.0.0.1'; port = 2233; reach = 'outbound' })
}
$outbound | ConvertTo-Json -Depth 4 | Set-Content -Path (Join-Path -Path $keyFolder -ChildPath 'inventory.outbound.json')

[pscustomobject]@{
    Panel     = $baseUrl
    Hosts     = 'node-lab1 (127.0.0.1:2231), node-lab2 (127.0.0.1:2232), node-lab3 (127.0.0.1:2233, outbound)'
    Config    = 'lab/node-lab/.keys/nexusinfra.lab.psd1'
    Inventory = 'lab/node-lab/.keys/inventory.lab.json, lab/node-lab/.keys/inventory.outbound.json'
}
