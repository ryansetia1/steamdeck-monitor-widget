#!/usr/bin/env python3
"""Read the local Steam Deck monitor widget API without third-party packages."""

import argparse
import ipaddress
import json
import os
import subprocess
import sys
import time
from datetime import datetime
from urllib.error import HTTPError, URLError
from urllib.request import urlopen


DEFAULT_ENDPOINT = "http://127.0.0.1:19842/status"
REMOTE_READ_SCRIPT = (
    "import sys; from urllib.request import urlopen; "
    "r=urlopen('http://127.0.0.1:19842/status', timeout=3); "
    "sys.stdout.buffer.write(r.read())"
)


def load_status(endpoint: str, timeout: float) -> dict:
    try:
        with urlopen(endpoint, timeout=timeout) as response:
            if response.status != 200:
                raise RuntimeError(f"server returned HTTP {response.status}")
            payload = json.loads(response.read().decode("utf-8"))
    except HTTPError as error:
        raise RuntimeError(f"server returned HTTP {error.code}") from error
    except URLError as error:
        raise RuntimeError(f"cannot reach widget endpoint: {error.reason}") from error
    except json.JSONDecodeError as error:
        raise RuntimeError("widget endpoint returned invalid JSON") from error

    if not isinstance(payload, dict) or not isinstance(payload.get("timestamp"), (int, float)):
        raise RuntimeError("widget response does not match the expected status schema")
    return payload


def is_tailscale_ip(address: str) -> bool:
    try:
        ip = ipaddress.ip_address(address)
    except ValueError:
        return False
    return ip in ipaddress.ip_network("100.64.0.0/10") or ip in ipaddress.ip_network("fd7a:115c:a1e0::/48")


