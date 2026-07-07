from __future__ import annotations

import ipaddress
from typing import Any


class DeviceValidationError(ValueError):
    """Raised when a managed-device definition is invalid."""


def validate_device(name: str, ip_text: str, config: dict[str, Any]) -> dict[str, str]:
    """Validate and normalize a managed device.

    The function is intentionally independent from Flask so it can be tested
    without creating an application or touching runtime configuration.
    """

    normalized_name = name.strip()
    if not normalized_name or len(normalized_name) > 40:
        raise DeviceValidationError("Το όνομα πρέπει να έχει 1–40 χαρακτήρες.")

    try:
        address = ipaddress.ip_address(ip_text.strip())
    except ValueError as exc:
        raise DeviceValidationError("Μη έγκυρη διεύθυνση IP.") from exc

    if address.version != 4:
        raise DeviceValidationError("Απαιτείται IPv4 διεύθυνση.")

    try:
        lan_network = ipaddress.ip_network(config["lan_net"], strict=False)
        lan_ip = ipaddress.ip_address(config["lan_ip"])
    except (KeyError, ValueError) as exc:
        raise DeviceValidationError("Το LAN configuration του gateway δεν είναι έγκυρο.") from exc

    if address not in lan_network:
        raise DeviceValidationError(f"Η IP πρέπει να ανήκει στο {lan_network}.")

    if address in (lan_network.network_address, lan_network.broadcast_address, lan_ip):
        raise DeviceValidationError("Η IP είναι δεσμευμένη ή είναι η IP της VPN VM.")

    devices = config.get("devices", [])
    if any(item.get("ip") == str(address) for item in devices):
        raise DeviceValidationError("Η IP υπάρχει ήδη στη λίστα.")

    return {"name": normalized_name, "ip": str(address)}
