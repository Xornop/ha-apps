# HA Gatekeeper

A Home Assistant add-on that exposes a single link. Visitors do **not** get a
real Home Assistant account:

- First visit → a small login page (username + password, configured in the
  add-on options).
- On success, a long-lived, `httponly` cookie is stored on that device and
  the configured `binary_sensor.gatekeeper_<user>` is turned on (then
  automatically turned back off a few seconds later).
- Any later visit from the same device skips the login page entirely and
  triggers the sensor immediately.

Wire the sensor into your own automation — the add-on only handles auth and
flips a sensor, it does not call any services directly.

## Installation

1. Add this repository to your Home Assistant add-on store (Settings →
   Add-ons → Add-on store → ⋮ → Repositories), or copy the `ha-gatekeeper`
   folder into your local `addons` folder.
2. Install "HA Gatekeeper", open its **Configuration** tab.
3. Add one entry per user under `users`, e.g.:

   ```yaml
   users:
     - name: guest1
       password: "a-strong-password"
     - name: guest2
       password: "another-strong-password"
   session_days: 365
   cookie_secure: true
   ```

4. Start the add-on. It listens on port `8099`.
5. Point a reverse proxy (or port forward) at `<host>:8099/trigger` so the
   link is reachable from outside your network. **Use HTTPS** and keep
   `cookie_secure: true` — with it on, the session cookie is marked
   `secure`, so it will silently fail to persist over plain HTTP. Only set
   `cookie_secure: false` for local/LAN-only testing over plain HTTP; if you
   do, devices will keep getting asked to log in as soon as you move to
   HTTPS unless you flip it back and log in again.

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

## Disclaimer


Don't use this to unlock doors or other stuff you don't want people to use/access. I can't promise the security of this app won't be compromised. Use at your own risk!
