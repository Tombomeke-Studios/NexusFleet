# Step 30: the NexusInfra node agent as a container (docs/images.md, "Adding a machine" in NexusInfra).
# Three options fail silently when they are forgotten: the restart policy, the port publication and the backups
# volume. Test checks each of them on the running container, so a container made by hand without them is fixed.
# A host with reach "outbound" (docs/agent-link.md) publishes no port at all: its agent connects to the control
# plane over the agent link (AGENT_LINK_URL, with a link token minted for this node), so nothing on it is open.
Register-NexusStep -Name 'AgentContainer' -Order 30 -Description 'Node agent container running with the right settings' -Test {
    param($Context)
    # The Test never sees the secrets, so a changed RABBITMQ_URL or INTERNAL_API_TOKEN looks "in order".
    # Install-NexusNode -Force recreates the container to apply it.
    if ($Context.Force) {
        return $false
    }
    $agent = $Context.Config.Agent
    $hostInfo = $Context.HostInfo
    $outbound = $hostInfo.Reach -eq 'outbound'
    $name = ConvertTo-NexusShellArgument -Value $agent.ContainerName

    # Prints key=value lines about the container. Of the environment only NODE_ID, AGENT_URL and AGENT_LINK_URL:
    # the secrets (RABBITMQ_URL, INTERNAL_API_TOKEN, AGENT_LINK_TOKEN) never leave the host.
    $script = @'
c={Name}
if ! sudo -n docker inspect "$c" >/dev/null 2>&1; then echo "exists=no"; exit 0; fi
echo "exists=yes"
sudo -n docker inspect --format 'image={{.Config.Image}}
running={{.State.Running}}
restart={{.HostConfig.RestartPolicy.Name}}
{{range $p, $b := .HostConfig.PortBindings}}{{range $b}}port={{.HostPort}}->{{$p}}
{{end}}{{end}}{{range .Mounts}}mount={{if .Name}}{{.Name}}{{else}}{{.Source}}{{end}}:{{.Destination}}
{{end}}{{range .HostConfig.ExtraHosts}}host={{.}}
{{end}}' "$c"
sudo -n docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$c" | grep -E '^({NodeIdName}|{AgentUrlName}|{LinkUrlName})=' | sed 's/^/env=/'
'@
    $script = $script.Replace('{Name}', $name).Replace('{NodeIdName}', $agent.EnvNames.NodeId).
    Replace('{AgentUrlName}', $agent.EnvNames.AgentUrl).Replace('{LinkUrlName}', $agent.EnvNames.LinkUrl)
    $answer = Invoke-NexusStepCommand -Context $Context -Purpose 'inspect the agent container' -Command $script -AllowFailure

    # Every key can appear more than once (ports, mounts, ...), so every key holds a list.
    $facts = @{}
    foreach ($line in $answer.StdOut -split "`n") {
        $key, $value = $line -split '=', 2
        if ($key) {
            $facts[$key.Trim()] += @("$value".Trim())
        }
    }

    $wanted = [ordered]@{
        'the container exists'                        = $facts.exists -contains 'yes'
        'it is running'                               = $facts.running -contains 'true'
        "the image is $($agent.Image)"                = $facts.image -contains $agent.Image
        "restart policy $($agent.RestartPolicy)"      = $facts.restart -contains $agent.RestartPolicy
        "volume $($agent.BackupVolume) is mounted"    = $facts.mount -contains "$($agent.BackupVolume):$($agent.BackupMountPath)"
        'the Docker socket is mounted'                = $facts.mount -contains "$($agent.DockerSocket):$($agent.DockerSocket)"
        "host mapping $($agent.HostGateway)"          = $facts.host -contains $agent.HostGateway
        "$($agent.EnvNames.NodeId)=$($hostInfo.Name)" = $facts.env -contains "$($agent.EnvNames.NodeId)=$($hostInfo.Name)"
    }
    if ($outbound) {
        # Nothing may be open on an outbound host: the agent connects to the control plane itself.
        $wanted['no port is published'] = -not $facts.port
        $linkEnv = "$($agent.EnvNames.LinkUrl)=$($Context.LinkUrl)"
        $wanted[$linkEnv] = $facts.env -contains $linkEnv
    }
    else {
        $wanted["port $($agent.Port) is published"] = $facts.port -contains "$($agent.Port)->$($agent.Port)/tcp"
        $urlEnv = "$($agent.EnvNames.AgentUrl)=$($hostInfo.AgentUrl)"
        $wanted[$urlEnv] = $facts.env -contains $urlEnv
    }
    $missing = @($wanted.Keys | Where-Object { -not $wanted[$_] })
    if ($missing.Count -gt 0 -and $facts.exists -contains 'yes' -and $Context.RunContext) {
        Write-NexusLog -Context $Context.RunContext -HostName $hostInfo.Name -Step 'AgentContainer' -Level Warning `
            -Message "the existing agent container is not as it should be: $($missing -join '; ')"
    }
    $missing.Count -eq 0
} -Apply {
    param($Context)
    $agent = $Context.Config.Agent
    $hostInfo = $Context.HostInfo
    if (-not $Context.Secrets) {
        throw 'the agent needs RABBITMQ_URL and INTERNAL_API_TOKEN, and none were given'
    }
    $outbound = $hostInfo.Reach -eq 'outbound'
    # ws:// is the link without TLS: the link token and every call to the agent would cross the network readable.
    $insecureLink = $outbound -and $Context.LinkUrl -like 'ws://*'
    if ($insecureLink -and -not $Context.Config.Api.AllowUnencryptedHttp) {
        throw "the agent link $($Context.LinkUrl) is ws://, so not encrypted. Put TLS in front of the gateway (wss://), " +
        'or set Api.AllowUnencryptedHttp in a lab (the same switch that allows the API token over http://).'
    }
    $q = { param($Value) ConvertTo-NexusShellArgument -Value "$Value" }
    $envFile = & $q $agent.EnvFile
    # The folder of the env file. Not Split-Path: on Windows that would turn the Linux path into C:\-style.
    $envDir = & $q $agent.EnvFile.Substring(0, $agent.EnvFile.LastIndexOf('/'))
    $name = & $q $agent.ContainerName
    $image = & $q $agent.Image

    # The two secrets arrive on stdin (one line each) and go straight into the env file (mode 600, root only).
    # docker run reads them from there: they never appear on a command line, so not in 'ps' on the host either.
    # A failed pull is fine when the image is already on the host (offline, or a lab image). The old container is
    # replaced; the backups volume is kept, so no backup is lost.
    # How the control plane reaches this agent. Direct: on its own address, so the port is published and AGENT_URL
    # says where. Outbound: the agent dials the link with a token minted for this node, which arrives as a third
    # line on stdin; no port is published.
    $secrets = @($Context.Secrets.RabbitMqUrl, $Context.Secrets.InternalApiToken)
    if ($outbound) {
        $minted = Invoke-NexusStepApi -Context $Context -Method POST -Path "/nodes/$($hostInfo.Name)/link-token"
        $secrets += [System.Net.NetworkCredential]::new('', $minted.token).SecurePassword
        if ($Context.RunContext) {
            # The log hides it too, should it ever appear in a message.
            $Context.RunContext.Secrets = @(@($Context.RunContext.Secrets) + $minted.token | Sort-Object -Property Length -Descending)
        }
        $readLink = 'IFS= read -r link_token'
        $reachEnv = "$(& $q $agent.EnvNames.LinkUrl) $(& $q $Context.LinkUrl) $(& $q $agent.EnvNames.LinkToken) " + '"$link_token"'
        if ($insecureLink) {
            $reachEnv += " $(& $q $agent.EnvNames.LinkInsecure) 'true'"
        }
        $publish = ''
    }
    else {
        $readLink = ''
        $reachEnv = "$(& $q $agent.EnvNames.AgentUrl) $(& $q $hostInfo.AgentUrl)"
        $publish = "-p $($agent.Port):$($agent.Port)"
    }

    $script = @"
set -eu
IFS= read -r rabbitmq_url
IFS= read -r internal_token
$readLink
sudo -n install -d -m 700 $envDir
printf '%s=%s\n' $(& $q $agent.EnvNames.NodeId) $(& $q $hostInfo.Name) \
    $(& $q $agent.EnvNames.RabbitMqUrl) "`$rabbitmq_url" \
    $(& $q $agent.EnvNames.InternalApiToken) "`$internal_token" \
    $reachEnv | sudo -n tee $envFile >/dev/null
sudo -n chmod 600 $envFile
sudo -n docker pull -q $image >/dev/null || sudo -n docker image inspect $image >/dev/null
sudo -n docker rm -f $name >/dev/null 2>&1 || true
sudo -n docker run -d --name $name \
    --restart $(& $q $agent.RestartPolicy) \
    --env-file $envFile $publish \
    -v $(& $q "$($agent.DockerSocket):$($agent.DockerSocket)") \
    -v $(& $q "$($agent.BackupVolume):$($agent.BackupMountPath)") \
    --add-host=$(& $q $agent.HostGateway) \
    $image >/dev/null
"@
    # For VerifyHealthy: a new agent started in this run, so the node's health must come from its heartbeats.
    $Context.State.AgentStarted = $true
    $null = Invoke-NexusStepCommand -Context $Context -Purpose 'start the agent container' -Command $script -Secret $secrets
} -Rollback {
    param($Context)
    $agent = $Context.Config.Agent
    # The container and its env file (it holds the secrets). Never the backups volume: that is data.
    $name = ConvertTo-NexusShellArgument -Value $agent.ContainerName
    $envFile = ConvertTo-NexusShellArgument -Value $agent.EnvFile
    $null = Invoke-NexusStepCommand -Context $Context -Purpose 'remove the agent container' `
        -Command "sudo -n docker rm -f $name >/dev/null 2>&1 || true; sudo -n rm -f $envFile"
}
