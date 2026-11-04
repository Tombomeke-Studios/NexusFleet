# src/api — the NexusInfra REST API

`Invoke-NexusApi.ps1` is the **only** place in NexusFleet that talks to the NexusInfra API. Every other function goes
through it.

## What it does

- **The token:** sends the API token (`nxi_...`) as a bearer token, kept as a `SecureString`.
- **Time-out:** gives up after `Api.TimeoutSeconds`.
- **Retries:** repeats only `GET` requests, after a network error or a `502`, `503` or `504`, with a doubling pause.
  A changing request is never sent twice.
- **Plain `http://`:** the token goes over `http://` only to this machine (loopback). For any other machine you must
  set `Api.AllowUnencryptedHttp`, and every request then gives a warning ([docs/security.md](../../docs/security.md)).
- **Errors:** every failure becomes an error with its own id:

| Error id | When |
|---|---|
| `NexusApi.Unauthorized` | `401`: the token is wrong, expired or revoked |
| `NexusApi.Forbidden` | `403`: the token lacks a scope |
| `NexusApi.NotFound` | `404`, which is also how NexusInfra answers when you may not see something |
| `NexusApi.Conflict` | `409`, for example a node that still hosts a deployment |
| `NexusApi.Unavailable` | `502`, `503` or `504`, after the retries |
| `NexusApi.HttpError` | any other HTTP error |
| `NexusApi.Unreachable` | no answer at all |
| `NexusApi.RequestFailed` | anything else |
| `NexusApi.UnencryptedNotAllowed` | the token would go over `http://` to another machine |

Tests: [`tests/api/`](../../tests/api/README.md), with mocks and against a real local HTTP server.
