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
    echo "[*] Adding widget to desktop layout(s)..."
    qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "
    var d = desktops();
    for (var i = 0; i < d.length; i++) {
        var ws = d[i].widgets();
        var has = false;
        for (var j = 0; j < ws.length; j++) {
            if (ws[j].type === 'org.ryan.deckmonitor') has = true;
        }
        if (!has) {
            var w = d[i].addWidget('org.ryan.deckmonitor');
            if (w) {
                w.userBackgroundHints = 'NoBackground';
            }
        }
    }
    " || true
fi

# 5. Install the panel ping indicator (compact "Ping xx ms" text for the taskbar)
PING_DIR="$HOME/.local/share/plasma/plasmoids/org.ryan.deckping"
mkdir -p "$PING_DIR"
cp "$SCRIPT_DIR/panel-ping/metadata.json" "$PING_DIR/"
cp -r "$SCRIPT_DIR/panel-ping/contents" "$PING_DIR/"
echo "[✓] Panel ping widget installed to $PING_DIR"

# 6. Add it to the taskbar, just left of the clock (skipped if already there)
if command -v qdbus6 >/dev/null 2>&1 && pgrep -x plasmashell >/dev/null; then
    echo "[*] Adding ping indicator to the taskbar..."
    RESULT=$(qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "
    var res = 'none';
    var ps = panels();
    for (var i = 0; i < ps.length && res === 'none'; i++) {
        var ws = ps[i].widgets();
        var clock = null, has = false;
        for (var j = 0; j < ws.length; j++) {
            if (ws[j].type === 'org.kde.plasma.digitalclock') clock = ws[j];
            if (ws[j].type === 'org.ryan.deckping') has = true;
        }
        if (clock && !has) {
            var w = ps[i].addWidget('org.ryan.deckping');
            res = 'added ' + w.id + ' ' + clock.id;
        } else if (has) { res = 'exists'; }
    }
    print(res);" 2>/dev/null || echo none)
    case "$RESULT" in
        added*)
            PING_ID=$(echo "$RESULT" | awk '{print $2}')
            CLOCK_ID=$(echo "$RESULT" | awk '{print $3}')
            # New widgets land at the far right; move it before the clock.
            # Plasma only reads the order at startup, so briefly restart the shell.
            kquitapp6 plasmashell >/dev/null 2>&1 || true
            for _ in $(seq 1 15); do pgrep -x plasmashell >/dev/null || break; sleep 1; done
            python3 - "$PING_ID" "$CLOCK_ID" <<'PYEOF'
import re, sys, os
ping, clock = sys.argv[1], sys.argv[2]
path = os.path.expanduser("~/.config/plasma-org.kde.plasma.desktop-appletsrc")
lines = open(path).read().split("\n")
for i, l in enumerate(lines):
    if l.startswith("AppletOrder="):
        ids = l.split("=", 1)[1].split(";")
        if ping in ids and clock in ids:
            ids.remove(ping)
            ids.insert(ids.index(clock), ping)
            lines[i] = "AppletOrder=" + ";".join(ids)
open(path, "w").write("\n".join(lines))
PYEOF
            nohup setsid plasmashell >/dev/null 2>&1 &
            echo "[✓] Ping indicator added next to the clock"
            ;;
        exists) echo "[✓] Ping indicator already on the taskbar" ;;
        *) echo "[!] Could not auto-add it. Right-click the panel → Add Widgets → 'Deck Ping'." ;;
    esac
fi

echo "=== Installation Complete! ==="
