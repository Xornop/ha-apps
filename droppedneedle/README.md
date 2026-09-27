# DroppedNeedle

Home Assistant app for [DroppedNeedle](https://www.droppedneedle.com/) —
self-hosted music requests and discovery, backed by its own library and
download engine. It doesn't run a download client itself; point it at a
download client you already run (slskd or SABnzbd) and it takes it from
there: search, request, verify, and import into your library.

Wraps the upstream image at
[`droppedneedle/droppedneedle`](https://hub.docker.com/r/droppedneedle/droppedneedle)
([source](https://github.com/DroppedNeedle/DroppedNeedle)) for Home
Assistant's app runtime (formerly "add-ons").

## Installation

1. Settings > Add-ons > Add-on store > ⋮ > Repositories, and add:
   `https://github.com/Xornop/ha-apps`
2. Find **DroppedNeedle** in the store and install it.
3. Start the app, then open its web UI (port 8688) and create the first
   admin account.

## Configuration

| Option                  | Default                | Description                                                                 |
| ------------------------ | ----------------------- | ----------------------------------------------------------------------------- |
| `puid`                    | `1000`                    | User ID the app runs as inside the container.                               |
| `pgid`                    | `1000`                    | Group ID the app runs as inside the container.                              |
| `umask`                   | `027`                     | Creation mask for new files. Use `002` if another app shares write access.  |
| `bind_host`               | `auto`                    | `auto` listens on IPv4 and IPv6. Set an interface IP to pin it.             |
| `trusted_proxy_ips`       | `127.0.0.1,::1`           | IPs/CIDRs whose `X-Forwarded-*` headers are trusted.                        |
| `tz`                      | `Etc/UTC`                 | Container timezone, e.g. `Europe/Amsterdam`.                                |
| `slskd_downloads_path`    | `/media/slskd/downloads`  | In-container path to your download client's completed-downloads directory, under `/media`. |

## Setup

1. Settings > Library in the app, add your library path as `/media/...`.
2. Settings > Download Client, point it at your slskd or SABnzbd instance
   and API key, then Test and Save.
3. Set `slskd_downloads_path` to match where your download client's
   completed files land under `/media`.

Keep your download client's completed-downloads directory and the music
library under the same `/media` mount, with no extra nested binds, so
imports move fast instead of falling back to copy-and-remove.

## Notes

- Not run through HA ingress: DroppedNeedle wasn't built to be proxied
  under a subpath, so it's exposed on its own port (8688) instead.
- On startup, the app takes ownership of `/media` for the configured
  `puid`/`pgid`, since a mismatch there is a common cause of download
  imports silently failing as read-only.
- Plugins run in-process with full privileges and no sandbox — only
  install ones whose code you've read.

## License

This app packaging is provided as-is. DroppedNeedle itself is licensed
under its own terms — see the [upstream repository](https://github.com/DroppedNeedle/DroppedNeedle).
