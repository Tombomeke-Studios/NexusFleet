function Import-NexusInventory {
    <#
    .SYNOPSIS
    Reads a JSON inventory of target hosts, checks every field and returns one NexusFleet.Host object per host.

    .DESCRIPTION
    The inventory is a JSON file with an optional "defaults" object and a "hosts" list. A field missing on a host
    is taken from "defaults". Fields per host:
      name      the node id in NexusInfra (required): lowercase letters, digits and dashes, starting with a letter,
                at most 63 characters (a NexusFleet rule: safe as NODE_ID, file name and DNS name)
      address   host name, IPv4 or IPv6 address to reach the host over SSH (required)
      port      SSH port (default 22)
      user      SSH user that may use sudo (required)
      location  where the node is, shown in NexusInfra (required)
      role      free label, e.g. "worker" (optional)
      keyFile   SSH private key for this host (optional; otherwise ssh's default)
      agentUrl  the address the orchestrator uses to reach the agent
                (default http://<address>:<Agent.Port from the config>)

    Every problem in the file is reported in one error, with the host it belongs to, so a broken inventory can be
    fixed in one go. Duplicate names and duplicate address:port pairs are refused. An unknown field (probably a
    typo) gives a warning. The output objects go straight into Test-NexusHost and Install-NexusNode.

    .PARAMETER Path
    The inventory file. Accepts pipeline input.

    .EXAMPLE
    Import-NexusInventory -Path ./config/inventory.json

    Reads and checks the inventory and shows the hosts.

    .EXAMPLE
    Import-NexusInventory -Path ./config/inventory.json | Format-Table Name, Address, Port, User, Location

    .EXAMPLE
    Get-Content ./config/inventory.example.json

    Shows the format: { "defaults": { "user": "fleet", "location": "home" }, "hosts": [ { "name": "node-web01", "address": "10.0.0.5" } ] }

    .OUTPUTS
    NexusFleet.Host: Name, Address, Port, User, Location, Role, KeyFile, AgentUrl.
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
        $run = Initialize-NexusRunContext

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
        $knownFields = 'name', 'address', 'port', 'user', 'location', 'role', 'keyFile', 'agentUrl'
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

            $agentUrl = if ($value.agentUrl) { $value.agentUrl } else { "http://$($value.address):$($config.Agent.Port)" }
            $hosts.Add([pscustomobject]@{
                    PSTypeName = 'NexusFleet.Host'
                    Name       = $value.name
                    Address    = $value.address
                    Port       = [int]$value.port
                    User       = $value.user
                    Location   = $value.location
                    Role       = $value.role
                    KeyFile    = $value.keyFile
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
