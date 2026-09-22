# slskd Home Assistant add-on

A Home Assistant add-on for [slskd](https://github.com/slskd/slskd) — a modern,
self-hosted, cross-platform client for the Soulseek peer-to-peer network with a
web UI and REST API.

## What it does

- Downloads the official self-contained `slskd` release binary for your
  add-on's architecture (amd64 / aarch64 / armv7) at build time — no upstream
  Docker image is used as a base, so this stays lightweight and easy to pin
  to a specific slskd version.
- Maps Home Assistant add-on options (Soulseek + web UI credentials, shared
  folders, speed/upload limits, listen port) onto slskd's `SLSKD_*`
  environment variables.
- Persists slskd's config, logs and database under the add-on's own `/data`
  volume, so they survive add-on restarts and updates.

## Installation

1. In Home Assistant, go to **Settings → Add-ons → Add-on Store**.
2. Click the **⋮** menu → **Repositories**, and add:
   `https://github.com/Xornop/ha-apps`
3. Find **slskd** in the store and click **Install**.

## Configuration

| Option | Description |
|---|---|
| `slsk_username` / `slsk_password` | Your Soulseek network account credentials. |
| `web_username` / `web_password` | Credentials for logging into the slskd web UI. |
| `listen_port` | TCP port slskd listens on for incoming peer connections. Forward this on your router for the best connectivity. |
| `shared_directories` | List of paths (under `/share/...` or `/media/...`, since those are the folders mapped into the add-on) to share with the network. |
| `downloads_directory` | Where completed downloads are saved. Leave blank to use slskd's default under the add-on's data folder. |
| `incomplete_directory` | Where in-progress downloads are staged. Leave blank for the default. |
| `upload_slots` | Maximum concurrent uploads. |
| `upload_speed_limit` / `download_speed_limit` | KB/s limits; `0` means unlimited. |
| `remote_configuration` | Allow editing slskd's config from its own web UI (in addition to these options). |
| `diagnostic_level` | Soulseek connection diagnostic verbosity: `None`, `Warning`, `Info`, or `Debug`. |

If you want folders outside `/share` or `/media` (e.g. a dedicated media
library mount), add the relevant `map:` entry to `config.yaml` and rebuild.

## Web UI / Ingress

This add-on is **not** set up for Home Assistant Ingress, because slskd needs
to know its own URL base path up front and Ingress paths aren't stable enough
for that to work reliably. Instead, `config.yaml` sets a direct `webui` link,
so the **Open Web UI** button on the add-on page takes you straight to
`http://<home-assistant-ip>:5030`.

## Updating slskd itself

The Soulseek client version is pinned via the `SLSKD_VERSION` build arg at
the top of the `Dockerfile`. To pick up a new slskd release, bump that
version, bump `version` in `config.yaml`, and rebuild.

## Notes

- `armv7` support depends on slskd continuing to publish a `linux-arm`
  release asset for the pinned version — if a build fails on that
  architecture, drop `armv7` from `arch:` in `config.yaml`.
- The Soulseek listen port (`50300` by default) is a peer-to-peer port, not
  something Ingress or a reverse proxy can help with — it needs to be
  reachable directly for good search/download performance.
