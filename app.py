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
import time
import urllib.request
from functools import wraps
from pathlib import Path
from typing import Any

from flask import (
    Flask,
    Response,
    flash,
    jsonify,
    redirect,
    render_template_string,
    request,
    session,
    url_for,
)

from i18n import (
    COUNTRY_KEYS,
    DEFAULT_LANGUAGE,
    SUPPORTED_LANGUAGES,
    TRANSLATIONS,
    country_label,
    localized_country_groups,
    normalize_language,
    translate,
)
from validation import DeviceValidationError, validate_device


def read_app_version() -> str:
    try:
        version = Path(__file__).with_name("VERSION").read_text(encoding="utf-8").strip()
    except OSError:
        return "development"
    return version or "development"


APP_VERSION = read_app_version()
CONFIG_PATH = Path(os.environ.get("VPN_CONFIG_PATH", "/var/lib/vpn-control/config.json"))
HEALTH_PATH = Path(os.environ.get("VPN_HEALTH_PATH", "/run/vpn-control/gateway-health.json"))
WEB_USER = os.environ.get("VPN_WEB_USER", "admin")
WEB_PASSWORD = os.environ.get("VPN_WEB_PASSWORD", "")
SECRET_KEY = os.environ.get("VPN_WEB_SECRET_KEY", "")
COMMAND_TIMEOUT = int(os.environ.get("VPN_COMMAND_TIMEOUT", "90"))

if not WEB_PASSWORD:
    raise RuntimeError("VPN_WEB_PASSWORD is not configured")
