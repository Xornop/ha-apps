# slskd Home Assistant add-on

A Home Assistant add-on for [slskd](https://github.com/slskd/slskd) — a modern,
self-hosted, cross-platform client for the Soulseek peer-to-peer network with a
web UI and REST API. Optionally routes Soulseek traffic through a WireGuard
VPN via a local SOCKS5 proxy.

## What it does

- Downloads the official self-contained `slskd` release binary for your
  add-on's architecture (amd64 / aarch64 / armv7) at build time, pinned to a
  specific version.
- Maps add-on options (Soulseek + web UI credentials, shared folders, speed/
  upload limits, listen port) onto slskd's `SLSKD_*` environment variables.
- Creates any configured shared/downloads/incomplete directory that doesn't
  already exist.
- Persists slskd's config, logs and database under the add-on's own `/data`
  volume.
- Optionally brings up a WireGuard tunnel and routes slskd's
  Soulseek connection through it via a local SOCKS5 proxy (see below).

## Installation

1. In Home Assistant, go to **Settings → Apps → App Store**.
2. Click the **⋮** menu → **Repositories**, and add:
   `https://github.com/Xornop/ha-apps`
3. Find **slskd** in the store and click **Install**.

## Configuration

| Option | Description |
|---|---|
| `slsk_username` / `slsk_password` | Your Soulseek network account credentials. |
| `web_username` / `web_password` | Credentials for logging into the slskd web UI. |
| `listen_port` | TCP port slskd listens on for incoming peer connections. Forward this on your router for the best connectivity. |
| `shared_directories` | List of paths (under `/share/...` or `/media/...`) to share with the network. Created automatically if missing. |
| `downloads_directory` / `incomplete_directory` | Where downloads land. Created automatically if missing; leave blank for slskd's default under `/data`. |
| `upload_slots` | Maximum concurrent uploads. |
| `upload_speed_limit` / `download_speed_limit` | KB/s limits; `0` means unlimited. |
| `remote_configuration` | Allow editing slskd's config from its own web UI too. |
| `diagnostic_level` | Soulseek diagnostic verbosity: `None`, `Warning`, `Info`, or `Debug`. |
| `vpn_enabled` | Route the Soulseek connection through the WireGuard VPN below. If `true`, the WireGuard options must be filled in or the add-on refuses to start (fails closed rather than connecting unprotected). |
| `wg_private_key` | Your WireGuard private key. |
| `wg_address` | The IPv4 address assigned to you by the VPN provider (e.g. `10.2.0.2/32`). IPv6 entries are ignored. |
| `wg_peer_public_key` | The VPN server's public key. |
| `wg_peer_endpoint` | The VPN server's `host:port`. |
| `wg_allowed_ips` | Normally left at the default `0.0.0.0/0, ::/0`. |

All of these WireGuard options come straight from your VPN provider's WireGuard config file.

## How the VPN works (split-tunnel via SOCKS5)

This add-on does **not** route all container traffic through the VPN. Instead:

1. A WireGuard interface (`wg0`) is brought up.
2. A local SOCKS5 proxy (`danted`) is started, bound so its own outbound
   traffic only ever leaves via `wg0` (using policy routing scoped to the
   tunnel's own IP — the container's normal default route is left alone).
3. slskd is configured (via `SLSKD_SOULSEEK_CONNECTION_PROXY_*`) to make its
   Soulseek connection through that proxy.

## Web UI

Reachable directly on your local network at `http://<home-assistant-ip>:5030`

## Notes

- `armv7` support depends on slskd continuing to publish a `linux-arm`
  release asset.
- The Soulseek listen port (`50300` by default) is a peer-to-peer port and
  is **not** routed through the VPN — it needs to be reachable directly on
  your network/router for good search and download performance for other
  Soulseek users. The VPN is only there to change your IP when downloading.