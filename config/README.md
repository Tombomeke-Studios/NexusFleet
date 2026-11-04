# config — every NexusInfra-specific value, and an example inventory

Nothing in this folder is secret, and no function in `src/` hard-codes a value that belongs here.

| File | What it is | In git |
|---|---|---|
| `nexusinfra.psd1` | The default configuration: the panel (`Api`), the node agent (`Agent`), `Docker`, the `Broker` as the hosts reach it, `Ssh`, `Preflight`, `Install`, `Health` and `Log`. Checked against NexusInfra's own docs | yes |
| `nexusinfra.local.psd1` | **Your** overrides: only the keys you change, in the same structure | no (git-ignored) |
| `inventory.example.json` | The format of an inventory, with `defaults` and `hosts` | yes |
| `inventory.json` | **Your** list of hosts | no (git-ignored) |

## Your own settings

Create `nexusinfra.local.psd1` with only what differs:

```powershell
@{
    Api    = @{ BaseUrl = 'https://panel.example.com' }
    Broker = @{ Host = '10.0.0.2' }
    Log    = @{ Directory = '~/nexusfleet/logs' }
}
```

Every value is checked when it is read. A wrong value stops the run with a list of every problem, and an unknown key
gives a warning (usually a typo).

- Every key, its default, its rule and its meaning: [docs/configuration.md](../docs/configuration.md).
- The inventory format: [docs/inventory.md](../docs/inventory.md).

## Secrets do not go here

The API token, the broker URL (it holds the broker's password) and NexusInfra's `INTERNAL_API_TOKEN` are stored with
SecretManagement, or passed as parameters. Git-ignoring a file is not secret storage. See
[docs/security.md](../docs/security.md).
