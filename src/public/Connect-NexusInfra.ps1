function Connect-NexusInfra {
    <#
    .SYNOPSIS
    Connects NexusFleet to a NexusInfra panel with an API token and checks that the token may manage nodes.

    .DESCRIPTION
    Checks the token before anything else happens, so a missing right shows up now and not halfway through an
    installation:
      - GET /me: the account behind the token must be a platform administrator (role admin or owner).
      - GET /users: the token must have the admin scope (node routes need it, see docs/ontwerpkeuzes.md E4).
    The write scope, also needed, cannot be checked without changing something; a token without it fails on
    the first change with a clear NexusApi.Forbidden error.

    Without -Token the token is read from SecretManagement (saved earlier with -Save). The connection is kept
    for the other NexusFleet cmdlets in this PowerShell session. The output shows the connection, never the
    token. Each run is logged in logs/<RunId>/run.log, without the token.

    .PARAMETER BaseUrl
    The address of the panel (the gateway, e.g. https://panel.example.com). Default: Api.BaseUrl from the config.

    .PARAMETER Token
    The API token (nxi_...) as a SecureString, e.g. from Read-Host -AsSecureString. Create it in the panel with
    the scopes write and admin. Default: the token stored with -Save.

    .PARAMETER Save
    Also store the token with SecretManagement (default vault), so later sessions can connect without -Token.

    .EXAMPLE
    Connect-NexusInfra -Token (Read-Host -AsSecureString 'API token') -Save

    Asks for the token, checks it against the panel from the config, and stores it for next time.

    .EXAMPLE
    Connect-NexusInfra

    Connects with the stored token.

    .EXAMPLE
    Connect-NexusInfra -BaseUrl 'https://panel.example.com' -Token $token

    Connects to another panel than the one in the config.

    .OUTPUTS
    NexusFleet.Connection: BaseUrl, User, PlatformRole, TokenSaved, RunId.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [ValidatePattern('^https?://\S+$')]
        [string]$BaseUrl,

        [securestring]$Token,

        [switch]$Save
    )

    $config = Get-NexusConfig
    if (-not $BaseUrl) {
        $BaseUrl = $config.Api.BaseUrl
    }
    if (-not $Token) {
        $Token = Get-NexusStoredToken -SecretName $config.Api.SecretName
    }

    # The plain text is only used so the log can redact it.
    $run = Initialize-NexusRunContext -Secret ([System.Net.NetworkCredential]::new('', $Token).Password)
    Write-NexusLog -Context $run -Message "Connecting to $BaseUrl"

    $api = @{
        BaseUrl              = $BaseUrl
        Token                = $Token
        TimeoutSeconds       = $config.Api.TimeoutSeconds
        RetryCount           = $config.Api.RetryCount
        AllowUnencryptedHttp = [bool]$config.Api.AllowUnencryptedHttp
    }

    try {
        $me = Invoke-NexusApi @api -Method GET -Path '/me'
    }
    catch {
        Write-NexusLog -Context $run -Level Error -Message $_.Exception.Message
        $PSCmdlet.ThrowTerminatingError($_)
    }

    if ($me.platformRole -notin 'admin', 'owner') {
        $message = "The account $($me.email) is not a platform administrator (role: $($me.platformRole)); " +
        'NexusFleet manages nodes, which needs an admin or owner account.'
        Write-NexusLog -Context $run -Level Error -Message $message
        $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                [System.InvalidOperationException]::new($message), 'NexusFleet.NotPlatformAdmin', 'PermissionDenied', $me.email))
    }

    try {
        # A read-only route behind the same admin check as the node routes: 200 with the admin scope, 403 without.
        $null = Invoke-NexusApi @api -Method GET -Path '/users'
    }
    catch {
        Write-NexusLog -Context $run -Level Error -Message $_.Exception.Message
        if ($_.FullyQualifiedErrorId -like 'NexusApi.Forbidden*') {
            $message = 'The API token does not have the admin scope. Create a token with the scopes write and admin.'
            $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                    [System.InvalidOperationException]::new($message, $_.Exception), 'NexusFleet.TokenMissingAdminScope', 'PermissionDenied', $BaseUrl))
        }
        $PSCmdlet.ThrowTerminatingError($_)
    }

    $script:NexusSession = [pscustomobject]@{
        PSTypeName           = 'NexusFleet.Session'
        BaseUrl              = $BaseUrl
        Token                = $Token
        User                 = $me.email
        PlatformRole         = $me.platformRole
        TimeoutSeconds       = $api.TimeoutSeconds
        RetryCount           = $api.RetryCount
        AllowUnencryptedHttp = $api.AllowUnencryptedHttp
        ConnectedAt          = [datetime]::UtcNow
    }
    Write-NexusLog -Context $run -Message "Connected to $BaseUrl as $($me.email) ($($me.platformRole))"

    $saved = $false
    if ($Save -and $PSCmdlet.ShouldProcess($config.Api.SecretName, 'Store the API token with SecretManagement')) {
        Save-NexusStoredToken -SecretName $config.Api.SecretName -Token $Token
        $saved = $true
        Write-NexusLog -Context $run -Message "API token stored with SecretManagement as '$($config.Api.SecretName)'"
    }

    [pscustomobject]@{
        PSTypeName   = 'NexusFleet.Connection'
        BaseUrl      = $BaseUrl
        User         = $me.email
        PlatformRole = $me.platformRole
        TokenSaved   = $saved
        RunId        = $run.RunId
    }
}
