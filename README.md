# 🎮 Steam Deck Desktop Monitor Widget

A lightweight, modern, and comprehensive desktop monitoring widget designed specifically for the **Steam Deck** running **KDE Plasma 6**.

Built with native QML/Plasma and a zero-dependency Python background daemon consuming less than 10MB of RAM.

---

## ⚡ Features Monitored

- **Hardware & Resources**:
  - **CPU Usage**: Real-time percent with dynamic color-changing progress bar (Blue → Orange → Red).
  - **RAM Usage**: Used vs. Total GB (e.g. `4.5 / 14.5 GB`), percent, and progress bar.
  - **Internal Storage**: `/home` disk space usage with visual progress bar, used/total GB, and remaining free space.
  - **MicroSD Card Storage**: `/run/media/deck/SDcard` disk space usage with visual progress bar and free space (auto-detects unmounted state).
- **Thermals & Battery**:
  - **APU Temperature**: Real-time Steam Deck APU temperature (via AMDGPU hwmon).
  - **Battery Percentage & Charging State**: Real-time level with prominent `⚡` icon and dynamic `CHARGING` / `PLUGGED IN` / `DISCHARGING` status.
  - **Battery Health**: Accurate health calculation (`charge_full` / `charge_full_design`).
- **Network & Connectivity**:
  - **Connected Wi-Fi**: Active network SSID display with offline detection.
  - **Ping Latency**: Ping time in ms to global DNS (`1.1.1.1`), with automatic offline detection and responsive layout.
  - **Tailscale**: VPN mesh status badge (`ONLINE` / `OFF`).
- **Background Services**:
  - **Syncthing**: Sync daemon status (`ACTIVE` / `OFF`).
  - **Dropbox**: File sync status (`ACTIVE` / `OFF`).
  - **Rclone (Google Drive)**: Cloud mount service status (`ACTIVE` / `OFF`).
  - **Tmux**: Active session counter (`X Active` / `No Session`).

---

## 🚀 Quick Installation

Clone this repository and run the install script:

```bash
git clone https://github.com/ryansetia1/steamdeck-monitor-widget.git
cd steamdeck-monitor-widget
chmod +x install.sh
./install.sh
```

The script will:
1. Copy the background daemon to `~/.local/bin/deck-monitor-daemon.py`.
2. Register and start the user systemd service (`deck-monitor.service`).
3. Install the Plasma 6 plasmoid to `~/.local/share/plasma/plasmoids/org.ryan.deckmonitor`.
4. Automatically append the widget to your current desktop screen.

---

## 🛠️ Manual Controls

### Service Management
```bash
# Check service status
systemctl --user status deck-monitor.service

# Restart service
systemctl --user restart deck-monitor.service

# Stop service
systemctl --user stop deck-monitor.service
```

### Inspect Metrics Endpoint
The background daemon serves a fast JSON endpoint on localhost:
```bash
curl -s http://127.0.0.1:19842/status
```

---

## 🗑️ Uninstallation

To cleanly remove the widget and background service:

```bash
./uninstall.sh
```

---

## 📜 License
MIT License
