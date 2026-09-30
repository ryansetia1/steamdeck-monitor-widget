---
name: steamdeck-monitor-reader
description: Read and interpret live metrics from a Steam Deck Desktop Monitor widget. Use when the user asks for the current CPU, RAM, storage, battery, thermals, network, or monitored service state on their Steam Deck; do not use for changing widget settings or system state.
---

# Steam Deck Monitor Reader

Read the widget's local JSON endpoint instead of inferring values from a screenshot or independently recomputing them. The daemon is read-only at `http://127.0.0.1:19842/status` and refreshes its cached data about every two seconds.

## Read live data

Run the bundled helper from this skill folder:

```bash
python3 scripts/read_status.py
```

Use `--json` when the task needs every field or values for another program. The helper fails clearly when the daemon is unavailable, the response is malformed, or the cache is stale. Do not start, restart, or modify `deck-monitor.service` unless the user explicitly asks.

## Read an active Steam Deck over Tailscale

For another device, use the helper only with `--tailscale-host`:

```bash
python3 scripts/read_status.py --tailscale-host steamdeck
```

This mode first verifies that the calling device is connected to Tailscale, finds the named peer in local Tailscale status, and requires that peer to be online. It then uses non-interactive SSH to ask the Steam Deck itself for `127.0.0.1:19842/status`; it never sends the widget port over the LAN or exposes it to the tailnet. The caller must already have a trusted SSH host key and key-based access to the Steam Deck's `deck` account. Use `--ssh-user` only when the Deck uses a different account.

If any of the Tailscale, online-peer, SSH, daemon, or fresh-data checks fail, stop and report the unavailable condition; do not fall back to a public, LAN, or arbitrary remote HTTP endpoint.

## Interpret and report

- Identify the result as a point-in-time reading and include its local timestamp when it is useful.
- Preserve the daemon's distinction between `battery.status`, `battery.charge_label`, `is_plugged`, and `is_charging`.
- Treat `temp: "N/A"`, `ping: "Offline"`, and `wifi.connected: false` as unavailable/offline values, not zero.
- `storage` is the `/home` filesystem; `sdcard` and `external_drives` are separate. An unmounted SD card has `sdcard.mounted: false`.
- Report only fields relevant to the user's question. Do not expose an SSID or external-drive mount path unless it is needed for the request.
- Explain that service booleans reflect the widget's process/status probes, rather than a guarantee that the underlying cloud or VPN service is healthy.

## Portability

This folder follows the portable Agent Skills layout (`SKILL.md` plus relative resources). Copy or symlink the entire `steamdeck-monitor-reader` folder into the skill directory recognized by Claude, Codex, or Antigravity; do not copy only `SKILL.md`, because it references `scripts/read_status.py`.

For endpoint details, schema, and setup notes, read [references/widget-api.md](references/widget-api.md).
