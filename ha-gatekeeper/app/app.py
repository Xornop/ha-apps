import hashlib
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

OPTIONS_PATH = "/data/options.json"
DB_PATH = "/data/sessions.db"
CORE_API = "http://supervisor/core/api"
SUPERVISOR_TOKEN = os.environ.get("SUPERVISOR_TOKEN", "")
COOKIE_NAME = "lt_token"


def _pw_fingerprint(password):
    return hashlib.sha256(password.encode("utf-8")).hexdigest()


NON_REMEMBER_EXPIRY_SECONDS = 12 * 3600  # server-side cap for un-remembered sessions
ROTATION_GRACE_SECONDS = 10  # old token stays valid this long after rotation


def load_options():
    with open(OPTIONS_PATH) as f:
        opts = json.load(f)
    users = {u["name"]: u["password"] for u in opts.get("users", [])}
    session_days = opts.get("session_days", 365)
    cookie_secure = opts.get("cookie_secure", True)
    success_message = opts.get("success_message", "Action triggered \u2705")
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

# Trust proxy headers for scheme/host purposes (single hop is enough for
# this, IP resolution below no longer depends on it).
app.wsgi_app = ProxyFix(app.wsgi_app, x_for=1, x_proto=1, x_host=1)


def client_ip():
    """Best-effort real visitor IP. Prefers Cloudflare's own header (set
    directly from the actual edge connection, so it doesn't depend on
    counting proxy hops). Otherwise walks X-Forwarded-For all the way back
    to its left-most (oldest / original) entry. Falls back to the direct
    connecting IP if neither header is present.

    Note: X-Forwarded-For can in principle be spoofed by a client that
    connects directly to your reverse proxy without going through
    Cloudflare, if that proxy appends to rather than replaces an existing
    header. Fine for logging/visibility; don't use this for access control."""
    if "CF-Connecting-IP" in request.headers:
        return request.headers["CF-Connecting-IP"]
    xff = request.headers.get("X-Forwarded-For")
    if xff:
        return xff.split(",")[0].strip()
    return request.remote_addr

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
    "token TEXT PRIMARY KEY, username TEXT, created_at INTEGER, "
    "expires_at INTEGER, remember INTEGER, pw_fingerprint TEXT)"
)
# Lightweight migration for installs upgrading from an earlier schema
existing_cols = {row[1] for row in db.execute("PRAGMA table_info(sessions)")}
if "expires_at" not in existing_cols:
    db.execute("ALTER TABLE sessions ADD COLUMN expires_at INTEGER")
if "remember" not in existing_cols:
    db.execute("ALTER TABLE sessions ADD COLUMN remember INTEGER")
if "pw_fingerprint" not in existing_cols:
    db.execute("ALTER TABLE sessions ADD COLUMN pw_fingerprint TEXT")
db.commit()
db_lock = threading.Lock()


def _purge_sessions_for_unknown_users():
    """Run once at startup: delete every stored session whose username
    isn't currently configured. Combined with restarting once while a user
    is absent, this guarantees old tokens are gone for good — even if no
    one visited the link during the window the user was missing."""
    with db_lock:
        if USERS:
            placeholders = ",".join("?" for _ in USERS)
            deleted = db.execute(
                f"DELETE FROM sessions WHERE username NOT IN ({placeholders})",
                tuple(USERS.keys()),
            ).rowcount
        else:
            deleted = db.execute("DELETE FROM sessions").rowcount
        db.commit()
    if deleted:
        logger.info(
            "Startup cleanup: purged %d session(s) for users no longer configured",
            deleted,
        )


_purge_sessions_for_unknown_users()


def _expiry_for(remember):
    now = int(time.time())
    if remember:
        return now + SESSION_DAYS * 86400
    return now + NON_REMEMBER_EXPIRY_SECONDS


def get_session(token):
    """Look up a token, purging expired sessions along the way.
    Returns {"username", "remember", "pw_fingerprint"} or None."""
    if not token:
        return None
    now = int(time.time())
    with db_lock:
        db.execute("DELETE FROM sessions WHERE expires_at < ?", (now,))
        row = db.execute(
            "SELECT username, remember, pw_fingerprint FROM sessions WHERE token = ?",
            (token,),
        ).fetchone()
        db.commit()
    if not row:
        return None
    username, remember, pw_fingerprint = row
    return {
        "username": username,
        "remember": bool(remember),
        "pw_fingerprint": pw_fingerprint,
    }


def create_session(username, remember):
    token = secrets.token_urlsafe(32)
    expires_at = _expiry_for(remember)
    fingerprint = _pw_fingerprint(USERS[username])
    with db_lock:
        db.execute(
            "INSERT INTO sessions "
            "(token, username, created_at, expires_at, remember, pw_fingerprint) "
            "VALUES (?, ?, ?, ?, ?, ?)",
            (token, username, int(time.time()), expires_at, int(bool(remember)), fingerprint),
        )
        db.commit()
    return token, expires_at


