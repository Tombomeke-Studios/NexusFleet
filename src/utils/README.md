# src/utils — shared helpers

Configuration (`Get-NexusConfig`, `Merge-NexusHashtable`), the run context and logging (`Initialize-NexusRunContext`,
`Write-NexusLog` with secret redaction), the session (`Get-NexusSession`), SecretManagement (`Get-NexusStoredToken`,
`Save-NexusStoredToken`), shell quoting (`ConvertTo-NexusShellArgument`), the ssh parameters of a host
(`Get-NexusSshParameter`), the API parameters of a session (`Get-NexusApiParameter`), the key=value answer of a
host (`ConvertFrom-NexusFactLine`) and the per-host loop of the cmdlets (`Invoke-NexusHostLoop`: one after the other
or in parallel, a progress bar, one result per host). All internal.
