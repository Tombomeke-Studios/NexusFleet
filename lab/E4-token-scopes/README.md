# E4 — API token scopes (source analysis)

Read in the local NexusInfra clone, branch `dev` (tag `nexusfleet-baseline` present), on 2 November 2026.
Nothing in NexusInfra was changed.

## Where the checks are

| File | What it does |
|---|---|
| `services/orchestrator/src/apiTokens.ts` | `API_SCOPES = ['write', 'admin']`; `scopeAllowsMethod`: GET/HEAD/OPTIONS always, other methods need `write`; `scopeAllowsAdmin`: needs `admin` |
| `services/orchestrator/src/auth.ts` | `requireAuth` applies `scopeAllowsMethod` to every request made with a token; `requirePlatformAdmin`: account `platformRole` must be `admin` or `owner`, and a token must also have `admin` |
| `services/orchestrator/src/api.ts` | `GET /nodes` has no extra guard; `POST /nodes`, `PATCH /nodes/:id/maintenance`, `DELETE /nodes/:id` use `requirePlatformAdmin` |
| `services/orchestrator/src/auth.ts` | `GET /me` returns `toPublicUser` (includes `platformRole`, not the token's scopes); `GET /users` is behind `requirePlatformAdmin` |

## NexusInfra's own tests that back this up

- `api.test.ts`: a non-admin gets `403` on `POST /nodes` and `DELETE /nodes/:id`; `DELETE` answers `409` while a
  deployment runs on the node.
- `auth.test.ts`: "does not administer the panel without the admin scope" (`GET /users`: `403` with `write`,
  `200` with `write` + `admin`); a token cannot mint another token.

## Still to do

Confirm against a running control plane in the real lab (E0, issue #14): mint tokens with `write` and with
`write admin`, call the three routes, note the status codes.
