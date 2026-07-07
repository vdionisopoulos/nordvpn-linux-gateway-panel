# NordVPN authentication and secret handling

This project does **not** require a raw WireGuard private key, a manual NordLynx configuration file, OpenVPN service credentials, or any NordVPN secret to be stored in the repository.

The gateway uses the official NordVPN Linux CLI and relies on the authentication session already stored locally by that client.

## What you need from NordVPN

You need:

- an active NordVPN subscription;
- the official NordVPN Linux client installed on the Ubuntu gateway;
- a successful login to the NordVPN Linux client;
- a successful test connection before installing the gateway panel.

You can authenticate in one of two ways.

### Browser login

This is the preferred method when the Ubuntu host can open a browser or when you can complete the login URL from another device:

```bash
nordvpn login
```

Complete the Nord Account sign-in flow and then verify:

```bash
nordvpn status
```

### Access-token login for a headless server

For a server without a graphical browser, generate an access token in your Nord Account and run:

```bash
nordvpn login --token
```

Paste the token only when the secure terminal prompt appears.

Do **not** place the token directly in the command line unless absolutely necessary. Supplying it as a command argument can expose it through shell history or process inspection.

Important token behavior:

- token login does not support multi-factor authentication during the token-login operation;
- the token is generated in Nord Account;
- logging out revokes the token used by the Linux client;
- the token must be treated as a secret.

## What this project stores

The web panel does not request, copy, or store the NordVPN account password or access token.

It calls commands such as:

```bash
nordvpn status
nordvpn connect gr
nordvpn set autoconnect on gr
```

These commands use the existing authenticated NordVPN Linux session on the Ubuntu host.

The panel has its own separate web username and password. Those credentials are stored locally in:

```text
/etc/vpn-control-web.env
```

The managed-device inventory and selected country are stored locally in:

```text
/var/lib/vpn-control/config.json
```

Neither file should be committed to Git.

## Secrets that must never be committed

Never publish or commit:

- NordVPN access tokens;
- Nord Account passwords;
- WireGuard or NordLynx private keys;
- OpenVPN service credentials;
- `/etc/vpn-control-web.env`;
- `/var/lib/vpn-control/config.json` from a real deployment;
- packet captures that may contain private network information.

If a token or private key is accidentally published, revoke or rotate it immediately before removing it from Git history.

## Verification before installing the panel

```bash
nordvpn status
nordvpn settings
nordvpn connect gr
ip -4 address show nordlynx
```

The installation should continue only when NordVPN reports a successful connection and the `nordlynx` interface exists.
