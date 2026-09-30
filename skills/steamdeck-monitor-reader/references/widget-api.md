# Widget API

The installed Steam Deck Desktop Monitor daemon listens only on the local machine:

```text
GET http://127.0.0.1:19842/status
```

It returns cached JSON and refreshes metrics roughly every two seconds. A successful response contains:

| Field | Meaning |
| --- | --- |
| `timestamp` | Unix epoch seconds when the current sample was collected. |
| `cpu_percent` | Host-wide CPU utilisation percentage. |
| `memory` | `percent`, `used_gb`, and `total_gb`. |
| `storage` | `/home` usage: `percent`, `used_gb`, `total_gb`, and `free_gb`. |
| `sdcard` | `mounted`, optional `mount`, and capacity fields when mounted. |
| `external_drives` | Array of connected external-drive objects. |
| `battery` | Charge percentage, charging state, health, and power flags. |
| `temp` | Highest eligible APU-related sensor, formatted as e.g. `"71°C"`, or `"N/A"`. |
| `wifi` | Active connection name, connected/tethering flags, and an icon name. |
| `services` | Boolean probes for Syncthing, Dropbox, Rclone, and Tailscale; plus `tmux_sessions`. |
| `ping` | Ping to `1.1.1.1`, formatted e.g. `"23.4 ms"`, or `"Offline"`. |

## Availability checks

For a direct diagnostic, use:

```bash
curl --fail --silent --show-error http://127.0.0.1:19842/status
```

If it fails, report that the widget daemon is unavailable. Do not restart it automatically. A user who wants to repair it can inspect `systemctl --user status deck-monitor.service` and choose whether to restart it.

## Remote access through Tailscale

The daemon intentionally binds to loopback only. An agent on another device must use the bundled helper's Tailscale mode:

```bash
python3 scripts/read_status.py --tailscale-host <deck-hostname>
```

The helper accepts only an online peer returned by `tailscale status --json`, connects to its verified Tailscale IP, and runs a loopback-only request over SSH. It refuses to contact a normal LAN or public address. Before using it, configure Tailscale on both devices, enable and authenticate SSH access to the Steam Deck, and establish a trusted host key plus key-based login for the `deck` account. No widget configuration or port-forwarding is required.

## Cross-agent installation

The directory is self-contained and uses no Codex-specific instruction syntax. Install it by placing the whole directory in the agent product's configured skills directory, preserving the relative `scripts/` and `references/` paths. The host running the agent must be the Steam Deck itself or use the verified Tailscale mode above; do not expose port `19842` publicly just to make the skill work remotely.