def find_online_peer(selector: str, timeout: float) -> str:
    """Return a verified Tailscale IP for an online peer selected by name or IP."""
    try:
        result = subprocess.run(
            ["tailscale", "status", "--json"],
            check=True,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        status = json.loads(result.stdout)
    except FileNotFoundError as error:
        raise RuntimeError("Tailscale CLI is not installed on this device") from error
    except subprocess.TimeoutExpired as error:
        raise RuntimeError("Tailscale status check timed out") from error
    except (subprocess.CalledProcessError, json.JSONDecodeError) as error:
        raise RuntimeError("this device is not connected to Tailscale") from error

    if status.get("BackendState") != "Running":
        raise RuntimeError("this device is not connected to Tailscale")

    wanted = selector.rstrip(".").lower()
    for peer in status.get("Peer", {}).values():
        ips = [ip for ip in peer.get("TailscaleIPs", []) if is_tailscale_ip(ip)]
        names = {
            str(peer.get("HostName", "")).rstrip(".").lower(),
            str(peer.get("DNSName", "")).rstrip(".").lower(),
            *[ip.lower() for ip in ips],
        }
        if wanted not in names:
            continue
        if not peer.get("Online"):
            raise RuntimeError(f"Steam Deck peer '{selector}' is offline in Tailscale")
        if not ips:
            raise RuntimeError(f"Steam Deck peer '{selector}' has no usable Tailscale address")
        return ips[0]
    raise RuntimeError(f"no Tailscale peer matches '{selector}'")


def load_remote_status(selector: str, ssh_user: str, timeout: float) -> dict:
    peer_ip = find_online_peer(selector, timeout)
    try:
        result = subprocess.run(
            [
                "ssh",
                "-o", "BatchMode=yes",
                "-o", f"ConnectTimeout={max(1, int(timeout))}",
                "-o", "PasswordAuthentication=no",
                f"{ssh_user}@{peer_ip}",
                "python3", "-c", REMOTE_READ_SCRIPT,
            ],
            check=True,
            capture_output=True,
            text=True,
            timeout=timeout + 2,
        )
        payload = json.loads(result.stdout)
    except FileNotFoundError as error:
        raise RuntimeError("SSH client is not installed on this device") from error
    except subprocess.TimeoutExpired as error:
        raise RuntimeError("Steam Deck did not respond through Tailscale SSH") from error
    except subprocess.CalledProcessError as error:
        detail = error.stderr.strip().splitlines()[-1] if error.stderr.strip() else "SSH command failed"
        raise RuntimeError(f"cannot read the active Steam Deck through Tailscale SSH: {detail}") from error
    except json.JSONDecodeError as error:
        raise RuntimeError("Steam Deck returned invalid widget JSON") from error

    if not isinstance(payload, dict) or not isinstance(payload.get("timestamp"), (int, float)):
        raise RuntimeError("Steam Deck response does not match the expected status schema")
    return payload


def as_text(value, unavailable="N/A"):
    return unavailable if value is None else str(value)


def summary(data: dict) -> str:
    memory = data.get("memory", {})
    storage = data.get("storage", {})
    battery = data.get("battery", {})
    wifi = data.get("wifi", {})
    services = data.get("services", {})
    timestamp = datetime.fromtimestamp(data["timestamp"]).astimezone().isoformat(timespec="seconds")
    active_services = ", ".join(name for name in ("syncthing", "dropbox", "rclone", "tailscale") if services.get(name)) or "none"
    return "\n".join((
        f"Timestamp: {timestamp}",
        f"CPU: {as_text(data.get('cpu_percent'))}% | Temperature: {as_text(data.get('temp'))}",
        f"RAM: {as_text(memory.get('used_gb'))} / {as_text(memory.get('total_gb'))} GB ({as_text(memory.get('percent'))}%)",
        f"Storage (/home): {as_text(storage.get('used_gb'))} / {as_text(storage.get('total_gb'))} GB ({as_text(storage.get('percent'))}%)",
        f"Battery: {as_text(battery.get('percent'))}% ({as_text(battery.get('charge_label'))}; health {as_text(battery.get('health'))})",
        f"Network: {as_text(wifi.get('name'))} | Ping: {as_text(data.get('ping'))}",
        f"Monitored services active: {active_services}; tmux sessions: {as_text(services.get('tmux_sessions'), '0')}",
    ))


def main() -> int:
    parser = argparse.ArgumentParser(description="Read the Steam Deck monitor widget's local JSON status.")
    parser.add_argument("--endpoint", default=None, help="Local widget endpoint; cannot be combined with --tailscale-host.")
    parser.add_argument("--tailscale-host", help="Online Steam Deck Tailscale hostname, DNS name, or Tailscale IP.")
    parser.add_argument("--ssh-user", default="deck", help="SSH username on the Steam Deck (default: deck).")
    parser.add_argument("--timeout", type=float, default=3.0)
    parser.add_argument("--max-age", type=float, default=10.0, help="Maximum accepted cache age in seconds.")
    parser.add_argument("--json", action="store_true", help="Print complete JSON instead of a concise summary.")
    args = parser.parse_args()

    if args.timeout <= 0 or args.max_age < 0:
        parser.error("--timeout must be positive and --max-age cannot be negative")
    if args.tailscale_host and args.endpoint:
        parser.error("--endpoint and --tailscale-host cannot be used together")
    try:
        if args.tailscale_host:
            data = load_remote_status(args.tailscale_host, args.ssh_user, args.timeout)
        else:
            endpoint = args.endpoint or os.environ.get("DECK_MONITOR_ENDPOINT", DEFAULT_ENDPOINT)
            data = load_status(endpoint, args.timeout)
        age = time.time() - data["timestamp"]
        if age > args.max_age:
            raise RuntimeError(f"widget data is stale ({age:.1f}s old; maximum is {args.max_age:.1f}s)")
        if age < -5:
            raise RuntimeError("widget timestamp is unexpectedly in the future")
    except RuntimeError as error:
        print(f"deck-monitor: {error}", file=sys.stderr)
        return 1

    print(json.dumps(data, indent=2, sort_keys=True) if args.json else summary(data))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
