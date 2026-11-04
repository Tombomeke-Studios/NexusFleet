# The build script for real: it builds into TestDrive, loads the built module in a separate process and zips it.
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester: variables set in BeforeAll are used in It blocks; the analyzer does not look across script blocks.')]
param()

BeforeAll {
    $root = Join-Path -Path $PSScriptRoot -ChildPath '../..'
    $manifest = Import-PowerShellDataFile -Path (Join-Path -Path $root -ChildPath 'NexusFleet.psd1')
    $build = & (Join-Path -Path $root -ChildPath 'tools/Build-NexusModule.ps1') -OutputPath (Join-Path -Path $TestDrive -ChildPath 'out')
    $built = Get-ChildItem -Path $build.Folder -Recurse -File | ForEach-Object { [System.IO.Path]::GetRelativePath($build.Folder, $_.FullName).Replace('\', '/') }
}

Describe 'Build-NexusModule' {
    It 'builds the version of the manifest, as a folder and a zip' {
        $build.Version | Should -Be $manifest.ModuleVersion
        Test-Path -Path $build.Zip | Should -BeTrue
        Split-Path -Path $build.Zip -Leaf | Should -Be "NexusFleet-$($manifest.ModuleVersion).zip"
    }

    It 'contains the manifest, the loader, every source file and the default config' {
        $built | Should -Contain 'NexusFleet.psd1'
        $built | Should -Contain 'NexusFleet.psm1'
        $built | Should -Contain 'config/nexusinfra.psd1'
        $built | Should -Contain 'config/inventory.example.json'
        $built | Should -Contain 'en-US/about_NexusFleet.help.txt'
        $sources = Get-ChildItem -Path (Join-Path -Path $root -ChildPath 'src') -Filter '*.ps1' -Recurse -File
        @($built | Where-Object { $_ -like 'src/*.ps1' -or $_ -like 'src/*/*.ps1' }).Count | Should -Be $sources.Count
    }

    It 'leaves out tests, tools, the lab, docs, logs and any local config' {
        $built | Where-Object { $_ -match '^(tests|tools|lab|docs|logs)/' } | Should -BeNullOrEmpty
        $built | Where-Object { $_ -match '\.local\.|inventory\.json$' } | Should -BeNullOrEmpty
        $built | Where-Object { $_ -like 'src/*/README.md' } | Should -BeNullOrEmpty
    }

    It 'checked that the built module loads and exports exactly the manifest''s cmdlets' {
        # The script throws otherwise; that it returned at all is the check. Here once more, the same way.
        $check = "(Import-Module -Name '$(Join-Path -Path $build.Folder -ChildPath 'NexusFleet.psd1')' -PassThru).ExportedFunctions.Count"
        pwsh -NoProfile -NonInteractive -Command $check | Should -Be $manifest.FunctionsToExport.Count
    }
}
