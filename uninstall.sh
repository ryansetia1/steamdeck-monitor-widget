#!/bin/bash
set -e

echo "=== Uninstalling Steam Deck Monitor Widget ==="

# 1. Stop and disable service
if systemctl --user is-active --quiet deck-monitor.service 2>/dev/null; then
    systemctl --user stop deck-monitor.service
fi
systemctl --user disable deck-monitor.service 2>/dev/null || true
rm -f "$HOME/.config/systemd/user/deck-monitor.service"
systemctl --user daemon-reload
echo "[✓] Service removed"

# 2. Remove daemon
rm -f "$HOME/.local/bin/deck-monitor-daemon.py"
echo "[✓] Daemon script removed"

# 3. Remove plasmoid
rm -rf "$HOME/.local/share/plasma/plasmoids/org.ryan.deckmonitor"
echo "[✓] Plasmoid removed"

echo "=== Uninstallation Complete! ==="
