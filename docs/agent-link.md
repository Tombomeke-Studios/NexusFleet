# Design: the agent link (agents that connect outbound)

Status: **agreed with Tom on 2026-11-04**; built in two repositories at the same time.
Why: [ontwerpkeuzes.md K11](ontwerpkeuzes.md#k11--nodes-achter-nat-de-agent-verbindt-zelf-105). Issues: NexusFleet #105, NexusInfra
#416.

## The problem

A NexusInfra node has two connections, in opposite directions:

| Direction | What | Today |
|---|---|---|
| node → control plane | heartbeats and events, to the broker | outbound from the node: works from anywhere |
| control plane → node | files, exec, the console, logs, backups, databases, `/disk` (`agentFetch` and the terminal proxy in the orchestrator) | the orchestrator **calls the agent** on its `agentUrl`, plain HTTP, port 9100 |

The second direction only works when the node has an address the orchestrator can reach. A node behind NAT
(a laptop on school Wi-Fi, a home server, a 4G or CGNAT connection) has none, so it becomes *healthy* but cannot
be used. The same hop also carries the shared `INTERNAL_API_TOKEN` in clear text over the internet.

## The decision

Each host gets a **reach**: how the control plane reaches its agent.

| `reach` | Meaning | Who provides the path |
|---|---|---|
| `direct` | The control plane calls the agent on an address of the node itself (`agentUrl`). The node needs an inbound port | Nobody: the network already does (public address, port forwarding) |
| `outbound` | The agent opens one connection to the control plane and the control plane's calls come back over it. The node needs **no inbound port** | The platform itself (NexusInfra, this design) |
| `tunnel` | NexusFleet opens an SSH reverse tunnel from the node, for a platform whose agent can only be called | NexusFleet; **later**, with the connectors extra, not in this design |

`direct` and `tunnel` both serve a platform that calls its node; the difference is who makes the node
reachable. `outbound` is for a platform whose agent can dial out itself, which NexusInfra gets here.

## The link (NexusInfra)

### Connection

- The agent dials `AGENT_LINK_URL`, e.g. `wss://nexus.example.com/agent-link`: through the gateway, so the same
  public name and port (443 behind TLS) as the panel. Only `wss://` is allowed, unless the host is loopback or
  `AGENT_LINK_ALLOW_INSECURE=true` (labs).
- Handshake headers: `x-nexus-node-id: <NODE_ID>` and `authorization: Bearer <AGENT_LINK_TOKEN>`.
- The gateway routes `/agent-link` to the orchestrator as a public route (no user JWT; the orchestrator
  checks the link token). The gateway's rate limit by address still applies.
- The orchestrator accepts the upgrade only when the token matches the **hash stored for that node id**
  (constant-time compare). One link per node: a new link replaces the old one.
- The agent reconnects with a doubling delay (1 s up to 30 s). Both sides ping every 15 s and drop the link
  after 45 s of silence.

### Per-node credential

- `POST /nodes/:id/link-token` (platform admin, scope `write`) mints a new random link token for that node,
  stores only its hash, returns `{ token }` once, and closes the node's current link. Calling it again rotates.
- A leaked token gives access to one node's link, never to another node's: the orchestrator binds the link to the
  node id the token was minted for. This is why the shared `INTERNAL_API_TOKEN` cannot be the link credential:
  with it, one node could open a link as another node and receive that node's file and exec traffic.

### Framing

The link carries **byte streams**, not API calls, so HTTP, server-sent events (live logs and stats) and the
terminal WebSocket all pass unchanged. Binary WebSocket messages:

```
[type: u8][streamId: u32 big-endian][payload]
type 1 OPEN   orchestrator → agent, empty payload
type 2 DATA   both ways, raw bytes
type 3 END    both ways, the sender will write no more
type 4 RESET  both ways, the stream failed; payload = short UTF-8 reason
```

- The orchestrator opens a stream per request. The agent answers an OPEN by connecting to its own HTTP server
  on `127.0.0.1:<PORT>` and piping the bytes both ways; it opens nothing else.
- On the orchestrator side a stream is a Node.js `Duplex`. `agentFetch` and the terminal proxy keep building the
  same requests; only the connection under them differs (an undici `Agent` with a `connect` function, and
  `createConnection` for `ws`). The `INTERNAL_API_TOKEN` header is still sent, so the agent's own checks are
  unchanged.
- Backpressure: a sender stops reading its source while the WebSocket's `bufferedAmount` is above 1 MiB.

### What changes in the node record

- `POST /nodes` accepts `connection: "direct" | "outbound"` (default `direct`). With `outbound`, `agentUrl` is
  not required and is ignored.
- `GET /nodes` returns `connection`, and for outbound nodes `linked: true | false` (a link is up right now).
- A call to an outbound node without a link answers like an unreachable agent today: `502`, with the reason
  `node has no agent link`. So `GET /nodes/:id/disk` keeps meaning "NexusInfra can control this node".
- `GET /config` lists `features: ["agent-link"]`, so a client can tell whether the control plane supports it.

### What changes in the agent

- New environment: `AGENT_LINK_URL`, `AGENT_LINK_TOKEN`, optional `AGENT_LINK_ALLOW_INSECURE`. When
  `AGENT_LINK_URL` is set the agent opens the link; its heartbeat reports `connection: "outbound"` and no
  `agentUrl`. Without it, everything works as before.
- The HTTP server and the broker connection are unchanged. Port 9100 is simply not published by the installer.

## NexusFleet

| Part | Change |
|---|---|
| Inventory | `reach`: `direct` (default) or `outbound`, in `defaults` or per host. `agentUrl` is required only for `direct` |
| Config | `Agent.Link.Path` (`/agent-link`), `Agent.Link.Url` (empty = derived from `Api.BaseUrl`: `http`→`ws`, `https`→`wss`, plus the path), the env names `AGENT_LINK_URL`/`AGENT_LINK_TOKEN`/`AGENT_LINK_ALLOW_INSECURE` |
| `Connect-NexusInfra` | Reads `GET /config` and keeps the features on the session |
| Preflight | For an `outbound` host: the control plane must list `agent-link`, and the host must reach the link's host and port (instead of the agent port being reachable) |
| `RegisterNode` | `POST /nodes` with `connection: "outbound"` and no `agentUrl` |
| `AgentContainer` | For `outbound`: no `-p 9100`, `AGENT_LINK_URL` in the container, and the link token minted with `POST /nodes/:id/link-token` and written to the env file (mode 600, over stdin like the other secrets) only when the container is (re)created |
| `VerifyHealthy`, `AgentReachable` | Unchanged: `/disk` goes over the link, so the same step proves an outbound node can be controlled |
| `Get-NexusFleetStatus` | Shows `Connection` and, for outbound nodes, `Linked` |

## Not in this design

- **The broker still needs its own port** (5672, or 5671 with TLS). Heartbeats and server commands keep using it.
  A network that only lets 443 out therefore still blocks a node. Carrying heartbeats and commands over the link
  as well would leave one connection per node; that is a later step.
- `tunnel` (SSH) for other platforms: the connectors extra.
- TLS in front of the gateway is a deployment choice (Caddy or Cloudflare Tunnel, see the
  [demo guide](../lab/demo/README.md#over-the-internet-without-a-vpn)), required for `wss://`.
