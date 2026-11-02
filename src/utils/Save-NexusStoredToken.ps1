function Save-NexusStoredToken {
    <#
    .SYNOPSIS
    Stores the NexusInfra API token with SecretManagement, in the default vault.

    .DESCRIPTION
    One of the two functions that talk to SecretManagement (the other is Get-NexusStoredToken). The token is
    stored as a SecureString, never in a file of NexusFleet. Gives a clear error when no vault is registered.

    .PARAMETER SecretName
    The name of the secret (config: Api.SecretName).

    .PARAMETER Token
    The API token.

    .EXAMPLE
    Save-NexusStoredToken -SecretName 'NexusFleet-ApiToken' -Token $token
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SecretName,

        [Parameter(Mandatory)]
        [securestring]$Token
    )

    if (-not (Get-Command -Name Set-Secret -ErrorAction SilentlyContinue)) {
        $exception = [System.InvalidOperationException]::new(
            'SecretManagement is not installed. Install it with: Install-Module Microsoft.PowerShell.SecretManagement -Scope CurrentUser')
        $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                $exception, 'NexusFleet.SecretManagementMissing', 'NotInstalled', $SecretName))
    }

    try {
        Set-Secret -Name $SecretName -SecureStringSecret $Token -ErrorAction Stop
    }
    catch {
        $exception = [System.InvalidOperationException]::new(
            "Could not store the API token as '$SecretName'. Is a vault registered? See README, or e.g.: " +
            "Install-Module Microsoft.PowerShell.SecretStore; Register-SecretVault -Name NexusFleet " +
            "-ModuleName Microsoft.PowerShell.SecretStore -DefaultVault ($($_.Exception.Message))", $_.Exception)
        $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                $exception, 'NexusFleet.TokenNotSaved', 'WriteError', $SecretName))
    }
}
