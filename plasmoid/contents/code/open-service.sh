#!/bin/sh
# Opens a service from a Deck Monitor service tile.
# Usage: open-service.sh <syncthing|dropbox|gdrive|tailscale|tmux> <1 if running, 0 if off>
key="$1"; ok="$2"

start_unit() {   # start a systemd user unit if it exists
    systemctl --user cat "$1" >/dev/null 2>&1 && systemctl --user start "$1"
}

case "$key" in
syncthing)
    if [ "$ok" != 1 ]; then
        start_unit syncthing.service || flatpak run com.github.zocker_160.SyncThingy >/dev/null 2>&1 &
        sleep 3
    fi
    xdg-open http://127.0.0.1:8384 ;;
dropbox)
    [ "$ok" != 1 ] && { start_unit dropbox.service || dropbox start; }
    xdg-open "$HOME/Dropbox" ;;
gdrive)
    dir=$(findmnt -t fuse.rclone -no TARGET 2>/dev/null | head -n1)
    xdg-open "${dir:-$HOME}" ;;
tailscale)
    xdg-open https://login.tailscale.com/admin/machines ;;
tmux)
    konsole -e sh -c 'tmux attach 2>/dev/null || tmux new -A -s main' ;;
esac
