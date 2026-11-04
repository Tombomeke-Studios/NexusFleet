<#
.SYNOPSIS
Builds the NexusFleet module as it is shipped: only the files the module needs, in one folder and a zip.

.DESCRIPTION
Used locally and by the release workflow (.github/workflows/release.yml), so both build the same way.
Copies into <OutputPath>/NexusFleet/:
  NexusFleet.psd1, NexusFleet.psm1, README.md
  src/<folder>/*.ps1                     (not the README.md placeholders)
  config/nexusinfra.psd1, config/inventory.example.json   (never a local config or a real inventory)
Then checks the result: the manifest is valid, and the built module loads and exports exactly the cmdlets of the
manifest. Writes <OutputPath>/NexusFleet-<version>.zip and returns what it built.

.PARAMETER OutputPath
Where to build. Default: out/ in the repository root (git-ignored). The NexusFleet folder there is replaced.

.EXAMPLE
./tools/Build-NexusModule.ps1

.EXAMPLE
./tools/Build-NexusModule.ps1 -OutputPath $env:TEMP/nf-build
#>
[CmdletBinding()]
[OutputType([pscustomobject])]
param(
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath = (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'out')
)

$root = Split-Path -Path $PSScriptRoot -Parent
$manifest = Import-PowerShellDataFile -Path (Join-Path -Path $root -ChildPath 'NexusFleet.psd1')
$version = $manifest.ModuleVersion

$outputFolder = (New-Item -Path $OutputPath -ItemType Directory -Force).FullName
$target = Join-Path -Path $outputFolder -ChildPath 'NexusFleet'
if (Test-Path -Path $target) {
    Remove-Item -Path $target -Recurse -Force
}

# What the module needs, and nothing else.
$files = @('NexusFleet.psd1', 'NexusFleet.psm1', 'README.md', 'config/nexusinfra.psd1', 'config/inventory.example.json')
$files += Get-ChildItem -Path (Join-Path -Path $root -ChildPath 'src') -Filter '*.ps1' -Recurse -File |
    ForEach-Object { [System.IO.Path]::GetRelativePath($root, $_.FullName) }

foreach ($file in $files) {
    $destination = Join-Path -Path $target -ChildPath $file
    New-Item -Path (Split-Path -Path $destination -Parent) -ItemType Directory -Force | Out-Null
    Copy-Item -Path (Join-Path -Path $root -ChildPath $file) -Destination $destination
}
# The loader throws when one of its folders is missing; a folder without code (none today) still has to exist.
foreach ($folder in 'core', 'utils', 'transports', 'api', 'steps', 'public') {
    New-Item -Path (Join-Path -Path $target -ChildPath "src/$folder") -ItemType Directory -Force | Out-Null
}

# Check the build before anyone gets it: in a separate process, so this session's own NexusFleet does not interfere.
$builtManifest = Join-Path -Path $target -ChildPath 'NexusFleet.psd1'
$null = Test-ModuleManifest -Path $builtManifest -ErrorAction Stop
$check = "`$m = Import-Module -Name '$builtManifest' -PassThru -ErrorAction Stop; (`$m.ExportedFunctions.Keys | Sort-Object) -join ','"
$exported = pwsh -NoProfile -NonInteractive -Command $check
if ($LASTEXITCODE -ne 0) {
    throw "The built module does not load: $exported"
}
$expected = ($manifest.FunctionsToExport | Sort-Object) -join ','
if ($exported -ne $expected) {
    throw "The built module exports '$exported', but the manifest lists '$expected'."
}

$zip = Join-Path -Path $outputFolder -ChildPath "NexusFleet-$version.zip"
Compress-Archive -Path $target -DestinationPath $zip -Force

[pscustomobject]@{
    Version = $version
    Folder  = $target
    Zip     = $zip
    Files   = $files.Count
}
