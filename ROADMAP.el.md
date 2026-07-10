# Roadmap επόμενων εκδόσεων

Το παρόν έγγραφο περιγράφει την **προτεινόμενη κατεύθυνση** των επόμενων εκδόσεων του NordVPN Linux Gateway Panel.

Το roadmap είναι ευέλικτο. Η σειρά και το scope μπορούν να αλλάξουν μετά από δοκιμές, feedback χρηστών, security review ή αλλαγές στο NordVPN Linux client. Μια λειτουργία θεωρείται δεσμευμένη μόνο όταν έχει καταγραφεί σε issue ή περιλαμβάνεται σε ενεργό release pull request.

Τρέχουσα σταθερή έκδοση: **v1.0.3**

## Βασικές αρχές

Κάθε μελλοντική αλλαγή πρέπει να διατηρεί τα εξής:

- Οι managed συσκευές δεν πρέπει να κάνουν αθόρυβο fallback στον κανονικό LAN router.
- Το DNS πρέπει να παραμένει fail-closed όταν δεν υπάρχει VPN tunnel.
- Τα updates πρέπει να παραμένουν transactional και αναστρέψιμα.
- Secrets και private runtime configuration δεν πρέπει να αποθηκεύονται στο repository.
- Νέα privileges, capabilities, listeners και firewall exceptions πρέπει να περιορίζονται στο απολύτως απαραίτητο.
- Οι υφιστάμενες εγκαταστάσεις πρέπει να παραμένουν αναβαθμίσιμες όπου είναι πρακτικά δυνατό.

---

## Παραδόθηκε στο v1.0.3 — Maintenance και ποιότητα repository

Η maintenance έκδοση ολοκλήρωσε το αρχικό scope ποιότητας χωρίς αλλαγή της routing αρχιτεκτονικής:

- Ολοκληρώθηκε το Community Profile με Code of Conduct και contribution templates.
- Διορθώθηκαν και επεκτάθηκαν τα bug-report και pull-request templates.
- Προστέθηκε δομημένο feature-request form.
- Αφαιρέθηκε το obsolete version-specific tag workflow και προστέθηκε reusable publisher.
- Προστέθηκαν έλεγχοι συγχρονισμού release metadata.
- Αναβαθμίστηκαν τα pytest και Ruff μετά από έλεγχο.
- Βελτιώθηκαν τα αγγλικά και ελληνικά UI labels και operational messages.
- Προστέθηκαν αγγλικό και ελληνικό roadmap και βελτιώθηκε η τεκμηρίωση.

---

## v1.1.0 — Diagnostics και λειτουργική υποστήριξη

**Στόχος:** ευκολότερη λειτουργία, επαλήθευση και τεχνική υποστήριξη του gateway.

Προτεινόμενο scope:

- Ενέργεια **Run diagnostics** από το web panel.
- Προβολή αποτελεσμάτων smoke test σε ασφαλές read-only diagnostics view.
- DNS resolution και tunnel connectivity checks.
- Εμφάνιση tunnel uptime, τελευταίου reconnect και τρέχοντος server.
- Export sanitized support bundle με:
  - installed version,
  - gateway health,
  - service status,
  - policy rules,
  - routing table `200`,
  - nftables rules,
  - πρόσφατα redacted logs.
- Audit log για:
  - αλλαγές χώρας,
  - connect/disconnect/reconnect,
  - προσθήκη και αφαίρεση συσκευής,
  - restore configuration,
  - application updates.
- Backup και restore configuration με validation πριν την ενεργοποίηση.

Security απαίτηση: τα support bundles δεν πρέπει να περιλαμβάνουν passwords, tokens, public IPs ή private device details, εκτός αν ο χρήστης τα συμπεριλάβει ρητά.

---

## v1.2.0 — Device groups και routing policies

**Στόχος:** μεγαλύτερη ευελιξία ανά συσκευή, χωρίς απώλεια της σαφούς fail-closed συμπεριφοράς.

Προτεινόμενο scope:

- Ομάδες συσκευών, όπως TVs, tablets, consoles και guests.
- Enable ή pause του VPN routing χωρίς διαγραφή της συσκευής.
- Προαιρετικά schedules ανά συσκευή ή group.
- Online/offline visibility και last-seen timestamps.
- Notes και tags ανά συσκευή.
- Import/export της λίστας managed συσκευών.
- Ρητές bypass policies με προειδοποίηση και audit history.

Παράδειγμα:

```text
Living-room TV → VPN καθημερινά, 18:00–01:00
Console        → VPN μόνο τα Σαββατοκύριακα
Tablet         → Πάντα μέσω VPN
Guest device   → Προσωρινά paused
```

Το bypass δεν πρέπει να δημιουργείται ποτέ έμμεσα. Το UI και το configuration πρέπει να ξεχωρίζουν καθαρά τις καταστάσεις **VPN**, **fail-closed**, **paused** και **intentional bypass**.

