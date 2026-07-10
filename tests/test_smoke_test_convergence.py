from pathlib import Path


SMOKE_TEST = Path(__file__).resolve().parents[1] / "scripts" / "smoke-test.sh"


def test_smoke_test_waits_for_connected_gateway_convergence() -> None:
    content = SMOKE_TEST.read_text(encoding="utf-8")

    wait_call = "if wait_for_initial_gateway_state; then"
    first_service_check = 'check "tv-vpn-gateway.service is active"'

    assert "INITIAL_CONVERGENCE_TIMEOUT" in content
    assert "initial_gateway_state_ready()" in content
    assert '.status == "healthy"' in content
    assert ".vpn_default_present == true" in content
    assert content.index(wait_call) < content.index(first_service_check)
