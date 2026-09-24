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
- Optionally brings up a WireGuard tunnel and routes **only** slskd's
  Soulseek connection through it via a local SOCKS5 proxy (see below), with
  optional, provider-agnostic inbound port forwarding.

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
| `listen_port` | TCP port slskd listens on for incoming peer connections. Used as-is when `vpn_enabled` is off, or when port forwarding is disabled/unavailable; when port forwarding succeeds, it's overridden automatically with the forwarded port instead. |
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
| `port_forward_method` | How to request an inbound port from the VPN, if at all: `natpmp` (default) or `none`. Only matters when `vpn_enabled` is true. |
| `wg_natpmp_gateway` | Optional override for the NAT-PMP gateway IP. Leave blank to use the guessed default (`.1` of your assigned WireGuard address, which is correct for most providers, including ProtonVPN). Only set this if port forwarding keeps failing and your provider's docs specify a different gateway. |

All of these come straight from your VPN provider's WireGuard config file
(e.g. ProtonVPN's downloadable `.conf`).

## How the VPN works (split-tunnel via SOCKS5 + optional port forwarding)

This add-on does **not** route all container traffic through the VPN. Instead:

1. A WireGuard interface (`wg0`) is brought up. This part is fully generic —
   any valid WireGuard peer config works, regardless of VPN provider.
2. A local SOCKS5 proxy (`danted`) is started, bound so its own outbound
   traffic only ever leaves via `wg0` (using policy routing scoped to the
   tunnel's own IP — the container's normal default route is left alone).
3. slskd is configured (via `SLSKD_SOULSEEK_CONNECTION_PROXY_*`) to make its
   outbound Soulseek connection (server login, searches, requesting
   downloads) through that proxy.
4. If `port_forward_method` is `natpmp` (the default) and the VPN server
   supports it, a NAT-PMP port is requested and forwarded to slskd's listen
   port, and renewed every 45 seconds. This lets other users connect back to
   you (uploads/sharing) through the VPN too, instead of you just appearing
   unreachable for incoming connections.

   Port forwarding is entirely optional and never blocks the VPN or the
   add-on from starting. If it's set to `none`, or NAT-PMP isn't supported
   by your provider/server, or the gateway can't be reached, the add-on logs
   a warning and simply falls back to the static `listen_port`.

   The NAT-PMP gateway is auto-detected as `.1` of your assigned WireGuard
   address by default, which matches most providers. Set
   `wg_natpmp_gateway` if your provider uses a different gateway IP.

### Verifying the VPN is actually being used

From the **Terminal & SSH** add-on (or the host), find the container name
(`docker ps | grep slskd`), then:

```
docker exec -it <container-name> curl --socks5 127.0.0.1:1080 https://api.ipify.org
docker exec -it <container-name> curl https://api.ipify.org
```

The first command should return your VPN provider's IP; the second, your
own. If they differ and the first matches your VPN, the Soulseek connection
is going through the tunnel. `wg show wg0` while downloading should also
show a climbing `transfer` counter.

Check the add-on log for `[slskd-addon][portfwd]` lines to see the port
forwarding status — success, a warning that it failed, or that it's
disabled.

## Web UI

Reachable directly on your local network at `http://<home-assistant-ip>:5030`
(the "Open Web UI" button opens this).

## Notes

- `armv7` support depends on slskd continuing to publish a `linux-arm`
  release asset for the pinned version.
- The Soulseek listen port is a peer-to-peer port. Without the VPN, with
  `port_forward_method` set to `none`, or if port forwarding fails, forward
  it on your router for good connectivity.