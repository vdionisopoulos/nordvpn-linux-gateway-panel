import json
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


def test_dns_is_mandatory_and_not_exposed_as_toggle() -> None:
    config = json.loads((REPO_ROOT / "config.example.json").read_text(encoding="utf-8"))

    assert "dns_enabled" not in config
    assert config["dns_user"] == "vpn-dns"
    assert config["dns_rule_priority"] == 9999
    assert len(config["dns_upstreams"]) >= 1

    for path in ("gateway.sh", "installer-lib.sh"):
        source = (REPO_ROOT / path).read_text(encoding="utf-8")
        assert "dns_enabled" not in source
