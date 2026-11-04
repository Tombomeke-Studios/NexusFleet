<#
.SYNOPSIS
Starts the node lab: a local NexusInfra control plane and two fresh Ubuntu hosts, for Install-NexusNode end to end.

.DESCRIPTION
A lab on this machine that needs nothing but Docker (see docker-compose.yml for the layout):
  1. Creates lab/node-lab/.keys/ (git-ignored): an SSH key pair, an empty known_hosts, and .env with random
     secrets for this lab (broker user, JWT secret, INTERNAL_API_TOKEN, admin password).
  2. Builds the host image and starts the stack (docker compose).
  3. Waits for the panel, signs in as the lab admin and creates an API token with the scopes write and admin.
  4. Writes for NexusFleet: .keys/api-token, .keys/nexusinfra.lab.psd1 (config override: panel, broker address
     as the hosts see it, known_hosts) and .keys/inventory.lab.json (the two hosts).
Every secret here is a lab-only value, created by this script and kept in the git-ignored .keys folder.

.PARAMETER Remove
Stops the lab and deletes its containers and volumes (the .keys folder stays; delete it by hand for new secrets).

.PARAMETER Version
The NexusInfra image tag, for the control plane and the agents alike. Default: 0.4.0-community, the published
images of the nexusfleet-baseline release (v0.4.0) on ghcr.io, so any machine and CI can pull them.

.EXAMPLE
./lab/node-lab/Start-NodeLab.ps1

.EXAMPLE
./lab/node-lab/Start-NodeLab.ps1 -Remove
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Remove,

    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string]$Version = '0.4.0-community'
)

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
docker @compose up --detach --build
if ($LASTEXITCODE -ne 0) { throw 'docker compose up failed' }

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

$tokenFile = Join-Path -Path $keyFolder -ChildPath 'api-token'
# A kept token only counts when this panel still knows it: the panel's database lives in its container, so a
# recreated lab has forgotten every token.
$tokenValid = $false
if (Test-Path -Path $tokenFile) {
    try {
        $null = Invoke-RestMethod -Uri "$baseUrl/me" -Headers @{ Authorization = "Bearer $(Get-Content -Path $tokenFile -Raw)" } -AllowUnencryptedAuthentication -TimeoutSec 5
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
@{
    Api    = @{ BaseUrl = '$baseUrl' }
    Broker = @{ Host = '172.29.50.10'; Port = 5672 }
    Agent  = @{ Image = 'ghcr.io/tombomeke-studios/nexusinfra/node-agent:$Version' }
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

[pscustomobject]@{
    Panel     = $baseUrl
    Hosts     = 'node-lab1 (127.0.0.1:2231), node-lab2 (127.0.0.1:2232)'
    Config    = 'lab/node-lab/.keys/nexusinfra.lab.psd1'
    Inventory = 'lab/node-lab/.keys/inventory.lab.json'
}
