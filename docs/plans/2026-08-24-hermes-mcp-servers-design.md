# Hermes MCP servers: Grafana, Home Assistant, time

2026-08-24

## Goal

Give the Hermes agent on osgiliath three more MCP servers: Grafana (metrics,
logs, dashboards), Home Assistant (device control), and `time` (a clock).

## Findings

### mcp-nixos.io is already in use

`mcp-nixos.io` is the website for `github.com/utensils/mcp-nixos`, which is
exactly what `agindin.mcp.servers.nixos` already runs via
`unstablePkgs.mcp-nixos` (3.0.1). It exposes `nix` and `nix_versions` over
search.nixos.org, NixHub, cache.nixos.org, FlakeHub, noogle, the NixOS wiki
and nix.dev. There is nothing to switch to. The site's only alternative
offering is a hosted HTTP endpoint, which would trade a local stdio process
for a third-party dependency.

### Immich has no viable server

No official Immich MCP server exists and nothing is packaged in nixpkgs or
mcp-servers-nix. The community implementations would each need packaging under
`packages/`, and several expose asset deletion over the whole library. Deferred
until an official server appears.

### Grafana subsumes Prometheus and Loki

`mcp-grafana` ships Prometheus and Loki tool categories, so a single server
covers metric queries and log search across both hosts. No separate Prometheus
or Loki MCP server is needed.

## Design

### Placement

`services/hermes.nix` is unchanged — it already consumes
`config.agindin.mcp.hermesServersConfig`. All three servers are additions to
`common/mcp.nix`, following the existing pattern: options under
`agindin.mcp.servers.*`, entries appended to `desktopServers` (from which
`hermesServers` is derived) and to `programs.mcp.servers`. Enabled per-host in
`hosts/osgiliath/home.nix`.

    agindin.mcp.servers = {
      grafana = { enable; url; tokenFile; readOnly = true; };
      homeAssistant = { enable; url; tokenFile; readOnly = false; };
      time = { enable; timezone = null; };
    };

### Packages

| Server | Package | Version |
|---|---|---|
| Grafana | `unstablePkgs.mcp-grafana` | 1.1.0 |
| Home Assistant | `unstablePkgs.ha-mcp` | 8.3.0 |
| time | `mcpPkgs.mcp-server-time` | 2026.7.10 |

Both non-`mcpPkgs` servers come from unstable rather than stable 26.05, which
carries `mcp-grafana` 0.14.0 and `ha-mcp` 7.4.1. `unstablePkgs.mcp-nixos` sets
the precedent. `mcp-servers-nix` dropped its own `mcp-grafana` once nixpkgs
gained one, so it comes from nixpkgs.

### Secret handling

Grafana 1.1.0 accepts `GRAFANA_SERVICE_ACCOUNT_TOKEN_FILE`, so the env value is
the agenix *path*. No wrapper, no secret in the Nix store, no secret in the
process environment, and the token reloads on rotation without a restart. This
is why the version bump to unstable is worth taking: 0.14.0 only accepts the
token inline and would force a shell wrapper.

`ha-mcp` only accepts `HOMEASSISTANT_TOKEN` inline, so it gets `haWrapper`,
a copy of the existing `githubWrapper` that reads `tokenFile` at startup. The
`programs.mcp` view instead uses `env.HOMEASSISTANT_TOKEN.file`, which
home-manager resolves itself. This is the same two-shape split `github`
already uses.

`time` has no secrets.

### Hardening

`mcp-grafana` gets `--disable-write` while `readOnly` is set (the default),
blocking dashboard edits, alert-rule changes, annotation writes and snapshot
creation.

`ha-mcp` gets two non-secret env pins, both because Hermes runs under
`ProtectSystem=strict` and `ProtectHome=true`:

- `HA_MCP_DISABLE_SETTINGS_UI=1` — it otherwise spawns a settings-UI web
  sidecar on a random port next to the stdio server.
- `HA_MCP_DISABLE_UPDATE_CHECK=1` — it otherwise queries PyPI on every start,
  which is meaningless when Nix pins the version.

Its `READ_ONLY_MODE` env var is wired to the `readOnly` option. Home Assistant
defaults to read-write (agent can actually control devices); flipping the
option hides write-capable tools at catalog time and blocks writes at call
time. `ha-mcp` resolves its data dir to `~/.ha-mcp`, which under Hermes is
`/var/lib/hermes/.ha-mcp` — inside the state dir that impermanence and restic
already cover.

### osgiliath wiring

Two new agenix secrets, owner and group `hermes`, mode `0440`, matching the
existing `hermes-*` entries:

- `hermes-grafana-token.age` — a Grafana **service account** token
- `hermes-homeassistant-token.age` — a Home Assistant long-lived access token

Grafana's URL is `http://127.0.0.1:10001`: mcp-grafana runs on osgiliath
alongside Grafana, so it reaches the loopback port directly and bypasses both
Caddy and the OIDC gate. Home Assistant runs on a separate HAOS box at
`http://10.88.88.3:8123`.

`time` takes no timezone override; it inherits `time.timeZone`
(`America/New_York`) from the host.

## Rejected

- **Immich** — see above.
- **Postgres** — anduin already exposes a web API over the same data, and no
  Postgres MCP server is packaged in either flake.
- **Frigate, Linkwarden, Miniflux, Tandoor** — community-only and unpackaged.
  Same cost as Immich, less payoff.
- **`mcp-server-memory`** — considered and dropped. Unbounded agent-written
  state for unclear benefit.
- **HA's built-in `mcp_server` integration over HTTP** — would put the bearer
  token in Hermes' `headers`, which lands in the world-readable Nix store.
  `ha-mcp` over stdio also has the richer toolset.