if not SECRET_KEY:
    raise RuntimeError("VPN_WEB_SECRET_KEY is not configured")

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
<html lang="{{ language }}">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>VPN Control</title>
  <style>
    :root { color-scheme: dark; font-family: system-ui, sans-serif; }
    body { margin: 0; background:#111827; color:#e5e7eb; }
    main { max-width: 980px; margin: 0 auto; padding: 24px; }
    h1 { margin:0 0 4px; }
    .header { display:flex; justify-content:space-between; align-items:flex-start; gap:16px; }
    .sub { color:#9ca3af; margin-top:0; }
    .language-switch { display:flex; gap:6px; padding-top:3px; }
    .language-switch a {
      color:#d1d5db; text-decoration:none; border:1px solid #4b5563;
      border-radius:8px; padding:7px 10px; font-size:13px; font-weight:700;
    }
    .language-switch a.active { background:#2563eb; border-color:#2563eb; color:white; }
    .grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(290px,1fr)); gap:16px; }
    .card { background:#1f2937; border:1px solid #374151; border-radius:14px; padding:18px; }
    label { display:block; margin:10px 0 6px; color:#d1d5db; }
    input, select, button {
      width:100%; box-sizing:border-box; border-radius:9px; border:1px solid #4b5563;
      padding:11px; font-size:15px;
    }
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
    .status-grid { display:grid; grid-template-columns:auto 1fr; gap:8px 14px; align-items:center; }
    .pill { display:inline-block; border-radius:999px; padding:3px 9px; font-size:12px; font-weight:700; }
    .healthy { background:#14532d; color:#bbf7d0; }
    .protected { background:#713f12; color:#fef08a; }
    .degraded, .stale, .unknown { background:#7f1d1d; color:#fecaca; }
    .yes { color:#86efac; } .no { color:#fca5a5; }
    footer { color:#6b7280; font-size:12px; margin-top:18px; text-align:center; }
    @media (max-width:600px) {
      .header { flex-direction:column; }
      .language-switch { align-self:flex-end; }
    }
  </style>
</head>
<body>
<main>
  <header class="header">
    <div>
      <h1>VPN Control Panel</h1>
      <p class="sub">{{ tr('subtitle') }}</p>
    </div>
    <nav class="language-switch" aria-label="Language">
      <a href="{{ url_for('set_language', language='en') }}"
         class="{{ 'active' if language == 'en' else '' }}"
         lang="en" hreflang="en">EN</a>
      <a href="{{ url_for('set_language', language='el') }}"
         class="{{ 'active' if language == 'el' else '' }}"
         lang="el" hreflang="el">ΕΛ</a>
    </nav>
  </header>

  {% for message in get_flashed_messages() %}
    <div class="flash">{{ message }}</div>
  {% endfor %}

  <div class="grid">
    <section class="card">
      <h2>{{ tr('exit_country') }}</h2>
      <form method="post" action="{{ url_for('set_country') }}">
        <input type="hidden" name="csrf" value="{{ csrf }}">
        <label for="country">{{ tr('default_country') }}</label>
        <select id="country" name="country">
          {% for group_label, country_items in country_groups %}
            <optgroup label="{{ group_label }}">
              {% for code, label in country_items %}
                <option value="{{ code }}" {% if code == config.country %}selected{% endif %}>{{ label }}</option>
              {% endfor %}
            </optgroup>
          {% endfor %}
        </select>
        <button type="submit" style="margin-top:12px">{{ tr('connect_save') }}</button>
        <p class="small muted">{{ tr('speed_note') }}</p>
      </form>
      <div class="actions">
        <form method="post" action="{{ url_for('reconnect') }}">
          <input type="hidden" name="csrf" value="{{ csrf }}">
          <button class="secondary" type="submit">{{ tr('new_server_same_country') }}</button>
        </form>
        <form method="post" action="{{ url_for('disconnect') }}">
          <input type="hidden" name="csrf" value="{{ csrf }}">
          <button class="danger" type="submit">{{ tr('disconnect') }}</button>
        </form>
      </div>
      <p class="small muted">{{ tr('disconnect_note') }}</p>
    </section>

    <section class="card">
      <h2>NordVPN</h2>
      <p><strong>{{ tr('public_ip') }}:</strong> {{ public_ip }}</p>
      <p><strong>{{ tr('country_check') }}:</strong> {{ public_country }}</p>
      <pre>{{ nord_status }}</pre>
      <form method="get"><button class="secondary" type="submit">{{ tr('refresh') }}</button></form>
    </section>

    <section class="card">
      <h2>{{ tr('gateway_health') }}</h2>
      <p><span class="pill {{ health.status_class }}">{{ health.status_label }}</span></p>
      <div class="status-grid">
        <span>{{ tr('heartbeat') }}</span><strong>{{ health.age_label }}</strong>
        <span>{{ tr('nordlynx') }}</span>
        <strong class="{{ 'yes' if health.vpn_ready else 'no' }}">
          {{ tr('ready') if health.vpn_ready else tr('unavailable') }}
        </strong>
        <span>{{ tr('policy_rules') }}</span>
        <strong>{{ health.policy_rules_actual }}/{{ health.policy_rules_expected }}</strong>
        <span>{{ tr('fail_closed_route') }}</span>
        <strong class="{{ 'yes' if health.fail_closed_present else 'no' }}">
          {{ tr('present') if health.fail_closed_present else tr('missing') }}
        </strong>
        <span>{{ tr('nftables_filter_nat') }}</span>
        <strong class="{{ 'yes' if health.nft_filter_present and health.nft_nat_present else 'no' }}">
          {{ tr('present') if health.nft_filter_present and health.nft_nat_present else tr('missing') }}
        </strong>
        <span>{{ tr('dns_proxy') }}</span>
        <strong class="{{ 'yes' if health.dns_service_active and health.dns_rule_present else 'no' }}">
          {{ tr('protected') if health.dns_service_active and health.dns_rule_present else tr('unavailable') }}
        </strong>
      </div>
      <p class="small muted">{{ tr('managed_dns') }}: <code>{{ config.lan_ip }}</code></p>
    </section>
  </div>

  <section class="card" style="margin-top:16px">
    <h2>{{ tr('devices_via_vpn') }}</h2>
    <table>
      <thead><tr><th>{{ tr('name') }}</th><th>IPv4</th><th></th></tr></thead>
      <tbody>
        {% for device in config.devices %}
          <tr>
            <td>{{ device.name }}</td>
            <td><code>{{ device.ip }}</code></td>
            <td>
              <form method="post" action="{{ url_for('remove_device') }}">
                <input type="hidden" name="csrf" value="{{ csrf }}">
                <input type="hidden" name="ip" value="{{ device.ip }}">
                <button class="danger" type="submit">{{ tr('remove') }}</button>
              </form>
            </td>
          </tr>
        {% else %}
          <tr><td colspan="3" class="muted">{{ tr('no_devices') }}</td></tr>
        {% endfor %}
      </tbody>
    </table>

    <form method="post" action="{{ url_for('add_device') }}" style="margin-top:16px">
      <input type="hidden" name="csrf" value="{{ csrf }}">
      <div class="grid">
        <div>
          <label for="name">{{ tr('device_name') }}</label>
          <input id="name" name="name" maxlength="40" required
                 placeholder="{{ tr('device_name_placeholder') }}">
        </div>
        <div>
          <label for="ip">IPv4</label>
          <input id="ip" name="ip" required inputmode="decimal" placeholder="192.168.1.50">
        </div>
      </div>
      <button type="submit" style="margin-top:12px">{{ tr('add_device') }}</button>
    </form>
    <p class="small muted">{{ device_config_hint }}</p>
  </section>

  <footer>VPN Control {{ app_version }}</footer>
</main>
</body>
</html>
"""


def current_language() -> str:
    saved = session.get("language")
    if saved in SUPPORTED_LANGUAGES:
        return str(saved)
    browser_match = request.accept_languages.best_match(SUPPORTED_LANGUAGES)
    return normalize_language(browser_match or DEFAULT_LANGUAGE)


def tr_for(language: str):
    def tr(key: str, **values: Any) -> str:
        return translate(language, key, **values)

    return tr


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
            language = current_language()
            return Response(
                translate(language, "authentication_required"),
                401,
                {"WWW-Authenticate": 'Basic realm="VPN Control"'},
            )
        return view(*args, **kwargs)

    return wrapped


def csrf_token() -> str:
    token = session.get("csrf")
    if not token:
        token = secrets.token_urlsafe(32)
        session["csrf"] = token
    return token


def validate_csrf(language: str) -> None:
    supplied = request.form.get("csrf", "")
    expected = session.get("csrf", "")
    if not expected or not hmac.compare_digest(supplied, expected):
        raise ValueError(translate(language, "invalid_csrf"))


def load_config() -> dict[str, Any]:
    with config_lock:
        with CONFIG_PATH.open("r", encoding="utf-8") as handle:
            return json.load(handle)


def save_config(config: dict[str, Any]) -> None:
    CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
    with config_lock:
        fd, tmp_name = tempfile.mkstemp(
            prefix=".config-",
            suffix=".json",
            dir=str(CONFIG_PATH.parent),
            text=True,
        )
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


def run_nordvpn(
    *args: str,
    timeout: int = COMMAND_TIMEOUT,
    language: str = DEFAULT_LANGUAGE,
) -> tuple[bool, str]:
    try:
        completed = subprocess.run(
            ["nordvpn", *args],
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        return False, translate(language, "nordvpn_timeout")

    output = "\n".join(
        part.strip() for part in (completed.stdout, completed.stderr) if part.strip()
    )
    return completed.returncode == 0, output or f"Exit code: {completed.returncode}"


def fetch_text(url: str, language: str) -> str:
    try:
        req = urllib.request.Request(url, headers={"User-Agent": f"vpn-control/{APP_VERSION}"})
        with urllib.request.urlopen(req, timeout=8) as response:
            return response.read(128).decode("utf-8", errors="replace").strip()
    except Exception:
        return translate(language, "unavailable")


def load_gateway_health(config: dict[str, Any], language: str) -> dict[str, Any]:
    default = {
        "status": "unknown",
        "status_class": "unknown",
        "status_label": translate(language, "status_unknown"),
        "age_label": translate(language, "no_heartbeat"),
        "vpn_ready": False,
        "policy_rules_actual": 0,
        "policy_rules_expected": len(config.get("devices", [])) + 1,
        "fail_closed_present": False,
        "nft_filter_present": False,
        "nft_nat_present": False,
        "dns_service_active": False,
        "dns_rule_present": False,
    }

    try:
        with HEALTH_PATH.open("r", encoding="utf-8") as handle:
            health = json.load(handle)
    except (OSError, json.JSONDecodeError):
        return default

    updated_epoch = int(health.get("updated_epoch", 0))
    age = max(0, int(time.time()) - updated_epoch) if updated_epoch else 999999
    stale_after = max(20, int(config.get("check_interval", 5)) * 4)
    stale = age > stale_after

    status = str(health.get("status", "unknown"))
    if stale:
        status_class = "stale"
        status_label = translate(language, "status_stale")
    elif status == "healthy":
        status_class = "healthy"
        status_label = translate(language, "status_healthy")
    elif status == "fail-closed":
        status_class = "protected"
        status_label = translate(language, "status_fail_closed")
    else:
        status_class = "degraded"
        status_label = translate(language, "status_degraded")

    default.update(health)
    default.update(
        {
            "status_class": status_class,
            "status_label": status_label,
            "age_label": (
                translate(language, "seconds_ago", seconds=age)
                if updated_epoch
                else translate(language, "no_heartbeat")
            ),
            "stale": stale,
        }
    )
    return default


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
    language = current_language()
    config = load_config()
    _, status_output = run_nordvpn("status", timeout=15, language=language)
    return render_template_string(
        PAGE,
        config=config,
        country_groups=localized_country_groups(language),
        nord_status=status_output,
        public_ip=fetch_text("https://api.ipify.org", language),
        public_country=fetch_text("https://ipinfo.io/country", language),
        health=load_gateway_health(config, language),
        csrf=csrf_token(),
        app_version=APP_VERSION,
        language=language,
        tr=tr_for(language),
        device_config_hint=translate(
            language,
            "device_config_hint",
            lan_ip=config["lan_ip"],
            lan_net=config["lan_net"],
        ),
    )


@app.get("/language/<language>")
@require_auth
def set_language(language: str):
    session["language"] = normalize_language(language)
    return redirect(url_for("index"))


@app.get("/healthz")
@require_auth
def healthz():
    language = current_language()
    config = load_config()
    health = load_gateway_health(config, language)
    response_code = 200 if health.get("status_class") in {"healthy", "protected"} else 503
    return jsonify(health), response_code


@app.post("/country")
@require_auth
def set_country():
    language = current_language()
    try:
        validate_csrf(language)
        code = request.form.get("country", "").lower()
        if code not in COUNTRY_KEYS:
            raise ValueError(translate(language, "unsupported_country"))

        ok_connect, output_connect = run_nordvpn("connect", code, language=language)
        if not ok_connect:
            raise RuntimeError(
                translate(language, "connection_failed", output=output_connect)
            )

        ok_auto, output_auto = run_nordvpn(
            "set", "autoconnect", "on", code, language=language
        )
        config = load_config()
        config["country"] = code
        save_config(config)
        label = country_label(language, code)

        if ok_auto:
            flash(translate(language, "connected_autoconnect_updated", country=label))
        else:
            flash(
                translate(
                    language,
                    "connected_autoconnect_failed",
                    country=label,
                    output=output_auto,
                )
            )
    except Exception as exc:
        flash(str(exc))
    return redirect(url_for("index"))


@app.post("/reconnect")
@require_auth
def reconnect():
    language = current_language()
    try:
        validate_csrf(language)
        config = load_config()
        code = config.get("country", "gr")
        if code not in COUNTRY_KEYS:
            raise ValueError(translate(language, "saved_country_invalid"))
        ok, output = run_nordvpn("connect", code, language=language)
        if not ok:
            raise RuntimeError(output)
        flash(
            translate(
                language,
                "reconnected_new_server",
                country=country_label(language, code),
            )
        )
    except Exception as exc:
        flash(str(exc))
    return redirect(url_for("index"))


@app.post("/disconnect")
@require_auth
def disconnect():
    language = current_language()
    try:
        validate_csrf(language)
        ok, output = run_nordvpn("disconnect", timeout=30, language=language)
        if not ok:
            raise RuntimeError(output)
        flash(translate(language, "vpn_disconnected"))
    except Exception as exc:
        flash(str(exc))
    return redirect(url_for("index"))


@app.post("/devices/add")
@require_auth
def add_device():
    language = current_language()
    try:
        validate_csrf(language)
        config = load_config()
        device = validate_device(
            request.form.get("name", ""),
            request.form.get("ip", ""),
            config,
        )
        devices = config.setdefault("devices", [])
        devices.append(device)
        devices.sort(key=lambda item: tuple(int(part) for part in item["ip"].split(".")))
        save_config(config)
        flash(
            translate(
                language,
                "device_added",
                name=device["name"],
                ip=device["ip"],
            )
        )
    except DeviceValidationError as exc:
        flash(translate(language, exc.message_key, **exc.message_values))
    except ValueError as exc:
        flash(str(exc))
    return redirect(url_for("index"))


@app.post("/devices/remove")
@require_auth
def remove_device():
    language = current_language()
    try:
        validate_csrf(language)
        address = str(ipaddress.ip_address(request.form.get("ip", "").strip()))
        config = load_config()
        before = len(config.get("devices", []))
        config["devices"] = [
            item for item in config.get("devices", []) if item.get("ip") != address
        ]
        if len(config["devices"]) == before:
            raise ValueError(translate(language, "device_not_found"))
        save_config(config)
        flash(translate(language, "device_removed", ip=address))
    except ValueError as exc:
        flash(str(exc))
    return redirect(url_for("index"))
