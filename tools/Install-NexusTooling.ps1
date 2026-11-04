<#
.SYNOPSIS
Installs the pinned development tools: Pester 5.7.1, PSScriptAnalyzer 1.25.0 and SecretManagement 1.1.2.

.DESCRIPTION
Used by CI and for a new development machine. The versions are pinned so every run tests with the same tools
(docs/ontwerpkeuzes.md K1, K2). A module that is already there in that version is skipped. The PowerShell Gallery
sometimes does not answer for a moment ("No match was found"), so each install is tried up to -MaxAttempts times,
with a growing pause.

.PARAMETER Name
Only these tools (Pester, PSScriptAnalyzer, SecretManagement). Default: all three.

.PARAMETER MaxAttempts
How often an install is tried before the script gives up.

.EXAMPLE
./tools/Install-NexusTooling.ps1

.EXAMPLE
./tools/Install-NexusTooling.ps1 -Name PSScriptAnalyzer
#>
[CmdletBinding()]
param(
    [ValidateSet('Pester', 'PSScriptAnalyzer', 'SecretManagement')]
    [string[]]$Name = @('Pester', 'PSScriptAnalyzer', 'SecretManagement'),

    [ValidateRange(1, 10)]
    [int]$MaxAttempts = 4
)

# The pinned versions. Change them here only, and say why in docs/ontwerpkeuzes.md.
$tools = @{
    Pester           = @{ Module = 'Pester'; Version = '5.7.1'; Extra = @{ SkipPublisherCheck = $true } }
    PSScriptAnalyzer = @{ Module = 'PSScriptAnalyzer'; Version = '1.25.0'; Extra = @{} }
    SecretManagement = @{ Module = 'Microsoft.PowerShell.SecretManagement'; Version = '1.1.2'; Extra = @{} }
}

foreach ($tool in $Name) {
    $spec = $tools[$tool]
    if (Get-Module -ListAvailable -Name $spec.Module | Where-Object { $_.Version -eq [version]$spec.Version }) {
        Write-Output "$($spec.Module) $($spec.Version): already installed"
        continue
    }
    $extra = $spec.Extra
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            Install-Module -Name $spec.Module -RequiredVersion $spec.Version -Scope CurrentUser -Force -ErrorAction Stop @extra
            Write-Output "$($spec.Module) $($spec.Version): installed"
            break
        }
        catch {
            if ($attempt -eq $MaxAttempts) {
                throw "Could not install $($spec.Module) $($spec.Version) after $MaxAttempts attempts: $($_.Exception.Message)"
            }
            Write-Warning "Installing $($spec.Module) failed (attempt $attempt of $MaxAttempts), trying again: $($_.Exception.Message)"
            Start-Sleep -Seconds (5 * $attempt)
        }
    }
}
