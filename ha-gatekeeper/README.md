# HA Gatekeeper

A Home Assistant add-on that exposes a single link. Visitors do **not** get a
real Home Assistant account:

- First visit → a small login page (username + password, configured in the
  add-on options), with an optional "Remember me" checkbox and optional
  custom Markdown text shown below it in its own card.
- On success, if **"Remember me"** was checked, a long-lived, `httponly`
  cookie is stored on that device (valid for `session_days`) and the
  configured `binary_sensor.gatekeeper_<user>` is turned on (then
  automatically turned back off a few seconds later). If it was **not**
  checked, a session-only cookie is used instead — it disappears as soon as
  the browser is fully closed, so the visitor has to log in again next
  time.
- Any later visit from the same device with a still-valid cookie skips the
  login page entirely and triggers the sensor immediately.
- If a user is later removed from the configuration, their saved session is
  revoked and their cookie is deleted the next time they visit — they're
  sent back to the login page instead of triggering anything.

Wire the sensor into your own automation — the add-on only handles auth and
flips a sensor, it does not call any services directly.

Runs on gunicorn (production WSGI server), not the Flask development
server.

## Installation

1. Add this repository to your Home Assistant add-on store (Settings →
   Add-ons → Add-on store → ⋮ → Repositories), or copy the `ha-gatekeeper`
   folder into your local `addons` folder.
2. Install "HA Gatekeeper", open its **Configuration** tab.
3. Configure the options, e.g.:

   ```yaml
   users:
     - name: guest1
       password: "a-strong-password"
     - name: guest2
       password: "another-strong-password"
   session_days: 365
   cookie_secure: true
   success_message: "Actie getriggerd ✅"
   error_message: "Error. Notify an admin."
   login_footer_text: ""
   ```

4. Start the add-on. It listens on port `8099`, and responds on both `/`
   and `/trigger` — so you can point a domain straight at it without
   needing a specific path.
5. Point a reverse proxy (e.g. NGINX Proxy Manager) or port forward at
   `<host>:8099` so the link is reachable from outside your network. **Use
   HTTPS** and keep `cookie_secure: true` (see below).

## Configuration options

| Option | Type | Default | Description |
|---|---|---|---|
| `users` | list | `[]` | One entry per person, each with its own `name` and `password`. |
| `session_days` | int | `365` | How many days a device stays logged in after a successful login. |
| `cookie_secure` | bool | `true` | Marks the session cookie `secure`, requiring HTTPS to persist. Keep `true` in production; only set `false` for local/LAN-only testing over plain HTTP — see warning below. |
| `success_message` | str | `"Actie getriggerd ✅"` | Text shown after a successful trigger. Emoji allowed. |
| `error_message` | str | `"Error. Notify an admin."` | Text shown if triggering the action fails (e.g. Home Assistant unreachable). |
| `login_footer_text` | str | `""` | Optional Markdown text shown below the login form, in its own card. Leave empty to show nothing. Use a YAML `\|` block in the options editor if you need multiple lines. |

Note: the rest of the login page's static text is in Dutch, but the
"Remember me" checkbox label is hardcoded in English — edit
`LOGIN_HTML` in `app/app.py` directly if you want it translated.

### `cookie_secure` warning

With `cookie_secure: true` (default), browsers will silently refuse to
store the session cookie unless the page is served over HTTPS — logins will
appear to work (the action still triggers) but the device will be asked to
log in again on every visit. Only set this to `false` for local/LAN-only
testing over plain HTTP, and switch it back to `true` — with users logging
in again — once you're behind HTTPS.

## Home Assistant automation example

```yaml
automation:
  - alias: "React to gatekeeper trigger"
    trigger:
      - platform: state
        entity_id: binary_sensor.gatekeeper_guest1
        to: "on"
    action:
      - service: light.toggle
        target:
          entity_id: light.living_room
```

Each configured user gets their own `binary_sensor.gatekeeper_<user>`
(slugified, lowercase), so you can build different automations per user if
needed.

## Logging

Every trigger and every failed login attempt is logged (visible in the
add-on's log tab), including the visitor's IP address:

```
2026-07-31 14:22:03 INFO Triggered by 'guest1' via new login (203.0.113.42)
2026-07-31 14:25:11 INFO Triggered by 'guest1' via saved session (203.0.113.42)
2026-07-31 14:26:40 WARNING Failed login attempt for username 'guest2' from 198.51.100.7
2026-07-31 14:30:02 WARNING Rejected session for removed user 'guest3' (203.0.113.55) — revoking token
```

The add-on trusts `X-Forwarded-For`/`X-Forwarded-Proto` from one reverse
proxy hop (via `ProxyFix`), so logs show the real visitor IP rather than
your reverse proxy's internal IP.

## Removing a user

Deleting a user's entry from `users` and restarting the add-on is enough —
their saved session is revoked and their cookie is cleared automatically
the next time they visit the link. Note: option changes only take effect
after an add-on **restart** (the Supervisor does not restart it
automatically when you save the configuration).

## Icon / logo

Drop `icon.png` (128×128, shown in the add-on list) and/or `logo.png`
(256×256, shown on the add-on's detail page) directly into this folder,
next to `config.yaml`. No configuration changes needed — Home Assistant
picks them up automatically.

## Notes / things to review before exposing this publicly

- Sessions are stored in `/data/sessions.db` (SQLite), which persists across
  add-on restarts and updates.
- Passwords are currently stored as plain text in the add-on's Supervisor
  configuration. Consider hashing them if that matters for your threat
  model.
- There's no rate limiting on login attempts — put this behind a reverse
  proxy with basic rate limiting if it's reachable from the public internet.
- `ingress: false` (this add-on does *not* use HA ingress) because ingress
  requires an authenticated HA session in the browser, which defeats the
  purpose here — visitors are never meant to have HA accounts.
- Runs with gunicorn (`--workers 1 --threads 4`) rather than the Flask dev
  server. A single worker is used deliberately so all requests share one
  SQLite connection to `/data/sessions.db`; threads still allow handling
  multiple requests concurrently.
