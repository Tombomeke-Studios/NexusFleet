function Get-NexusStoredToken {
    <#
    .SYNOPSIS
    Reads a NexusFleet secret (the API token, or one of the agent's secrets) from SecretManagement.

    .DESCRIPTION
    One of the two functions that talk to SecretManagement (the other is Save-NexusStoredToken). Gives a clear
    error when SecretManagement is not installed or no secret was stored yet.

    .PARAMETER SecretName
    The name of the secret (config: Api.SecretName, Agent.SecretNames).

    .PARAMETER Label
    What the secret is, for the error message. Default: API token.

    .PARAMETER StoreHint
    How to store it, for the error message. Default: the Connect-NexusInfra -Save command.

    .EXAMPLE
    $token = Get-NexusStoredToken -SecretName 'NexusFleet-ApiToken'

    .EXAMPLE
    Get-NexusStoredToken -SecretName 'NexusFleet-RabbitMqUrl' -Label 'RABBITMQ_URL' -StoreHint "Set-Secret -Name NexusFleet-RabbitMqUrl -Secret (Read-Host -AsSecureString)"
    #>
    [CmdletBinding()]
    [OutputType([securestring])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SecretName,

        [ValidateNotNullOrEmpty()]
        [string]$Label = 'API token',

        [ValidateNotNullOrEmpty()]
        [string]$StoreHint = "Connect-NexusInfra -Token (Read-Host -AsSecureString 'API token') -Save"
    )

    if (-not (Get-Command -Name Get-Secret -ErrorAction SilentlyContinue)) {
        $exception = [System.InvalidOperationException]::new(
            'SecretManagement is not installed. Install it with: Install-Module Microsoft.PowerShell.SecretManagement ' +
            '-Scope CurrentUser and register a vault (see README), or pass the value as a parameter.')
        $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                $exception, 'NexusFleet.SecretManagementMissing', 'NotInstalled', $SecretName))
    }

    try {
        $secret = Get-Secret -Name $SecretName -ErrorAction Stop
    }
    catch {
        $exception = [System.InvalidOperationException]::new(
            "No $Label stored under '$SecretName'. Store it with: $StoreHint ($($_.Exception.Message))", $_.Exception)
        $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                $exception, 'NexusFleet.TokenNotStored', 'ObjectNotFound', $SecretName))
    }

    if ($secret -isnot [securestring]) {
        throw "The secret '$SecretName' is not a SecureString; store the $Label again with: $StoreHint"
    }
    $secret
}
