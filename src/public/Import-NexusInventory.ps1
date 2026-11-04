function Import-NexusInventory {
    <#
    .SYNOPSIS
    Reads a JSON inventory of target hosts, checks every field and returns one NexusFleet.Host object per host.

    .DESCRIPTION
    The inventory is the list of machines NexusFleet works on. It is a JSON file with an optional "defaults" object
    and a "hosts" list; a field a host does not set is taken from "defaults". The fields of a host:

      name      the node id in NexusInfra (required): lowercase letters, digits and dashes, starting with a letter,
                at most 63 characters, so it is safe as NODE_ID, as a file name and as a DNS name
      address   host name, IPv4 or IPv6 address to reach the host over SSH (required)
      port      SSH port (default 22)
      user      SSH user that may use sudo without a password (required)
      location  where the node is, shown in NexusInfra (required)
      role      a free label, e.g. "worker" (optional)
      keyFile   SSH private key for this host (optional; otherwise ssh's default keys and agent)
      reach     how the control plane reaches this host's agent: "direct" (default) calls the agent on its
                agentUrl; "outbound" means the agent connects to the control plane itself, for a host behind NAT
                (needs a NexusInfra with the agent link, see docs/agent-link.md)
      agentUrl  the address the orchestrator uses to reach this host's agent, only for reach "direct"
                (default http://<address>:<Agent.Port from the config>)

    Every problem in the file is reported in one error, each with the host it belongs to ("host 3 (node-vps01):
    port must be 1-65535"), so a broken inventory is fixed in one go. Duplicate names and duplicate address:port
    pairs are refused. An unknown field, probably a typo, gives a warning. Nothing is contacted: this only reads and
    checks the file. The objects go straight into Test-NexusHost, Install-NexusNode and Get-NexusFleetStatus.

    .PARAMETER Path
    The inventory file (JSON). Several files can come in through the pipeline; each is read and checked on its own.

    .EXAMPLE
    Import-NexusInventory -Path ./config/inventory.json

    Reads and checks the inventory and shows the hosts.

    .EXAMPLE
    Import-NexusInventory -Path ./config/inventory.json | Format-Table Name, Address, Port, User, Location

    Shows the hosts as a table, to check what NexusFleet will work on.

    .EXAMPLE
    Import-NexusInventory -Path ./config/inventory.json | Test-NexusHost

    Reads the inventory and checks every host (the usual first step).

    .INPUTS
    System.String
    The path of an inventory file.

    .OUTPUTS
    NexusFleet.Host
    Name, Address, Port, User, Location, Role, KeyFile, Reach, AgentUrl (empty for an outbound host): one object per host, in the order of the file.

    .NOTES
    Error ids: NexusFleet.InventoryNotFound (no such file) and NexusFleet.InventoryInvalid (broken JSON, or every
    problem found, in one message). The format is described in docs/inventory.md; config/inventory.example.json is
    an example. Keep your own inventory in config/inventory.json: that file is git-ignored.

    .LINK
    https://github.com/Tombomeke-Studios/NexusFleet/blob/dev/docs/inventory.md

    .LINK
    about_NexusFleet

    .LINK
    Test-NexusHost

    .LINK
    Install-NexusNode
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    process {
        if (-not (Test-Path -Path $Path -PathType Leaf)) {
            $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                    [System.IO.FileNotFoundException]::new("Inventory file not found: '$Path'."), 'NexusFleet.InventoryNotFound', 'ObjectNotFound', $Path))
        }
        $config = Get-NexusConfig
        $run = Initialize-NexusRunContext -LogRoot $config.Log.Directory -KeepRuns $config.Log.KeepRuns

        try {
            $inventory = Get-Content -Path $Path -Raw | ConvertFrom-Json -AsHashtable -ErrorAction Stop
        }
        catch {
            $message = "Inventory '$Path' is not valid JSON: $($_.Exception.Message)"
            Write-NexusLog -Context $run -Level Error -Message $message
            $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                    [System.InvalidOperationException]::new($message), 'NexusFleet.InventoryInvalid', 'InvalidData', $Path))
        }

        $defaults = if ($inventory.defaults -is [hashtable]) { $inventory.defaults } else { @{} }
        $entries = @($inventory.hosts)
        $knownFields = 'name', 'address', 'port', 'user', 'location', 'role', 'keyFile', 'reach', 'agentUrl'
        $problems = [System.Collections.Generic.List[string]]::new()
        $hosts = [System.Collections.Generic.List[object]]::new()

        if ($entries.Count -eq 0 -or $null -eq $entries[0]) {
            $problems.Add('the inventory has no hosts (expected a "hosts" list)')
        }

        for ($i = 0; $i -lt $entries.Count -and $null -ne $entries[0]; $i++) {
            $entry = $entries[$i]
            # The host's name if it has a usable one, else its position (1-based).
            $label = if ($entry.name -is [string] -and $entry.name) { "host $($i + 1) ($($entry.name))" } else { "host $($i + 1)" }

            foreach ($field in $entry.Keys | Where-Object { $_ -notin $knownFields }) {
                Write-Warning "Inventory ${label}: unknown field '$field' (check the spelling); it is ignored."
            }

            # A value on the host wins; otherwise the default.
            $value = @{}
            foreach ($field in $knownFields) {
                $value[$field] = if ($entry.ContainsKey($field)) { $entry[$field] } else { $defaults[$field] }
            }
            if ($null -eq $value.port) { $value.port = 22 }
            if ($null -eq $value.reach) { $value.reach = 'direct' }

            foreach ($required in 'name', 'address', 'user', 'location') {
                if ([string]::IsNullOrWhiteSpace([string]$value[$required])) {
                    $problems.Add("${label}: $required is missing")
                }
            }
            if ($value.name -and $value.name -notmatch '^[a-z][a-z0-9-]{0,62}$') {
                $problems.Add("${label}: name '$($value.name)' must be lowercase letters, digits and dashes, starting with a letter (max 63)")
            }
            # Same rule as Invoke-NexusHostCommand: not starting with a dash, so it can never become an ssh option.
            if ($value.address -and $value.address -notmatch '^([A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?|[0-9A-Fa-f]*:[0-9A-Fa-f:]*)$') {
                $problems.Add("${label}: address '$($value.address)' is not a host name, IPv4 or IPv6 address")
            }
            if (-not ($value.port -is [long] -or $value.port -is [int]) -or $value.port -lt 1 -or $value.port -gt 65535) {
                $problems.Add("${label}: port '$($value.port)' must be a whole number 1-65535")
            }
            if ($value.user -and $value.user -notmatch '^[a-z_][a-z0-9_-]{0,31}$') {
                $problems.Add("${label}: user '$($value.user)' is not a Linux user name")
            }
            if ($value.agentUrl -and $value.agentUrl -notmatch '^https?://\S+$') {
                $problems.Add("${label}: agentUrl '$($value.agentUrl)' must be an http(s) URL")
            }
            if ($value.reach -notin 'direct', 'outbound') {
                $problems.Add("${label}: reach '$($value.reach)' must be direct or outbound")
            }
            if ($value.reach -eq 'outbound' -and $entry.ContainsKey('agentUrl')) {
                $problems.Add("${label}: agentUrl is never used for a host with reach outbound (its agent connects to the control plane); remove it")
            }

            # An outbound agent is never called on an address of its own, so it has no agent URL.
            $agentUrl = if ($value.reach -eq 'outbound') { $null }
            elseif ($value.agentUrl) { $value.agentUrl }
            else { "http://$($value.address):$($config.Agent.Port)" }
            $hosts.Add([pscustomobject]@{
                    PSTypeName = 'NexusFleet.Host'
                    Name       = $value.name
                    Address    = $value.address
                    Port       = [int]$value.port
                    User       = $value.user
                    Location   = $value.location
                    Role       = $value.role
                    KeyFile    = $value.keyFile
                    Reach      = $value.reach
                    AgentUrl   = $agentUrl
                })
        }

        # Duplicates: two hosts with the same node name, or the same machine twice.
        foreach ($group in $hosts | Where-Object Name | Group-Object -Property Name | Where-Object Count -GT 1) {
            $problems.Add("name '$($group.Name)' is used more than once")
        }
        foreach ($group in $hosts | Where-Object Address | Group-Object -Property { "$($_.Address):$($_.Port)" } | Where-Object Count -GT 1) {
            $problems.Add("$($group.Name) is listed more than once")
        }

        if ($problems.Count -gt 0) {
            $message = "Inventory '$Path' is not valid:`n- " + ($problems -join "`n- ")
            Write-NexusLog -Context $run -Level Error -Message $message
            $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                    [System.InvalidOperationException]::new($message), 'NexusFleet.InventoryInvalid', 'InvalidData', $Path))
        }

        Write-NexusLog -Context $run -Message "Imported $($hosts.Count) host(s) from $Path"
        # One object at a time into the pipeline, so Test-NexusHost can start on the first host right away.
        foreach ($nexusHost in $hosts) {
            $nexusHost
        }
    }
}
