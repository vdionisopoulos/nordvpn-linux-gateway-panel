from __future__ import annotations

from typing import Any

SUPPORTED_LANGUAGES = ("en", "el")
DEFAULT_LANGUAGE = "en"

COUNTRY_GROUP_DEFINITIONS = (
    ("country_group_nearby", ("gr", "bg", "rs", "ro", "it", "at", "de")),
    ("country_group_western_europe", ("es", "fr", "nl", "uk")),
    ("country_group_americas_asia", ("us", "kr", "jp")),
)

COUNTRY_KEYS = {
    "gr": "country_gr",
    "bg": "country_bg",
    "rs": "country_rs",
    "ro": "country_ro",
    "it": "country_it",
    "at": "country_at",
    "de": "country_de",
    "es": "country_es",
    "fr": "country_fr",
    "nl": "country_nl",
    "uk": "country_uk",
    "us": "country_us",
    "kr": "country_kr",
    "jp": "country_jp",
}

TRANSLATIONS: dict[str, dict[str, str]] = {
    "en": {
        "language_name": "English",
        "language_selector": "Language",
        "subtitle": "Manage LAN devices through NordLynx",
        "exit_country": "Exit country",
        "default_country": "Preferred country",
        "connect_save": "Connect and save",
        "speed_note": (
            "Actual speed depends on distance, server load, and your provider's route."
        ),
        "new_server_same_country": "New server in same country",
        "disconnect": "Disconnect",
        "disconnect_note": (
            "Disconnect is fail-closed: managed devices lose Internet access until the VPN "
            "returns."
        ),
        "public_ip": "Public IP",
        "country_check": "Detected country",
        "nordvpn_status": "NordVPN status",
        "refresh": "Refresh",
        "gateway_health": "Gateway health",
        "heartbeat": "Heartbeat",
        "nordlynx": "NordLynx",
        "policy_rules": "Policy rules",
        "fail_closed_route": "Fail-closed route",
        "nftables_filter_nat": "nftables filter/NAT",
        "dns_proxy": "DNS proxy",
        "managed_dns": "DNS for managed devices",
        "ready": "Ready",
        "unavailable": "Unavailable",
        "present": "Present",
        "missing": "Missing",
        "protected": "Protected",
        "devices_via_vpn": "Devices through VPN",
        "name": "Name",
        "remove": "Remove",
        "no_devices": "No devices have been added.",
        "device_name": "Device name",
        "device_name_placeholder": "e.g. Apple TV",
        "add_device": "Add device",
        "device_config_hint": (
            "Set Router/Gateway and DNS to {lan_ip}, using a fixed IP in subnet {lan_net}."
        ),
        "status_unknown": "Unknown",
        "status_stale": "Stale heartbeat",
        "status_healthy": "Healthy",
        "status_fail_closed": "Fail-closed",
        "status_degraded": "Protection degraded",
        "no_heartbeat": "No heartbeat",
        "seconds_ago": "{seconds}s ago",
        "authentication_required": "Authentication required",
        "invalid_csrf": "Invalid CSRF token. Refresh the page and try again.",
        "nordvpn_timeout": "The NordVPN command timed out. Try again or check nordvpnd.",
        "nordvpn_unavailable": (
            "The NordVPN CLI is unavailable. Verify the installation and nordvpnd service."
        ),
        "unsupported_country": "Unsupported country.",
        "connection_failed": "Connection failed:\n{output}",
        "connected_autoconnect_updated": (
            "Connected to {country}. Auto-connect was updated."
        ),
        "connected_autoconnect_failed": (
            "Connected to {country}, but auto-connect failed: {output}"
        ),
        "saved_country_invalid": "The saved country is invalid.",
        "reconnected_new_server": "Reconnected to a new server in {country}.",
        "vpn_disconnected": (
            "The VPN was disconnected. Managed devices remain fail-closed."
        ),
        "device_added": (
            "Added {name} ({ip}). The change will apply within a few seconds."
        ),
        "device_removed": (
            "Removed device {ip}. The change will apply within a few seconds."
        ),
        "device_not_found": "The device was not found.",
        "configuration_update_failed": (
            "The gateway configuration could not be updated. Check the web service logs."
        ),
        "validation_name": "The name must contain 1–40 characters.",
        "validation_ip": "Invalid IP address.",
        "validation_ipv4": "An IPv4 address is required.",
        "validation_lan_config": "The gateway LAN configuration is invalid.",
        "validation_outside_lan": "The IP must belong to {network}.",
        "validation_reserved_ip": "The IP is reserved or belongs to the VPN gateway.",
        "validation_duplicate_ip": "The IP already exists in the list.",
        "country_group_nearby": "Nearby / usually lower latency",
        "country_group_western_europe": "Western Europe",
        "country_group_americas_asia": "Americas / Asia",
        "country_gr": "Greece",
        "country_bg": "Bulgaria",
        "country_rs": "Serbia",
        "country_ro": "Romania",
        "country_it": "Italy",
        "country_at": "Austria",
        "country_de": "Germany",
        "country_es": "Spain",
        "country_fr": "France",
        "country_nl": "Netherlands",
        "country_uk": "United Kingdom",
        "country_us": "United States",
        "country_kr": "South Korea",
        "country_jp": "Japan",
    },
    "el": {
        "language_name": "Ελληνικά",
        "language_selector": "Γλώσσα",
        "subtitle": "Διαχείριση συσκευών LAN μέσω NordLynx",
        "exit_country": "Χώρα εξόδου",
        "default_country": "Προεπιλεγμένη χώρα",
        "connect_save": "Σύνδεση και αποθήκευση",
        "speed_note": (
            "Η πραγματική ταχύτητα εξαρτάται από την απόσταση, τον φόρτο του server και "
            "τη διαδρομή του παρόχου."
        ),
        "new_server_same_country": "Νέος server ίδιας χώρας",
        "disconnect": "Αποσύνδεση",
        "disconnect_note": (
            "Η αποσύνδεση είναι fail-closed: οι managed συσκευές χάνουν Internet μέχρι "
            "να επανέλθει το VPN."
        ),
        "public_ip": "Δημόσια IP",
        "country_check": "Εντοπισμένη χώρα",
        "nordvpn_status": "Κατάσταση NordVPN",
        "refresh": "Ανανέωση",
        "gateway_health": "Κατάσταση gateway",
        "heartbeat": "Heartbeat",
        "nordlynx": "NordLynx",
        "policy_rules": "Κανόνες δρομολόγησης",
        "fail_closed_route": "Fail-closed route",
        "nftables_filter_nat": "nftables filter/NAT",
        "dns_proxy": "DNS proxy",
        "managed_dns": "DNS για managed συσκευές",
        "ready": "Έτοιμο",
        "unavailable": "Μη διαθέσιμο",
        "present": "Παρόν",
        "missing": "Απουσιάζει",
        "protected": "Προστατευμένο",
        "devices_via_vpn": "Συσκευές μέσω VPN",
        "name": "Όνομα",
        "remove": "Αφαίρεση",
        "no_devices": "Δεν έχουν προστεθεί συσκευές.",
        "device_name": "Όνομα συσκευής",
        "device_name_placeholder": "π.χ. Apple TV",
        "add_device": "Προσθήκη συσκευής",
        "device_config_hint": (
            "Στη συσκευή όρισε Router/Gateway και DNS το {lan_ip}, με σταθερή IP στο subnet "
            "{lan_net}."
        ),
        "status_unknown": "Άγνωστη κατάσταση",
        "status_stale": "Παλιό heartbeat",
        "status_healthy": "Κανονική λειτουργία",
        "status_fail_closed": "Fail-closed",
        "status_degraded": "Υποβαθμισμένη προστασία",
        "no_heartbeat": "Χωρίς heartbeat",
        "seconds_ago": "πριν από {seconds} δευτ.",
        "authentication_required": "Απαιτείται ταυτοποίηση",
        "invalid_csrf": "Μη έγκυρο CSRF token. Ανανέωσε τη σελίδα και δοκίμασε ξανά.",
        "nordvpn_timeout": "Η εντολή NordVPN έληξε λόγω timeout. Έλεγξε το nordvpnd.",
        "nordvpn_unavailable": (
            "Το NordVPN CLI δεν είναι διαθέσιμο. Έλεγξε την εγκατάσταση και το nordvpnd."
        ),
        "unsupported_country": "Μη υποστηριζόμενη χώρα.",
        "connection_failed": "Αποτυχία σύνδεσης:\n{output}",
        "connected_autoconnect_updated": (
            "Έγινε σύνδεση στη χώρα {country} και ενημερώθηκε το auto-connect."
        ),
        "connected_autoconnect_failed": (
            "Έγινε σύνδεση στη χώρα {country}, αλλά απέτυχε το auto-connect: {output}"
        ),
        "saved_country_invalid": "Η αποθηκευμένη χώρα δεν είναι έγκυρη.",
        "reconnected_new_server": "Έγινε επανασύνδεση σε νέο server στη χώρα {country}.",
        "vpn_disconnected": (
            "Το VPN αποσυνδέθηκε. Οι managed συσκευές παραμένουν fail-closed."
        ),
        "device_added": (
            "Προστέθηκε η συσκευή {name} ({ip}). Η αλλαγή θα εφαρμοστεί σε λίγα δευτερόλεπτα."
        ),
        "device_removed": (
            "Αφαιρέθηκε η συσκευή {ip}. Η αλλαγή θα εφαρμοστεί σε λίγα δευτερόλεπτα."
        ),
        "device_not_found": "Η συσκευή δεν βρέθηκε.",
        "configuration_update_failed": (
            "Δεν ήταν δυνατή η ενημέρωση του gateway configuration. Έλεγξε τα logs του web service."
        ),
        "validation_name": "Το όνομα πρέπει να έχει 1–40 χαρακτήρες.",
        "validation_ip": "Μη έγκυρη διεύθυνση IP.",
        "validation_ipv4": "Απαιτείται IPv4 διεύθυνση.",
        "validation_lan_config": "Το LAN configuration του gateway δεν είναι έγκυρο.",
        "validation_outside_lan": "Η IP πρέπει να ανήκει στο {network}.",
        "validation_reserved_ip": "Η IP είναι δεσμευμένη ή ανήκει στο VPN gateway.",
        "validation_duplicate_ip": "Η IP υπάρχει ήδη στη λίστα.",
        "country_group_nearby": "Κοντινές / συνήθως χαμηλότερο latency",
        "country_group_western_europe": "Δυτική Ευρώπη",
        "country_group_americas_asia": "Αμερική / Ασία",
        "country_gr": "Ελλάδα",
        "country_bg": "Βουλγαρία",
        "country_rs": "Σερβία",
        "country_ro": "Ρουμανία",
        "country_it": "Ιταλία",
        "country_at": "Αυστρία",
        "country_de": "Γερμανία",
        "country_es": "Ισπανία",
        "country_fr": "Γαλλία",
        "country_nl": "Ολλανδία",
        "country_uk": "Ηνωμένο Βασίλειο",
        "country_us": "Ηνωμένες Πολιτείες",
        "country_kr": "Νότια Κορέα",
        "country_jp": "Ιαπωνία",
    },
}


def normalize_language(language: str | None) -> str:
    if language in SUPPORTED_LANGUAGES:
        return language
    return DEFAULT_LANGUAGE


def translate(language: str, key: str, **values: Any) -> str:
    normalized = normalize_language(language)
    text = TRANSLATIONS[normalized].get(key, TRANSLATIONS[DEFAULT_LANGUAGE].get(key, key))
    return text.format(**values)


def localized_country_groups(language: str) -> list[tuple[str, list[tuple[str, str]]]]:
    return [
        (
            translate(language, group_key),
            [(code, translate(language, COUNTRY_KEYS[code])) for code in country_codes],
        )
        for group_key, country_codes in COUNTRY_GROUP_DEFINITIONS
    ]


def country_label(language: str, country_code: str) -> str:
    key = COUNTRY_KEYS.get(country_code)
    return translate(language, key) if key else country_code.upper()
