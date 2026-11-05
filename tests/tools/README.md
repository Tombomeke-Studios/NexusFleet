# tests/tools — tests for the scripts in tools/

| File | What it proves |
|---|---|
| `Invoke-NexusLint.Tests.ps1` | Findings are reported (also as GitHub annotations and a Markdown summary), and as SARIF 2.1.0; only PSScriptAnalyzer's own intermittent `RULE_ERROR`s are retried |
| `Write-NexusTestReport.Tests.ps1` | The report shows the totals, every failed test with its reason and `file:line`, test files whose setup broke, coverage per file, and whether a coverage minimum is met. It runs small Pester fixtures in a separate `pwsh` |
| `Test-NexusCommitMessage.Tests.ps1` | Good and wrong messages, pipeline input, and a real git repository in `TestDrive` (with a merge) for `-Range` |
| `Build-NexusModule.Tests.ps1` | The build contains only the module files and the help, loads in a clean `pwsh`, and exports exactly the manifest's cmdlets |
