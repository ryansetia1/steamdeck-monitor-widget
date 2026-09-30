import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground | PlasmaCore.Types.ConfigurableBackground

    property int baseFontSize: Plasmoid.configuration.fontSizeScale || 12

    preferredRepresentation: fullRepresentation
    implicitWidth: 320 + (baseFontSize - 12) * 15
    implicitHeight: 390 + (baseFontSize - 12) * 16
    Layout.minimumWidth: 280
    Layout.minimumHeight: 350
    Layout.preferredWidth: implicitWidth
    Layout.preferredHeight: implicitHeight

    Component.onCompleted: {
        Plasmoid.userBackgroundHints = PlasmaCore.Types.NoBackground;
    }

    fullRepresentation: Item {
        id: container
        anchors.fill: parent

        // State properties
        property var monitorData: ({
            cpu_percent: 0,
            memory: { percent: 0, used_gb: 0, total_gb: 0 },
            storage: { percent: 0, used_gb: 0, total_gb: 0, free_gb: 0 },
            sdcard: { mounted: false, percent: 0, used_gb: 0, total_gb: 0, free_gb: 0 },
            battery: { percent: 0, status: "Unknown", health: "N/A", is_plugged: false, is_charging: false, charge_label: "Discharging" },
            temp: "N/A",
            wifi: { name: "Disconnected", is_tethering: false, icon: "network-wireless-disconnected-symbolic", connected: false },
            services: { syncthing: false, dropbox: false, rclone: false, tmux_sessions: 0, tailscale: false },
            ping: "..."
        })
        property bool isConnected: false

        function fetchMetrics() {
            var xhr = new XMLHttpRequest();
            xhr.open("GET", "http://127.0.0.1:19842/status");
            xhr.timeout = 1800;
            xhr.onreadystatechange = function() {
                if (xhr.readyState === XMLHttpRequest.DONE) {
                    if (xhr.status === 200) {
                        try {
                            container.monitorData = JSON.parse(xhr.responseText);
                            container.isConnected = true;
                        } catch (e) {
                            container.isConnected = false;
                        }
                    } else {
                        container.isConnected = false;
                    }
                }
            };
            xhr.ontimeout = function() {
                container.isConnected = false;
            };
            xhr.send();
        }

        function getBarColor(pct) {
            if (pct >= 85) return "#ff5252";
            if (pct >= 70) return "#ffa726";
            return "#00e676";
        }

        Timer {
            id: pollTimer
            interval: 2000
            running: true
            repeat: true
            triggeredOnStart: true
            onTriggered: container.fetchMetrics()
        }

        // Background Card with smooth rounded corners
        Rectangle {
            anchors.fill: parent
            color: "#161820"
            radius: 16
            border.color: container.isConnected ? "#2c3242" : "#4a2424"
            border.width: 1
            clip: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 9

                // --- HEADER ---
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Rectangle {
                        width: 8
                        height: 8
                        radius: 4
                        color: container.isConnected ? "#00e676" : "#ff5252"
                    }

                    Text {
                        text: "DECK MONITOR"
                        color: "#ffffff"
                        font.pixelSize: root.baseFontSize + 2
                        font.bold: true
                        font.letterSpacing: 1.1
                    }

                    Item { Layout.fillWidth: true }

                    // Ping Indicator Badge
                    Rectangle {
                        color: "#212532"
                        radius: 8
                        height: root.baseFontSize + 10
                        Layout.preferredWidth: pingRow.implicitWidth + 12
                        Layout.maximumWidth: 100

                        RowLayout {
                            id: pingRow
                            anchors.centerIn: parent
                            spacing: 4

                            Rectangle {
                                width: 5
                                height: 5
                                radius: 2.5
                                color: (container.monitorData.ping && container.monitorData.ping !== "Offline") ? "#00e5ff" : "#ff5252"
                            }
                            Text {
                                text: container.monitorData.ping ? container.monitorData.ping : "..."
                                color: "#cfd8dc"
                                font.pixelSize: root.baseFontSize - 2
                                font.bold: true
                            }
                        }
                    }
                }

                // --- WI-FI STATUS BAR ---
                Rectangle {
                    Layout.fillWidth: true
                    height: root.baseFontSize + 14
                    radius: 8
                    color: "#1e222d"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 6

                        Text {
                            text: (container.monitorData.wifi && container.monitorData.wifi.is_tethering) ? "Hotspot" : "Wi-Fi"
                            color: "#cfd8dc"
                            font.pixelSize: root.baseFontSize - 1
                            font.bold: true
                        }

                        Item { Layout.fillWidth: true }

                        RowLayout {
                            spacing: 5
                            Layout.alignment: Qt.AlignRight

                            Kirigami.Icon {
                                source: (container.monitorData.wifi && container.monitorData.wifi.icon) ? container.monitorData.wifi.icon : "network-wireless-symbolic"
                                Layout.preferredWidth: root.baseFontSize + 1
                                Layout.preferredHeight: root.baseFontSize + 1
                            }
                            Text {
                                text: (container.monitorData.wifi && container.monitorData.wifi.name) ? container.monitorData.wifi.name : "Offline"
                                color: (container.monitorData.wifi && container.monitorData.wifi.connected) ? "#ffffff" : "#ef5350"
                                font.pixelSize: root.baseFontSize - 1
                                font.bold: true
                                elide: Text.ElideRight
                                Layout.maximumWidth: 160
                            }
                        }
                    }
                }

                // Divider
                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: "#242834"
                }

                // --- HARDWARE SECTION (CPU, RAM) ---
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 7

                    // CPU
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "CPU"; color: "#cfd8dc"; font.pixelSize: root.baseFontSize - 1; font.bold: true }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: (container.monitorData.cpu_percent || 0).toFixed(1) + "%"
                                color: "#ffffff"
                                font.pixelSize: root.baseFontSize - 1
                                font.bold: true
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 6
                            radius: 3
                            color: "#242936"
                            Rectangle {
                                width: Math.max(0, Math.min(parent.width, parent.width * ((container.monitorData.cpu_percent || 0) / 100.0)))
                                height: parent.height
                                radius: 3
                                color: container.getBarColor(container.monitorData.cpu_percent || 0)
                                Behavior on width { NumberAnimation { duration: 250 } }
                            }
                        }
                    }

                    // RAM
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "RAM"; color: "#cfd8dc"; font.pixelSize: root.baseFontSize - 1; font.bold: true }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: (container.monitorData.memory.used_gb || 0) + " / " + (container.monitorData.memory.total_gb || 0) + " GB (" + Math.round(container.monitorData.memory.percent || 0) + "%)"
                                color: "#ffffff"
                                font.pixelSize: root.baseFontSize - 1
                                font.bold: true
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 6
                            radius: 3
                            color: "#242936"
                            Rectangle {
                                width: Math.max(0, Math.min(parent.width, parent.width * ((container.monitorData.memory.percent || 0) / 100.0)))
                                height: parent.height
                                radius: 3
                                color: container.getBarColor(container.monitorData.memory.percent || 0)
                                Behavior on width { NumberAnimation { duration: 250 } }
                            }
                        }
                    }

                    // --- SIDE-BY-SIDE STORAGE (INTERNAL & MICROSD) ---
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        // Internal Storage (Left)
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            spacing: 2

                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: "Internal"; color: "#cfd8dc"; font.pixelSize: root.baseFontSize - 1; font.bold: true }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: (container.monitorData.storage.percent || 0).toFixed(1) + "%"
                                    color: "#ffffff"
                                    font.pixelSize: root.baseFontSize - 1
                                    font.bold: true
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 6
                                radius: 3
                                color: "#242936"
                                Rectangle {
                                    width: Math.max(0, Math.min(parent.width, parent.width * ((container.monitorData.storage.percent || 0) / 100.0)))
                                    height: parent.height
                                    radius: 3
                                    color: container.getBarColor(container.monitorData.storage.percent || 0)
                                    Behavior on width { NumberAnimation { duration: 250 } }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: (container.monitorData.storage.used_gb || 0) + "/" + Math.round(container.monitorData.storage.total_gb || 0) + "G"
                                    color: "#90a4ae"
                                    font.pixelSize: root.baseFontSize - 3
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: (container.monitorData.storage.free_gb || 0) + "G free"
                                    color: "#eceff1"
                                    font.pixelSize: root.baseFontSize - 3
                                    font.bold: true
                                }
                            }
                        }

                        // MicroSD Storage (Right)
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            spacing: 2

                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: "MicroSD"; color: "#cfd8dc"; font.pixelSize: root.baseFontSize - 1; font.bold: true }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: container.monitorData.sdcard.mounted ? ((container.monitorData.sdcard.percent || 0).toFixed(1) + "%") : "N/A"
                                    color: container.monitorData.sdcard.mounted ? "#ffffff" : "#90a4ae"
                                    font.pixelSize: root.baseFontSize - 1
                                    font.bold: true
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 6
                                radius: 3
                                color: "#242936"
                                Rectangle {
                                    width: container.monitorData.sdcard.mounted ? Math.max(0, Math.min(parent.width, parent.width * ((container.monitorData.sdcard.percent || 0) / 100.0))) : 0
                                    height: parent.height
                                    radius: 3
                                    color: container.getBarColor(container.monitorData.sdcard.percent || 0)
                                    Behavior on width { NumberAnimation { duration: 250 } }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: container.monitorData.sdcard.mounted ? (Math.round(container.monitorData.sdcard.used_gb || 0) + "/" + Math.round(container.monitorData.sdcard.total_gb || 0) + "G") : "Not Inserted"
                                    color: "#90a4ae"
                                    font.pixelSize: root.baseFontSize - 3
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: container.monitorData.sdcard.mounted ? (Math.round(container.monitorData.sdcard.free_gb || 0) + "G free") : ""
                                    color: "#eceff1"
                                    font.pixelSize: root.baseFontSize - 3
                                    font.bold: true
                                }
                            }
                        }
                    }
                }

                // Divider
                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: "#242834"
                }

                // --- TEMP & BATTERY ROW ---
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 7

                    // Temp Badge
                    Rectangle {
                        Layout.fillWidth: true
                        height: root.baseFontSize + 38
                        radius: 10
                        color: "#1e222d"

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 1
                            Text {
                                text: "APU TEMP"
                                color: "#90a4ae"
                                font.pixelSize: root.baseFontSize - 3
                                font.bold: true
                                Layout.alignment: Qt.AlignHCenter
                            }
                            Text {
                                text: container.monitorData.temp || "N/A"
                                color: "#ffb74d"
                                font.pixelSize: root.baseFontSize + 3
                                font.bold: true
                                Layout.alignment: Qt.AlignHCenter
                            }
                        }
                    }

                    // Battery Badge
                    Rectangle {
                        Layout.fillWidth: true
                        height: root.baseFontSize + 38
                        radius: 10
                        color: "#1e222d"

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 1
                            Text {
                                text: "BATTERY"
                                color: "#90a4ae"
                                font.pixelSize: root.baseFontSize - 3
                                font.bold: true
                                Layout.alignment: Qt.AlignHCenter
                            }
                            Text {
                                text: (container.monitorData.battery.is_plugged ? "⚡ " : "") + (container.monitorData.battery.percent || 0) + "%"
                                color: container.monitorData.battery.is_plugged ? "#00e676" : "#ffffff"
                                font.pixelSize: root.baseFontSize + 3
                                font.bold: true
                                Layout.alignment: Qt.AlignHCenter
                            }
                            Text {
                                text: container.monitorData.battery.charge_label ? container.monitorData.battery.charge_label.toUpperCase() : "DISCHARGING"
                                color: container.monitorData.battery.is_plugged ? "#00e676" : "#78909c"
                                font.pixelSize: root.baseFontSize - 3
                                font.bold: true
                                Layout.alignment: Qt.AlignHCenter
                            }
                        }
                    }

                    // Battery Health Badge
                    Rectangle {
                        Layout.fillWidth: true
                        height: root.baseFontSize + 38
                        radius: 10
                        color: "#1e222d"

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 1
                            Text {
                                text: "BAT HEALTH"
                                color: "#90a4ae"
                                font.pixelSize: root.baseFontSize - 3
                                font.bold: true
                                Layout.alignment: Qt.AlignHCenter
                            }
                            Text {
                                text: container.monitorData.battery.health || "N/A"
                                color: "#4dd0e1"
                                font.pixelSize: root.baseFontSize + 3
                                font.bold: true
                                Layout.alignment: Qt.AlignHCenter
                            }
                            Text {
                                text: "HEALTH"
                                color: "#546e7a"
                                font.pixelSize: root.baseFontSize - 3
                                font.bold: true
                                Layout.alignment: Qt.AlignHCenter
                            }
                        }
                    }
                }

                // Divider
                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: "#242834"
                }

                // --- SERVICES GRID ---
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 5

                    Text {
                        text: "SERVICES"
                        color: "#78909c"
                        font.pixelSize: root.baseFontSize - 2
                        font.bold: true
                        font.letterSpacing: 0.8
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: 7
                        rowSpacing: 5

                        // Syncthing
                        Rectangle {
                            Layout.fillWidth: true
                            height: root.baseFontSize + 14
                            radius: 8
                            color: "#1e222d"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 6
                                anchors.rightMargin: 6
                                spacing: 4
                                Kirigami.Icon {
                                    source: "syncthing"
                                    Layout.preferredWidth: root.baseFontSize + 1
                                    Layout.preferredHeight: root.baseFontSize + 1
                                }
                                Text {
                                    text: "Syncthing"
                                    color: "#cfd8dc"
                                    font.pixelSize: root.baseFontSize - 2
                                    font.bold: true
                                    elide: Text.ElideRight
                                    Layout.maximumWidth: parent.width * 0.55
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: container.monitorData.services.syncthing ? "ACTIVE" : "OFF"
                                    color: container.monitorData.services.syncthing ? "#00e676" : "#78909c"
                                    font.pixelSize: root.baseFontSize - 3
                                    font.bold: true
                                }
                            }
                        }

                        // Dropbox
                        Rectangle {
                            Layout.fillWidth: true
                            height: root.baseFontSize + 14
                            radius: 8
                            color: "#1e222d"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 6
                                anchors.rightMargin: 6
                                spacing: 4
                                Image {
                                    source: Qt.resolvedUrl("../icons/dropbox.svg")
                                    Layout.preferredWidth: root.baseFontSize + 1
                                    Layout.preferredHeight: root.baseFontSize + 1
                                    sourceSize.width: 32
                                    sourceSize.height: 32
                                    fillMode: Image.PreserveAspectFit
                                }
                                Text {
                                    text: "Dropbox"
                                    color: "#cfd8dc"
                                    font.pixelSize: root.baseFontSize - 2
                                    font.bold: true
                                    elide: Text.ElideRight
                                    Layout.maximumWidth: parent.width * 0.55
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: container.monitorData.services.dropbox ? "ACTIVE" : "OFF"
                                    color: container.monitorData.services.dropbox ? "#00e676" : "#78909c"
                                    font.pixelSize: root.baseFontSize - 3
                                    font.bold: true
                                }
                            }
                        }

                        // Rclone
                        Rectangle {
                            Layout.fillWidth: true
                            height: root.baseFontSize + 14
                            radius: 8
                            color: "#1e222d"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 6
                                anchors.rightMargin: 6
                                spacing: 4
                                Kirigami.Icon {
                                    source: "folder-gdrive"
                                    Layout.preferredWidth: root.baseFontSize + 1
                                    Layout.preferredHeight: root.baseFontSize + 1
                                }
                                Text {
                                    text: "Rclone"
                                    color: "#cfd8dc"
                                    font.pixelSize: root.baseFontSize - 2
                                    font.bold: true
                                    elide: Text.ElideRight
                                    Layout.maximumWidth: parent.width * 0.55
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: container.monitorData.services.rclone ? "ACTIVE" : "OFF"
                                    color: container.monitorData.services.rclone ? "#00e676" : "#78909c"
                                    font.pixelSize: root.baseFontSize - 3
                                    font.bold: true
                                }
                            }
                        }

                        // Tailscale
                        Rectangle {
                            Layout.fillWidth: true
                            height: root.baseFontSize + 14
                            radius: 8
                            color: "#1e222d"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 6
                                anchors.rightMargin: 6
                                spacing: 4
                                Kirigami.Icon {
                                    source: "network-vpn"
                                    Layout.preferredWidth: root.baseFontSize + 1
                                    Layout.preferredHeight: root.baseFontSize + 1
                                }
                                Text {
                                    text: "Tailscale"
                                    color: "#cfd8dc"
                                    font.pixelSize: root.baseFontSize - 2
                                    font.bold: true
                                    elide: Text.ElideRight
                                    Layout.maximumWidth: parent.width * 0.55
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: container.monitorData.services.tailscale ? "ONLINE" : "OFF"
                                    color: container.monitorData.services.tailscale ? "#00e676" : "#78909c"
                                    font.pixelSize: root.baseFontSize - 3
                                    font.bold: true
                                }
                            }
                        }
                    }

                    // Tmux Bar
                    Rectangle {
                        Layout.fillWidth: true
                        height: root.baseFontSize + 14
                        radius: 8
                        color: "#1e222d"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 6
                            anchors.rightMargin: 6
                            spacing: 4
                            Kirigami.Icon {
                                source: "utilities-terminal"
                                Layout.preferredWidth: root.baseFontSize + 1
                                Layout.preferredHeight: root.baseFontSize + 1
                            }
                            Text { text: "Tmux Sessions"; color: "#cfd8dc"; font.pixelSize: root.baseFontSize - 2; font.bold: true }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: (container.monitorData.services.tmux_sessions > 0) ? (container.monitorData.services.tmux_sessions + " Active") : "No Session"
                                color: (container.monitorData.services.tmux_sessions > 0) ? "#00e676" : "#78909c"
                                font.pixelSize: root.baseFontSize - 3
                                font.bold: true
                            }
                        }
                    }
                }
            }
        }
    }
}
