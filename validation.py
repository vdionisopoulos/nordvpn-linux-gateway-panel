from __future__ import annotations

import ipaddress
from typing import Any


class DeviceValidationError(ValueError):
    """Raised when a managed-device definition is invalid."""

    def __init__(self, message_key: str, **message_values: Any) -> None:
        super().__init__(message_key)
        self.message_key = message_key
        self.message_values = message_values


def validate_device(name: str, ip_text: str, config: dict[str, Any]) -> dict[str, str]:
    """Validate and normalize a managed device.

    The function is intentionally independent from Flask so it can be tested
    without creating an application or touching runtime configuration.
    """

    normalized_name = name.strip()
    if not normalized_name or len(normalized_name) > 40:
        raise DeviceValidationError("validation_name")

    try:
        address = ipaddress.ip_address(ip_text.strip())
    except ValueError as exc:
        raise DeviceValidationError("validation_ip") from exc

    if address.version != 4:
        raise DeviceValidationError("validation_ipv4")

    try:
        lan_network = ipaddress.ip_network(config["lan_net"], strict=False)
        lan_ip = ipaddress.ip_address(config["lan_ip"])
    except (KeyError, ValueError) as exc:
        raise DeviceValidationError("validation_lan_config") from exc

    if address not in lan_network:
        raise DeviceValidationError("validation_outside_lan", network=str(lan_network))

    if address in (lan_network.network_address, lan_network.broadcast_address, lan_ip):
        raise DeviceValidationError("validation_reserved_ip")

    devices = config.get("devices", [])
    if any(item.get("ip") == str(address) for item in devices):
        raise DeviceValidationError("validation_duplicate_ip")

    return {"name": normalized_name, "ip": str(address)}
