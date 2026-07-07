#!/usr/bin/env python3
from __future__ import annotations

import hmac
import ipaddress
import json
import os
import secrets
import subprocess
import tempfile
import threading
import urllib.request
from functools import wraps
from pathlib import Path
from typing import Any

from flask import Flask, Response, flash, redirect, render_template_string, request, session, url_for

CONFIG_PATH = Path(os.environ.get("VPN_CONFIG_PATH", "/var/lib/vpn-control/config.json"))
WEB_USER = os.environ.get("VPN_WEB_USER", "admin")
WEB_PASSWORD = os.environ.get("VPN_WEB_PASSWORD", "")
SECRET_KEY = os.environ.get("VPN_WEB_SECRET_KEY", "")
COMMAND_TIMEOUT = int(os.environ.get("VPN_COMMAND_TIMEOUT", "90"))

if not WEB_PASSWORD:
    raise RuntimeError("VPN_WEB_PASSWORD is not configured")
if not SECRET_KEY:
    raise RuntimeError("VPN_WEB_SECRET_KEY is not configured")

COUNTRY_GROUPS = [
    (
        "Κοντινές / συνήθως χαμηλότερο latency",
        [
            ("gr", "Ελλάδα"),
            ("bg", "Βουλγαρία"),
            ("rs", "Σερβία"),
            ("ro", "Ρουμανία"),
            ("it", "Ιταλία"),
            ("at", "Αυστρία"),
            ("de", "Γερμανία"),
        ],
    ),
    (
        "Δυτική Ευρώπη",
        [
            ("es", "Ισπανία"),
            ("fr", "Γαλλία"),
            ("nl", "Ολλανδία"),
            ("uk", "Ηνωμένο Βασίλειο"),
        ],
    ),
    (
        "Αμερική / Ασία",
        [
            ("us", "Ηνωμένες Πολιτείες"),
            ("kr", "Νότια Κορέα"),
            ("jp", "Ιαπωνία"),
        ],
    ),
]

COUNTRIES = {
    code: label
    for _, country_items in COUNTRY_GROUPS
    for code, label in country_items
}

app = Flask(__name__)
app.secret_key = SECRET_KEY
app.config.update(
    SESSION_COOKIE_HTTPONLY=True,
    SESSION_COOKIE_SAMESITE="Strict",
    MAX_CONTENT_LENGTH=16 * 1024,
)
config_lock = threading.Lock()

