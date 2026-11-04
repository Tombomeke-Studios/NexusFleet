# src/utils — shared helpers

Configuration (`Get-NexusConfig`, `Merge-NexusHashtable`), the run context and logging (`Initialize-NexusRunContext`,
`Write-NexusLog` with secret redaction), the session (`Get-NexusSession`), SecretManagement (`Get-NexusStoredToken`,
`Save-NexusStoredToken`), shell quoting (`ConvertTo-NexusShellArgument`), the ssh parameters of a host
(`Get-NexusSshParameter`) and the API parameters of a session (`Get-NexusApiParameter`). All internal.
