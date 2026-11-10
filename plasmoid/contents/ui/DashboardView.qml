import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Fullscreen dock dashboard for the Steam Deck's internal 1280x800 panel.
// Tuned to be read from arm's length: few elements, big numbers, high contrast.
Item {
    id: dash

    property var d: ({})
    property bool connected: false
    property bool glass: false
    signal restoreRequested()

    // ---------- palette ----------
    readonly property color cBg: glass ? "transparent" : "#0c0f14"
    readonly property color cCard: glass ? Qt.rgba(1, 1, 1, 0.07) : "#161b24"
    readonly property color cBorder: glass ? Qt.rgba(1, 1, 1, 0.12) : "#252c3a"
    readonly property color cTrack: glass ? Qt.rgba(1, 1, 1, 0.10) : "#262d3b"
    readonly property color cText: "#f5f7fa"
    readonly property color cLabel: "#a9b6c8"
    readonly property color cMuted: "#8b99ad"
    readonly property color cGreen: "#4ade80"
    readonly property color cAmber: "#fbbf24"
    readonly property color cRed: "#f87171"
    readonly property color cBlue: "#60a5fa"
    readonly property color cOff: "#5b6678"

    // ---------- data helpers ----------
    readonly property var mem: d.memory || {}
    readonly property var disk: d.storage || {}
    readonly property var sd: d.sdcard || {}
    readonly property var bat: d.battery || {}
    readonly property var wifi: d.wifi || {}
    readonly property var svc: d.services || {}
    readonly property real cpu: d.cpu_percent || 0
    readonly property real tempC: parseFloat(d.temp)
    readonly property real pingMs: parseFloat(d.ping)
    readonly property bool pingOk: !isNaN(pingMs)
    readonly property var drives: {
        var list = [{ name: "Internal SSD", pct: disk.percent || 0, free: disk.free_gb || 0, total: disk.total_gb || 0 }];
        if (sd.mounted)
            list.push({ name: "microSD", pct: sd.percent || 0, free: sd.free_gb || 0, total: sd.total_gb || 0 });
        var ext = d.external_drives || [];
        for (var i = 0; i < ext.length; i++)
            list.push({ name: ext[i].name || "External drive", pct: ext[i].percent || 0,
                        free: ext[i].free_gb || 0, total: ext[i].total_gb || 0 });
        return list;
    }
    // Two drives get the roomy layout; three or more switch to single-line rows
    readonly property bool compactDrives: drives.length > 2

    function loadColor(p) { return p >= 85 ? cRed : (p >= 70 ? cAmber : cGreen) }
    function tempColor(t) { return isNaN(t) ? cMuted : (t >= 85 ? cRed : (t >= 70 ? cAmber : cGreen)) }
    function batColor(p, plugged) { return plugged ? cGreen : (p <= 20 ? cRed : (p <= 40 ? cAmber : cGreen)) }
    function pingColor() { return !pingOk ? cRed : (pingMs <= 80 ? cGreen : (pingMs <= 150 ? cAmber : cRed)) }
    function gb(v) { v = v || 0; return v >= 100 ? Math.round(v) : v.toFixed(1) }

    // ---------- reusable pieces ----------
    component Card: Rectangle {
        color: dash.cCard
        radius: 14
        border.color: dash.cBorder
        border.width: 1
    }

    component Caption: Text {
        color: dash.cLabel
        font.pixelSize: 17
        font.weight: Font.DemiBold
        font.letterSpacing: 1.6
        font.capitalization: Font.AllUppercase
    }

    component Bar: Rectangle {
        property real pct: 0
        property color fill: dash.cGreen
        implicitHeight: 14
        radius: height / 2
        color: dash.cTrack
        Rectangle {
            height: parent.height
            radius: parent.radius
            width: Math.max(parent.height, parent.width * Math.max(0, Math.min(1, parent.pct / 100)))
            visible: parent.pct > 0
            color: parent.fill
            Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
        }
    }

    // Big-number tile: caption + status, huge value, one supporting line, bar.
    component HeroTile: Card {
        id: hero
        property string label
        property string status
        property string value
        property string unit
        property string sub
        property real pct: 0
        property color accent: dash.cGreen
        property bool charging: false   // shows a bolt above the unit

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 22
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Caption { text: hero.label }
                Item { Layout.fillWidth: true }
                Text {
                    text: hero.status
                    visible: text.length > 0
                    color: hero.accent
                    font.pixelSize: 16
                    font.weight: Font.Bold
                    font.letterSpacing: 1.2
                }
            }

            Item { Layout.fillHeight: true }

            Row {
                spacing: 4
                Text {
                    id: bigNum
                    text: hero.value
                    color: dash.cText
                    font.pixelSize: 116
                    font.weight: Font.Bold
                    font.letterSpacing: -3
                }
                Text {
                    text: hero.unit
                    color: hero.accent
                    font.pixelSize: 46
                    font.weight: Font.Bold
                    anchors.baseline: bigNum.baseline
                    Image {
                        visible: hero.charging
                        source: Qt.resolvedUrl("../icons/bolt.svg")
                        width: 30; height: 40
                        sourceSize: Qt.size(60, 80)
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.top
                        anchors.bottomMargin: -2
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.topMargin: 2
                text: hero.sub
                color: dash.cLabel
                font.pixelSize: 21
                font.weight: Font.Medium
                elide: Text.ElideRight
            }

            Item { Layout.preferredHeight: 18 }

            Bar {
                Layout.fillWidth: true
                implicitHeight: 16
                pct: hero.pct
                fill: hero.accent
            }
        }
    }

    component DriveRow: ColumnLayout {
        id: drive
        property string name
        property real pct: 0
        property real freeGb: 0
        property real totalGb: 0
        property bool compact: false
        spacing: compact ? 6 : 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Text {
                text: drive.name
                color: dash.cText
                font.pixelSize: drive.compact ? 19 : 21
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            Text {
                visible: drive.compact
                text: dash.gb(drive.freeGb) + " GB free"
                color: dash.cLabel
                font.pixelSize: 16
            }
            Text {
                text: Math.round(drive.pct) + "%"
                color: dash.loadColor(drive.pct)
                font.pixelSize: drive.compact ? 22 : 28
                font.weight: Font.Bold
            }
        }
        Bar {
            Layout.fillWidth: true
            implicitHeight: drive.compact ? 8 : 12
            pct: drive.pct
            fill: dash.loadColor(drive.pct)
        }
        Text {
            visible: !drive.compact
            text: dash.gb(drive.freeGb) + " GB free of " + dash.gb(drive.totalGb) + " GB"
            color: dash.cLabel
            font.pixelSize: 18
        }
    }

    // ---------- layout ----------
    Rectangle { anchors.fill: parent; color: dash.cBg }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 16

        // Header: identity + live state on the left, clock + restore on the right
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 44
            spacing: 14

            Image {
                source: Qt.resolvedUrl("../icons/steamdeck.svg")
                Layout.preferredWidth: 30
                Layout.preferredHeight: 30
                sourceSize: Qt.size(60, 60)
                fillMode: Image.PreserveAspectFit
            }
            Text {
                text: "Steam Deck"
                color: dash.cText
                font.pixelSize: 24
                font.weight: Font.Bold
            }
            // Only speaks up when something is wrong
            Text {
                visible: !dash.connected
                Layout.leftMargin: 8
                text: "Monitor daemon not responding"
                color: dash.cRed
                font.pixelSize: 18
                font.weight: Font.DemiBold
            }

            Item { Layout.fillWidth: true }

            // e.g. "Mon, 10 Nov 2026"  20:17
            Text {
                id: dateLabel
                Layout.alignment: Qt.AlignBaseline
                color: dash.cLabel
                font.pixelSize: 24
                font.weight: Font.DemiBold
            }
            Text {
                id: clock
                Layout.leftMargin: 10
                Layout.alignment: Qt.AlignBaseline
                color: dash.cText
                font.pixelSize: 34
                font.weight: Font.Bold
                font.features: { "tnum": 1 }
                Timer {
                    interval: 5000; running: dash.visible; repeat: true; triggeredOnStart: true
                    onTriggered: {
                        var now = new Date();
                        clock.text = Qt.formatTime(now, "HH:mm");
                        dateLabel.text = now.toLocaleDateString(Qt.locale("en_US"), "ddd, d MMM yyyy");
                    }
                }
            }

            Rectangle {
                Layout.leftMargin: 6
                Layout.preferredWidth: 44
                Layout.preferredHeight: 44
                radius: 10
                color: restoreMouse.containsMouse ? dash.cTrack : dash.cCard
                border.color: dash.cBorder
                border.width: 1
                Kirigami.Icon {
                    anchors.centerIn: parent
                    width: 22; height: 22
                    source: "view-restore"
                }
                MouseArea {
                    id: restoreMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: dash.restoreRequested()
                }
            }
        }

        // Row 1: the four numbers you glance at
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: 6
            spacing: 16

            HeroTile {
                Layout.fillWidth: true; Layout.fillHeight: true; Layout.preferredWidth: 1
                label: "APU Temp"
                status: isNaN(dash.tempC) ? "" : (dash.tempC >= 85 ? "HOT" : (dash.tempC >= 70 ? "WARM" : "NORMAL"))
                value: isNaN(dash.tempC) ? "--" : Math.round(dash.tempC)
                unit: "°C"
                sub: "Throttles at 85°C"
                pct: isNaN(dash.tempC) ? 0 : dash.tempC
                accent: dash.tempColor(dash.tempC)
            }
            HeroTile {
                Layout.fillWidth: true; Layout.fillHeight: true; Layout.preferredWidth: 1
                label: "Battery"
                status: dash.bat.is_charging ? "CHARGING" : (dash.bat.is_plugged ? "PLUGGED IN" : "ON BATTERY")
                value: dash.bat.percent !== undefined ? dash.bat.percent : "--"
                unit: "%"
                sub: "Health " + (dash.bat.health || "N/A")
                pct: dash.bat.percent || 0
                accent: dash.batColor(dash.bat.percent || 0, dash.bat.is_plugged)
                charging: !!dash.bat.is_plugged
            }
            HeroTile {
                Layout.fillWidth: true; Layout.fillHeight: true; Layout.preferredWidth: 1
                label: "CPU"
                value: Math.round(dash.cpu)
                unit: "%"
                sub: "4 cores · 8 threads"
                pct: dash.cpu
                accent: dash.loadColor(dash.cpu)
            }
            HeroTile {
                Layout.fillWidth: true; Layout.fillHeight: true; Layout.preferredWidth: 1
                label: "Memory"
                value: Math.round(dash.mem.percent || 0)
                unit: "%"
                sub: dash.gb(dash.mem.used_gb) + " / " + dash.gb(dash.mem.total_gb) + " GB"
                pct: dash.mem.percent || 0
                accent: dash.loadColor(dash.mem.percent || 0)
            }
        }

        // Row 2: storage, network, services
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: 5
            spacing: 16

            // Storage
            Card {
                Layout.fillWidth: true; Layout.fillHeight: true; Layout.preferredWidth: 1
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 22
                    spacing: 0
                    RowLayout {
                        Layout.fillWidth: true
                        Caption { text: "Storage" }
                        Item { Layout.fillWidth: true }
                        Text {
                            visible: dash.drives.length > 1
                            text: dash.drives.length + " DRIVES"
                            color: dash.cMuted
                            font.pixelSize: 16
                            font.weight: Font.Bold
                            font.letterSpacing: 1.2
                        }
                    }
                    Item { Layout.preferredHeight: dash.compactDrives ? 6 : 0 }
                    // Each drive gets an equal slice of the card; rows appear/disappear as drives are (un)plugged
                    Repeater {
                        model: dash.drives
                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.minimumHeight: row.implicitHeight
                            DriveRow {
                                id: row
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                compact: dash.compactDrives
                                name: modelData.name
                                pct: modelData.pct
                                freeGb: modelData.free
                                totalGb: modelData.total
                            }
                        }
                    }
                }
            }

            // Network
            Card {
                Layout.fillWidth: true; Layout.fillHeight: true; Layout.preferredWidth: 1
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 22
                    spacing: 0
                    RowLayout {
                        Layout.fillWidth: true
                        Caption { text: "Network" }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: !dash.wifi.connected ? "OFFLINE" : (dash.wifi.is_tethering ? "HOTSPOT" : "WI-FI")
                            color: dash.wifi.connected ? dash.cBlue : dash.cRed
                            font.pixelSize: 16
                            font.weight: Font.Bold
                            font.letterSpacing: 1.2
                        }
                    }
                    Item { Layout.fillHeight: true }
                    Text {
                        Layout.fillWidth: true
                        text: dash.wifi.name || "Disconnected"
                        color: dash.cText
                        font.pixelSize: 30
                        font.weight: Font.Bold
                        elide: Text.ElideRight
                    }
                    Item { Layout.fillHeight: true }
                    Text {
                        text: "Ping"
                        color: dash.cMuted
                        font.pixelSize: 18
                    }
                    Row {
                        spacing: 6
                        Text {
                            id: pingNum
                            text: dash.pingOk ? Math.round(dash.pingMs) : (dash.d.ping === "Offline" ? "Offline" : "…")
                            color: dash.pingColor()
                            font.pixelSize: dash.pingOk ? 72 : 44
                            font.weight: Font.Bold
                            font.letterSpacing: -1
                        }
                        Text {
                            visible: dash.pingOk
                            text: "ms"
                            color: dash.cLabel
                            font.pixelSize: 28
                            font.weight: Font.Bold
                            anchors.baseline: pingNum.baseline
                        }
                    }
                    Item { Layout.fillHeight: true }
                }
            }

            // Services
            Card {
                Layout.fillWidth: true; Layout.fillHeight: true; Layout.preferredWidth: 1
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 22
                    spacing: 0
                    Caption { text: "Services" }
                    Item { Layout.preferredHeight: 8 }
                    Repeater {
                        model: [
                            { name: "Syncthing",    icon: "syncthing.svg",     ok: !!dash.svc.syncthing, on: "Active",  off: "Off" },
                            { name: "Dropbox",      icon: "dropbox.svg",       ok: !!dash.svc.dropbox,   on: "Synced",  off: "Off" },
                            { name: "Google Drive", icon: "google-drive.svg",  ok: !!dash.svc.rclone,    on: "Mounted", off: "Off" },
                            { name: "Tailscale",    icon: "tailscale.svg",     ok: !!dash.svc.tailscale, on: "Online",  off: "Off" },
                            { name: "tmux",         icon: "tmux.png",          ok: (dash.svc.tmux_sessions || 0) > 0,
                              on: (dash.svc.tmux_sessions || 0) + " open", off: "None" }
                        ]
                        Item {
                          Layout.fillWidth: true
                          Layout.fillHeight: true
                          RowLayout {
                            anchors.fill: parent
                            spacing: 14
                            Image {
                                source: Qt.resolvedUrl("../icons/" + modelData.icon)
                                Layout.preferredWidth: 30
                                Layout.preferredHeight: 30
                                sourceSize: Qt.size(60, 60)
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                                opacity: modelData.ok ? 1.0 : 0.5
                            }
                            Text {
                                text: modelData.name
                                color: modelData.ok ? dash.cText : dash.cMuted
                                font.pixelSize: 22
                                font.weight: Font.DemiBold
                                Layout.fillWidth: true
                            }
                            Text {
                                text: modelData.ok ? modelData.on : modelData.off
                                color: modelData.ok ? dash.cGreen : dash.cMuted
                                font.pixelSize: 19
                                font.weight: Font.DemiBold
                            }
                          }
                        }
                    }
                }
            }
        }
    }
}
