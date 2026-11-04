function Invoke-NexusHostInstall {
    <#
    .SYNOPSIS
    Turns one host into a NexusInfra node (or, with -PlanOnly, says what that would take). Never throws.

    .DESCRIPTION
    The per-host work of Install-NexusNode (E3: tested directly, the parallel loop around it stays thin).
      1. The preflight (Invoke-NexusHostPreflight). A host that is not ready is not touched: the result names the
         failed check. A missing Docker is only a warning there: the Docker step installs it.
      2. The installation steps from src/steps/ (Get-NexusStep) through the step runner: each step's Test, and Apply
         where needed. When a step fails, what this run changed is rolled back.
    With -PlanOnly only the Tests run (the dry run of -WhatIf): nothing on the host or in NexusInfra changes, and
    no secrets are needed.

    Returns one NexusFleet.InstallResult: Host, Success, PlanOnly, Changed (did this run change anything?), Step
    (where it failed), Error, Steps (per step: Step, Outcome, Rollback, Error) and Preflight (the checks).

    .PARAMETER HostInfo
    A NexusFleet.Host from Import-NexusInventory.

    .PARAMETER Config
    The NexusFleet config (Get-NexusConfig).

    .PARAMETER Session
    The connection from Connect-NexusInfra (passed in: in a parallel runspace the module's session does not exist).

    .PARAMETER Secrets
    The agent's secrets: a hashtable with RabbitMqUrl and InternalApiToken, both SecureStrings. Not needed with
    -PlanOnly.

    .PARAMETER PlanOnly
    Only check and report what would be done.

    .PARAMETER Force
    Recreate the agent container even when it looks in order (in the context as Force), e.g. after a secret changed.

    .PARAMETER RunContext
    Optional run context: the preflight and every step are then logged in the host's log.

    .EXAMPLE
    Invoke-NexusHostInstall -HostInfo $host -Config (Get-NexusConfig) -Session (Get-NexusSession) -Secrets $secrets
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [PSTypeName('NexusFleet.Host')]
        [pscustomobject]$HostInfo,

        [Parameter(Mandatory)]
        [hashtable]$Config,

        [Parameter(Mandatory)]
        [PSTypeName('NexusFleet.Session')]
        [pscustomobject]$Session,

        [hashtable]$Secrets,

        [switch]$PlanOnly,

        [switch]$Force,

        [PSTypeName('NexusFleet.RunContext')]
        [pscustomobject]$RunContext
    )

    $result = [pscustomobject]@{
        PSTypeName = 'NexusFleet.InstallResult'
        Host       = $HostInfo.Name
        Success    = $false
        PlanOnly   = [bool]$PlanOnly
        Changed    = $false
        Step       = $null
        Error      = $null
        Steps      = @()
        Preflight  = $null
    }

    try {
        # 1. Is the host ready? Then nothing is touched yet.
        $preflight = Invoke-NexusHostPreflight -HostInfo $HostInfo -Config $Config -RunContext $RunContext
        $result.Preflight = $preflight
        if (-not $preflight.Success) {
            $result.Step = $preflight.Step
            $result.Error = "preflight failed, nothing was changed: $($preflight.Error)"
            return $result
        }

        # 2. The steps. Everything a step needs is in its context, so a step never reads a module variable
        # (those do not exist in a parallel runspace).
        $ssh = @{
            HostName              = $HostInfo.Address
            Port                  = $HostInfo.Port
            UserName              = $HostInfo.User
            ConnectTimeoutSeconds = $Config.Ssh.ConnectTimeoutSeconds
        }
        if ($HostInfo.KeyFile) { $ssh.KeyFile = $HostInfo.KeyFile }
        if ($Config.Ssh.KnownHostsFile) { $ssh.KnownHostsFile = $Config.Ssh.KnownHostsFile }

        $context = @{
            HostInfo   = $HostInfo
            Config     = $Config
            Ssh        = $ssh
            Api        = @{
                BaseUrl              = $Session.BaseUrl
                Token                = $Session.Token
                TimeoutSeconds       = $Session.TimeoutSeconds
                RetryCount           = $Session.RetryCount
                AllowUnencryptedHttp = [bool]$Session.AllowUnencryptedHttp
            }
            Secrets    = $Secrets
            RunContext = $RunContext
            Force      = [bool]$Force
            # Steps remember things here between their Test and their Rollback (e.g. "the node existed already").
            State      = @{}
        }

        $sequence = @{ HostName = $HostInfo.Name; Step = @(Get-NexusStep); Context = $context; PlanOnly = $PlanOnly }
        if ($RunContext) { $sequence.RunContext = $RunContext }
        $run = Invoke-NexusStepSequence @sequence

        $result.Success = $run.Success
        $result.Step = $run.Step
        $result.Error = $run.Error
        $result.Steps = $run.Steps
        # A failed run was rolled back, but a rollback is not "nothing happened": Changed says whether this run
        # applied anything at all.
        $result.Changed = @($run.Steps | Where-Object { $_.Outcome -eq 'Applied' -or $_.Rollback }).Count -gt 0
    }
    catch {
        $result.Step = 'Install'
        $result.Error = "installation of $($HostInfo.Name) failed unexpectedly: $($_.Exception.Message)"
        if ($RunContext) {
            Write-NexusLog -Context $RunContext -HostName $HostInfo.Name -Step 'Install' -Level Error -Message $result.Error
        }
    }
    $result
}
