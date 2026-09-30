#!/usr/bin/env python3
"""Read the local Steam Deck monitor widget API without third-party packages."""

import argparse
import json
import os
import sys
import time
from datetime import datetime
from urllib.error import HTTPError, URLError
from urllib.request import urlopen


DEFAULT_ENDPOINT = "http://127.0.0.1:19842/status"


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
    parser.add_argument("--endpoint", default=os.environ.get("DECK_MONITOR_ENDPOINT", DEFAULT_ENDPOINT))
    parser.add_argument("--timeout", type=float, default=3.0)
    parser.add_argument("--max-age", type=float, default=10.0, help="Maximum accepted cache age in seconds.")
    parser.add_argument("--json", action="store_true", help="Print complete JSON instead of a concise summary.")
    args = parser.parse_args()

    if args.timeout <= 0 or args.max_age < 0:
        parser.error("--timeout must be positive and --max-age cannot be negative")
    try:
        data = load_status(args.endpoint, args.timeout)
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
