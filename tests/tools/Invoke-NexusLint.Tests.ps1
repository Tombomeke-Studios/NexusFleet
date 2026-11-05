# Mock bodies run when the lint *script* calls Invoke-ScriptAnalyzer. A script file has its own
# script scope, so a mock body cannot see $script: variables of this test file. It does see plain
# variables from BeforeAll/BeforeEach/It, which is why these are plain, and why the call counter is
# a hashtable (changing $state.Attempt changes the shared object, not a local copy).
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester: variables set in BeforeAll/BeforeEach are used in It blocks and mocks; the analyzer does not look across script blocks.')]
param()

BeforeAll {
    $lintScript = Join-Path -Path $PSScriptRoot -ChildPath '../../tools/Invoke-NexusLint.ps1'

    # One fake finding, shaped like a PSScriptAnalyzer DiagnosticRecord.
    $fakeFinding = [pscustomobject]@{
        RuleName   = 'PSAvoidUsingCmdletAliases'
        Severity   = 'Warning'
        ScriptPath = Join-Path -Path $TestDrive -ChildPath 'Bad.ps1'
        Line       = 2
        Column     = 5
        Message    = "'gci' is an alias of 'Get-ChildItem'."
    }
}

Describe 'Invoke-NexusLint' {
    BeforeEach {
        $state = @{ Attempt = 0 }
    }

    It 'succeeds after one run when there are no findings' {
        Mock -CommandName Invoke-ScriptAnalyzer -MockWith { }

        { & $lintScript -Path $TestDrive } | Should -Not -Throw
        Should -Invoke -CommandName Invoke-ScriptAnalyzer -Times 1 -Exactly
    }

    It 'fails on findings and never retries them away' {
        Mock -CommandName Invoke-ScriptAnalyzer -MockWith { $fakeFinding }

        { & $lintScript -Path $TestDrive -WarningAction SilentlyContinue } | Should -Throw -ExpectedMessage '*found 1 issue*'
        Should -Invoke -CommandName Invoke-ScriptAnalyzer -Times 1 -Exactly
    }

    It 'retries when the analyzer fails internally, and succeeds when the next run is clean' {
        Mock -CommandName Invoke-ScriptAnalyzer -MockWith {
            $state.Attempt++
            if ($state.Attempt -eq 1) {
                Write-Error -Message 'Object reference not set to an instance of an object.' -ErrorId 'RULE_ERROR'
            }
        }

        { & $lintScript -Path $TestDrive -WarningAction SilentlyContinue } | Should -Not -Throw
        Should -Invoke -CommandName Invoke-ScriptAnalyzer -Times 2 -Exactly
    }

    It 'gives up after MaxAttempts when the analyzer keeps failing internally' {
        Mock -CommandName Invoke-ScriptAnalyzer -MockWith {
            Write-Error -Message 'Object reference not set to an instance of an object.' -ErrorId 'RULE_ERROR'
        }

        { & $lintScript -Path $TestDrive -MaxAttempts 3 -WarningAction SilentlyContinue } |
            Should -Throw -ExpectedMessage '*kept failing internally after 3 attempts*'
        Should -Invoke -CommandName Invoke-ScriptAnalyzer -Times 3 -Exactly
    }

    It 'does not retry other analyzer errors' {
        Mock -CommandName Invoke-ScriptAnalyzer -MockWith {
            Write-Error -Message 'Cannot find the settings file.' -ErrorId 'SettingsFileNotFound'
        }

        { & $lintScript -Path $TestDrive } | Should -Throw -ExpectedMessage '*Cannot find the settings file*'
        Should -Invoke -CommandName Invoke-ScriptAnalyzer -Times 1 -Exactly
    }

    It 'writes a Markdown summary with a table of the findings when asked' {
        Mock -CommandName Invoke-ScriptAnalyzer -MockWith { $fakeFinding }
        $summary = Join-Path -Path $TestDrive -ChildPath 'summary.md'

        try { & $lintScript -Path $TestDrive -SummaryPath $summary -WarningAction SilentlyContinue } catch { $null = $_ }

        $text = Get-Content -Path $summary -Raw
        $text | Should -Match '## :x: PSScriptAnalyzer: 1 finding\(s\)'
        $text | Should -Match ([regex]::Escape("| ``Bad.ps1`` | 2 | PSAvoidUsingCmdletAliases | 'gci' is an alias of 'Get-ChildItem'. |"))
    }

    It 'writes a green summary when there are no findings' {
        Mock -CommandName Invoke-ScriptAnalyzer -MockWith { }
        $summary = Join-Path -Path $TestDrive -ChildPath 'clean.md'

        & $lintScript -Path $TestDrive -SummaryPath $summary

        Get-Content -Path $summary -Raw | Should -Match '## :white_check_mark: PSScriptAnalyzer: no findings'
    }

    It 'writes a GitHub annotation per finding when asked' {
        Mock -CommandName Invoke-ScriptAnalyzer -MockWith { $fakeFinding }

        $output = try { & $lintScript -Path $TestDrive -GitHubAnnotations } catch { $null }

        $output | Should -Contain "::error file=Bad.ps1,line=2::PSAvoidUsingCmdletAliases: 'gci' is an alias of 'Get-ChildItem'."
    }

    It 'writes the findings as SARIF 2.1.0 for GitHub code scanning (#132)' {
        Mock -CommandName Invoke-ScriptAnalyzer -MockWith { $fakeFinding }
        $sarifPath = Join-Path -Path $TestDrive -ChildPath 'lint.sarif'

        try { & $lintScript -Path $TestDrive -SarifPath $sarifPath -WarningAction SilentlyContinue } catch { $null = $_ }

        $sarif = Get-Content -Path $sarifPath -Raw | ConvertFrom-Json
        $sarif.version | Should -Be '2.1.0'
        $run = $sarif.runs[0]
        $run.tool.driver.name | Should -Be 'PSScriptAnalyzer'
        $run.tool.driver.rules.id | Should -Be 'PSAvoidUsingCmdletAliases'
        $result = $run.results[0]
        $result.ruleId | Should -Be 'PSAvoidUsingCmdletAliases'
        $result.level | Should -Be 'warning'
        $result.message.text | Should -Be "'gci' is an alias of 'Get-ChildItem'."
        $result.locations[0].physicalLocation.artifactLocation.uri | Should -Be 'Bad.ps1'
        $result.locations[0].physicalLocation.region.startLine | Should -Be 2
        $result.locations[0].physicalLocation.region.startColumn | Should -Be 5
    }

    It 'writes a SARIF file without results when there are no findings, so code scanning closes old alerts' {
        Mock -CommandName Invoke-ScriptAnalyzer -MockWith { }
        $sarifPath = Join-Path -Path $TestDrive -ChildPath 'clean.sarif'

        & $lintScript -Path $TestDrive -SarifPath $sarifPath

        $sarif = Get-Content -Path $sarifPath -Raw | ConvertFrom-Json
        $sarif.runs[0].results | Should -HaveCount 0
    }
}
