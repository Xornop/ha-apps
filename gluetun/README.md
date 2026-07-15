# Gluetun VPN Add-on for Home Assistant

A Home Assistant add-on that provides a VPN client for multiple providers using [Gluetun](https://github.com/qdm12/gluetun).

## Installation

1. Add this repository to your Home Assistant add-on store
2. Install the **Gluetun VPN** add-on
3. Configure your VPN settings (see below)
4. Start the add-on

## Configuration

| Option | Type | Required | Description |
|--------|------|----------|-------------|
| `vpn_provider` | string | Yes | VPN provider (e.g. `protonvpn`, `nordvpn`, `surfshark`) |
| `vpn_type` | string | Yes | `openvpn` or `wireguard` |
| `openvpn_user` | string | No | OpenVPN username |
| `openvpn_password` | string | No | OpenVPN password |
| `wireguard_private_key` | string | No | WireGuard private key |
| `wireguard_addresses` | string | No | WireGuard address (e.g. `10.2.0.2/32`) |
| `shadowsocks_enabled` | bool | No | Enable Shadowsocks proxy |
| `shadowsocks_port` | int | No | Shadowsocks port (default: `8388`) |
| `shadowsocks_password` | string | No | Shadowsocks password |
| `shadowsocks_method` | string | No | Encryption method (default: `aes-256-gcm`) |
| `http_proxy_enabled` | bool | No | Enable HTTP proxy |
| `http_proxy_port` | int | No | HTTP proxy port (default: `8888`) |
| `tz` | string | No | Timezone (e.g. `Europe/Amsterdam`) |
| `server_countries` | string | No | Exit node countries, seperated by commas |

## Supported VPN Providers

`airvpn`, `cyberghost`, `expressvpn`, `fastestvpn`, `hidemyass`, `ipvanish`, `ivpn`, `mullvad`, `nordvpn`, `perfectprivacy`, `privado`, `privateinternetaccess`, `privatevpn`, `protonvpn`, `purevpn`, `slickvpn`, `surfshark`, `torguard`, `vpnsecure`, `vpnunlimited`, `vyprvpn`, `wevpn`, `windscribe`

## Example configuration (ProtonVPN via OpenVPN)

```yaml
vpn_provider: protonvpn
vpn_type: openvpn
openvpn_user: your_username
openvpn_password: your_password
tz: Europe/Amsterdam
```

## Ports

| Port | Protocol | Description |
|------|----------|-------------|
| `8388` | TCP/UDP | Shadowsocks proxy |
| `8000` | TCP | Gluetun HTTP control API |

## Notes

- This add-on requires `NET_ADMIN` privileges to manage network routing
- Built on Gluetun v3.39.0
- Based on [m2sh/ha-addon-gluetun](https://github.com/m2sh/ha-addon-gluetun)
