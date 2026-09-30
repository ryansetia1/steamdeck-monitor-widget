import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground | PlasmaCore.Types.ConfigurableBackground

    preferredRepresentation: fullRepresentation
    implicitWidth: 320
    implicitHeight: 380
    Layout.minimumWidth: 270
    Layout.minimumHeight: 350
    Layout.preferredWidth: 330
    Layout.preferredHeight: 390

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
            wifi: "Disconnected",
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
                        font.pixelSize: 12
                        font.bold: true
                        font.letterSpacing: 1.2
                    }

                    Item { Layout.fillWidth: true }

                    // Ping Indicator Badge
                    Rectangle {
                        color: "#212532"
                        radius: 8
                        height: 22
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
                                color: "#b0bec5"
                                font.pixelSize: 10
                                font.bold: true
                            }
                        }
                    }
                }

                // --- WI-FI STATUS BAR ---
                Rectangle {
                    Layout.fillWidth: true
                    height: 24
                    radius: 8
                    color: "#1d212c"
                    border.color: (container.monitorData.wifi && container.monitorData.wifi !== "Disconnected") ? "#293245" : "#3e2727"
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 6

                        Text {
                            text: "Wi-Fi"
                            color: "#80cbc4"
                            font.pixelSize: 10
                            font.bold: true
                        }

                        Item { Layout.fillWidth: true }

                        Text {
                            text: (container.monitorData.wifi && container.monitorData.wifi !== "Disconnected") ? ("📶 " + container.monitorData.wifi) : "Offline"
                            color: (container.monitorData.wifi && container.monitorData.wifi !== "Disconnected") ? "#e0f2f1" : "#ef5350"
                            font.pixelSize: 10
                            font.bold: true
                            elide: Text.ElideRight
                            Layout.maximumWidth: parent.width - 60
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
                            Text { text: "CPU"; color: "#90caf9"; font.pixelSize: 11; font.bold: true }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: (container.monitorData.cpu_percent || 0).toFixed(1) + "%"
                                color: "#ffffff"
                                font.pixelSize: 11
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
                                color: (container.monitorData.cpu_percent > 85) ? "#ff5252" : ((container.monitorData.cpu_percent > 65) ? "#ffa726" : "#29b6f6")
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
                            Text { text: "RAM"; color: "#ce93d8"; font.pixelSize: 11; font.bold: true }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: (container.monitorData.memory.used_gb || 0) + " / " + (container.monitorData.memory.total_gb || 0) + " GB (" + (container.monitorData.memory.percent || 0) + "%)"
                                color: "#ffffff"
                                font.pixelSize: 11
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
                                color: (container.monitorData.memory.percent > 85) ? "#ff5252" : "#ab47bc"
                                Behavior on width { NumberAnimation { duration: 250 } }
                            }
                        }
                    }

                    // --- SIDE-BY-SIDE STORAGE (INTERNAL & MICROSD) ---
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        // Internal Storage (Left)
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            spacing: 2

                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: "Internal (/home)"; color: "#80cbc4"; font.pixelSize: 10; font.bold: true }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: (container.monitorData.storage.percent || 0) + "%"
                                    color: "#ffffff"
                                    font.pixelSize: 10
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
                                    color: (container.monitorData.storage.percent > 90) ? "#ff5252" : ((container.monitorData.storage.percent > 75) ? "#ffa726" : "#26a69a")
                                    Behavior on width { NumberAnimation { duration: 250 } }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: (container.monitorData.storage.used_gb || 0) + " / " + (container.monitorData.storage.total_gb || 0) + " GB"
                                    color: "#78909c"
                                    font.pixelSize: 9
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: (container.monitorData.storage.free_gb || 0) + " GB free"
                                    color: "#cfd8dc"
                                    font.pixelSize: 9
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
                                Text { text: "MicroSD Card"; color: "#ffb74d"; font.pixelSize: 10; font.bold: true }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: container.monitorData.sdcard.mounted ? ((container.monitorData.sdcard.percent || 0) + "%") : "N/A"
                                    color: container.monitorData.sdcard.mounted ? "#ffffff" : "#78909c"
                                    font.pixelSize: 10
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
                                    color: (container.monitorData.sdcard.percent > 90) ? "#ff5252" : ((container.monitorData.sdcard.percent > 75) ? "#ff9800" : "#ffb74d")
                                    Behavior on width { NumberAnimation { duration: 250 } }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: container.monitorData.sdcard.mounted ? ((container.monitorData.sdcard.used_gb || 0) + " / " + (container.monitorData.sdcard.total_gb || 0) + " GB") : "Not Inserted"
                                    color: "#78909c"
                                    font.pixelSize: 9
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: container.monitorData.sdcard.mounted ? ((container.monitorData.sdcard.free_gb || 0) + " GB free") : ""
                                    color: "#cfd8dc"
                                    font.pixelSize: 9
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
                        height: 50
                        radius: 10
                        color: "#1e222d"

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 1
                            Text {
                                text: "APU TEMP"
                                color: "#90a4ae"
                                font.pixelSize: 9
                                font.bold: true
                                Layout.alignment: Qt.AlignHCenter
                            }
                            Text {
                                text: container.monitorData.temp || "N/A"
                                color: "#ffb74d"
                                font.pixelSize: 13
                                font.bold: true
                                Layout.alignment: Qt.AlignHCenter
                            }
                        }
                    }

                    // Battery Badge
                    Rectangle {
                        Layout.fillWidth: true
                        height: 50
                        radius: 10
                        color: container.monitorData.battery.is_plugged ? "#1a2c26" : "#1e222d"
                        border.color: container.monitorData.battery.is_plugged ? "#2e7d32" : "#2a303d"
                        border.width: 1

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 1
                            Text {
                                text: "BATTERY"
                                color: "#90a4ae"
                                font.pixelSize: 9
                                font.bold: true
                                Layout.alignment: Qt.AlignHCenter
                            }
                            Text {
                                text: (container.monitorData.battery.is_plugged ? "⚡ " : "") + (container.monitorData.battery.percent || 0) + "%"
                                color: container.monitorData.battery.is_plugged ? "#69f0ae" : "#ffffff"
                                font.pixelSize: 13
                                font.bold: true
                                Layout.alignment: Qt.AlignHCenter
                            }
                            Text {
                                text: container.monitorData.battery.charge_label ? container.monitorData.battery.charge_label.toUpperCase() : "DISCHARGING"
                                color: container.monitorData.battery.is_plugged ? "#00e676" : "#78909c"
                                font.pixelSize: 8
                                font.bold: true
                                Layout.alignment: Qt.AlignHCenter
                            }
                        }
                    }

                    // Battery Health Badge
                    Rectangle {
                        Layout.fillWidth: true
                        height: 50
                        radius: 10
                        color: "#1e222d"

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 1
                            Text {
                                text: "BAT HEALTH"
                                color: "#90a4ae"
                                font.pixelSize: 9
                                font.bold: true
                                Layout.alignment: Qt.AlignHCenter
                            }
                            Text {
                                text: container.monitorData.battery.health || "N/A"
                                color: "#4dd0e1"
                                font.pixelSize: 13
                                font.bold: true
                                Layout.alignment: Qt.AlignHCenter
                            }
                            Text {
                                text: "HEALTH"
                                color: "#546e7a"
                                font.pixelSize: 8
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
                        font.pixelSize: 9
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
                            height: 25
                            radius: 8
                            color: container.monitorData.services.syncthing ? "#182c22" : "#20232c"
                            border.color: container.monitorData.services.syncthing ? "#2e7d32" : "#323744"
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                Text { text: "Syncthing"; color: "#cfd8dc"; font.pixelSize: 10; font.bold: true }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: container.monitorData.services.syncthing ? "ACTIVE" : "OFF"
                                    color: container.monitorData.services.syncthing ? "#00e676" : "#78909c"
                                    font.pixelSize: 9
                                    font.bold: true
                                }
                            }
                        }

                        // Dropbox
                        Rectangle {
                            Layout.fillWidth: true
                            height: 25
                            radius: 8
                            color: container.monitorData.services.dropbox ? "#172735" : "#20232c"
                            border.color: container.monitorData.services.dropbox ? "#1565c0" : "#323744"
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                Text { text: "Dropbox"; color: "#cfd8dc"; font.pixelSize: 10; font.bold: true }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: container.monitorData.services.dropbox ? "ACTIVE" : "OFF"
                                    color: container.monitorData.services.dropbox ? "#40c4ff" : "#78909c"
                                    font.pixelSize: 9
                                    font.bold: true
                                }
                            }
                        }

                        // Rclone (Compact label - no overflow)
                        Rectangle {
                            Layout.fillWidth: true
                            height: 25
                            radius: 8
                            color: container.monitorData.services.rclone ? "#182c22" : "#20232c"
                            border.color: container.monitorData.services.rclone ? "#2e7d32" : "#323744"
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                Text { text: "Rclone"; color: "#cfd8dc"; font.pixelSize: 10; font.bold: true }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: container.monitorData.services.rclone ? "ACTIVE" : "OFF"
                                    color: container.monitorData.services.rclone ? "#00e676" : "#78909c"
                                    font.pixelSize: 9
                                    font.bold: true
                                }
                            }
                        }

                        // Tailscale
                        Rectangle {
                            Layout.fillWidth: true
                            height: 25
                            radius: 8
                            color: container.monitorData.services.tailscale ? "#1f2235" : "#20232c"
                            border.color: container.monitorData.services.tailscale ? "#5c6bc0" : "#323744"
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                Text { text: "Tailscale"; color: "#cfd8dc"; font.pixelSize: 10; font.bold: true }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: container.monitorData.services.tailscale ? "ONLINE" : "OFF"
                                    color: container.monitorData.services.tailscale ? "#8c9eff" : "#78909c"
                                    font.pixelSize: 9
                                    font.bold: true
                                }
                            }
                        }
                    }

                    // Tmux Bar
                    Rectangle {
                        Layout.fillWidth: true
                        height: 24
                        radius: 8
                        color: (container.monitorData.services.tmux_sessions > 0) ? "#1c2630" : "#20232c"
                        border.color: (container.monitorData.services.tmux_sessions > 0) ? "#00838f" : "#323744"
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            Text { text: "Tmux Sessions"; color: "#b0bec5"; font.pixelSize: 10; font.bold: true }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: (container.monitorData.services.tmux_sessions > 0) ? (container.monitorData.services.tmux_sessions + " Active") : "No Session"
                                color: (container.monitorData.services.tmux_sessions > 0) ? "#00e5ff" : "#78909c"
                                font.pixelSize: 9
                                font.bold: true
                            }
                        }
                    }
                }
            }
        }
    }
}
