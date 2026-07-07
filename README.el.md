# NordVPN Linux Gateway Panel

Μικρό Ubuntu gateway και web panel για τη δρομολόγηση επιλεγμένων συσκευών LAN μέσω NordVPN NordLynx.

## Λειτουργίες

- Προσθήκη και αφαίρεση συσκευών με IPv4
- Αλλαγή χώρας εξόδου από browser
- Αποθήκευση χώρας ως στόχου auto-connect
- Reconnect σε άλλον server της ίδιας χώρας
- Policy routing ανά συσκευή
- NAT με nftables
- Fail-closed λειτουργία όταν πέσει το VPN
- Αυτόματη εκκίνηση μέσω systemd

## Εγκατάσταση

Απαιτείται Ubuntu Server με σταθερή IP στο ίδιο LAN με τις συσκευές και εγκατεστημένο/συνδεδεμένο NordVPN Linux CLI.

```bash
git clone https://github.com/vdionisopoulos/nordvpn-linux-gateway-panel.git
cd nordvpn-linux-gateway-panel
sudo ./install.sh
```

Το panel ανοίγει στη διεύθυνση:

```text
http://IP-ΤΗΣ-VM:8080
```

## Ρύθμιση συσκευής

Κάθε managed συσκευή χρειάζεται:

```text
Σταθερή IPv4
Gateway/Router = IP της Ubuntu VM
DNS = 103.86.96.100 ή 103.86.99.100
```

Απενεργοποίησε το IPv6 στη συσκευή ή υλοποίησε αντίστοιχο IPv6 routing/filtering, ώστε να μην παρακάμπτει το VPN.

## Ασφάλεια

Μην εκθέσεις τη θύρα του panel στο Internet και μην κάνεις port forwarding από το router. Τα credentials του HTTP Basic Authentication δεν κρυπτογραφούνται χωρίς TLS.

## Άδεια

MIT
