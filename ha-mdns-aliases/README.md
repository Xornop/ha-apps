# HA mDNS Aliases

A Home Assistant App that answers IPv4 mDNS A-record queries for additional
local hostnames, such as `smarthome.local`, without changing Home Assistant's
existing hostname.

## Features

- Automatic IPv4 address detection.
- Multiple configurable aliases.
- No Ingress or web interface.
- Configurable log level.
- Ignores incoming DNS responses and does not echo questions in its replies.

## Installation

1. Add this repository to the Home Assistant App Store.
2. Install **HA mDNS Aliases**.
3. Configure `hostnames`, for example `smarthome`.
4. Start the App manually for the first test.
5. Check the logs for the detected IPv4 address.
6. Test `http://smarthome.local:8123` from a device on the same LAN.

The App is configured with `boot: manual` intentionally. After verifying that
your network remains stable and aliases resolve correctly, you can change
`boot` to `auto` if you want it to start automatically.

## Configuration

- `hostnames`: Comma-separated hostnames without `.local`.
  Example: `smarthome,tablet,hassio`.
- `log_level`: `debug`, `info`, `warning`, `error`, or `silent`.

The IPv4 address is automatically detected using the system's default route.
Check the `Detected response IPv4 address` log entry to see which address was
selected.

### Log levels

| Level | Description |
|---|---|
| `debug` | Diagnostic information about matching requests and malformed packets |
| `info` | Startup information, configured aliases, and selected IPv4 address |
| `warning` | Warnings and errors only |
| `error` | Errors only |
| `silent` | Suppresses responder log messages |

Use `debug` temporarily for troubleshooting. `info` or `warning` is recommended
for normal operation.

## Usage

Open `http://smarthome.local:8123` from a device on the same local network,
assuming Home Assistant is accessible on port 8123.

## Limitations and safety notes

- This is a small IPv4 mDNS responder, not a full Avahi implementation.
- IPv6 AAAA records are not provided.
- The existing Home Assistant hostname is not changed.
- mDNS normally works only within the same LAN or VLAN.
- Use unique aliases to avoid hostname conflicts.
- On systems with VPNs or multiple network interfaces, the default route may
  select the wrong IPv4 address.
- UDP port 5353 is the standard mDNS port and is shared with existing mDNS
  services. The responder must remain protocol-correct to avoid interference.
- Keep the App stopped if enabling it makes Home Assistant or the network slow.
