<#
.SYNOPSIS
Runs the NexusFleet demo on the node lab in one command: every lab host, and one host that cannot work.

.DESCRIPTION
The node lab (lab/node-lab/Start-NodeLab.ps1) writes everything a demo needs into its .keys folder. This script
puts it together and runs Invoke-NexusDemo.ps1:
  1. The lab config override, through $env:NEXUSFLEET_CONFIG (nothing is written into config/; the variable is put
     back afterwards).
  2. The connection, with the lab's API token.
  3. A demo inventory: the two direct hosts, the outbound host when the control plane lists the agent-link feature,
     and node-broken, a host on a port where nothing listens. node-broken is the failing host of criterion 3.
  4. Invoke-NexusDemo.ps1 with the lab's agent secrets.
Returns what Invoke-NexusDemo.ps1 returns (Folder, Phases, Criteria). CI runs it on a fresh lab and fails when a
criterion does not hold; locally it is the quickest way to see the whole MVP work.

.PARAMETER KeysPath
The node lab's .keys folder. Default: lab/node-lab/.keys.

.PARAMETER OutputPath
Where the demo results go. Default: lab/demo/results/ (git-ignored).

.EXAMPLE
./lab/node-lab/Start-NodeLab.ps1
./lab/demo/Invoke-NexusLabDemo.ps1

Starts the node lab, then runs the demo on it and prints each phase and the three criteria.
#>
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'Lab-only secrets, created by Start-NodeLab.ps1 in the git-ignored .keys folder.')]
[CmdletBinding()]
param(
    [ValidateScript({ Test-Path -Path (Join-Path $_ 'api-token') -PathType Leaf })]
    [string]$KeysPath = (Join-Path -Path $PSScriptRoot -ChildPath '../node-lab/.keys'),

    [string]$OutputPath = (Join-Path -Path $PSScriptRoot -ChildPath 'results')
)

$ErrorActionPreference = 'Stop'
$keys = (Resolve-Path -Path $KeysPath).ProviderPath
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../../NexusFleet.psd1') -Force

# The lab's secrets: key=value lines, written by Start-NodeLab.ps1.
$settings = @{}
foreach ($line in Get-Content -Path (Join-Path -Path $keys -ChildPath '.env')) {
    $key, $value = $line -split '=', 2
    $settings[$key] = $value
}
$tokenText = (Get-Content -Path (Join-Path -Path $keys -ChildPath 'api-token') -Raw).Trim()
$token = ConvertTo-SecureString -String $tokenText -AsPlainText -Force
# The broker as the hosts see it, on the lab network.
$rabbitMqUrl = ConvertTo-SecureString -String "amqp://$($settings.RABBITMQ_USER):$($settings.RABBITMQ_PASS)@172.29.50.10:5672" -AsPlainText -Force
$internalToken = ConvertTo-SecureString -String $settings.INTERNAL_API_TOKEN -AsPlainText -Force

$previousConfig = $env:NEXUSFLEET_CONFIG
$env:NEXUSFLEET_CONFIG = Join-Path -Path $keys -ChildPath 'nexusinfra.lab.psd1'
try {
    $connection = Connect-NexusInfra -Token $token
    Write-Verbose "Connected to $($connection.BaseUrl) as $($connection.User)"

    # Does this control plane have the agent link? Only then can the outbound host work.
    $features = @((Invoke-RestMethod -Uri "$($connection.BaseUrl)/config" -Headers @{ Authorization = "Bearer $tokenText" }).features)
    $hasLink = 'agent-link' -in $features

    $direct = Get-Content -Path (Join-Path -Path $keys -ChildPath 'inventory.lab.json') -Raw | ConvertFrom-Json
    $hosts = @($direct.hosts)
    if ($hasLink) {
        $outbound = Get-Content -Path (Join-Path -Path $keys -ChildPath 'inventory.outbound.json') -Raw | ConvertFrom-Json
        $hosts += @($outbound.hosts)
    }
    # Nothing listens on this port, so the preflight fails at Reachable, and the other hosts must go on (criterion 3).
    $hosts += [pscustomobject]@{ name = 'node-broken'; address = '127.0.0.1'; port = 2239; agentUrl = 'http://172.29.50.29:9100' }

    $null = New-Item -Path $OutputPath -ItemType Directory -Force
    $inventoryPath = Join-Path -Path $OutputPath -ChildPath 'inventory.demo.json'
    [ordered]@{ defaults = $direct.defaults; hosts = $hosts } | ConvertTo-Json -Depth 4 | Set-Content -Path $inventoryPath
    Write-Verbose "Demo inventory: $(@($hosts.name) -join ', ') (agent link: $hasLink)"

    & (Join-Path -Path $PSScriptRoot -ChildPath 'Invoke-NexusDemo.ps1') -InventoryPath $inventoryPath -OutputPath $OutputPath `
        -RabbitMqUrl $rabbitMqUrl -InternalApiToken $internalToken
}
finally {
    $env:NEXUSFLEET_CONFIG = $previousConfig
}
