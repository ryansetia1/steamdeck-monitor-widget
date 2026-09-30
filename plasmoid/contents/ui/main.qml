import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    preferredRepresentation: fullRepresentation
    implicitWidth: 320
    implicitHeight: 390
    Layout.minimumWidth: 280
    Layout.minimumHeight: 360
    Layout.preferredWidth: 330
    Layout.preferredHeight: 400

    fullRepresentation: Item {
        id: container
        anchors.fill: parent

        // State properties
        property var monitorData: ({
            cpu_percent: 0,
            memory: { percent: 0, used_gb: 0, total_gb: 0 },
            storage: { percent: 0, used_gb: 0, total_gb: 0, free_gb: 0 },
            battery: { percent: 0, status: "Loading...", health: "N/A" },
            temp: "N/A",
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

        // Background Card
        Rectangle {
            anchors.fill: parent
            color: "#181a20"
            radius: 12
            border.color: container.isConnected ? "#2d3342" : "#4a2525"
            border.width: 1
            clip: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 12

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
                        font.pixelSize: 13
                        font.bold: true
                        font.letterSpacing: 1.2
                    }

                    Item { Layout.fillWidth: true }

                    // Ping indicator
                    Rectangle {
                        color: "#232733"
                        radius: 6
                        height: 22
                        width: pingText.implicitWidth + 14

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 4
                            Rectangle {
                                width: 5
                                height: 5
                                radius: 2.5
                                color: (container.monitorData.ping && container.monitorData.ping !== "Offline") ? "#00e5ff" : "#ff5252"
                            }
                            Text {
                                id: pingText
                                text: container.monitorData.ping ? container.monitorData.ping : "..."
                                color: "#b0bec5"
                                font.pixelSize: 10
                                font.bold: true
                            }
                        }
                    }
                }

                // Divider
                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: "#282c37"
                }

                // --- HARDWARE SECTION (CPU, RAM, STORAGE) ---
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    // CPU
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3

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
                            color: "#262c3a"
                            Rectangle {
                                width: Math.max(0, Math.min(parent.width, parent.width * ((container.monitorData.cpu_percent || 0) / 100.0)))
                                height: parent.height
                                radius: 3
                                color: (container.monitorData.cpu_percent > 85) ? "#ff5252" : ((container.monitorData.cpu_percent > 65) ? "#ffa726" : "#29b6f6")
                                Behavior on width { NumberAnimation { duration: 300 } }
                            }
                        }
                    }

                    // RAM
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3

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
                            color: "#262c3a"
                            Rectangle {
                                width: Math.max(0, Math.min(parent.width, parent.width * ((container.monitorData.memory.percent || 0) / 100.0)))
                                height: parent.height
                                radius: 3
                                color: (container.monitorData.memory.percent > 85) ? "#ff5252" : "#ab47bc"
                                Behavior on width { NumberAnimation { duration: 300 } }
                            }
                        }
                    }

                    // INTERNAL STORAGE
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3

                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "Internal Storage (/home)"; color: "#80cbc4"; font.pixelSize: 11; font.bold: true }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: (container.monitorData.storage.used_gb || 0) + " / " + (container.monitorData.storage.total_gb || 0) + " GB"
                                color: "#ffffff"
                                font.pixelSize: 11
                                font.bold: true
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 6
                            radius: 3
                            color: "#262c3a"
                            Rectangle {
                                width: Math.max(0, Math.min(parent.width, parent.width * ((container.monitorData.storage.percent || 0) / 100.0)))
                                height: parent.height
                                radius: 3
                                color: (container.monitorData.storage.percent > 90) ? "#ff5252" : ((container.monitorData.storage.percent > 75) ? "#ffa726" : "#26a69a")
                                Behavior on width { NumberAnimation { duration: 300 } }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "Sisa Ruang: " + (container.monitorData.storage.free_gb || 0) + " GB bebas"
                                color: "#78909c"
                                font.pixelSize: 10
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: (container.monitorData.storage.percent || 0) + "%"
                                color: "#b0bec5"
                                font.pixelSize: 10
                            }
                        }
                    }
                }

                // Divider
                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: "#282c37"
                }

                // --- TEMP & BATTERY ROW ---
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    // Temp Badge
                    Rectangle {
                        Layout.fillWidth: true
                        height: 52
                        radius: 8
                        color: "#202531"

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 2
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
                                font.pixelSize: 14
                                font.bold: true
                                Layout.alignment: Qt.AlignHCenter
                            }
                        }
                    }

                    // Battery Badge
                    Rectangle {
                        Layout.fillWidth: true
                        height: 52
                        radius: 8
                        color: "#202531"

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 2
                            Text {
                                text: "BATTERY"
                                color: "#90a4ae"
                                font.pixelSize: 9
                                font.bold: true
                                Layout.alignment: Qt.AlignHCenter
                            }
                            Text {
                                text: (container.monitorData.battery.percent || 0) + "% " + ((container.monitorData.battery.status === "Charging") ? "⚡" : "")
                                color: "#69f0ae"
                                font.pixelSize: 14
                                font.bold: true
                                Layout.alignment: Qt.AlignHCenter
                            }
                        }
                    }

                    // Battery Health Badge
                    Rectangle {
                        Layout.fillWidth: true
                        height: 52
                        radius: 8
                        color: "#202531"

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 2
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
                                font.pixelSize: 14
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
                    color: "#282c37"
                }

                // --- SERVICES & NETWORK STATUS GRID ---
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        text: "SERVICES & NETWORK"
                        color: "#78909c"
                        font.pixelSize: 10
                        font.bold: true
                        font.letterSpacing: 0.8
                    }

                    // Services Grid
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: 8
                        rowSpacing: 6

                        // Syncthing
                        Rectangle {
                            Layout.fillWidth: true
                            height: 26
                            radius: 6
                            color: container.monitorData.services.syncthing ? "#1b3327" : "#242730"
                            border.color: container.monitorData.services.syncthing ? "#2e7d32" : "#37474f"
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
                            height: 26
                            radius: 6
                            color: container.monitorData.services.dropbox ? "#1b2c3a" : "#242730"
                            border.color: container.monitorData.services.dropbox ? "#1565c0" : "#37474f"
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

                        // Rclone
                        Rectangle {
                            Layout.fillWidth: true
                            height: 26
                            radius: 6
                            color: container.monitorData.services.rclone ? "#1b3327" : "#242730"
                            border.color: container.monitorData.services.rclone ? "#2e7d32" : "#37474f"
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                Text { text: "Rclone (GDrive)"; color: "#cfd8dc"; font.pixelSize: 10; font.bold: true }
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
                            height: 26
                            radius: 6
                            color: container.monitorData.services.tailscale ? "#23263a" : "#242730"
                            border.color: container.monitorData.services.tailscale ? "#5c6bc0" : "#37474f"
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

                    // Tmux Bar (full width)
                    Rectangle {
                        Layout.fillWidth: true
                        height: 24
                        radius: 6
                        color: (container.monitorData.services.tmux_sessions > 0) ? "#202a35" : "#242730"
                        border.color: (container.monitorData.services.tmux_sessions > 0) ? "#00838f" : "#37474f"
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
