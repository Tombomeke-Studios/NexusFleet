function Connect-NexusInfra {
    <#
    .SYNOPSIS
    Connects NexusFleet to a NexusInfra panel with an API token and checks that the token may manage nodes.

    .DESCRIPTION
    Every other NexusFleet cmdlet that talks to NexusInfra (Install-NexusNode, Get-NexusFleetStatus) needs this
    connection first. Connect-NexusInfra checks the token before anything else happens, so a missing right shows
    up now and not halfway through an installation:

      GET /me     the account behind the token must be a platform administrator (role admin or owner)
      GET /users  the token must have the admin scope; this read-only route sits behind the same check as the
                  node routes, so it answers 200 with the scope and 403 without it
      GET /config the features of this control plane, e.g. agent-link (needed for hosts with reach outbound);
                  an older NexusInfra lists none, which is not an error

    The write scope, also needed to register nodes, cannot be checked without changing something. A token
    without it fails on the first change with a clear NexusApi.Forbidden error.

    Without -Token, the token is read from SecretManagement (stored earlier with -Save). The connection (address,
    token as a SecureString, account and API settings) is kept for the rest of this PowerShell session. The output
    shows the connection, never the token, and the run's log (logs/<RunId>/run.log) never contains the token.

    The token is only sent over plain http:// to this machine (localhost); for another http:// address set
    Api.AllowUnencryptedHttp = $true in config/nexusinfra.local.psd1, which is meant for a trusted lab network only.

    .PARAMETER BaseUrl
    The address of the panel: its gateway, e.g. https://panel.example.com or http://localhost:9400. Default:
    Api.BaseUrl from the config.

    .PARAMETER Token
    The API token (nxi_...) as a SecureString, e.g. from Read-Host -AsSecureString. Create it in the panel as a
    platform administrator, with the scopes write and admin. Default: the token stored earlier with -Save.

    .PARAMETER Save
    Also store the token with SecretManagement (in the default vault, under Api.SecretName), so a later session
    connects without -Token. Supports -WhatIf.

    .EXAMPLE
    Connect-NexusInfra -Token (Read-Host -AsSecureString 'API token') -Save

    Asks for the token, checks it against the panel from the config, and stores it for next time.

    .EXAMPLE
    Connect-NexusInfra

    Connects with the token stored earlier with -Save.

    .EXAMPLE
    Connect-NexusInfra -BaseUrl 'https://panel.example.com' -Token $token

    Connects to another panel than the one in the config, with a token already in $token.

    .INPUTS
    None. Connect-NexusInfra does not take pipeline input.

    .OUTPUTS
    NexusFleet.Connection
    BaseUrl, User (the account's e-mail), PlatformRole, TokenSaved (did -Save store it), RunId (of the log).

    .NOTES
    Error ids: NexusFleet.NotPlatformAdmin (the account is not admin or owner), NexusFleet.TokenMissingAdminScope,
    NexusFleet.TokenNotStored (no -Token and nothing stored), NexusFleet.SecretManagementMissing, and the NexusApi.*
    errors of the API client (Unauthorized for a wrong or expired token, Unreachable when the panel does not answer).
    Storing the token needs Microsoft.PowerShell.SecretManagement and a registered vault (see the user guide).

    .LINK
    https://github.com/Tombomeke-Studios/NexusFleet/blob/dev/docs/user-guide.md#connect-nexusinfra

    .LINK
    about_NexusFleet

    .LINK
    Install-NexusNode

    .LINK
    Get-NexusFleetStatus
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
    $run = Initialize-NexusRunContext -LogRoot $config.Log.Directory -KeepRuns $config.Log.KeepRuns -Secret ([System.Net.NetworkCredential]::new('', $Token).Password)
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

    # What this control plane supports beyond NexusInfra 0.4.0, e.g. 'agent-link' (docs/agent-link.md). An older
    # version lists no features; a failure here is not a reason to refuse the connection, it only means "none".
    $features = @()
    try {
        $features = @((Invoke-NexusApi @api -Method GET -Path '/config').features | Where-Object { $_ })
    }
    catch {
        Write-Verbose "GET /config failed, so no extra features are assumed: $($_.Exception.Message)"
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
        Features             = $features
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
