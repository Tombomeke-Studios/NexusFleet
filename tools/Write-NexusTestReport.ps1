<#
.SYNOPSIS
Turns a Pester run into a readable report: totals, every failed test with its reason and location, per-file
results, the slowest tests and the code coverage.

.DESCRIPTION
Used by CI (.github/workflows/ci.yml) after Invoke-Pester -PassThru, and usable locally. It writes Markdown:
  - a headline: passed / failed / skipped / not run, and the duration
  - "Failed": every test file whose setup failed (BeforeAll, discovery) and every failed test, with the test's
    full name, the file and line where it failed, and Pester's message (what was expected, what came instead)
  - "Test files": passed, failed and skipped per file, failing files first
  - "Slowest tests": the five slowest, to spot a test that waits for real time
  - "Coverage" (when the run measured it): the total, and each source file below 100 % with its missed lines
With -GitHubAnnotations the report also holds one ::error line per failure (property Annotations); printed in a
workflow step, GitHub shows each failure on its line in the pull request. With -SummaryPath (CI: $env:GITHUB_STEP_SUMMARY) the Markdown is appended to that
file. The report never throws for failed tests: the caller decides what a failure means (CI fails the job).

.PARAMETER Result
The result of Invoke-Pester with -PassThru (or Run.PassThru in a configuration).

.PARAMETER Title
The headline, e.g. 'Unit tests (ubuntu-latest)'.

.PARAMETER SummaryPath
A file to append the Markdown to. CI passes $env:GITHUB_STEP_SUMMARY.

.PARAMETER RepositoryRoot
Paths in the report are shown relative to this folder. Default: the repository root.

.PARAMETER GitHubAnnotations
Also prepare a GitHub Actions ::error annotation for every failure (property Annotations).

.EXAMPLE
$result = Invoke-Pester -Path ./tests -ExcludeTagFilter Integration -PassThru -Output None
./tools/Write-NexusTestReport.ps1 -Result $result -Title 'Unit tests'

Shows the report of a local run as Markdown text.

.EXAMPLE
$report = ./tools/Write-NexusTestReport.ps1 -Result $result -Title 'Unit tests (ubuntu-latest)' -SummaryPath $env:GITHUB_STEP_SUMMARY -GitHubAnnotations
$report.Annotations

What CI runs: the report in the job summary, and the annotations in the step's output.

.OUTPUTS
NexusFleet.TestReport: Title, Passed, Failed, Skipped, NotRun, Total, Coverage (percent or $null), Markdown,
Failures (Name, File, Line, Message), Annotations.
#>
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'RepositoryRoot',
    Justification = 'Used inside the $relative script block; the analyzer does not look into script blocks.')]
[CmdletBinding()]
[OutputType([pscustomobject])]
param(
    [Parameter(Mandatory)]
    [object]$Result,

    [ValidateNotNullOrEmpty()]
    [string]$Title = 'Pester',

    [string]$SummaryPath,

    [ValidateNotNullOrEmpty()]
    [string]$RepositoryRoot = (Split-Path -Path $PSScriptRoot -Parent),

    [switch]$GitHubAnnotations
)

# Numbers the same on every machine (0.6 s, not 0,6 s on a Dutch Windows).
$format = { param([string]$Pattern, [object[]]$Values) [string]::Format([cultureinfo]::InvariantCulture, $Pattern, $Values) }