def rotate_session(old_token):
    """Issue a fresh token for the same session. The old token stays valid
    for ROTATION_GRACE_SECONDS to absorb near-duplicate requests, then
    expires like any other session. Returns (new_token, new_expiry, remember)
    or None if old_token wasn't a valid session."""
    now = int(time.time())
    with db_lock:
        row = db.execute(
            "SELECT username, remember, pw_fingerprint FROM sessions WHERE token = ?",
            (old_token,),
        ).fetchone()
        if not row:
            return None
        username, remember, fingerprint = row
        new_token = secrets.token_urlsafe(32)
        new_expiry = _expiry_for(bool(remember))
        db.execute(
            "INSERT INTO sessions "
            "(token, username, created_at, expires_at, remember, pw_fingerprint) "
            "VALUES (?, ?, ?, ?, ?, ?)",
            (new_token, username, now, new_expiry, remember, fingerprint),
        )
        # Never extend the old token's validity, only shorten it to the grace window
        db.execute(
            "UPDATE sessions SET expires_at = MIN(expires_at, ?) WHERE token = ?",
            (now + ROTATION_GRACE_SECONDS, old_token),
        )
        db.commit()
    return new_token, new_expiry, bool(remember)


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
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Login</title>
  <style>
    body {{ font-family: sans-serif; display: flex; flex-direction: column;
            justify-content: center; align-items: center; height: 100vh;
            margin: 0; background: #f2f2f2; gap: 1rem; }}
    form {{ background: white; padding: 2rem; border-radius: 8px;
            box-shadow: 0 2px 8px rgba(0,0,0,0.1); display: flex;
            flex-direction: column; gap: 0.75rem; width: 250px;
            box-sizing: border-box; }}
    input {{ padding: 0.5rem; font-size: 1rem; }}
    button {{ padding: 0.6rem; font-size: 1rem; cursor: pointer; }}
    .error {{ color: #b00020; font-size: 0.9rem; }}
    .footer {{ background: white; padding: 1rem 1.5rem; border-radius: 8px;
               box-shadow: 0 2px 8px rgba(0,0,0,0.1); width: 250px;
               box-sizing: border-box; font-size: 0.85rem; color: #555;
               text-align: center; }}
    .footer:empty {{ display: none; }}
    .footer a {{ color: #555; }}
    .remember {{ display: flex; align-items: center; gap: 0.4rem;
                 font-size: 0.9rem; }}
  </style>
</head>
<body>
  <form method="post">
    {error}
    <input name="username" placeholder="Username" autofocus required>
    <input name="password" type="password" placeholder="Password" required>
    <label class="remember">
      <input type="checkbox" name="remember"> Remember me
    </label>
    <button type="submit">Log in</button>
  </form>
  <div class="footer">{footer}</div>
</body>
</html>"""

RESULT_HTML = """<!doctype html>
<html lang="en">
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
        return RESULT_HTML.format(title="Success", message=SUCCESS_MESSAGE, error_class="")
    return RESULT_HTML.format(title="Error", message=ERROR_MESSAGE, error_class=" error")


@app.route("/", methods=["GET", "POST"])
@app.route("/trigger", methods=["GET", "POST"])
def trigger():
    token = request.cookies.get(COOKIE_NAME)
    session = get_session(token)
    username = session["username"] if session else None
    stale_cookie = False

    if username and username not in USERS:
        logger.warning(
            "Rejected session for removed user '%s' (%s) — revoking token",
            username, client_ip(),
        )
        revoke_session(token)
        username = None
        stale_cookie = True
    elif username and session["pw_fingerprint"] != _pw_fingerprint(USERS[username]):
        logger.warning(
            "Rejected session for '%s' (%s) — password changed, revoking token",
            username, client_ip(),
        )
        revoke_session(token)
        username = None
        stale_cookie = True

    if username:
        rotated = rotate_session(token)
        ok = fire_and_reset(username)
        if ok:
            logger.info(
                "Triggered by '%s' via saved session (%s)",
                username, client_ip(),
            )
        resp = make_response(render_result(ok), 200 if ok else 502)
        if rotated:
            new_token, new_expiry, remember = rotated
            resp.set_cookie(
                COOKIE_NAME,
                new_token,
                max_age=(new_expiry - int(time.time())) if remember else None,
                httponly=True,
                secure=COOKIE_SECURE,
                samesite="Lax",
            )
        return resp

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
            form_username, client_ip(),
        )
        error = '<p class="error">Incorrect password</p>'
        resp = make_response(LOGIN_HTML.format(error=error, footer=LOGIN_FOOTER_HTML), 401)
        if stale_cookie:
            resp.delete_cookie(COOKIE_NAME)
        return resp

    remember_me = request.form.get("remember") == "on"
    new_token, expires_at = create_session(form_username, remember_me)
    ok = fire_and_reset(form_username)
    if ok:
        logger.info(
            "Triggered by '%s' via new login (%s, remember_me=%s)",
            form_username, client_ip(), remember_me,
        )

    resp = make_response(render_result(ok), 200 if ok else 502)
    resp.set_cookie(
        COOKIE_NAME,
        new_token,
        max_age=(expires_at - int(time.time())) if remember_me else None,
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
