# The inventory

The inventory is the list of hosts NexusFleet works on: a JSON file, read and checked by `Import-NexusInventory`.
Keep your own in `config/inventory.json` (git-ignored). [config/inventory.example.json](../config/inventory.example.json)
shows the format.

```json
{
  "defaults": { "user": "fleet", "port": 22, "location": "home", "keyFile": "C:/Users/you/.ssh/nexusfleet" },
  "hosts": [
    { "name": "node-home01", "address": "192.168.1.20" },
    { "name": "node-home02", "address": "192.168.1.21", "role": "storage" },
    { "name": "node-vps01",  "address": "203.0.113.10", "port": 2222, "location": "vps",
      "agentUrl": "http://10.8.0.10:9100" },
    { "name": "node-laptop01", "address": "127.0.0.1", "port": 2222, "location": "laptop", "reach": "outbound" }
  ]
}
```

## Fields

`defaults` is optional. A field a host does not set is taken from `defaults`.

| Field | Required | Rule | Meaning |
|---|---|---|---|
| `name` | yes | lowercase letters, digits and `-`, starting with a letter, at most 63 characters | The node id in NexusInfra (`NODE_ID`). Also used for log file names, so it must be safe as a file name and a DNS label. |
| `address` | yes | host name, IPv4 or IPv6 address | Where to reach the host over SSH. |
| `port` | no, default `22` | 1-65535 | The SSH port. |
| `user` | yes | a Linux user name | The SSH user. It must be able to use `sudo` without a password. |
| `location` | yes | text | Shown in NexusInfra (for example `home`, `vps`, `office`). |
| `role` | no | text | A free label for your own grouping. |
| `keyFile` | no | a path | The SSH private key for this host. Without it, ssh uses its default keys and the ssh agent. |
| `reach` | no, default `direct` | `direct` or `outbound` | How the control plane reaches this host's agent. `direct`: the orchestrator calls the agent on `agentUrl`, so the host needs an address the control plane can reach and port 9100 open. `outbound`: the agent connects to the control plane itself over the agent link, so the host needs **no open port** at all; use it for a host behind NAT (a laptop on Wi-Fi, a home server, 4G). Needs a NexusInfra with the agent link; see [agent-link.md](agent-link.md). |
| `agentUrl` | no, default `http://<address>:<Agent.Port>`; not allowed with `reach: outbound` | http(s) URL | The address **the orchestrator** uses to reach this host's agent. Set it when the orchestrator reaches the host on another address than you do, for example over a private network. |

## Checks

`Import-NexusInventory` reads the whole file and reports every problem in one error, each with the host it belongs
to, so a broken file is fixed in one go:

```text
Inventory './config/inventory.json' is not valid:
- host 2 (node-home02): address 'my host' is not a host name, IPv4 or IPv6 address
- host 3 (node-vps01): port '70000' must be a whole number 1-65535
- host 4: name is missing
```

It also refuses two hosts with the same name, and two hosts with the same address and port. A field it does not know
gives a warning, since it is probably a typo (`adress`), and the import continues.

Nothing is contacted: the file is only read and checked. The result is one `NexusFleet.Host` object per host, in the
order of the file, ready for `Test-NexusHost`, `Install-NexusNode` and `Get-NexusFleetStatus`.

## Tips

- Use the same `name` as the host name of the machine. That makes logs and the panel easy to match.
- Put the key in `defaults`, and override it only for hosts that need another one.
- To show the third "Klaar als" criterion in a demo, add a host on a port where nothing listens. It fails on its
  own, and the others finish.
