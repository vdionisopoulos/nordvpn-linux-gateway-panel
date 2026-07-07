import base64
import os

os.environ.setdefault("VPN_WEB_PASSWORD", "test-password")
os.environ.setdefault("VPN_WEB_SECRET_KEY", "test-secret-key")

from app import app, current_language  # noqa: E402


def authorization_header() -> dict[str, str]:
    token = base64.b64encode(b"admin:test-password").decode("ascii")
    return {"Authorization": f"Basic {token}"}


def test_browser_language_is_used_when_no_preference_is_saved() -> None:
    with app.test_request_context("/", headers={"Accept-Language": "el,en;q=0.8"}):
        assert current_language() == "el"


def test_unsupported_browser_language_falls_back_to_english() -> None:
    with app.test_request_context("/", headers={"Accept-Language": "fr"}):
        assert current_language() == "en"


def test_language_route_persists_user_choice() -> None:
    client = app.test_client()

    response = client.get("/language/el", headers=authorization_header())

    assert response.status_code == 302
    with client.session_transaction() as saved_session:
        assert saved_session["language"] == "el"
