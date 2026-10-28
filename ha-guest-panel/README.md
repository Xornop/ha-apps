# HA Guest Panel

A fully isolated control panel for a hand-picked set of Home Assistant entities, served on its own port, completely separate from the Home Assistant frontend and login.

Hand it to guests, put it on a wall tablet, or open it on a phone: they can control only the entities you choose, and nothing else.

## Features

- Runs on its own port (default `8125`), no Home Assistant login required
- Entities are organised into named groups, each with an optional highlighted "main" entity
- Strict allowlist: only the configured entities can be read or controlled, and only a fixed set of services per domain
- Optimistic UI: buttons react instantly, state is refreshed every 5 seconds
- Dark, mobile-friendly layout

### Supported entity types

| Domain | Controls |
| --- | --- |
| `light` | On/off, brightness slider, warm/cold white (if the light supports color temperature) |
| `switch`, `input_boolean`, `fan` | On/off |
| `cover` | Open, stop, close |
| `lock` | Lock / unlock |
| `media_player` | On/off, previous, play/pause, next, volume up/down |
| anything else | Read-only state (with unit, if any) |

Media player buttons only appear when the player reports support for the matching feature. Volume buttons are shown as long as the player is on.

## Installation

1. Add this repository to the Home Assistant add-on store (or copy the add-on folder into your local `/addons` directory).
2. Install **Guest Panel**.
3. Create a long-lived access token in Home Assistant (Profile → Security → Long-lived access tokens).
4. Fill in the configuration (see below) and start the add-on.
5. Open `http://<home-assistant-ip>:8125`.

## Configuration

```yaml
ha_token: "your-long-lived-access-token"
groups:
  - name: "Living room"
    main_entity: "light.living_room"
    entities:
      - "light.reading_lamp"
      - "cover.curtains"
      - "media_player.tv"
  - name: "Entrance"
    entities:
      - "lock.front_door"
      - "switch.porch_light"
```

| Option | Required | Description |
| --- | --- | --- |
| `ha_token` | yes | Long-lived access token used by the add-on to talk to Home Assistant. The add-on stops if it is empty. |
| `groups` | no | List of groups shown on the panel. With no groups, the panel is empty. |
| `groups[].name` | yes | Title of the group. |
| `groups[].main_entity` | no | Entity shown first in the group, with a highlighted card. |
| `groups[].entities` | yes | Entities shown in the group. |

`main_entity` and `entities` are also what the server allows: any entity not listed here is rejected by the API, even if someone crafts a request by hand.

## Security notes

- **The panel has no authentication.** Anyone who can reach port `8125` can operate every configured entity. Keep it on your local network and do not expose it to the internet.
- The access token never leaves the add-on; the browser only talks to the panel's own `/api` endpoints.
- Use a dedicated Home Assistant user for the token if you want to limit what it can do, and avoid putting sensitive entities (alarms, garage doors, locks) in groups unless you really want guests to control them.
- Only these services are accepted: `turn_on`, `turn_off`, `toggle` (lights, switches, input booleans, fans), `open_cover`, `close_cover`, `stop_cover`, `lock`, `unlock`, and for media players `turn_on`, `turn_off`, `media_play_pause`, `media_previous_track`, `media_next_track`, `volume_up`, `volume_down`.

## How it works

A small Node.js (Express) server reads the add-on options, polls the Home Assistant REST API for the configured entities, and serves a static single-page frontend. Service calls from the browser are validated against the entity allowlist and the per-domain service list before they are forwarded to Home Assistant.

| Endpoint | Method | Purpose |
| --- | --- | --- |
| `/api/states` | GET | Returns all groups with the current state of each entity |
| `/api/service` | POST | Calls an allowed service on an allowed entity |

## Project structure

```
guest-panel/
├── config.yaml
├── Dockerfile
├── package.json
├── server.js
└── public/
    ├── index.html
    ├── app.js
    └── style.css
```

## Troubleshooting

- **"No ha_token set" in the log:** the `ha_token` option is empty. Set it and restart the add-on.
- **Entities show as `unavailable`:** check the entity ID for typos and that the token is valid.
- **A media player button is missing:** the integration does not report that feature. Check the `supported_features` attribute of the entity in Developer Tools.
- **Nothing happens when pressing a button:** check the add-on log for `HA rejected ...` messages.
