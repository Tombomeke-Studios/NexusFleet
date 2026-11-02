function Get-NexusStoredToken {
    <#
    .SYNOPSIS
    Reads the NexusInfra API token from SecretManagement.

    .DESCRIPTION
    One of the two functions that talk to SecretManagement (the other is Save-NexusStoredToken). Gives a clear
    error when SecretManagement is not installed or no token was stored yet.

    .PARAMETER SecretName
    The name of the secret (config: Api.SecretName).

    .EXAMPLE
    $token = Get-NexusStoredToken -SecretName 'NexusFleet-ApiToken'
    #>
    [CmdletBinding()]
    [OutputType([securestring])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SecretName
    )

    if (-not (Get-Command -Name Get-Secret -ErrorAction SilentlyContinue)) {
        $exception = [System.InvalidOperationException]::new(
            'SecretManagement is not installed. Install it with: Install-Module Microsoft.PowerShell.SecretManagement ' +
            '-Scope CurrentUser, register a vault (see README), or pass the token with -Token.')
        $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                $exception, 'NexusFleet.SecretManagementMissing', 'NotInstalled', $SecretName))
    }

    try {
        $secret = Get-Secret -Name $SecretName -ErrorAction Stop
    }
    catch {
        $exception = [System.InvalidOperationException]::new(
            "No API token stored under '$SecretName'. Store one with: " +
            "Connect-NexusInfra -Token (Read-Host -AsSecureString 'API token') -Save ($($_.Exception.Message))", $_.Exception)
        $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                $exception, 'NexusFleet.TokenNotStored', 'ObjectNotFound', $SecretName))
    }

    if ($secret -isnot [securestring]) {
        throw "The secret '$SecretName' is not a SecureString; store the token again with Connect-NexusInfra -Save."
    }
    $secret
}
