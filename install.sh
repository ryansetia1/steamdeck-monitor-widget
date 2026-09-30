#!/bin/bash
set -e

echo "=== Installing Steam Deck Monitor Widget ==="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 1. Install daemon script
mkdir -p "$HOME/.local/bin"
cp "$SCRIPT_DIR/bin/deck-monitor-daemon.py" "$HOME/.local/bin/"
chmod +x "$HOME/.local/bin/deck-monitor-daemon.py"
echo "[✓] Daemon script copied to ~/.local/bin/deck-monitor-daemon.py"

# 2. Install systemd user service
mkdir -p "$HOME/.config/systemd/user"
cp "$SCRIPT_DIR/systemd/deck-monitor.service" "$HOME/.config/systemd/user/"
systemctl --user daemon-reload
systemctl --user enable --now deck-monitor.service
echo "[✓] Systemd service enabled and started"

# 3. Install Plasma 6 Plasmoid
PLASMOID_DIR="$HOME/.local/share/plasma/plasmoids/org.ryan.deckmonitor"
mkdir -p "$PLASMOID_DIR/contents/ui" "$PLASMOID_DIR/contents/icons" "$PLASMOID_DIR/contents/config"
cp "$SCRIPT_DIR/plasmoid/metadata.json" "$PLASMOID_DIR/"
cp -r "$SCRIPT_DIR/plasmoid/contents/ui/"* "$PLASMOID_DIR/contents/ui/"
if [ -d "$SCRIPT_DIR/plasmoid/contents/icons" ]; then
    cp -r "$SCRIPT_DIR/plasmoid/contents/icons/"* "$PLASMOID_DIR/contents/icons/"
fi
if [ -d "$SCRIPT_DIR/plasmoid/contents/config" ]; then
    cp -r "$SCRIPT_DIR/plasmoid/contents/config/"* "$PLASMOID_DIR/contents/config/"
fi
echo "[✓] Plasmoid installed to $PLASMOID_DIR"

# 4. Optional: add to desktop
if command -v qdbus6 >/dev/null 2>&1; then
    echo "[*] Adding widget to current desktop layout..."
    qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "
    var d = desktops();
    if (d.length > 0) {
        var w = d[0].addWidget('org.ryan.deckmonitor');
        if (w) {
            w.userBackgroundHints = 'NoBackground';
        }
    }
    " || true
fi

echo "=== Installation Complete! ==="
