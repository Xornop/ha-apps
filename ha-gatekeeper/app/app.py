import json
import logging
import os
import secrets
import sqlite3
import threading
import time

import requests
import markdown
from flask import Flask, make_response, request
from werkzeug.middleware.proxy_fix import ProxyFix

logging.basicConfig(
    level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s"
)
logger = logging.getLogger("ha-gatekeeper")

app = Flask(__name__)
# Trust X-Forwarded-For/-Proto from the reverse proxy (e.g. NGINX Proxy
# Manager) so request.remote_addr reflects the real visitor, not the proxy.
app.wsgi_app = ProxyFix(app.wsgi_app, x_for=1, x_proto=1, x_host=1)

OPTIONS_PATH = "/data/options.json"
DB_PATH = "/data/sessions.db"
CORE_API = "http://supervisor/core/api"
SUPERVISOR_TOKEN = os.environ.get("SUPERVISOR_TOKEN", "")
COOKIE_NAME = "lt_token"


def load_options():
    with open(OPTIONS_PATH) as f:
        opts = json.load(f)
    users = {u["name"]: u["password"] for u in opts.get("users", [])}
    session_days = opts.get("session_days", 365)
    cookie_secure = opts.get("cookie_secure", True)
    success_message = opts.get("success_message", "Actie getriggerd \u2705")
    error_message = opts.get("error_message", "Error. Notify an admin.")
    login_footer_text = opts.get("login_footer_text", "")
    return (
        users, session_days, cookie_secure,
        success_message, error_message, login_footer_text,
    )


(
    USERS, SESSION_DAYS, COOKIE_SECURE,
    SUCCESS_MESSAGE, ERROR_MESSAGE, LOGIN_FOOTER_TEXT,
) = load_options()

LOGIN_FOOTER_HTML = (
    markdown.markdown(LOGIN_FOOTER_TEXT) if LOGIN_FOOTER_TEXT.strip() else ""
)

if not COOKIE_SECURE:
    print(
        "WARNING: cookie_secure is OFF. The session cookie will be sent over "
        "plain HTTP. Only use this for local/LAN-only testing."
    )

db = sqlite3.connect(DB_PATH, check_same_thread=False)
db.execute(
    "CREATE TABLE IF NOT EXISTS sessions ("
    "token TEXT PRIMARY KEY, username TEXT, created_at INTEGER)"
)
db.commit()
db_lock = threading.Lock()


def username_for_token(token):
    if not token:
        return None
    with db_lock:
        row = db.execute(
            "SELECT username FROM sessions WHERE token = ?", (token,)
        ).fetchone()
    return row[0] if row else None


def create_session(username):
    token = secrets.token_urlsafe(32)
    with db_lock:
        db.execute(
            "INSERT INTO sessions (token, username, created_at) VALUES (?, ?, ?)",
            (token, username, int(time.time())),
        )
        db.commit()
    return token


def revoke_session(token):
    with db_lock:
        db.execute("DELETE FROM sessions WHERE token = ?", (token,))
        db.commit()


def set_binary_sensor(username, state):
    slug = username.lower().replace(" ", "_")
    resp = requests.post(
        f"{CORE_API}/states/binary_sensor.gatekeeper_{slug}",
        headers={
            "Authorization": f"Bearer {SUPERVISOR_TOKEN}",
            "Content-Type": "application/json",
        },
        json={
            "state": state,
            "attributes": {"friendly_name": f"Gatekeeper ({username})"},
        },
        timeout=10,
    )
    resp.raise_for_status()


def fire_and_reset(username, hold_seconds=3):
    """Turn the sensor on, then back off after a few seconds so the
    automation's state trigger can fire again on the next visit.
    Returns True if the initial "on" call succeeded."""
    try:
        set_binary_sensor(username, "on")
    except Exception as exc:  # noqa: BLE001
        logger.error("Failed to set binary_sensor for %s: %s", username, exc)
        return False

    def _reset():
        time.sleep(hold_seconds)
        try:
            set_binary_sensor(username, "off")
        except Exception as exc:  # noqa: BLE001
            logger.error("Failed to reset binary_sensor for %s: %s", username, exc)

    threading.Thread(target=_reset, daemon=True).start()
    return True


