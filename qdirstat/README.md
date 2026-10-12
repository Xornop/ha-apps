# QDirStat

A WizTree-style disk usage analyzer for Home Assistant. Browse a treemap of your storage right from the sidebar and find out what is eating your disk space.

Built on [jlesage/qdirstat](https://github.com/jlesage/docker-qdirstat).

## Features

- QDirStat GUI in the Home Assistant sidebar (ingress)
- Scan the HA config, share, media, backup and SSL folders
- Optionally mount a host partition to scan the whole system, including Docker layers
- Timestamps on every log line

## Folders

| Path            | Content          | Access     |
|-----------------|------------------|------------|
| `/scan/config`  | HA config        | read-only  |
| `/scan/ssl`     | SSL certificates | read-only  |
| `/scan/share`   | Share            | read-write |
| `/scan/media`   | Media            | read-write |
| `/scan/backup`  | Backups          | read-write |
| `/scan/host`    | Host partition   | see below  |

## Options

| Option         | Default                            | Description                                                  |
|----------------|------------------------------------|--------------------------------------------------------------|
| `mount_device` | `/dev/disk/by-label/hassos-data`   | Host partition to mount on `/scan/host`. Leave empty to skip. |

On Home Assistant OS the default is the data partition. On other installs, use your own device, e.g. `/dev/sda1`.

## Notes

- The add-on needs `full_access` and the `SYS_ADMIN` capability to mount host partitions.
- The app runs as root. The host partition is mounted read-only when possible, but if the host already has it mounted read-write it falls back to read-write. Deleting files in QDirStat then affects the real system, so be careful.
- The add-on does not start on boot. Start it when you need it.
- Port 5800 is optional and disabled by default.
