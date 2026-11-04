# The report script against a real Pester run: small test files with a pass, a failed Should, a throw, a skip and a
# file whose BeforeAll breaks, run by Pester 5 in a separate pwsh process (a Pester run inside a Pester run would
# share Pester's state). That process also runs the report script and hands back its result as JSON.
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester: variables set in BeforeAll are used in It blocks; the analyzer does not look across script blocks.')]
param()

BeforeAll {
    $reportScript = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '../../tools/Write-NexusTestReport.ps1')).Path
    $fixtures = New-Item -Path (Join-Path -Path $TestDrive -ChildPath 'fixtures') -ItemType Directory
    Set-Content -Path (Join-Path -Path $fixtures -ChildPath 'Sample.Tests.ps1') -Value @'
Describe 'Sample' {
    It 'passes' { 1 | Should -Be 1 }
    It 'compares' {
        $answer = 41
        $answer | Should -Be 42 -Because 'the answer is 42'
    }
    It 'throws' { throw 'the host went away' }
    It 'skips' { Set-ItResult -Skipped -Because 'no lab here' }
}
'@
    Set-Content -Path (Join-Path -Path $fixtures -ChildPath 'Broken.Tests.ps1') -Value @'
BeforeAll { throw 'the setup is broken' }
Describe 'Broken' { It 'never runs' { 1 | Should -Be 1 } }
'@
    $summaryFile = Join-Path -Path $TestDrive -ChildPath 'summary.md'
    $run = @"
Import-Module Pester -MinimumVersion 5.0 -MaximumVersion 5.99
`$result = Invoke-Pester -Path '$fixtures' -PassThru -Output None
`$report = & '$reportScript' -Result `$result -Title 'Fixture run' -RepositoryRoot '$fixtures' -SummaryPath '$summaryFile' -GitHubAnnotations
`$report | Select-Object Title, Passed, Failed, Skipped, Total, Coverage, Markdown, Annotations, Failures | ConvertTo-Json -Depth 4
"@
    $report = pwsh -NoProfile -NonInteractive -Command $run | Out-String | ConvertFrom-Json
}

Describe 'Write-NexusTestReport' {
    It 'counts what Pester counted' {
        $report.Passed | Should -Be 1
        $report.Failed | Should -Be 3
        $report.Skipped | Should -Be 1
        $report.Total | Should -Be 5
        $report.Coverage | Should -BeNullOrEmpty
    }

    It 'opens with a headline that says it failed, with the totals' {
        $lines = $report.Markdown -split "`n"
        $lines[0] | Should -Be '## :x: Fixture run'
        $lines[2] | Should -Match '^\*\*1 passed, 3 failed, 1 skipped, 0 not run \(filtered out\)\*\* of 5 tests in \d+\.\d s$'
    }

    It 'names each failed test with the file and the line of the failing Should, and Pester''s message' {
        $compare = $report.Failures | Where-Object Name -EQ 'Sample.compares'
        $compare.File | Should -Be 'Sample.Tests.ps1'
        $compare.Line | Should -Be 5
        $compare.Message | Should -Be 'Expected 42, because the answer is 42, but got 41.'
        $report.Markdown | Should -Match ([regex]::Escape('- **Sample.compares** at `Sample.Tests.ps1:5`'))
    }

    It 'reports a throw with its message and the line of the It block' {
        $throws = $report.Failures | Where-Object Name -EQ 'Sample.throws'
        $throws.Line | Should -Be 7
        $throws.Message | Should -Match 'the host went away'
    }

    It 'reports a test file whose setup failed once, with the reason, instead of its tests one by one' {
        $report.Markdown | Should -Match ([regex]::Escape('- **Broken.Tests.ps1**: the file failed before its tests could run'))
        $report.Markdown | Should -Match 'the setup is broken'
        $report.Failures.Name | Should -Not -Contain 'Broken.never runs'
    }

    It 'lists every test file, failing ones first, with its counts' {
        $table = @($report.Markdown -split "`n" | Where-Object { $_ -like '| :*' })
        $table[0] | Should -Match '^\| :x: \| `Broken\.Tests\.ps1` \| 0 \| 1 \| 0 \|'
        $table[1] | Should -Match '^\| :x: \| `Sample\.Tests\.ps1` \| 1 \| 2 \| 1 \|'
    }

    It 'prepares one GitHub annotation per failure, on the right file and line' {
        $report.Annotations | Should -HaveCount 3
        $report.Annotations | Should -Contain '::error file=Broken.Tests.ps1,title=Test file failed::the setup is broken'
        $report.Annotations | Should -Contain '::error file=Sample.Tests.ps1,line=5,title=Sample.compares::Expected 42, because the answer is 42, but got 41.'
    }

    It 'appends the Markdown to the summary file' {
        Get-Content -Path $summaryFile -Raw | Should -Match '## :x: Fixture run'
    }
}

