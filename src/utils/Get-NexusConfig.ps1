function Get-NexusConfig {
    <#
    .SYNOPSIS
    Reads and validates the NexusInfra-specific configuration.

    .DESCRIPTION
    Reads config/nexusinfra.psd1, applies config/nexusinfra.local.psd1 on top when it exists, and checks
    every value against a list of rules. All problems are reported in one error, so a broken config can
    be fixed in one go. Returns the config as a hashtable, e.g. $config.Agent.Port.

    .PARAMETER Path
    The config file. Default: config/nexusinfra.psd1 of the module.

    .PARAMETER LocalPath
    The optional local override. Default: nexusinfra.local.psd1 next to the config file.

    .EXAMPLE
    $config = Get-NexusConfig
    $config.Agent.Image
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$Path = (Join-Path -Path $PSScriptRoot -ChildPath '../../config/nexusinfra.psd1'),

        [string]$LocalPath
    )

    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        throw "NexusFleet config file not found: '$Path'."
    }
    # A clean full path for messages (no 'src/utils/../../').
    $Path = (Resolve-Path -Path $Path).ProviderPath
    if (-not $LocalPath) {
        $LocalPath = Join-Path -Path (Split-Path -Path $Path -Parent) -ChildPath 'nexusinfra.local.psd1'
    }

    $config = $null
    $filesRead = [System.Collections.Generic.List[string]]::new()
    foreach ($file in $Path, $LocalPath) {
        if (-not (Test-Path -Path $file -PathType Leaf)) {
            continue
        }
        $filesRead.Add($file)
        try {
            # Import-PowerShellDataFile only accepts data, never runs code from the file.
            $data = Import-PowerShellDataFile -Path $file -ErrorAction Stop
        }
        catch {
            throw "NexusFleet cannot read config file '$file': $($_.Exception.Message)"
        }
        $config = if ($null -eq $config) { $data } else { Merge-NexusHashtable -Base $config -Override $data }
    }

    # One rule per value: where it is, what it must be (for the message), and the check itself.
    $rules = @(
        @{ Key = 'Api.BaseUrl'; Expect = 'an http(s) URL'; Test = { param($v) $v -is [string] -and $v -match '^https?://\S+$' } }
        @{ Key = 'Api.TimeoutSeconds'; Expect = 'a whole number 1-300'; Test = { param($v) $v -is [int] -and $v -ge 1 -and $v -le 300 } }
        @{ Key = 'Api.RetryCount'; Expect = 'a whole number 0-10'; Test = { param($v) $v -is [int] -and $v -ge 0 -and $v -le 10 } }
        @{ Key = 'Api.AllowUnencryptedHttp'; Expect = '$true or $false'; Test = { param($v) $v -is [bool] } }
        @{ Key = 'Api.SecretName'; Expect = 'a secret name (letters, digits, . _ -)'; Test = { param($v) $v -is [string] -and $v -match '^[A-Za-z0-9._-]+$' } }
        @{ Key = 'Agent.Image'; Expect = 'an image name'; Test = { param($v) $v -is [string] -and $v -match '^\S+$' } }
        @{ Key = 'Agent.ContainerName'; Expect = 'a Docker container name'; Test = { param($v) $v -is [string] -and $v -match '^[a-zA-Z0-9][a-zA-Z0-9_.-]+$' } }
        @{ Key = 'Agent.Port'; Expect = 'a port number 1-65535'; Test = { param($v) $v -is [int] -and $v -ge 1 -and $v -le 65535 } }
        @{ Key = 'Agent.RestartPolicy'; Expect = "'unless-stopped' or 'always' (other policies leave the node offline after a reboot)"; Test = { param($v) $v -in 'unless-stopped', 'always' } }
        @{ Key = 'Agent.BackupVolume'; Expect = 'a Docker volume name'; Test = { param($v) $v -is [string] -and $v -match '^[a-zA-Z0-9][a-zA-Z0-9_.-]+$' } }
        @{ Key = 'Agent.BackupMountPath'; Expect = 'an absolute Linux path'; Test = { param($v) $v -is [string] -and $v -match '^/\S*$' } }
        @{ Key = 'Agent.DockerSocket'; Expect = 'an absolute Linux path'; Test = { param($v) $v -is [string] -and $v -match '^/\S*$' } }
        @{ Key = 'Agent.HostGateway'; Expect = "'<name>:host-gateway'"; Test = { param($v) $v -is [string] -and $v -match '^\S+:host-gateway$' } }
        @{ Key = 'Agent.EnvNames.NodeId'; Expect = 'an environment variable name'; Test = { param($v) $v -is [string] -and $v -match '^[A-Z_][A-Z0-9_]*$' } }
        @{ Key = 'Agent.EnvNames.RabbitMqUrl'; Expect = 'an environment variable name'; Test = { param($v) $v -is [string] -and $v -match '^[A-Z_][A-Z0-9_]*$' } }
        @{ Key = 'Agent.EnvNames.InternalApiToken'; Expect = 'an environment variable name'; Test = { param($v) $v -is [string] -and $v -match '^[A-Z_][A-Z0-9_]*$' } }
        @{ Key = 'Agent.EnvNames.AgentUrl'; Expect = 'an environment variable name'; Test = { param($v) $v -is [string] -and $v -match '^[A-Z_][A-Z0-9_]*$' } }
        @{ Key = 'Agent.EnvFile'; Expect = 'an absolute Linux path to a file'; Test = { param($v) $v -is [string] -and $v -match '^(/[A-Za-z0-9._-]+)+$' } }
        @{ Key = 'Agent.SecretNames.RabbitMqUrl'; Expect = 'a secret name (letters, digits, . _ -)'; Test = { param($v) $v -is [string] -and $v -match '^[A-Za-z0-9._-]+$' } }
        @{ Key = 'Agent.SecretNames.InternalApiToken'; Expect = 'a secret name (letters, digits, . _ -)'; Test = { param($v) $v -is [string] -and $v -match '^[A-Za-z0-9._-]+$' } }
        @{ Key = 'Docker.Package'; Expect = 'a Debian package name'; Test = { param($v) $v -is [string] -and $v -match '^[a-z0-9][a-z0-9.+-]+$' } }
        @{ Key = 'Docker.AptLockTimeoutSeconds'; Expect = 'a whole number 0-3600'; Test = { param($v) $v -is [int] -and $v -ge 0 -and $v -le 3600 } }
        @{ Key = 'Broker.Host'; Expect = 'a host name or IP address'; Test = { param($v) $v -is [string] -and $v -match '^([A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?|[0-9A-Fa-f]*:[0-9A-Fa-f:]*)$' } }
        @{ Key = 'Broker.Port'; Expect = 'a port number 1-65535'; Test = { param($v) $v -is [int] -and $v -ge 1 -and $v -le 65535 } }
        @{ Key = 'Ssh.ConnectTimeoutSeconds'; Expect = 'a whole number 1-300'; Test = { param($v) $v -is [int] -and $v -ge 1 -and $v -le 300 } }
        @{ Key = 'Ssh.KnownHostsFile'; Expect = "a file path or ''"; Test = { param($v) $v -is [string] } }
        @{ Key = 'Preflight.MinDiskFreeMB'; Expect = 'a whole number 0-1000000'; Test = { param($v) $v -is [int] -and $v -ge 0 -and $v -le 1000000 } }
        @{ Key = 'Preflight.SupportedOs'; Expect = "a list of OS ids, e.g. @('ubuntu')"; Test = { param($v) @($v).Count -ge 1 -and @($v | Where-Object { $_ -isnot [string] -or $_ -notmatch '^[a-z0-9._-]+$' }).Count -eq 0 } }
        @{ Key = 'Preflight.ThrottleLimit'; Expect = 'a whole number 1-256'; Test = { param($v) $v -is [int] -and $v -ge 1 -and $v -le 256 } }
        @{ Key = 'Install.ThrottleLimit'; Expect = 'a whole number 1-256'; Test = { param($v) $v -is [int] -and $v -ge 1 -and $v -le 256 } }
        @{ Key = 'Health.DegradedAfterSeconds'; Expect = 'a whole number 1-300'; Test = { param($v) $v -is [int] -and $v -ge 1 -and $v -le 300 } }
        @{ Key = 'Health.OfflineAfterSeconds'; Expect = 'a whole number 1-300'; Test = { param($v) $v -is [int] -and $v -ge 1 -and $v -le 300 } }
        @{ Key = 'Health.VerifyTimeoutSeconds'; Expect = 'a whole number 1-3600'; Test = { param($v) $v -is [int] -and $v -ge 1 -and $v -le 3600 } }
        @{ Key = 'Health.PollIntervalSeconds'; Expect = 'a whole number 1-60'; Test = { param($v) $v -is [int] -and $v -ge 1 -and $v -le 60 } }
    )

    $problems = [System.Collections.Generic.List[string]]::new()
    foreach ($rule in $rules) {
        # Walk the dotted key: 'Agent.EnvNames.NodeId' -> $config['Agent']['EnvNames']['NodeId'].
        $value = $config
        foreach ($part in $rule.Key.Split('.')) {
            $value = if ($value -is [hashtable]) { $value[$part] } else { $null }
        }

        if ($null -eq $value) {
            $problems.Add("$($rule.Key) is missing")
        }
        elseif (-not (& $rule.Test $value)) {
            $problems.Add("$($rule.Key) must be $($rule.Expect), but is '$value'")
        }
    }

    # Rules that compare two values. Only checked when both values passed their own rule.
    $health = $config.Health
    if ($health.DegradedAfterSeconds -is [int] -and $health.OfflineAfterSeconds -is [int] -and
        $health.OfflineAfterSeconds -le $health.DegradedAfterSeconds) {
        $problems.Add('Health.OfflineAfterSeconds must be greater than Health.DegradedAfterSeconds')
    }

    if ($problems.Count -gt 0) {
        throw "NexusFleet config is not valid (read from: $($filesRead -join ', ')):`n- " + ($problems -join "`n- ")
    }

    $config
}
