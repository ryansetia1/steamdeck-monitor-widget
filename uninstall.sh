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

# 4. Remove panel ping widget (remove it from the panel first, then the files)
if command -v qdbus6 >/dev/null 2>&1 && pgrep -x plasmashell >/dev/null; then
    qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "
    var ps = panels();
    for (var i = 0; i < ps.length; i++) {
        var ws = ps[i].widgets();
        for (var j = 0; j < ws.length; j++) {
            if (ws[j].type === 'org.ryan.deckping') ws[j].remove();
        }
    }" >/dev/null 2>&1 || true
fi
rm -rf "$HOME/.local/share/plasma/plasmoids/org.ryan.deckping"
echo "[✓] Panel ping widget removed"

echo "=== Uninstallation Complete! ==="
