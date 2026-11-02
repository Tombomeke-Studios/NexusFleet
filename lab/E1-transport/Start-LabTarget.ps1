<#
.SYNOPSIS
Starts the lab target containers for experiment E1.

.DESCRIPTION
Creates a lab-only SSH key pair in lab/E1-transport/.keys (git-ignored), builds the target image twice
(plain Ubuntu with sshd, and the same with PowerShell installed) and starts them:
  - nexusfleet-e1-plain on localhost:2222
  - nexusfleet-e1-pwsh  on localhost:2223
Also creates a second, unauthorised key to test the "wrong key" case. Requires Docker.

.EXAMPLE
./lab/E1-transport/Start-LabTarget.ps1

.EXAMPLE
./lab/E1-transport/Start-LabTarget.ps1 -Remove
Stops and removes both containers.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Remove
)

$keyFolder = Join-Path -Path $PSScriptRoot -ChildPath '.keys'
$containers = @(
    @{ Name = 'nexusfleet-e1-plain'; Port = 2222; WithPwsh = 'false' }
    @{ Name = 'nexusfleet-e1-pwsh'; Port = 2223; WithPwsh = 'true' }
)

foreach ($container in $containers) {
    if ($PSCmdlet.ShouldProcess($container.Name, 'Remove existing container')) {
        docker rm --force $container.Name 2>$null | Out-Null
    }
}
if ($Remove) {
    return
}

if (-not (Test-Path -Path $keyFolder)) {
    New-Item -Path $keyFolder -ItemType Directory | Out-Null
}
foreach ($keyName in 'id_ed25519', 'wrong_ed25519') {
    $keyPath = Join-Path -Path $keyFolder -ChildPath $keyName
    if (-not (Test-Path -Path $keyPath)) {
        ssh-keygen -t ed25519 -N '' -C "nexusfleet-e1-$keyName" -f $keyPath -q
        if ($LASTEXITCODE -ne 0) { throw "ssh-keygen failed for $keyName" }
    }
}
$publicKey = Get-Content -Path (Join-Path -Path $keyFolder -ChildPath 'id_ed25519.pub') -Raw

foreach ($container in $containers) {
    $image = "$($container.Name):latest"
    if ($PSCmdlet.ShouldProcess($image, 'Build image and start container')) {
        docker build --quiet --tag $image --build-arg "PUBKEY=$($publicKey.Trim())" `
            --build-arg "WITH_PWSH=$($container.WithPwsh)" (Join-Path -Path $PSScriptRoot -ChildPath 'target') | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "docker build failed for $image" }

        docker run --detach --name $container.Name --publish "127.0.0.1:$($container.Port):22" $image | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "docker run failed for $($container.Name)" }

        [pscustomobject]@{
            Container = $container.Name
            Endpoint  = "fleet@localhost:$($container.Port)"
            ImageMB   = [math]::Round((docker image inspect $image --format '{{.Size}}') / 1MB)
        }
    }
}