PAGE = r"""
<!doctype html>
<html lang="el">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>VPN Control</title>
  <style>
    :root { color-scheme: dark; font-family: system-ui, sans-serif; }
    body { margin: 0; background:#111827; color:#e5e7eb; }
    main { max-width: 920px; margin: 0 auto; padding: 24px; }
    h1 { margin-bottom: 4px; }
    .sub { color:#9ca3af; margin-top:0; }
    .grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(290px,1fr)); gap:16px; }
    .card { background:#1f2937; border:1px solid #374151; border-radius:14px; padding:18px; }
    label { display:block; margin:10px 0 6px; color:#d1d5db; }
    input, select, button { width:100%; box-sizing:border-box; border-radius:9px; border:1px solid #4b5563; padding:11px; font-size:15px; }
    input, select { background:#111827; color:#f9fafb; }
    button { background:#2563eb; color:white; cursor:pointer; font-weight:700; }
    button.secondary { background:#374151; }
    button.danger { background:#991b1b; width:auto; padding:7px 11px; }
    table { width:100%; border-collapse:collapse; }
    th, td { text-align:left; padding:10px 7px; border-bottom:1px solid #374151; }
    code, pre { background:#111827; border-radius:7px; }
    pre { white-space:pre-wrap; padding:12px; overflow:auto; }
    .muted { color:#9ca3af; }
    .flash { padding:11px; margin:0 0 14px; border-radius:9px; background:#334155; }
    .actions { display:flex; gap:10px; margin-top:12px; }
    .actions form { flex:1; }
    .small { font-size:13px; }
  </style>
</head>
<body>
<main>
  <h1>VPN Control Panel</h1>
  <p class="sub">Διαχείριση συσκευών LAN μέσω NordLynx</p>

  {% for message in get_flashed_messages() %}
    <div class="flash">{{ message }}</div>
  {% endfor %}

  <div class="grid">
    <section class="card">
      <h2>Χώρα εξόδου</h2>
      <form method="post" action="{{ url_for('set_country') }}">
        <input type="hidden" name="csrf" value="{{ csrf }}">
        <label for="country">Προεπιλεγμένη χώρα</label>
        <select id="country" name="country">
          {% for group_label, country_items in country_groups %}
            <optgroup label="{{ group_label }}">
              {% for code, label in country_items %}
                <option value="{{ code }}" {% if code == config.country %}selected{% endif %}>{{ label }}</option>
              {% endfor %}
            </optgroup>
          {% endfor %}
        </select>
        <button type="submit" style="margin-top:12px">Σύνδεση και αποθήκευση</button>
        <p class="small muted">Οι κοντινότερες χώρες συνήθως δίνουν μικρότερο latency. Η πραγματική ταχύτητα εξαρτάται και από φόρτο server και διαδρομή παρόχου.</p>
      </form>
      <div class="actions">
        <form method="post" action="{{ url_for('reconnect') }}">
          <input type="hidden" name="csrf" value="{{ csrf }}">
          <button class="secondary" type="submit">Νέος server ίδιας χώρας</button>
        </form>
        <form method="post" action="{{ url_for('disconnect') }}">
          <input type="hidden" name="csrf" value="{{ csrf }}">
          <button class="danger" type="submit">Disconnect</button>
        </form>
      </div>
      <p class="small muted">Το disconnect είναι fail-closed: οι δηλωμένες συσκευές χάνουν Internet μέχρι να επανέλθει το VPN.</p>
    </section>

    <section class="card">
      <h2>Κατάσταση</h2>
      <p><strong>Public IP:</strong> {{ public_ip }}</p>
      <p><strong>Country check:</strong> {{ public_country }}</p>
      <pre>{{ nord_status }}</pre>
      <form method="get"><button class="secondary" type="submit">Ανανέωση</button></form>
    </section>
  </div>

  <section class="card" style="margin-top:16px">
    <h2>Συσκευές μέσω VPN</h2>
    <table>
      <thead><tr><th>Όνομα</th><th>IPv4</th><th></th></tr></thead>
      <tbody>
        {% for device in config.devices %}
          <tr>
            <td>{{ device.name }}</td>
            <td><code>{{ device.ip }}</code></td>
            <td>
              <form method="post" action="{{ url_for('remove_device') }}">
                <input type="hidden" name="csrf" value="{{ csrf }}">
                <input type="hidden" name="ip" value="{{ device.ip }}">
                <button class="danger" type="submit">Αφαίρεση</button>
              </form>
            </td>
          </tr>
        {% else %}
          <tr><td colspan="3" class="muted">Δεν υπάρχουν συσκευές.</td></tr>
        {% endfor %}
      </tbody>
    </table>

    <form method="post" action="{{ url_for('add_device') }}" style="margin-top:16px">
      <input type="hidden" name="csrf" value="{{ csrf }}">
      <div class="grid">
        <div>
          <label for="name">Όνομα συσκευής</label>
          <input id="name" name="name" maxlength="40" required placeholder="π.χ. Apple TV">
        </div>
        <div>
          <label for="ip">IPv4</label>
          <input id="ip" name="ip" required inputmode="decimal" placeholder="192.168.1.50">
        </div>
      </div>
      <button type="submit" style="margin-top:12px">Προσθήκη συσκευής</button>
    </form>
    <p class="small muted">
      Στη συσκευή βάλε Router/Gateway <code>{{ config.lan_ip }}</code> και σταθερή IP στο subnet <code>{{ config.lan_net }}</code>.
    </p>
  </section>
</main>
</body>
</html>
"""

def require_auth(view):
    @wraps(view)
    def wrapped(*args, **kwargs):
        auth = request.authorization
        valid = (
            auth is not None
            and hmac.compare_digest(auth.username or "", WEB_USER)
            and hmac.compare_digest(auth.password or "", WEB_PASSWORD)
        )
        if not valid:
            return Response("Authentication required", 401, {"WWW-Authenticate": 'Basic realm="VPN Control"'})
        return view(*args, **kwargs)
    return wrapped

def csrf_token() -> str:
    token = session.get("csrf")
    if not token:
        token = secrets.token_urlsafe(32)
        session["csrf"] = token
    return token

def validate_csrf() -> None:
    supplied = request.form.get("csrf", "")
    expected = session.get("csrf", "")
    if not expected or not hmac.compare_digest(supplied, expected):
        raise ValueError("Μη έγκυρο CSRF token. Ανανέωσε τη σελίδα.")

def load_config() -> dict[str, Any]:
    with config_lock:
        with CONFIG_PATH.open("r", encoding="utf-8") as handle:
            return json.load(handle)

def save_config(config: dict[str, Any]) -> None:
    CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
    with config_lock:
        fd, tmp_name = tempfile.mkstemp(prefix=".config-", suffix=".json", dir=str(CONFIG_PATH.parent), text=True)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                json.dump(config, handle, ensure_ascii=False, indent=2)
                handle.write("\n")
                handle.flush()
                os.fsync(handle.fileno())
            os.chmod(tmp_name, 0o640)
            os.replace(tmp_name, CONFIG_PATH)
        finally:
            if os.path.exists(tmp_name):
                os.unlink(tmp_name)

def run_nordvpn(*args: str, timeout: int = COMMAND_TIMEOUT) -> tuple[bool, str]:
    try:
        completed = subprocess.run(
            ["nordvpn", *args],
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        return False, "Το nordvpn command έληξε λόγω timeout."
    output = "\n".join(part.strip() for part in (completed.stdout, completed.stderr) if part.strip())
    return completed.returncode == 0, output or f"Exit code: {completed.returncode}"

def fetch_text(url: str) -> str:
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "vpn-control/1.0"})
        with urllib.request.urlopen(req, timeout=8) as response:
            return response.read(128).decode("utf-8", errors="replace").strip()
    except Exception:
        return "Unavailable"

