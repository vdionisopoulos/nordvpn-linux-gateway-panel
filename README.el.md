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

## Απαιτήσεις

### Ubuntu gateway

Το gateway μπορεί να εγκατασταθεί σε φυσικό Ubuntu υπολογιστή ή σε virtual machine. Η προτεινόμενη χρήση είναι ένα μικρό Ubuntu Server που παραμένει συνεχώς ενεργό.

Προτεινόμενοι πόροι για λίγες τηλεοράσεις, tablets ή άλλες συσκευές streaming:

```text
CPU:      2 vCPU
Μνήμη:    2 GB RAM
Swap:     1 GB
Δίσκος:   10 GB ελεύθερος χώρος
Δίκτυο:   1 φυσικό ή virtual network adapter
```

Η εφαρμογή χρησιμοποιεί ελάχιστους πόρους. Η πραγματική απόδοση του VPN εξαρτάται κυρίως από τον επεξεργαστή του host, την ταχύτητα της σύνδεσης Internet και τον NordVPN server που έχει επιλεγεί.

Το λειτουργικό σύστημα πρέπει να διαθέτει:

- Ubuntu Server με `systemd`, `bash`, `apt` και `sudo`
- Υποστήριξη IPv4 forwarding
- Policy routing μέσω `ip rule` και custom routing tables
- nftables για forwarding, filtering και source NAT
- Python 3 και υποστήριξη virtual environments

Ο installer εγκαθιστά αυτόματα τα απαιτούμενα Ubuntu packages, όπως Python, `jq`, `nftables` και τα βοηθητικά εργαλεία.

### Δικτύωση virtual machine

Αν το gateway λειτουργεί ως VM, ο network adapter πρέπει να συνδέεται απευθείας στο ίδιο LAN με τις συσκευές που θα χρησιμοποιούν το VPN.

Παραδείγματα:

- Hyper-V: **External Virtual Switch**
- VMware: **Bridged Networking**
- VirtualBox: **Bridged Adapter**

Ένα NAT-only ή host-only virtual network δεν είναι κατάλληλο, επειδή οι τηλεοράσεις και οι υπόλοιπες συσκευές του LAN πρέπει να μπορούν να επικοινωνούν απευθείας με την Ubuntu VM.

Η VM πρέπει να έχει:

- Σταθερή IPv4 ή μόνιμο DHCP reservation
- IPv4 στο ίδιο subnet με τις managed συσκευές
- Κανονικό default route προς το οικιακό router
- Πρόσβαση στο Internet πριν ρυθμιστεί το NordVPN
- Αναγνωρίσιμο LAN interface, όπως `eth0`, `ens18` ή `enp0s3`

Παράδειγμα:

```text
LAN router:       192.168.1.1
Ubuntu gateway:   192.168.1.2
LAN subnet:       192.168.1.0/24
Web panel:        http://192.168.1.2:8080
```

Η θύρα `8080` πρέπει να είναι ελεύθερη στην Ubuntu VM. Δεν πρέπει να δημιουργηθεί port forwarding από το Internet προς αυτή τη θύρα.

### NordVPN account και Linux client

Πριν την εγκατάσταση του project πρέπει να έχει εγκατασταθεί και να έχει γίνει authentication στο επίσημο NordVPN Linux CLI.

Απαιτούνται:

- Ενεργός λογαριασμός NordVPN
- Εγκατεστημένο NordVPN Linux CLI
- Επιτυχές `nordvpn login`
- Επιλεγμένο NordLynx ως VPN technology
- Ο Linux χρήστης του web service να ανήκει στο group `nordvpn`
- Επιτυχής δοκιμαστική σύνδεση σε τουλάχιστον μία χώρα

Προτεινόμενος έλεγχος:

```bash
nordvpn settings
nordvpn status
ip -4 address show nordlynx
```

Το NordVPN πρέπει να εμφανίζει `NORDLYNX` ως ενεργή τεχνολογία και το interface `nordlynx` πρέπει να εμφανίζεται μετά τη σύνδεση.

### Απαιτήσεις router και LAN

Το LAN router πρέπει να υποστηρίζει DHCP reservations ή άλλον τρόπο ώστε οι IP των συσκευών να παραμένουν σταθερές.

Δεν απαιτείται router-wide static route. Κάθε managed συσκευή ρυθμίζεται ξεχωριστά ώστε να χρησιμοποιεί την Ubuntu VM ως IPv4 default gateway.

Το LAN πρέπει να επιτρέπει απευθείας επικοινωνία μεταξύ:

```text
Managed συσκευή <-> Ubuntu gateway <-> LAN router
```

Guest Wi-Fi isolation ή client isolation δεν πρέπει να εμποδίζει την επικοινωνία της συσκευής με την Ubuntu VM.

### Απαιτήσεις managed συσκευών

Κάθε τηλεόραση, tablet, κονσόλα ή άλλη συσκευή χρειάζεται:

- Σταθερή IPv4 ή DHCP reservation
- IPv4 στο ίδιο subnet με την Ubuntu VM
- Την IPv4 της Ubuntu VM ως Router/Default Gateway
- Λειτουργικό DNS, όπως το NordVPN DNS
- Απενεργοποιημένο IPv6 ή αντίστοιχο IPv6 routing/filtering

Παράδειγμα ρύθμισης συσκευής:

```text
IPv4 address:  192.168.1.50
Subnet mask:   255.255.255.0
Router:        192.168.1.2
DNS:           103.86.96.100
Εναλλακτικό:   103.86.99.100
```

Το IPv6 πρέπει να απενεργοποιηθεί στη managed συσκευή, εκτός αν έχει υλοποιηθεί αντίστοιχη IPv6 δρομολόγηση μέσω VPN. Διαφορετικά, η συσκευή μπορεί να παρακάμψει το IPv4 gateway.

### Διαχειριστική πρόσβαση

Για την εγκατάσταση απαιτούνται:

- Linux χρήστης με δικαιώματα `sudo`
- SSH ή τοπική console πρόσβαση στην Ubuntu VM
- Δικαίωμα εγκατάστασης packages και systemd services
- Δικαίωμα διαχείρισης routes, nftables και IPv4 forwarding

Το web panel προορίζεται αποκλειστικά για χρήση μέσα σε έμπιστο ιδιωτικό LAN.

### Έλεγχοι πριν την εγκατάσταση

```bash
nordvpn status
ip -4 -br address
ip -4 route
systemctl is-active nordvpnd
sudo nft list ruleset
sudo ss -ltn | grep ':8080' || true
```

Επιβεβαίωσε ότι:

- Το NordVPN συνδέεται επιτυχώς
- Η Ubuntu VM έχει τη σωστή σταθερή LAN IP
- Το default route δείχνει στο κανονικό LAN router
- Το `nordvpnd` είναι ενεργό
- Η θύρα `8080` δεν χρησιμοποιείται ήδη

## Εγκατάσταση

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