Describe 'Write-NexusTestReport on a green run' {
    BeforeAll {
        $green = New-Item -Path (Join-Path -Path $TestDrive -ChildPath 'green') -ItemType Directory
        Set-Content -Path (Join-Path -Path $green -ChildPath 'Green.Tests.ps1') -Value "Describe 'Green' { It 'passes' { 1 | Should -Be 1 } }"
        $run = @"
Import-Module Pester -MinimumVersion 5.0 -MaximumVersion 5.99
`$result = Invoke-Pester -Path '$green' -PassThru -Output None
(& '$reportScript' -Result `$result -Title 'Green run' -RepositoryRoot '$green' -GitHubAnnotations) | Select-Object Markdown, Annotations | ConvertTo-Json
"@
        $greenReport = pwsh -NoProfile -NonInteractive -Command $run | Out-String | ConvertFrom-Json
    }

    It 'says it passed, has no Failed section and no annotations' {
        ($greenReport.Markdown -split "`n")[0] | Should -Be '## :white_check_mark: Green run'
        $greenReport.Markdown | Should -Not -Match '### Failed'
        @($greenReport.Annotations) | Should -HaveCount 0
    }
}

Describe 'Write-NexusTestReport with coverage' {
    BeforeAll {
        $covered = New-Item -Path (Join-Path -Path $TestDrive -ChildPath 'covered') -ItemType Directory
        Set-Content -Path (Join-Path -Path $covered -ChildPath 'Code.ps1') -Value @'
function Get-Half {
    param([int]$Value)
    if ($Value -gt 0) {
        $Value / 2
    }
    else {
        0
    }
}
'@
        Set-Content -Path (Join-Path -Path $covered -ChildPath 'Code.Tests.ps1') -Value @'
BeforeAll { . (Join-Path -Path $PSScriptRoot -ChildPath 'Code.ps1') }
Describe 'Get-Half' { It 'halves' { Get-Half -Value 4 | Should -Be 2 } }
'@
        $run = @"
Import-Module Pester -MinimumVersion 5.0 -MaximumVersion 5.99
`$config = New-PesterConfiguration
`$config.Run.Path = '$covered'
`$config.Run.PassThru = `$true
`$config.Output.Verbosity = 'None'
`$config.CodeCoverage.Enabled = `$true
`$config.CodeCoverage.Path = '$(Join-Path -Path $covered -ChildPath 'Code.ps1')'
`$config.CodeCoverage.UseBreakpoints = `$false
`$result = Invoke-Pester -Configuration `$config
(& '$reportScript' -Result `$result -Title 'Covered run' -RepositoryRoot '$covered') | Select-Object Coverage, Markdown | ConvertTo-Json
"@
        $coveredReport = pwsh -NoProfile -NonInteractive -Command $run | Out-String | ConvertFrom-Json
    }

    It 'gives the total coverage and the missed lines per source file' {
        $coveredReport.Coverage | Should -BeGreaterThan 0
        $coveredReport.Coverage | Should -BeLessThan 100
        $coveredReport.Markdown | Should -Match "### Coverage of src/: $([regex]::Escape("$($coveredReport.Coverage)")) %"
        $coveredReport.Markdown | Should -Match '\| `Code\.ps1` \| \d+ % \| 7 \|'
    }
}
