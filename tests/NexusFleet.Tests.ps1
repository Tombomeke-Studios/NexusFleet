BeforeAll {
    $script:repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $script:manifestPath = Join-Path -Path $script:repoRoot -ChildPath 'NexusFleet.psd1'
    $script:sourceFolders = 'core', 'utils', 'transports', 'api', 'steps', 'public'
}

Describe 'NexusFleet manifest' {
    BeforeAll {
        $script:manifest = Test-ModuleManifest -Path $script:manifestPath -ErrorAction Stop
        $script:manifestData = Import-PowerShellDataFile -Path $script:manifestPath
    }

    It 'is a valid module manifest' {
        $script:manifest.Name | Should -Be 'NexusFleet'
    }

    It 'requires PowerShell 7.2 or later' {
        $script:manifest.PowerShellVersion | Should -Be ([version]'7.2')
    }

    It 'only supports PowerShell 7 (Core)' {
        $script:manifest.CompatiblePSEditions | Should -Be @('Core')
    }

    It 'lists the exported functions explicitly, never with a wildcard' {
        $script:manifestData.ContainsKey('FunctionsToExport') | Should -BeTrue
        $script:manifestData.FunctionsToExport -contains '*' | Should -BeFalse
    }
}

Describe 'NexusFleet module' {
    BeforeAll {
        $script:manifestData = Import-PowerShellDataFile -Path $script:manifestPath
    }

    AfterAll {
        Remove-Module -Name NexusFleet -Force -ErrorAction SilentlyContinue
    }

    It 'imports without errors' {
        { Import-Module -Name $script:manifestPath -Force -ErrorAction Stop } | Should -Not -Throw
    }

    It 'exports exactly the functions listed in the manifest' {
        $module = Import-Module -Name $script:manifestPath -Force -PassThru
        $exported = @($module.ExportedFunctions.Keys | Sort-Object) -join ', '
        $listed = @($script:manifestData.FunctionsToExport | Sort-Object) -join ', '

        $exported | Should -Be $listed
    }

    It 'exports no cmdlets, variables or aliases' {
        $module = Import-Module -Name $script:manifestPath -Force -PassThru

        $module.ExportedCmdlets.Count | Should -Be 0
        $module.ExportedVariables.Count | Should -Be 0
        $module.ExportedAliases.Count | Should -Be 0
    }
}

Describe 'NexusFleet loader' {
    BeforeEach {
        # A throw-away copy of the module in Pester's TestDrive, with one probe script per
        # source folder. Each probe writes its folder name to a file when it is loaded.
        $script:fakeRoot = Join-Path -Path $TestDrive -ChildPath 'NexusFleet'
        $script:loadLog = Join-Path -Path $TestDrive -ChildPath 'load-order.txt'
        New-Item -Path $script:fakeRoot -ItemType Directory -Force | Out-Null
        Copy-Item -Path $script:manifestPath -Destination $script:fakeRoot
        Copy-Item -Path (Join-Path -Path $script:repoRoot -ChildPath 'NexusFleet.psm1') -Destination $script:fakeRoot

        foreach ($folder in $script:sourceFolders) {
            $folderPath = Join-Path -Path $script:fakeRoot -ChildPath "src/$folder"
            New-Item -Path $folderPath -ItemType Directory -Force | Out-Null
            Set-Content -Path (Join-Path -Path $folderPath -ChildPath 'Probe.ps1') `
                -Value "Add-Content -Path '$script:loadLog' -Value '$folder'"
        }
    }

    AfterEach {
        Remove-Module -Name NexusFleet -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $script:fakeRoot, $script:loadLog -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'dot-sources the source folders in the fixed order' {
        Import-Module -Name (Join-Path -Path $script:fakeRoot -ChildPath 'NexusFleet.psd1') -Force

        Get-Content -Path $script:loadLog | Should -Be $script:sourceFolders
    }

    It 'fails with a clear error when a source folder is missing' {
        Remove-Item -Path (Join-Path -Path $script:fakeRoot -ChildPath 'src/api') -Recurse -Force

        { Import-Module -Name (Join-Path -Path $script:fakeRoot -ChildPath 'NexusFleet.psd1') -Force -ErrorAction Stop } |
            Should -Throw -ExpectedMessage "*source folder*api*is missing*"
    }

    It 'names the broken file when a source script fails to load' {
        Set-Content -Path (Join-Path -Path $script:fakeRoot -ChildPath 'src/steps/Broken.ps1') -Value 'throw "boom"'

        { Import-Module -Name (Join-Path -Path $script:fakeRoot -ChildPath 'NexusFleet.psd1') -Force -ErrorAction Stop } |
            Should -Throw -ExpectedMessage "*Broken.ps1*boom*"
    }
}
