from __future__ import annotations

import pytest

from validation import DeviceValidationError, validate_device


@pytest.fixture
def config() -> dict:
    return {
        "lan_net": "192.168.1.0/24",
        "lan_ip": "192.168.1.2",
        "devices": [{"name": "Existing", "ip": "192.168.1.50"}],
    }


def test_valid_device_is_normalized(config: dict) -> None:
    assert validate_device("  Living Room TV  ", "192.168.1.60", config) == {
        "name": "Living Room TV",
        "ip": "192.168.1.60",
    }


@pytest.mark.parametrize("name", ["", "   ", "x" * 41])
def test_invalid_name(config: dict, name: str) -> None:
    with pytest.raises(DeviceValidationError):
        validate_device(name, "192.168.1.60", config)


@pytest.mark.parametrize(
    "ip_text",
    [
        "not-an-ip",
        "2001:db8::1",
        "10.0.0.5",
        "192.168.1.0",
        "192.168.1.255",
        "192.168.1.2",
        "192.168.1.50",
    ],
)
def test_invalid_addresses(config: dict, ip_text: str) -> None:
    with pytest.raises(DeviceValidationError):
        validate_device("Device", ip_text, config)