@app.after_request
def security_headers(response):
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Referrer-Policy"] = "no-referrer"
    response.headers["Content-Security-Policy"] = (
        "default-src 'self'; style-src 'unsafe-inline'; "
        "form-action 'self'; frame-ancestors 'none'"
    )
    response.headers["Cache-Control"] = "no-store"
    return response

@app.get("/")
@require_auth
def index():
    config = load_config()
    _, status_output = run_nordvpn("status", timeout=15)
    return render_template_string(
        PAGE,
        config=config,
        countries=COUNTRIES,
        country_groups=COUNTRY_GROUPS,
        nord_status=status_output,
        public_ip=fetch_text("https://api.ipify.org"),
        public_country=fetch_text("https://ipinfo.io/country"),
        csrf=csrf_token(),
    )

@app.post("/country")
@require_auth
def set_country():
    try:
        validate_csrf()
        code = request.form.get("country", "").lower()
        if code not in COUNTRIES:
            raise ValueError("Μη υποστηριζόμενη χώρα.")

        ok_connect, output_connect = run_nordvpn("connect", code)
        if not ok_connect:
            raise RuntimeError(f"Αποτυχία σύνδεσης:\n{output_connect}")

        ok_auto, output_auto = run_nordvpn("set", "autoconnect", "on", code)
        config = load_config()
        config["country"] = code
        save_config(config)

        if ok_auto:
            flash(f"Συνδέθηκε: {COUNTRIES[code]}. Το auto-connect ενημερώθηκε.")
        else:
            flash(f"Συνδέθηκε: {COUNTRIES[code]}, αλλά απέτυχε το auto-connect: {output_auto}")
    except Exception as exc:
        flash(str(exc))
    return redirect(url_for("index"))

@app.post("/reconnect")
@require_auth
def reconnect():
    try:
        validate_csrf()
        config = load_config()
        code = config.get("country", "gr")
        if code not in COUNTRIES:
            raise ValueError("Η αποθηκευμένη χώρα δεν είναι έγκυρη.")
        ok, output = run_nordvpn("connect", code)
        if not ok:
            raise RuntimeError(output)
        flash(f"Έγινε reconnect σε νέο server: {COUNTRIES[code]}.")
    except Exception as exc:
        flash(str(exc))
    return redirect(url_for("index"))

@app.post("/disconnect")
@require_auth
def disconnect():
    try:
        validate_csrf()
        ok, output = run_nordvpn("disconnect", timeout=30)
        if not ok:
            raise RuntimeError(output)
        flash("Το VPN αποσυνδέθηκε. Οι managed συσκευές παραμένουν fail-closed.")
    except Exception as exc:
        flash(str(exc))
    return redirect(url_for("index"))

@app.post("/devices/add")
@require_auth
def add_device():
    try:
        validate_csrf()
        name = request.form.get("name", "").strip()
        ip_text = request.form.get("ip", "").strip()

        if not name or len(name) > 40:
            raise ValueError("Το όνομα πρέπει να έχει 1–40 χαρακτήρες.")

        address = ipaddress.ip_address(ip_text)
        if address.version != 4:
            raise ValueError("Απαιτείται IPv4 διεύθυνση.")

        config = load_config()
        lan_network = ipaddress.ip_network(config["lan_net"], strict=False)
        lan_ip = ipaddress.ip_address(config["lan_ip"])

        if address not in lan_network:
            raise ValueError(f"Η IP πρέπει να ανήκει στο {lan_network}.")
        if address in (lan_network.network_address, lan_network.broadcast_address, lan_ip):
            raise ValueError("Η IP είναι δεσμευμένη ή είναι η IP της VPN VM.")

        devices = config.setdefault("devices", [])
        if any(item["ip"] == str(address) for item in devices):
            raise ValueError("Η IP υπάρχει ήδη στη λίστα.")

        devices.append({"name": name, "ip": str(address)})
        devices.sort(key=lambda item: tuple(int(part) for part in item["ip"].split(".")))
        save_config(config)
        flash(f"Προστέθηκε: {name} ({address}). Εφαρμογή σε λίγα δευτερόλεπτα.")
    except Exception as exc:
        flash(str(exc))
    return redirect(url_for("index"))

@app.post("/devices/remove")
@require_auth
def remove_device():
    try:
        validate_csrf()
        ip_text = request.form.get("ip", "").strip()
        address = str(ipaddress.ip_address(ip_text))

        config = load_config()
        before = len(config.get("devices", []))
        config["devices"] = [item for item in config.get("devices", []) if item.get("ip") != address]
        if len(config["devices"]) == before:
            raise ValueError("Η συσκευή δεν βρέθηκε.")

        save_config(config)
        flash(f"Αφαιρέθηκε η συσκευή {address}. Εφαρμογή σε λίγα δευτερόλεπτα.")
    except Exception as exc:
        flash(str(exc))
    return redirect(url_for("index"))