---

## v1.3.0 — Security και access control

**Στόχος:** ισχυρότερη προστασία του panel σε λιγότερο αξιόπιστα LAN περιβάλλοντα.

Προτεινόμενο scope:

- Προαιρετικό HTTPS μέσω Caddy ή Nginx.
- Form-based login αντί για HTTP Basic Authentication.
- Session expiration και login rate limiting.
- Ρόλοι:
  - Administrator,
  - Operator,
  - Read-only.
- Προαιρετικό TOTP multi-factor authentication.
- Περιορισμός πρόσβασης στο panel ανά subnet.
- Security-event audit records.
- Encrypted configuration backup export.
- Προαιρετικό Unix socket μεταξύ reverse proxy και Gunicorn.

Οι δυνατότητες αυτές πρέπει να παραμείνουν optional, ώστε η βασική LAN-only εγκατάσταση να παραμένει ελαφριά.

---

## v1.4.0 — Monitoring, metrics και alerts

**Στόχος:** προληπτική ενημέρωση όταν αλλάζει η κατάσταση του gateway ή του tunnel.

Προτεινόμενο scope:

- Prometheus-compatible metrics endpoint.
- Παράδειγμα Grafana dashboard.
- Historical health και reconnect data.
- Notifications μέσω:
  - email,
  - Telegram,
  - Discord,
  - generic webhook.
- Alerts όταν:
  - αποσυνδέεται το VPN tunnel,
  - το DNS proxy δεν είναι protected,
  - απουσιάζει η blackhole route,
  - τα policy-rule counts διαφέρουν από τα expected,
  - λείπει η nftables προστασία,
  - αποτυγχάνει update ή rollback.

Πιθανά metrics:

```text
vpn_gateway_healthy
vpn_tunnel_connected
vpn_policy_rules_expected
vpn_policy_rules_actual
vpn_dns_protected
vpn_managed_devices
vpn_reconnect_total
```

Τα metrics δεν πρέπει από προεπιλογή να εκθέτουν device names, private addresses, credentials ή public IP information.

---

## v2.0.0 — Multiple tunnels και διαφορετική χώρα ανά συσκευή

**Στόχος:** ανεξάρτητα VPN profiles για διαφορετικές συσκευές ή groups.

Παράδειγμα επιθυμητής λειτουργίας:

```text
Living-room TV → United States
Bedroom TV     → Greece
Tablet         → Germany
Console        → United Kingdom
```

Πρόκειται για μεγάλη αρχιτεκτονική αλλαγή που απαιτεί έρευνα και prototype. Επειδή το NordVPN CLI συνήθως διαχειρίζεται ένα ενεργό tunnel, μια πιθανή σχεδίαση μπορεί να απαιτεί:

- Linux network namespaces,
- ξεχωριστό tunnel process ή profile ανά namespace,
- ξεχωριστά routing tables,
- nftables marks,
- device-to-profile mapping,
- ανεξάρτητο DNS handling ανά tunnel,
- fail-closed blackhole route ανά profile,
- migration του configuration schema και των systemd services.

Ενδεικτικό μοντέλο:

```text
Device group US
  → fwmark 101
  → routing table 201
  → namespace vpn-us
  → US tunnel

Device group DE
  → fwmark 102
  → routing table 202
  → namespace vpn-de
  → DE tunnel
```

Η έκδοση v2.0.0 πρέπει να προχωρήσει μόνο αφού αποδειχθεί με δοκιμές ότι isolation, DNS routing, restart behavior, upgrades και fail-closed guarantees παραμένουν αξιόπιστα.

---

## Μελλοντικές ιδέες

Τα παρακάτω είναι υποψήφιες κατευθύνσεις και όχι προγραμματισμένες εκδόσεις:

- IPv6 fail-closed routing.
- ARM64 και Raspberry Pi validation.
- Debian support.
- Docker ή Podman deployment όπου το networking model το επιτρέπει.
- Ansible role και cloud-init installation.
- Τεκμηριωμένο REST API.
- Home Assistant integration.
- OpenWrt companion integration.
- High availability με δεύτερο gateway.
- Provider abstraction για άλλα WireGuard-compatible VPN services.

## Συνεισφορά στο roadmap

Ένα feature request πρέπει να εξηγεί:

1. Το πρόβλημα που λύνει.
2. Την αναμενόμενη λειτουργική συμπεριφορά.
3. Την επίδραση σε routing, DNS, nftables, privileges και fail-closed guarantees.
4. Backward compatibility και upgrade considerations.
5. Τα tests που απαιτούνται για την ασφαλή επιβεβαίωση της λειτουργίας.

Για μεγάλες αλλαγές, άνοιξε πρώτα GitHub issue ώστε να συζητηθούν η αρχιτεκτονική και η κατάλληλη έκδοση στόχος.
