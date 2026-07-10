import os
import subprocess

import pytest

os.environ.setdefault("VPN_WEB_PASSWORD", "test-password")
os.environ.setdefault("VPN_WEB_SECRET_KEY", "test-secret-key")

import app as app_module  # noqa: E402


@pytest.mark.parametrize(
    ("language", "expected"),
    [
        (
            "en",
            "The NordVPN CLI is unavailable. Verify the installation and nordvpnd service.",
        ),
        (
            "el",
            "Το NordVPN CLI δεν είναι διαθέσιμο. Έλεγξε την εγκατάσταση και το nordvpnd.",
        ),
    ],
)
def test_run_nordvpn_reports_missing_cli(
    monkeypatch: pytest.MonkeyPatch,
    language: str,
    expected: str,
) -> None:
    def missing_command(*args, **kwargs):
        raise FileNotFoundError

    monkeypatch.setattr(app_module.subprocess, "run", missing_command)

    ok, message = app_module.run_nordvpn("status", language=language)

    assert ok is False
    assert message == expected


def test_run_nordvpn_reports_timeout(monkeypatch: pytest.MonkeyPatch) -> None:
    def timeout(*args, **kwargs):
        raise subprocess.TimeoutExpired(cmd=["nordvpn", "status"], timeout=1)

    monkeypatch.setattr(app_module.subprocess, "run", timeout)

    ok, message = app_module.run_nordvpn("status", timeout=1, language="en")

    assert ok is False
    assert "timed out" in message
