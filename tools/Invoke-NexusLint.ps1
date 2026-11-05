<#
.SYNOPSIS
Runs PSScriptAnalyzer on the repository with the project settings.

.DESCRIPTION
Used locally and in CI, so both lint the same way. The run fails when there is at least one finding.

PSScriptAnalyzer sometimes fails by itself with an internal rule error (RULE_ERROR), a known race in
its command lookup (PowerShell/PSScriptAnalyzer#2205, docs/ontwerpkeuzes.md K2). Only that error is
retried, up to MaxAttempts. Findings about the code and any other error are never retried.

.PARAMETER Path
The folder to analyse. Default: the repository root.

.PARAMETER MaxAttempts
How many times to run the analyzer when it keeps failing internally.

.PARAMETER GitHubAnnotations
Also write each finding as a GitHub Actions annotation (::error file=...,line=...::).

.PARAMETER SummaryPath
Also append a Markdown summary (no findings, or a table of them) to this file. CI passes $env:GITHUB_STEP_SUMMARY.

.PARAMETER SarifPath
Also write the findings to this file as SARIF 2.1.0, the format GitHub code scanning reads. CI uploads it, so every
finding shows in the repository's Security tab and on its line in the pull request. Written also when there are no
findings: an empty result list is how code scanning learns that old findings are fixed.

.EXAMPLE
./tools/Invoke-NexusLint.ps1
Lints the repository; no output and no error means clean.

.EXAMPLE
./tools/Invoke-NexusLint.ps1 -GitHubAnnotations
What CI runs.
#>
[CmdletBinding()]
param(
    [ValidateScript({ Test-Path -Path $_ -PathType Container })]
    [string]$Path = (Split-Path -Path $PSScriptRoot -Parent),

    [ValidateRange(1, 10)]
    [int]$MaxAttempts = 3,

    [switch]$GitHubAnnotations,

    [string]$SummaryPath,

    [string]$SarifPath
)

$settingsPath = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'PSScriptAnalyzerSettings.psd1'

for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
    $analyzerErrors = $null
    $findings = Invoke-ScriptAnalyzer -Path $Path -Recurse -Settings $settingsPath `
        -ErrorVariable analyzerErrors -ErrorAction SilentlyContinue

    $ruleErrors = @($analyzerErrors | Where-Object { $_.FullyQualifiedErrorId -like 'RULE_ERROR*' })
    $otherErrors = @($analyzerErrors | Where-Object { $_.FullyQualifiedErrorId -notlike 'RULE_ERROR*' })

    if ($otherErrors) {
        throw "PSScriptAnalyzer failed: $($otherErrors[0].Exception.Message)"
    }
    if (-not $ruleErrors) {
        break
    }
    Write-Warning "PSScriptAnalyzer failed internally (attempt $attempt of $MaxAttempts): $($ruleErrors[0].Exception.Message)"
}

if ($ruleErrors) {
    throw "PSScriptAnalyzer kept failing internally after $MaxAttempts attempts."
}

if ($SummaryPath) {
    $files = @(Get-ChildItem -Path $Path -Include '*.ps1', '*.psm1', '*.psd1' -Recurse -File).Count
    $summary = if ($findings) {
        @("## :x: PSScriptAnalyzer: $(@($findings).Count) finding(s) in $files files", '',
            '| File | Line | Rule | Message |', '|---|---:|---|---|')
        foreach ($finding in $findings) {
            $file = [System.IO.Path]::GetRelativePath($Path, $finding.ScriptPath).Replace('\', '/')
            "| ``$file`` | $($finding.Line) | $($finding.RuleName) | $($finding.Message.Replace('|', '\|')) |"
        }
    }
    else {
        "## :white_check_mark: PSScriptAnalyzer: no findings in $files files"
    }
    Add-Content -Path $SummaryPath -Value ($summary -join "`n") -Encoding utf8
}

if ($SarifPath) {
    # SARIF (Static Analysis Results Interchange Format): one run of one tool, its rules, and one result per finding
    # with the file (relative to the repository, with /), the line and the column.
    $levels = @{ Error = 'error'; ParseError = 'error'; Warning = 'warning'; Information = 'note' }
    $results = foreach ($finding in $findings) {
        [ordered]@{
            ruleId    = $finding.RuleName
            level     = $levels["$($finding.Severity)"] ?? 'warning'
            message   = @{ text = $finding.Message }
            locations = @(@{
                    physicalLocation = @{
                        artifactLocation = @{ uri = [System.IO.Path]::GetRelativePath($Path, $finding.ScriptPath).Replace('\', '/') }
                        region           = @{ startLine = [math]::Max(1, [int]$finding.Line); startColumn = [math]::Max(1, [int]$finding.Column) }
                    }
                })
        }
    }
    $sarif = [ordered]@{
        '$schema' = 'https://json.schemastore.org/sarif-2.1.0.json'
        version   = '2.1.0'
        runs      = @(@{
                tool    = @{
                    driver = @{
                        name           = 'PSScriptAnalyzer'
                        informationUri = 'https://github.com/PowerShell/PSScriptAnalyzer'
                        rules          = @($findings.RuleName | Sort-Object -Unique | ForEach-Object { @{ id = $_ } })
                    }
                }
                results = @($results)
            })
    }
    $sarif | ConvertTo-Json -Depth 10 | Set-Content -Path $SarifPath -Encoding utf8
}

if ($findings) {
    foreach ($finding in $findings) {
        $file = [System.IO.Path]::GetRelativePath($Path, $finding.ScriptPath)
        if ($GitHubAnnotations) {
            Write-Output "::error file=$file,line=$($finding.Line)::$($finding.RuleName): $($finding.Message)"
        }
        else {
            # A warning per finding: unlike a table on the output, it is shown even though we throw below.
            Write-Warning "$($file):$($finding.Line) $($finding.RuleName): $($finding.Message)"
        }
    }
    throw "PSScriptAnalyzer found $(@($findings).Count) issue(s)."
}
