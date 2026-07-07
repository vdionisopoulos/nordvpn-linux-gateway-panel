import json
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


def test_dns_is_mandatory_and_not_exposed_as_toggle() -> None:
    config = json.loads((REPO_ROOT / "config.example.json").read_text(encoding="utf-8"))
    gateway_source = (REPO_ROOT / "gateway.sh").read_text(encoding="utf-8")
    installer_source = (REPO_ROOT / "installer-lib.sh").read_text(encoding="utf-8")

    assert "dns_enabled" not in config
    assert config["dns_user"] == "vpn-dns"
    assert config["dns_rule_priority"] == 9999
    assert len(config["dns_upstreams"]) >= 1

    assert "DNS_ENABLED" not in gateway_source
    assert ".dns_enabled = true" not in installer_source
    assert "del(.dns_enabled)" in installer_source