# A path as it reads in the repository: relative, with forward slashes (also on Windows).
$relative = {
    param([string]$Path)
    if (-not $Path) { return '' }
    [System.IO.Path]::GetRelativePath($RepositoryRoot, $Path).Replace('\', '/')
}

# GitHub reads an annotation up to the end of the line: newlines and % must be escaped, and in the properties
# (file, line, title) also : and ,. See "workflow commands" in the GitHub Actions docs.
$escapeData = { param([string]$Text) $Text.Replace('%', '%25').Replace("`r", '%0D').Replace("`n", '%0A') }
$escapeProperty = { param([string]$Text) (& $escapeData $Text).Replace(':', '%3A').Replace(',', '%2C') }

# Where a test failed and why. Pester puts the file and line of a failed Should in TargetObject; for anything
# else (a throw, a failed mock) the It block itself is the best location.
$describeFailure = {
    param($Test)
    $errorRecord = @($Test.ErrorRecord)[0]
    $message = if ($errorRecord.DisplayErrorMessage) { $errorRecord.DisplayErrorMessage } elseif ($errorRecord) { $errorRecord.Exception.Message } else { 'no error message' }
    $file = $Test.ScriptBlock.File
    $line = $Test.ScriptBlock.StartPosition.StartLine
    if ($errorRecord.TargetObject -is [System.Collections.IDictionary] -and $errorRecord.TargetObject.File) {
        $file = $errorRecord.TargetObject.File
        $line = $errorRecord.TargetObject.Line
    }
    [pscustomobject]@{ Name = $Test.ExpandedPath; File = & $relative $file; Line = $line; Message = "$message".Trim() }
}

$tests = @($Result.Tests)
$failedTests = @($tests | Where-Object Result -EQ 'Failed')
# A container (test file) fails as a whole when its BeforeAll or its discovery throws; its tests then have no
# error of their own. Report the container's error once, and leave its tests out of the failure list.
$failedContainers = @($Result.Containers | Where-Object { $_.Result -eq 'Failed' -and $_.ErrorRecord })
$brokenFiles = @($failedContainers | ForEach-Object { $_.Item.ToString() })
$failures = @($failedTests | Where-Object { $_.ErrorRecord -or $_.ScriptBlock.File -notin $brokenFiles } | ForEach-Object { & $describeFailure $_ })

$failedCount = $Result.FailedCount
$markdown = [System.Collections.Generic.List[string]]::new()
$mark = if ($failedCount -gt 0 -or $failedContainers.Count -gt 0) { ':x:' } else { ':white_check_mark:' }
$markdown.Add("## $mark $Title")
$markdown.Add('')
$markdown.Add((& $format '**{0} passed, {1} failed, {2} skipped, {3} not run (filtered out)** of {4} tests in {5:n1} s' @($Result.PassedCount, $failedCount, $Result.SkippedCount, $Result.NotRunCount, $Result.TotalCount, $Result.Duration.TotalSeconds)))
$markdown.Add('')

if ($failedContainers.Count -gt 0 -or $failures.Count -gt 0) {
    $markdown.Add('### Failed')
    $markdown.Add('')
    foreach ($container in $failedContainers) {
        $message = (@($container.ErrorRecord)[0].Exception.Message).Trim()
        $markdown.Add("- **$(& $relative $container.Item.ToString())**: the file failed before its tests could run")
        $markdown.Add('')
        $markdown.Add('  ```text')
        foreach ($line in $message -split "`n") { $markdown.Add("  $line") }
        $markdown.Add('  ```')
    }
    foreach ($failure in $failures) {
        $markdown.Add("- **$($failure.Name)** at ``$($failure.File):$($failure.Line)``")
        $markdown.Add('')
        $markdown.Add('  ```text')
        foreach ($line in ($failure.Message -split "`n" | Select-Object -First 20)) { $markdown.Add("  $($line.TrimEnd())") }
        $markdown.Add('  ```')
    }
    $markdown.Add('')
}

# Per test file, failing files first, then by name.
$markdown.Add('### Test files')
$markdown.Add('')
$markdown.Add('| | File | Passed | Failed | Skipped | Time |')
$markdown.Add('|---|---|---:|---:|---:|---:|')
# Tests the run filtered out (an Integration test in a unit run) are NotRun: they are not part of this run.
$byFile = $tests | Where-Object Result -NE 'NotRun' | Group-Object -Property { $_.ScriptBlock.File } | ForEach-Object {
    $group = @($_.Group)
    [pscustomobject]@{
        File    = & $relative $_.Name
        Passed  = @($group | Where-Object Result -EQ 'Passed').Count
        Failed  = @($group | Where-Object Result -EQ 'Failed').Count
        Skipped = @($group | Where-Object Result -EQ 'Skipped').Count
        Seconds = ($group | Measure-Object -Property { $_.Duration.TotalSeconds } -Sum).Sum
    }
}
foreach ($file in $byFile | Sort-Object -Property @{ Expression = { $_.Failed -gt 0 }; Descending = $true }, File) {
    $icon = if ($file.Failed -gt 0) { ':x:' } elseif ($file.Passed -eq 0) { ':fast_forward:' } else { ':white_check_mark:' }
    $markdown.Add((& $format '| {0} | `{1}` | {2} | {3} | {4} | {5:n1} s |' @($icon, $file.File, $file.Passed, $file.Failed, $file.Skipped, $file.Seconds)))
}
$markdown.Add('')

$slowest = @($tests | Where-Object Result -EQ 'Passed' | Sort-Object -Property { $_.Duration } -Descending | Select-Object -First 5)
if ($slowest.Count -gt 0) {
    $markdown.Add('### Slowest tests')
    $markdown.Add('')
    $markdown.Add('| Test | Time |')
    $markdown.Add('|---|---:|')
    foreach ($test in $slowest) {
        $markdown.Add((& $format '| {0} | {1:n2} s |' @($test.ExpandedPath.Replace('|', '\|'), $test.Duration.TotalSeconds)))
    }
    $markdown.Add('')
}

$coverage = $null
if ($Result.CodeCoverage) {
    $coverage = [math]::Round($Result.CodeCoverage.CoveragePercent, 1)
    $markdown.Add("### Coverage of src/: $coverage %")
    $markdown.Add('')
    # Pester lists the executed and the missed commands; together they are every analyzed command of a file.
    $executed = @($Result.CodeCoverage.CommandsExecuted) | Group-Object -Property File -AsHashTable -AsString
    $missed = @($Result.CodeCoverage.CommandsMissed) | Group-Object -Property File -AsHashTable -AsString
    if ($missed -and $missed.Count -gt 0) {
        $markdown.Add('| File | Covered | Missed lines |')
        $markdown.Add('|---|---:|---|')
        foreach ($file in $missed.Keys | Sort-Object) {
            $missedHere = @($missed[$file])
            $total = $missedHere.Count + $(if ($executed -and $executed.ContainsKey($file)) { @($executed[$file]).Count } else { 0 })
            $percent = if ($total) { 100 * ($total - $missedHere.Count) / $total } else { 0 }
            $lines = ($missedHere.Line | Sort-Object -Unique) -join ', '
            $markdown.Add((& $format '| `{0}` | {1:n0} % | {2} |' @((& $relative $file), $percent, $lines)))
        }
    }
    else {
        $markdown.Add('Every command in src/ ran in the tests.')
    }
    $markdown.Add('')
}

# One GitHub annotation per failure. Returned in the report (not written here), so the caller prints them where
# GitHub reads them: the step's output.
$annotations = @(
    foreach ($container in $failedContainers) {
        $file = & $escapeProperty (& $relative $container.Item.ToString())
        "::error file=$file,title=$(& $escapeProperty 'Test file failed')::$(& $escapeData (@($container.ErrorRecord)[0].Exception.Message))"
    }
    foreach ($failure in $failures) {
        "::error file=$(& $escapeProperty $failure.File),line=$($failure.Line),title=$(& $escapeProperty $failure.Name)::$(& $escapeData $failure.Message)"
    }
)

$text = $markdown -join "`n"
if ($SummaryPath) {
    Add-Content -Path $SummaryPath -Value $text -Encoding utf8
}

[pscustomobject]@{
    PSTypeName  = 'NexusFleet.TestReport'
    Title       = $Title
    Passed      = $Result.PassedCount
    Failed      = $failedCount
    Skipped     = $Result.SkippedCount
    NotRun      = $Result.NotRunCount
    Total       = $Result.TotalCount
    Coverage    = $coverage
    Markdown    = $text
    Failures    = $failures
    # The ::error lines; empty unless -GitHubAnnotations.
    Annotations = [string[]]@($(if ($GitHubAnnotations) { $annotations }))
}
