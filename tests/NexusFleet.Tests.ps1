[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester: $exportedFunctions is set in BeforeDiscovery and used by -ForEach; the analyzer does not look across script blocks.')]
param()

BeforeDiscovery {
    # The exported cmdlets, known while Pester discovers the tests (for the help test below).
    $exportedFunctions = @((Import-PowerShellDataFile -Path (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'NexusFleet.psd1')).FunctionsToExport)
}

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

    It 'requires PowerShell 7.6 or later' {
        $script:manifest.PowerShellVersion | Should -Be ([version]'7.6')
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

Describe 'Help of every exported cmdlet' {
    BeforeAll {
        Import-Module -Name $script:manifestPath -Force
    }

    AfterAll {
        Remove-Module -Name NexusFleet -Force -ErrorAction SilentlyContinue
    }

    It '<_> has a synopsis, a description, an example and help for every parameter' -ForEach $exportedFunctions {
        $help = Get-Help -Name $_ -Full

        # Without comment-based help, PowerShell generates a synopsis that is only the syntax.
        $help.Synopsis | Should -Not -BeNullOrEmpty
        $help.Synopsis | Should -Not -Match "^\s*$_ "
        ($help.description.Text -join '') | Should -Not -BeNullOrEmpty
        @($help.examples.example).Count | Should -BeGreaterThan 0

        $common = [System.Management.Automation.PSCmdlet]::CommonParameters + [System.Management.Automation.PSCmdlet]::OptionalCommonParameters
        foreach ($parameter in (Get-Command -Name $_).Parameters.Keys | Where-Object { $_ -notin $common }) {
            $parameterHelp = $help.parameters.parameter | Where-Object { $_.name -eq $parameter }
            ($parameterHelp.description.Text -join '') | Should -Not -BeNullOrEmpty -Because "parameter -$parameter needs a .PARAMETER description"
        }
    }

    # The parts above only say that help exists. These say that it is useful: what Get-Help -Full shows a user.
    Context '<_>' -ForEach $exportedFunctions {
        BeforeAll {
            $name = $_
            $help = Get-Help -Name $name -Full
            $common = [System.Management.Automation.PSCmdlet]::CommonParameters + [System.Management.Automation.PSCmdlet]::OptionalCommonParameters
            $parameters = @((Get-Command -Name $name).Parameters.Keys | Where-Object { $_ -notin $common })
        }

        It 'has a synopsis of one sentence and a description that explains, not only names' {
            $help.Synopsis | Should -Match '\.$' -Because 'the synopsis is one full sentence'
            ($help.description.Text -join "`n").Length | Should -BeGreaterThan 300 -Because 'the description says what it does, what it changes and what it needs'
        }

        It 'describes every parameter in at least a short sentence' {
            foreach ($parameter in $parameters) {
                $text = ($help.parameters.parameter | Where-Object { $_.name -eq $parameter }).description.Text -join ' '
                $text.Length | Should -BeGreaterThan 25 -Because "-$parameter needs more than a label"
            }
        }

        It 'has at least two examples; each one parses, calls the cmdlet and says what it does' {
            $examples = @($help.examples.example)
            $examples.Count | Should -BeGreaterOrEqual 2
            foreach ($example in $examples) {
                $code = "$($example.code)"
                $parseErrors = $null
                $null = [System.Management.Automation.Language.Parser]::ParseInput($code, [ref]$null, [ref]$parseErrors)
                $parseErrors | Should -BeNullOrEmpty -Because "this example must be valid PowerShell: $code"
                $code | Should -Match ([regex]::Escape($name)) -Because 'an example of a cmdlet uses that cmdlet'
                ($example.remarks.Text -join '').Trim() | Should -Not -BeNullOrEmpty -Because "this example needs a line that explains it: $code"
            }
        }

        It 'uses only parameters that exist in its examples' {
            foreach ($example in @($help.examples.example)) {
                $tokens = $null
                $ast = [System.Management.Automation.Language.Parser]::ParseInput("$($example.code)", [ref]$tokens, [ref]$null)
                $calls = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq $name }, $true)
                foreach ($call in $calls) {
                    foreach ($used in $call.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] }) {
                        $known = (Get-Command -Name $name).Parameters.Keys + @((Get-Command -Name $name).Parameters.Values.Aliases)
                        $used.ParameterName | Should -BeIn $known -Because "-$($used.ParameterName) in the example '$($example.code)' must exist"
                    }
                }
            }
        }

        It 'names what it takes from the pipeline (INPUTS) and what it returns (OUTPUTS)' {
            ($help.inputTypes.inputType.type.name -join '').Trim() | Should -Not -BeNullOrEmpty
            ($help.returnValues.returnValue.type.name -join '').Trim() | Should -Not -BeNullOrEmpty
        }

        It 'has NOTES and LINKs: the related cmdlets and the online documentation' {
            ($help.alertSet.alert.Text -join '').Trim() | Should -Not -BeNullOrEmpty
            $links = @($help.relatedLinks.navigationLink)
            @($links | Where-Object { $_.uri -match '^https://github\.com/Tombomeke-Studios/NexusFleet' }).Count | Should -BeGreaterThan 0 -Because 'one link goes to the online documentation'
            @($links | Where-Object { $_.linkText -match '^about_NexusFleet$|-Nexus' }).Count | Should -BeGreaterThan 0 -Because 'the related cmdlets or about_NexusFleet are linked'
        }
    }
}

Describe 'about_NexusFleet' {
    BeforeAll {
        Import-Module -Name $script:manifestPath -Force
    }

    AfterAll {
        Remove-Module -Name NexusFleet -Force -ErrorAction SilentlyContinue
    }

    It 'is shipped with the module and shown by Get-Help' {
        $topic = Join-Path -Path (Split-Path -Path $script:manifestPath -Parent) -ChildPath 'en-US/about_NexusFleet.help.txt'
        Test-Path -Path $topic | Should -BeTrue
        $text = Get-Help -Name about_NexusFleet | Out-String
        # The topic's own text, not Get-Help's "could not find" message (which would also name it).
        $text | Should -Match 'SHORT DESCRIPTION'
        $text | Should -Match 'turns Linux hosts into NexusInfra nodes'
    }

    It 'mentions every exported cmdlet' {
        $text = Get-Content -Path (Join-Path -Path (Split-Path -Path $script:manifestPath -Parent) -ChildPath 'en-US/about_NexusFleet.help.txt') -Raw -ErrorAction Stop
        foreach ($name in $exportedFunctions) {
            $text | Should -Match ([regex]::Escape($name))
        }
    }
}
