<#
.SYNOPSIS
Runs the Pester tests the way CI does, and writes the results, the coverage and a readable report.

.DESCRIPTION
One entry point for the tests, locally and in CI (.github/workflows/ci.yml), so both run the same thing:
  -Suite Unit         every test except the Integration ones (unit, LocalHttp, LocalSsh, scale); with coverage
  -Suite Integration  only the Integration tests, against the lab containers (lab/E1-transport, lab/node-lab)
It loads Pester 5 (never 6 or Windows' 3.4), writes to -OutputPath:
  pester-<suite>.xml    the results in NUnit XML (for any tool that reads test results)
  coverage-<suite>.xml  the coverage of src/ in JaCoCo format (Unit only)
  report-<suite>.md     the report of tools/Write-NexusTestReport.ps1: totals, every failure with its reason and
                        location, per-file results, slowest tests, coverage per file
and throws when a test failed, so a CI job fails with it. With -CI the report also goes into the GitHub job
summary and every failure becomes an annotation on its line.

.PARAMETER Suite
Unit (default) or Integration.

.PARAMETER OutputPath
Where the result files go. Default: TestResults/ in the repository root (git-ignored).

.PARAMETER Title
The headline of the report. Default: '<Suite> tests on <OS>'.

.PARAMETER CI
Write the report to $env:GITHUB_STEP_SUMMARY and print GitHub annotations for the failures.

.PARAMETER NoCoverage
Skip the coverage measurement (faster, for a quick local run).

.PARAMETER MinimumCoverage
Fail when the coverage of src/ is below this percentage (Unit only). CI passes 95, so new code without tests can
not slip in unnoticed. Without it, coverage is only reported.

.EXAMPLE
./tools/Invoke-NexusTests.ps1

Runs the unit tests with coverage; the report is in TestResults/report-Unit.md.

.EXAMPLE
./tools/Invoke-NexusTests.ps1 -Suite Integration

Runs the integration tests; start the labs first (see lab/README.md).

.OUTPUTS
NexusFleet.TestReport (see tools/Write-NexusTestReport.ps1).
#>
[CmdletBinding()]
[OutputType([pscustomobject])]
param(
    [ValidateSet('Unit', 'Integration')]
    [string]$Suite = 'Unit',

    [string]$OutputPath = (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'TestResults'),

    [string]$Title,

    [switch]$CI,

    [switch]$NoCoverage,

    [ValidateRange(0, 100)]
    [double]$MinimumCoverage
)

$root = Split-Path -Path $PSScriptRoot -Parent
Import-Module -Name Pester -MinimumVersion 5.0 -MaximumVersion 5.99 -ErrorAction Stop
$null = New-Item -Path $OutputPath -ItemType Directory -Force
if (-not $Title) {
    $os = if ($IsWindows) { 'Windows' } elseif ($IsMacOS) { 'macOS' } else { 'Linux' }
    $Title = "$Suite tests on $os (PowerShell $($PSVersionTable.PSVersion))"
}

$config = New-PesterConfiguration
$config.Run.Path = Join-Path -Path $root -ChildPath 'tests'
$config.Run.PassThru = $true
$config.Output.Verbosity = 'Detailed'
$config.TestResult.Enabled = $true
$config.TestResult.OutputFormat = 'NUnitXml'
$config.TestResult.OutputPath = Join-Path -Path $OutputPath -ChildPath "pester-$Suite.xml"
if ($Suite -eq 'Unit') {
    $config.Filter.ExcludeTag = 'Integration'
}
else {
    $config.Filter.Tag = 'Integration'
}
if ($Suite -eq 'Unit' -and -not $NoCoverage) {
    $config.CodeCoverage.Enabled = $true
    $config.CodeCoverage.Path = Join-Path -Path $root -ChildPath 'src'
    # The profiler-based measurement: much faster than one breakpoint per command.
    $config.CodeCoverage.UseBreakpoints = $false
    $config.CodeCoverage.OutputFormat = 'JaCoCo'
    $config.CodeCoverage.OutputPath = Join-Path -Path $OutputPath -ChildPath "coverage-$Suite.xml"
}

$result = Invoke-Pester -Configuration $config

$reportArgs = @{ Result = $result; Title = $Title; RepositoryRoot = $root }
if ($PSBoundParameters.ContainsKey('MinimumCoverage')) { $reportArgs.MinimumCoverage = $MinimumCoverage }
if ($CI) {
    $reportArgs.GitHubAnnotations = $true
    if ($env:GITHUB_STEP_SUMMARY) { $reportArgs.SummaryPath = $env:GITHUB_STEP_SUMMARY }
}
$report = & (Join-Path -Path $PSScriptRoot -ChildPath 'Write-NexusTestReport.ps1') @reportArgs
Set-Content -Path (Join-Path -Path $OutputPath -ChildPath "report-$Suite.md") -Value $report.Markdown -Encoding utf8
foreach ($annotation in $report.Annotations) {
    # Straight to the console, where GitHub reads it; not on the pipeline, which carries the report object.
    [Console]::Out.WriteLine($annotation)
}

# Integration tests skip themselves when a lab is not running; in CI the labs are started first, so a skip there
# means the setup failed, and that must not pass silently.
if ($CI -and $Suite -eq 'Integration' -and $result.SkippedCount -gt 0) {
    throw "$($result.SkippedCount) integration test(s) were skipped: a lab did not start. See the job log."
}
if ($result.Result -ne 'Passed') {
    throw "$Title`: $($result.FailedCount) test(s) failed$(if ($result.FailedContainers.Count) { ", $($result.FailedContainers.Count) test file(s) could not run" }). See the report."
}
if ($report.CoverageMet -eq $false) {
    throw "$Title`: the coverage of src/ is $($report.Coverage) %, below the minimum of $MinimumCoverage %. See the report."
}
$report
