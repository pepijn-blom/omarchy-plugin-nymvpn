# Omarchy NymVPN Plugin

Bar widget for [NymVPN](https://nym.com/) on [Omarchy Linux](https://omarchy.org/). Toggle the tunnel, switch entry and exit countries, and watch the built-in fair-use data allowance.

This is an unofficial third-party Quickshell plugin (`pepijn-blom.nymvpn`). It talks to `nym-vpnc`, which RPCs to the `nym-vpnd` daemon. It does not install NymVPN itself, and it is not affiliated with Nym.

## Features

- Status icon on the Omarchy bar (connected, disconnected, quota warning)
- Left click opens a keyboard-friendly panel
- Right click connects or disconnects. If no account is stored (or the daemon is down), it opens the panel with a warning instead of starting a tunnel
- Middle click refreshes status and the gateway list
- Fast (2-hop WireGuard) vs Mixnet (5-hop) mode switch
- Searchable entry and exit country pickers
- Fair-use usage (`used / limit` plus reset time)
- Sign in with a recovery phrase when no account is stored on the device
- Collapsible settings: ads, IPv6, LAN bypass, anti-censorship, residential exit, custom DNS
- Bypass VPN: exclude named processes or absolute paths (type `ssh` or `/usr/bin/ssh` even if it is not running)
- Geo-exclusion: bypass the tunnel for CN / RU only (the only codes `nym-vpnc` v2026.12.2 accepts; other ISO codes are rejected by the daemon and the field snaps back to the daemon truth)

## Icon

The bar uses the official NymVPN **N** mark from the app icon, theme-colored like Tailscale and Dropbox. The letter is drawn as a solid glyph (two verticals and a diagonal), so it stays crisp and recognizable at bar sizes instead of collapsing into rings.

State changes are shown through color and motion:

- **Connected** — the N is solid; a small packet dot traces the diagonal, with a dimmer cover-traffic dot running the other way in mixnet mode
- **Connecting** — the N pulses
- **Disconnected** — the N dims
- **Warning** — a small badge shows next to the mark

## Keyboard shortcuts

Inside the panel:

- `j` / `k` or arrows: move cursor
- `enter` / `space`: activate the current control
- `t`: toggle the tunnel (opens sign-in if no account is stored)
- `r`: refresh status
- `x` / `d`: force disconnect
- `esc`: close (or clear the recovery-phrase field if it is focused)
- Settings header: expand or collapse. On a setting row, `enter` / `space` or left/right toggles it. Below the toggles, Bypass VPN lists excluded processes; `enter` removes a name, focuses the add field (name or absolute path), or opens the running-process picker.
- When no account is stored: connect attempts (switch, `t`, right-click, IPC) show **Sign in to connect** and focus the recovery-phrase field. `enter` on the account section also focuses the field. `enter` in the field signs in.

## Requirements

- `nym-vpnc` on `PATH` (the CLI from nym-vpn-core — not the same binary as `nym-vpn-app`)
- `nym-vpnd` running (systemd service on packaged installs)
- Polkit rule allowing daemon access without password prompts (see below)
- An account stored on the device. Connect is refused until one is stored. Sign in from the panel with your recovery phrase (or create an account from the same row).

### Polkit Configuration

`nym-vpnd` communicates over a unix socket secured by Polkit (`com.nymvpn.vpnd.unix-access`). To avoid password prompts on every CLI query, create `/etc/polkit-1/rules.d/50-nym-vpn.rules`:

```javascript
polkit.addRule(function(action, subject) {
    if (action.id === "com.nymvpn.vpnd.unix-access" &&
        (subject.isInGroup("wheel") || subject.isInGroup("nym-vpn"))) {
        return polkit.Result.YES;
    }
});
```

A reference rule is shipped in `polkit/50-nym-vpn.rules`. You can install it using `./install --polkit` (requires sudo) or copy it manually:

```bash
sudo install -D -m 0644 polkit/50-nym-vpn.rules /etc/polkit-1/rules.d/50-nym-vpn.rules
```

The widget shows **Not installed** until `nym-vpnc` is on PATH. Having the GUI (`nym-vpn-app`) or daemon (`nym-vpnd`) alone is not enough.

## Installation

### Via Omarchy Plugin Manager (Recommended)

```bash
omarchy plugin add https://github.com/pepijn-blom/omarchy-plugin-nymvpn.git --enable
```

Note: `omarchy plugin add` does not execute system scripts or install root files. To configure the optional Polkit rule, run:

```bash
~/.config/omarchy/plugins/pepijn-blom.nymvpn/install --polkit --no-enable
```

or install `polkit/50-nym-vpn.rules` manually as shown above.

### From Local Repository

```bash
./install
# or, to also install the Polkit rule in /etc (requires sudo):
./install --polkit
```

That copies the plugin to `~/.config/omarchy/plugins/pepijn-blom.nymvpn/`, validates the manifest, and enables it on the right side of the bar. Pass `--no-enable` to skip automatic bar placement.

If the icon does not appear after the first install, run `omarchy restart shell` so Quickshell drops a stale QML cache.

## Usage

- **Bar:** left click for the panel, right click to connect/disconnect, middle click to refresh. Right click does not start a tunnel when no account is stored — it opens the panel and focuses sign-in.
- **Bypass VPN:** under Settings, add process names or absolute paths that should skip the tunnel (for example `ssh` or `/usr/bin/ssh`). Type a name or path even if the process is not running yet, or pick from what is running. Linux NymVPN only supports exclude-by-PID, which is too late for short-lived tools like `ssh` (they connect before the next PID sync). For those, the plugin installs a `nym-exclude` wrapper in `~/.local/bin` so new processes start outside the tunnel. Attaching a running PID does not migrate sockets already opened through the tunnel — restart the app, or reconnect, after adding it.
- **Sign in:** if the panel shows no account on this device, paste your recovery phrase and choose Sign in (or Create account to open the Nym site). The power switch, `t`, and `toggleVpn` / `connectVpn` IPC all refuse connect until then.
- **IPC:** `omarchy-shell shell summon pepijn-blom.nymvpn`, `omarchy-shell pepijn-blom.nymvpn toggleVpn`, `omarchy-shell pepijn-blom.nymvpn status`. Blocked connects return `Sign in to connect` (or `nym-vpnd is not running`) instead of `ok`.

`Force Disconnect` (and the `x` / `d` keys) send `nym-vpnc disconnect --wait`. Use that if a connect attempt is stuck or the daemon reports an error. It does not run on a normal refresh.

## Privacy

The helper parses `nym-vpnc` text output and forwards a small JSON snapshot to the bar. Account addresses (`n1…`) are redacted and are not stored in plugin settings.

Telemetry settings (Sentry crash reports and anonymous network statistics) default to **off** in this plugin. Toggling them in the settings card sends `nym-vpnc sentry set <on|off>` and `nym-vpnc network-stats set --enabled <on|off>` to configure the daemon directly. When you configure custom settings, they are saved under your plugin entry in `~/.config/omarchy/shell.json` and reconciled against the daemon when the plugin runs.

Sign-in is handled by a separate `login.py` helper. The recovery phrase is typed into a masked field, sent once over stdin to the helper (never stored in plugin settings or IPC), then wiped from the panel. The helper must pass the phrase to `nym-vpnc account set <SECRET>` as a command-line argument because that CLI offers no stdin option, so the phrase is briefly visible to same-user processes via `/proc/<pid>/cmdline`; the helper makes a best-effort attempt to overwrite that memory after spawn, which can fail depending on permissions. Helper output is sanitized so the phrase cannot appear in status or error text. The daemon stores the account; this plugin does not.

## Development

```bash
make test
make validate   # tests plus `omarchy plugin validate .`
```

`status.py` shells out to `nym-vpnc`. There is no machine-readable CLI today, so parsers are covered by fixtures in `tests/test_status.py`. `login.py` is covered in `tests/test_login.py`. `split.py` matches process names against `/proc` and syncs PIDs via `nym-vpnc split-tunnel`; parsers and matching are covered in `tests/test_split.py`. Gateway lists are cached under `$XDG_CACHE_HOME/omarchy-nymvpn` for five minutes.

## Uninstall

### Via Omarchy Plugin Manager

```bash
omarchy plugin remove pepijn-blom.nymvpn --yes
```

This unregisters the plugin from the shell and deletes the plugin directory (or creates a `.bak` backup if unversioned). To also clean up any split-tunnel bypass wrappers in `~/.local/bin` and the Polkit rule, run `./uninstall --polkit` from this repository or remove them manually.

### From Local Repository

```bash
./uninstall
# or, to also remove the /etc Polkit rule if unchanged (requires sudo):
./uninstall --polkit
```

This disables the widget in the shell, removes `~/.local/bin` bypass wrappers created by this plugin, clears the gateway cache, and removes the plugin folder. VPN account credentials and daemon settings remain stored by `nym-vpnd`.

## License

[MIT](LICENSE) © 2026 Pepijn Blom
