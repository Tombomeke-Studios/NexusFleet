# tests/utils — tests for src/utils

| File | What it proves |
|---|---|
| `Get-NexusConfig.Tests.ps1`, `Merge-NexusHashtable.Tests.ps1` | Reading and merging the config, warnings for unknown keys, every problem reported at once |
| `Initialize-NexusRunContext.Tests.ps1` | The RunId, the log folder (also under `-WhatIf`), `Log.Directory`, and removing old runs without ever touching anything else |
| `Write-NexusLog.Tests.ps1` | The line format, one file per host, redaction (longest secret first, `nxi_` tokens), and a warning instead of an error when the file cannot be written |
| `NexusStoredToken.Tests.ps1` | SecretManagement: storing and reading, and clear errors when it or a vault is missing |
| `Get-NexusSession.Tests.ps1` | The error when you are not connected |
| `Get-NexusSshParameter.Tests.ps1`, `Get-NexusApiParameter.Tests.ps1` | The splats for ssh and the API |
| `Get-NexusAgentLinkUrl.Tests.ps1` | The link URL derived from the panel address, or the one from the config |
| `ConvertTo-NexusShellArgument.Tests.ps1` | Quoting for bash, including quotes inside the value |
| `ConvertFrom-NexusFactLine.Tests.ps1` | `key=value` answers: an `=` in the value, Windows line endings, empty lines |
| `Get-NexusUrlPassword.Tests.ps1` | The password from a broker URL, encoded or missing, and a text that is no URL |
| `Invoke-NexusHostLoop.Tests.ps1` | The shared loop: one after the other with mocks, and in real runspaces. A failing host still gets a result, and the internal marker never leaks out |