LOGIN_HTML = """<!doctype html>
<html lang="nl">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Inloggen</title>
  <style>
    body {{ font-family: sans-serif; display: flex; justify-content: center;
            align-items: center; height: 100vh; margin: 0; background: #f2f2f2; }}
    form {{ background: white; padding: 2rem; border-radius: 8px;
            box-shadow: 0 2px 8px rgba(0,0,0,0.1); display: flex;
            flex-direction: column; gap: 0.75rem; width: 250px; }}
    input {{ padding: 0.5rem; font-size: 1rem; }}
    button {{ padding: 0.6rem; font-size: 1rem; cursor: pointer; }}
    .error {{ color: #b00020; font-size: 0.9rem; }}
    .footer {{ margin-top: 1rem; width: 250px; font-size: 0.85rem;
               color: #555; text-align: center; }}
    .footer a {{ color: #555; }}
    .remember {{ display: flex; align-items: center; gap: 0.4rem;
                 font-size: 0.9rem; }}
  </style>
</head>
<body>
  <div>
    <form method="post">
      {error}
      <input name="username" placeholder="Gebruikersnaam" autofocus required>
      <input name="password" type="password" placeholder="Wachtwoord" required>
      <label class="remember">
        <input type="checkbox" name="remember"> Onthoud mij
      </label>
      <button type="submit">Inloggen</button>
    </form>
    <div class="footer">{footer}</div>
  </div>
</body>
</html>"""

RESULT_HTML = """<!doctype html>
<html lang="nl">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{title}</title>
  <style>
    body {{ font-family: sans-serif; display: flex; justify-content: center;
            align-items: center; height: 100vh; margin: 0; background: #f2f2f2; }}
    .box {{ background: white; padding: 2rem; border-radius: 8px;
            box-shadow: 0 2px 8px rgba(0,0,0,0.1); text-align: center; }}
    .box.error {{ border: 1px solid #b00020; }}
  </style>
</head>
<body>
  <div class="box{error_class}"><p>{message}</p></div>
</body>
</html>"""


def render_result(success):
    if success:
        return RESULT_HTML.format(title="Gelukt", message=SUCCESS_MESSAGE, error_class="")
    return RESULT_HTML.format(title="Fout", message=ERROR_MESSAGE, error_class=" error")


@app.route("/", methods=["GET", "POST"])
@app.route("/trigger", methods=["GET", "POST"])
def trigger():
    token = request.cookies.get(COOKIE_NAME)
    username = username_for_token(token)
    stale_cookie = False

    if username and username not in USERS:
        logger.warning(
            "Rejected session for removed user '%s' (%s) — revoking token",
            username, request.remote_addr,
        )
        revoke_session(token)
        username = None
        stale_cookie = True

    if username:
        ok = fire_and_reset(username)
        if ok:
            logger.info(
                "Triggered by '%s' via saved session (%s)",
                username, request.remote_addr,
            )
        return render_result(ok), (200 if ok else 502)

    if request.method == "GET":
        resp = make_response(LOGIN_HTML.format(error="", footer=LOGIN_FOOTER_HTML))
        if stale_cookie:
            resp.delete_cookie(COOKIE_NAME)
        return resp

    form_username = request.form.get("username", "").strip()
    form_password = request.form.get("password", "")

    if USERS.get(form_username) != form_password:
        logger.warning(
            "Failed login attempt for username '%s' from %s",
            form_username, request.remote_addr,
        )
        error = '<p class="error">Fout wachtwoord</p>'
        resp = make_response(LOGIN_HTML.format(error=error, footer=LOGIN_FOOTER_HTML), 401)
        if stale_cookie:
            resp.delete_cookie(COOKIE_NAME)
        return resp

    new_token = create_session(form_username)
    ok = fire_and_reset(form_username)
    if ok:
        logger.info(
            "Triggered by '%s' via new login (%s, remember_me=%s)",
            form_username, request.remote_addr,
            request.form.get("remember") == "on",
        )

    remember_me = request.form.get("remember") == "on"
    resp = make_response(render_result(ok), 200 if ok else 502)
    resp.set_cookie(
        COOKIE_NAME,
        new_token,
        max_age=(SESSION_DAYS * 86400) if remember_me else None,
        httponly=True,
        secure=COOKIE_SECURE,
        samesite="Lax",
    )
    return resp


@app.route("/healthz")
def healthz():
    return "ok"


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8099)
