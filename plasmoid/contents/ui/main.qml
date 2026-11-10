import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground | PlasmaCore.Types.ConfigurableBackground

    property bool glassMode: Plasmoid.configuration ? Plasmoid.configuration.backgroundStyle === 1 : false
    property real glassOpacity: ((Plasmoid.configuration && Plasmoid.configuration.glassOpacity) || 55) / 100
    property int baseFontSize: (Plasmoid.configuration && Plasmoid.configuration.fontSizeScale) || 12
    property bool autoScreenMigrate: (Plasmoid.configuration && Plasmoid.configuration.autoScreenMigrate !== undefined) ? Plasmoid.configuration.autoScreenMigrate : true
    property bool deckFullscreen: (Plasmoid.configuration && Plasmoid.configuration.deckFullscreen !== undefined) ? Plasmoid.configuration.deckFullscreen : true
    property bool deckSolidBg: (Plasmoid.configuration && Plasmoid.configuration.deckSolidBg !== undefined) ? Plasmoid.configuration.deckSolidBg : true

    property bool isOnDeckScreen: false
    property bool isDualScreenActive: false
    property bool shouldBeVisible: true

    readonly property bool isFullscreenDashboard: root.isOnDeckScreen && root.deckFullscreen
    readonly property bool effectiveGlassMode: (root.isOnDeckScreen && root.deckSolidBg) ? false : root.glassMode

    readonly property int compactWidth: 320 + (baseFontSize - 12) * 15
    readonly property int compactHeight: 390 + (baseFontSize - 12) * 16

    function setDeckFullscreen(val) {
        root.deckFullscreen = val;
        if (Plasmoid.configuration) {
            Plasmoid.configuration.deckFullscreen = val;
        }
    }

    preferredRepresentation: fullRepresentation
    implicitWidth: 320 + (baseFontSize - 12) * 15
    implicitHeight: 390 + (baseFontSize - 12) * 16
    Layout.minimumWidth: 280
    Layout.minimumHeight: 350
    Layout.preferredWidth: implicitWidth
    Layout.preferredHeight: implicitHeight

    visible: shouldBeVisible

    function updateScreenState() {
        var screens = Qt.application.screens;
        var hasEdp = false;
        var hasExt = false;
        var edpScreenIndex = -1;

        if (screens && screens.length > 0) {
            for (var i = 0; i < screens.length; i++) {
                var s = screens[i];
                if (s && s.name && s.name.toLowerCase().indexOf("edp") !== -1) {
                    hasEdp = true;
                    edpScreenIndex = i;
                } else if (s && s.name) {
                    hasExt = true;
                }
            }
        }

        var scrName = (root.Screen && root.Screen.name) ? root.Screen.name : "";
        if (scrName.length > 0) {
            root.isOnDeckScreen = scrName.toLowerCase().indexOf("edp") !== -1;
        } else if (Plasmoid.containment && edpScreenIndex !== -1) {
            root.isOnDeckScreen = (Plasmoid.containment.screen === edpScreenIndex);
        }

        root.isDualScreenActive = (hasEdp && hasExt);

        if (root.autoScreenMigrate && root.isDualScreenActive) {
            root.shouldBeVisible = root.isOnDeckScreen;
        } else {
            root.shouldBeVisible = true;
        }
    }

    Connections {
        target: Qt.application
        function onScreensChanged() {
            root.updateScreenState();
        }
    }

    Connections {
        target: root.Screen
        function onNameChanged() {
            root.updateScreenState();
        }
    }

    Timer {
        id: screenCheckTimer
        interval: 2000
        running: true
        repeat: true
        onTriggered: root.updateScreenState()
    }

    Component.onCompleted: {
        Plasmoid.userBackgroundHints = PlasmaCore.Types.NoBackground;
        root.updateScreenState();
    }

    fullRepresentation: Item {
        id: container
        anchors.fill: parent
        visible: root.shouldBeVisible

        // State properties
        property var monitorData: ({
            cpu_percent: 0,
            memory: { percent: 0, used_gb: 0, total_gb: 0 },
            storage: { percent: 0, used_gb: 0, total_gb: 0, free_gb: 0 },
            sdcard: { mounted: false, percent: 0, used_gb: 0, total_gb: 0, free_gb: 0 },
            external_drives: [],
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
            xhr.onerror = function() {
                container.isConnected = false;
            };
            xhr.send();
        }

        // Inner tiles/tracks: solid colour, or a faint white veil in glass mode
        function tileColor(solid) {
            return root.effectiveGlassMode ? Qt.rgba(1, 1, 1, 0.08) : solid;
        }

        function getBarColor(pct) {
            if (pct >= 85) return "#ff5252";
            if (pct >= 70) return "#ffa726";
            return "#00e676";
        }

        function getTempColor(tempStr) {
            if (!tempStr || tempStr === "N/A") return "#90a4ae";
            var val = parseFloat(tempStr);
            if (isNaN(val)) return "#90a4ae";
            if (val >= 85) return "#ff5252";
            if (val >= 70) return "#ffa726";
            return "#00e676";
        }

        function getHealthColor(healthStr) {
            if (!healthStr || healthStr === "N/A") return "#90a4ae";
            var val = parseFloat(healthStr);
            if (isNaN(val)) return "#90a4ae";
            if (val >= 80) return "#00e676";
            if (val >= 60) return "#ffa726";
            return "#ff5252";
        }

        function getPingColor(pingStr) {
            if (!pingStr || pingStr === "Offline" || pingStr === "...") return "#ff5252";
            var val = parseFloat(pingStr);
            if (isNaN(val)) return "#ff5252";
            if (val <= 80) return "#00e676";
            if (val <= 150) return "#ffa726";
            return "#ff5252";
        }

        Timer {
            id: pollTimer
            interval: 2000
            running: root.shouldBeVisible
            repeat: true
            triggeredOnStart: true
            onTriggered: container.fetchMetrics()
        }

        Connections {
            target: root
            function onShouldBeVisibleChanged() {
                if (root.shouldBeVisible) {
                    container.fetchMetrics();
                }
            }
        }

        // Background Card with smooth rounded corners
        Rectangle {
            id: mainCard
            x: root.isFullscreenDashboard ? 12 : ((container.width > root.compactWidth + 32) ? (container.width - root.compactWidth - 16) : 0)
            y: root.isFullscreenDashboard ? 12 : 16
            width: root.isFullscreenDashboard ? (container.width - 24) : root.compactWidth
            height: root.isFullscreenDashboard ? (container.height - 24) : root.compactHeight
            color: root.effectiveGlassMode ? Qt.rgba(0.09, 0.10, 0.14, root.glassOpacity) : "#161820"
            radius: 16
            border.color: root.effectiveGlassMode
                ? (container.isConnected ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 0.32, 0.32, 0.5))
                : (container.isConnected ? "#2c3242" : "#4a2424")
            border.width: 1
            clip: true

            // --- COMPACT VIEW (FLOATING CARD) ---
            ColumnLayout {
                id: compactView
                visible: !root.isFullscreenDashboard
                anchors.fill: parent
                anchors.margins: 12
                spacing: 9

                // --- HEADER ---
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Image {
                        source: Qt.resolvedUrl("../icons/steamdeck.svg")
                        Layout.preferredWidth: root.baseFontSize + 6
                        Layout.preferredHeight: root.baseFontSize + 6
                        sourceSize.width: 48
                        sourceSize.height: 48
                        fillMode: Image.PreserveAspectFit
                        opacity: container.isConnected ? 1.0 : 0.4
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
                        color: container.tileColor("#212532")
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
                                color: container.getPingColor(container.monitorData.ping)
                            }
                            Text {
                                text: container.monitorData.ping ? container.monitorData.ping : "..."
                                color: "#cfd8dc"
                                font.pixelSize: root.baseFontSize - 2
                                font.bold: true
                            }
                        }
                    }

                    // Fullscreen Dashboard Toggle Button (Active on Steam Deck Screen)
                    Rectangle {
                        visible: root.isOnDeckScreen
                        color: container.tileColor("#212532")
                        radius: 8
                        height: root.baseFontSize + 10
                        Layout.preferredWidth: root.baseFontSize + 12
                        Layout.alignment: Qt.AlignVCenter

                        Kirigami.Icon {
                            anchors.centerIn: parent
                            source: "view-fullscreen"
                            Layout.preferredWidth: root.baseFontSize
                            Layout.preferredHeight: root.baseFontSize
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.setDeckFullscreen(true)
                        }
                    }
                }

                // --- WI-FI STATUS BAR ---
                Rectangle {
                    Layout.fillWidth: true
                    height: root.baseFontSize + 14
                    radius: 8
                    color: container.tileColor("#1e222d")

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
                    color: container.tileColor("#242834")
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
                            color: container.tileColor("#242936")
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
                            color: container.tileColor("#242936")
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
                                color: container.tileColor("#242936")
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
                                color: container.tileColor("#242936")
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

                    // --- EXTERNAL STORAGE DRIVES (Dynamically rendered if connected) ---
                    Repeater {
                        model: (container.monitorData.external_drives && container.monitorData.external_drives.length > 0) ? container.monitorData.external_drives : 0

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                Kirigami.Icon {
                                    source: "drive-removable-media-usb"
                                    Layout.preferredWidth: root.baseFontSize
                                    Layout.preferredHeight: root.baseFontSize
                                }
                                Text {
                                    text: modelData.name || "External Drive"
                                    color: "#cfd8dc"
                                    font.pixelSize: root.baseFontSize - 1
                                    font.bold: true
                                    elide: Text.ElideRight
                                    Layout.maximumWidth: parent.width * 0.7
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: (modelData.percent || 0).toFixed(1) + "%"
                                    color: "#ffffff"
                                    font.pixelSize: root.baseFontSize - 1
                                    font.bold: true
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 6
                                radius: 3
                                color: container.tileColor("#242936")
                                Rectangle {
                                    width: Math.max(0, Math.min(parent.width, parent.width * ((modelData.percent || 0) / 100.0)))
                                    height: parent.height
                                    radius: 3
                                    color: container.getBarColor(modelData.percent || 0)
                                    Behavior on width { NumberAnimation { duration: 250 } }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: (modelData.used_gb >= 1000 ? (modelData.used_gb/1024).toFixed(1) + "T" : Math.round(modelData.used_gb || 0) + "G") + "/" + (modelData.total_gb >= 1000 ? (modelData.total_gb/1024).toFixed(1) + "T" : Math.round(modelData.total_gb || 0) + "G")
                                    color: "#90a4ae"
                                    font.pixelSize: root.baseFontSize - 3
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: (modelData.free_gb >= 1000 ? (modelData.free_gb/1024).toFixed(1) + "T free" : Math.round(modelData.free_gb || 0) + "G free")
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
                    color: container.tileColor("#242834")
                }

                // --- TEMP & BATTERY ROW ---
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    // Temp Badge
                    Item {
                        Layout.fillWidth: true
                        height: root.baseFontSize + 38

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
                                color: container.getTempColor(container.monitorData.temp)
                                font.pixelSize: root.baseFontSize + 3
                                font.bold: true
                                Layout.alignment: Qt.AlignHCenter
                            }
                            Text {
                                text: "APU"
                                color: "transparent"
                                font.pixelSize: root.baseFontSize - 3
                                font.bold: true
                                Layout.alignment: Qt.AlignHCenter
                            }
                        }
                    }

                    // Vertical Separator
                    Rectangle {
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: root.baseFontSize + 24
                        Layout.alignment: Qt.AlignVCenter
                        color: container.tileColor("#282d3c")
                    }

                    // Battery Badge
                    Item {
                        Layout.fillWidth: true
                        height: root.baseFontSize + 38

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

                    // Vertical Separator
                    Rectangle {
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: root.baseFontSize + 24
                        Layout.alignment: Qt.AlignVCenter
                        color: container.tileColor("#282d3c")
                    }

                    // Battery Health Badge
                    Item {
                        Layout.fillWidth: true
                        height: root.baseFontSize + 38

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
                                color: container.getHealthColor(container.monitorData.battery.health)
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
                    color: container.tileColor("#242834")
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
                            color: container.tileColor("#1e222d")

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
                                    text: (container.monitorData.services && container.monitorData.services.syncthing) ? "ACTIVE" : "OFF"
                                    color: (container.monitorData.services && container.monitorData.services.syncthing) ? "#00e676" : "#78909c"
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
                            color: container.tileColor("#1e222d")

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
                                    text: (container.monitorData.services && container.monitorData.services.dropbox) ? "ACTIVE" : "OFF"
                                    color: (container.monitorData.services && container.monitorData.services.dropbox) ? "#00e676" : "#78909c"
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
                            color: container.tileColor("#1e222d")

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
                                    text: (container.monitorData.services && container.monitorData.services.rclone) ? "ACTIVE" : "OFF"
                                    color: (container.monitorData.services && container.monitorData.services.rclone) ? "#00e676" : "#78909c"
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
                            color: container.tileColor("#1e222d")

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
                                    text: (container.monitorData.services && container.monitorData.services.tailscale) ? "ONLINE" : "OFF"
                                    color: (container.monitorData.services && container.monitorData.services.tailscale) ? "#00e676" : "#78909c"
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
                        color: container.tileColor("#1e222d")

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
                                text: (container.monitorData.services && container.monitorData.services.tmux_sessions > 0) ? (container.monitorData.services.tmux_sessions + " Active") : "No Session"
                                color: (container.monitorData.services && container.monitorData.services.tmux_sessions > 0) ? "#00e676" : "#78909c"
                                font.pixelSize: root.baseFontSize - 3
                                font.bold: true
                            }
                        }
                    }
                }
            }

            // ========================================================
            // --- FULLSCREEN DASHBOARD VIEW (WIDESCREEN 1280x800) ---
            // ========================================================
            ColumnLayout {
                id: dashboardView
                visible: root.isFullscreenDashboard
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                // --- TOP DASHBOARD HEADER ---
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Image {
                        source: Qt.resolvedUrl("../icons/steamdeck.svg")
                        Layout.preferredWidth: 26
                        Layout.preferredHeight: 26
                        sourceSize.width: 52
                        sourceSize.height: 52
                        fillMode: Image.PreserveAspectFit
                        opacity: container.isConnected ? 1.0 : 0.4
                    }

                    Text {
                        text: "STEAM DECK HARDWARE MONITOR"
                        color: "#ffffff"
                        font.pixelSize: 15
                        font.bold: true
                        font.letterSpacing: 1.2
                    }

                    Rectangle {
                        color: "#1e293b"
                        radius: 6
                        Layout.preferredHeight: 22
                        Layout.preferredWidth: 110
                        Text {
                            anchors.centerIn: parent
                            text: "DOCK DASHBOARD"
                            color: "#38bdf8"
                            font.pixelSize: 10
                            font.bold: true
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Wi-Fi Chip
                    Rectangle {
                        color: container.tileColor("#1e222d")
                        radius: 8
                        Layout.preferredHeight: 28
                        Layout.preferredWidth: wifiHeadRow.implicitWidth + 14

                        RowLayout {
                            id: wifiHeadRow
                            anchors.centerIn: parent
                            spacing: 6

                            Kirigami.Icon {
                                source: (container.monitorData.wifi && container.monitorData.wifi.icon) ? container.monitorData.wifi.icon : "network-wireless-symbolic"
                                Layout.preferredWidth: 14
                                Layout.preferredHeight: 14
                            }
                            Text {
                                text: (container.monitorData.wifi && container.monitorData.wifi.name) ? container.monitorData.wifi.name : "Offline"
                                color: "#e2e8f0"
                                font.pixelSize: 11
                                font.bold: true
                            }
                        }
                    }

                    // Ping Chip
                    Rectangle {
                        color: container.tileColor("#1e222d")
                        radius: 8
                        Layout.preferredHeight: 28
                        Layout.preferredWidth: pingHeadRow.implicitWidth + 14

                        RowLayout {
                            id: pingHeadRow
                            anchors.centerIn: parent
                            spacing: 5

                            Rectangle {
                                width: 6; height: 6; radius: 3
                                color: container.getPingColor(container.monitorData.ping)
                            }
                            Text {
                                text: container.monitorData.ping ? container.monitorData.ping : "..."
                                color: "#cfd8dc"
                                font.pixelSize: 11
                                font.bold: true
                            }
                        }
                    }

                    // Restore to Compact Mode Button
                    Rectangle {
                        color: container.tileColor("#212532")
                        radius: 8
                        Layout.preferredHeight: 28
                        Layout.preferredWidth: 28
                        Layout.alignment: Qt.AlignVCenter

                        Kirigami.Icon {
                            anchors.centerIn: parent
                            source: "view-restore"
                            Layout.preferredWidth: 14
                            Layout.preferredHeight: 14
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.setDeckFullscreen(false)
                        }
                    }
                }

                // Divider
                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: container.tileColor("#242834")
                }

                // --- 3-COLUMN DASHBOARD BODY ---
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 14

                    // ==================== COLUMN 1: COMPUTE & STORAGE ====================
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: 1
                        spacing: 10

                        // CPU Card
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            color: container.tileColor("#1b1f2a")
                            radius: 12
                            border.color: container.tileColor("#282d3c"); border.width: 1

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 6

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text { text: "CPU (Zen 2 APU)"; color: "#90a4ae"; font.pixelSize: 12; font.bold: true }
                                    Item { Layout.fillWidth: true }
                                    Text {
                                        text: (container.monitorData.cpu_percent || 0).toFixed(1) + "%"
                                        color: "#ffffff"
                                        font.pixelSize: 18
                                        font.bold: true
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 8
                                    radius: 4
                                    color: container.tileColor("#242936")
                                    Rectangle {
                                        width: Math.max(0, Math.min(parent.width, parent.width * ((container.monitorData.cpu_percent || 0) / 100.0)))
                                        height: parent.height
                                        radius: 4
                                        color: container.getBarColor(container.monitorData.cpu_percent || 0)
                                        Behavior on width { NumberAnimation { duration: 250 } }
                                    }
                                }

                                Text {
                                    text: "4 Cores / 8 Threads • Custom AMD Aerith/Sephiroth"
                                    color: "#64748b"
                                    font.pixelSize: 10
                                }
                            }
                        }

                        // RAM Card
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            color: container.tileColor("#1b1f2a")
                            radius: 12
                            border.color: container.tileColor("#282d3c"); border.width: 1

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 6

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text { text: "RAM (LPDDR5)"; color: "#90a4ae"; font.pixelSize: 12; font.bold: true }
                                    Item { Layout.fillWidth: true }
                                    Text {
                                        text: (container.monitorData.memory.used_gb || 0) + " / " + (container.monitorData.memory.total_gb || 0) + " GB"
                                        color: "#ffffff"
                                        font.pixelSize: 16
                                        font.bold: true
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 8
                                    radius: 4
                                    color: container.tileColor("#242936")
                                    Rectangle {
                                        width: Math.max(0, Math.min(parent.width, parent.width * ((container.monitorData.memory.percent || 0) / 100.0)))
                                        height: parent.height
                                        radius: 4
                                        color: container.getBarColor(container.monitorData.memory.percent || 0)
                                        Behavior on width { NumberAnimation { duration: 250 } }
                                    }
                                }

                                Text {
                                    text: Math.round(container.monitorData.memory.percent || 0) + "% Unified High-Speed LPDDR5 Memory"
                                    color: "#64748b"
                                    font.pixelSize: 10
                                }
                            }
                        }

                        // Storage Card (Internal + MicroSD)
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            color: container.tileColor("#1b1f2a")
                            radius: 12
                            border.color: container.tileColor("#282d3c"); border.width: 1

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 8

                                // Internal NVMe
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 3

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text { text: "Internal NVMe (/home)"; color: "#90a4ae"; font.pixelSize: 11; font.bold: true }
                                        Item { Layout.fillWidth: true }
                                        Text {
                                            text: (container.monitorData.storage.free_gb || 0) + " GB free (" + (container.monitorData.storage.percent || 0).toFixed(0) + "%)"
                                            color: "#38bdf8"
                                            font.pixelSize: 11
                                            font.bold: true
                                        }
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 6
                                        radius: 3
                                        color: container.tileColor("#242936")
                                        Rectangle {
                                            width: Math.max(0, Math.min(parent.width, parent.width * ((container.monitorData.storage.percent || 0) / 100.0)))
                                            height: parent.height
                                            radius: 3
                                            color: container.getBarColor(container.monitorData.storage.percent || 0)
                                            Behavior on width { NumberAnimation { duration: 250 } }
                                        }
                                    }
                                }

                                // MicroSD
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 3

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text { text: "MicroSD Card (Games & Saves)"; color: "#90a4ae"; font.pixelSize: 11; font.bold: true }
                                        Item { Layout.fillWidth: true }
                                        Text {
                                            text: container.monitorData.sdcard.mounted ? ((container.monitorData.sdcard.free_gb || 0) + " GB free (" + (container.monitorData.sdcard.percent || 0).toFixed(0) + "%)") : "Not Inserted"
                                            color: container.monitorData.sdcard.mounted ? "#38bdf8" : "#90a4ae"
                                            font.pixelSize: 11
                                            font.bold: true
                                        }
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 6
                                        radius: 3
                                        color: container.tileColor("#242936")
                                        Rectangle {
                                            width: container.monitorData.sdcard.mounted ? Math.max(0, Math.min(parent.width, parent.width * ((container.monitorData.sdcard.percent || 0) / 100.0))) : 0
                                            height: parent.height
                                            radius: 3
                                            color: container.getBarColor(container.monitorData.sdcard.percent || 0)
                                            Behavior on width { NumberAnimation { duration: 250 } }
                                        }
                                    }
                                }

                                // External Drives Repeater
                                Repeater {
                                    model: (container.monitorData.external_drives && container.monitorData.external_drives.length > 0) ? container.monitorData.external_drives : 0

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2

                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text { text: "USB: " + (modelData.name || "Drive"); color: "#90a4ae"; font.pixelSize: 10; font.bold: true; elide: Text.ElideRight; Layout.maximumWidth: 180 }
                                            Item { Layout.fillWidth: true }
                                            Text { text: (modelData.percent || 0).toFixed(0) + "%"; color: "#38bdf8"; font.pixelSize: 10; font.bold: true }
                                        }
                                        Rectangle {
                                            Layout.fillWidth: true; height: 5; radius: 2.5; color: container.tileColor("#242936")
                                            Rectangle {
                                                width: Math.max(0, Math.min(parent.width, parent.width * ((modelData.percent || 0) / 100.0)))
                                                height: parent.height; radius: 2.5
                                                color: container.getBarColor(modelData.percent || 0)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ==================== COLUMN 2: THERMALS & POWER (CENTER HERO) ====================
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: 1.1
                        spacing: 10

                        // Zen 2 APU Thermal Card
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            color: container.tileColor("#1b1f2a")
                            radius: 12
                            border.color: container.tileColor("#282d3c"); border.width: 1

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 14
                                spacing: 8

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text { text: "🔥 ZEN 2 APU THERMALS"; color: "#90a4ae"; font.pixelSize: 12; font.bold: true; font.letterSpacing: 1.0 }
                                    Item { Layout.fillWidth: true }
                                    Rectangle {
                                        color: container.tileColor("#242936")
                                        radius: 6
                                        Layout.preferredHeight: 20
                                        Layout.preferredWidth: 90
                                        Text {
                                            anchors.centerIn: parent
                                            text: parseFloat(container.monitorData.temp) < 70 ? "● SAFE" : (parseFloat(container.monitorData.temp) < 85 ? "● WARM" : "● CRITICAL")
                                            color: container.getTempColor(container.monitorData.temp)
                                            font.pixelSize: 10
                                            font.bold: true
                                        }
                                    }
                                }

                                Item { Layout.fillHeight: true }

                                ColumnLayout {
                                    Layout.alignment: Qt.AlignHCenter
                                    spacing: 4

                                    Text {
                                        text: container.monitorData.temp || "N/A"
                                        color: container.getTempColor(container.monitorData.temp)
                                        font.pixelSize: 48
                                        font.bold: true
                                        Layout.alignment: Qt.AlignHCenter
                                    }
                                    Text {
                                        text: "Zen 2 APU Package Temperature"
                                        color: "#64748b"
                                        font.pixelSize: 11
                                        Layout.alignment: Qt.AlignHCenter
                                    }
                                }

                                Item { Layout.fillHeight: true }

                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 8
                                    radius: 4
                                    color: container.tileColor("#242936")
                                    Rectangle {
                                        width: Math.max(0, Math.min(parent.width, parent.width * ((parseFloat(container.monitorData.temp) || 0) / 100.0)))
                                        height: parent.height
                                        radius: 4
                                        color: container.getTempColor(container.monitorData.temp)
                                        Behavior on width { NumberAnimation { duration: 250 } }
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text { text: "35°C (Idle)"; color: "#64748b"; font.pixelSize: 9 }
                                    Item { Layout.fillWidth: true }
                                    Text { text: "70°C (Warm)"; color: "#64748b"; font.pixelSize: 9 }
                                    Item { Layout.fillWidth: true }
                                    Text { text: "85°C (Throttle)"; color: "#64748b"; font.pixelSize: 9 }
                                }
                            }
                        }

                        // Battery & Power System Card
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            color: container.tileColor("#1b1f2a")
                            radius: 12
                            border.color: container.tileColor("#282d3c"); border.width: 1

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 14
                                spacing: 8

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text { text: "⚡ POWER & BATTERY"; color: "#90a4ae"; font.pixelSize: 12; font.bold: true; font.letterSpacing: 1.0 }
                                    Item { Layout.fillWidth: true }
                                    Rectangle {
                                        color: container.monitorData.battery.is_plugged ? "#052e16" : container.tileColor("#242936")
                                        radius: 6
                                        Layout.preferredHeight: 20
                                        Layout.preferredWidth: 100
                                        Text {
                                            anchors.centerIn: parent
                                            text: container.monitorData.battery.charge_label ? container.monitorData.battery.charge_label.toUpperCase() : "DISCHARGING"
                                            color: container.monitorData.battery.is_plugged ? "#4ade80" : "#94a3b8"
                                            font.pixelSize: 9
                                            font.bold: true
                                        }
                                    }
                                }

                                Item { Layout.fillHeight: true }

                                ColumnLayout {
                                    Layout.alignment: Qt.AlignHCenter
                                    spacing: 4

                                    Text {
                                        text: (container.monitorData.battery.is_plugged ? "⚡ " : "") + (container.monitorData.battery.percent || 0) + "%"
                                        color: container.monitorData.battery.is_plugged ? "#4ade80" : "#ffffff"
                                        font.pixelSize: 44
                                        font.bold: true
                                        Layout.alignment: Qt.AlignHCenter
                                    }
                                    Text {
                                        text: "Battery Health: " + (container.monitorData.battery.health || "N/A") + " • " + (container.monitorData.battery.is_plugged ? "USB-C Hub Power Delivery" : "Discharging on Battery")
                                        color: "#64748b"
                                        font.pixelSize: 11
                                        Layout.alignment: Qt.AlignHCenter
                                    }
                                }

                                Item { Layout.fillHeight: true }

                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 8
                                    radius: 4
                                    color: container.tileColor("#242936")
                                    Rectangle {
                                        width: Math.max(0, Math.min(parent.width, parent.width * ((container.monitorData.battery.percent || 0) / 100.0)))
                                        height: parent.height
                                        radius: 4
                                        color: container.getBarColor(container.monitorData.battery.percent || 0)
                                        Behavior on width { NumberAnimation { duration: 250 } }
                                    }
                                }
                            }
                        }
                    }

                    // ==================== COLUMN 3: NETWORK & DAEMONS ====================
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: 1
                        spacing: 10

                        // Network Connectivity Card
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 120
                            color: container.tileColor("#1b1f2a")
                            radius: 12
                            border.color: container.tileColor("#282d3c"); border.width: 1

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 8

                                Text { text: "🌐 NETWORK & WI-FI"; color: "#90a4ae"; font.pixelSize: 12; font.bold: true; font.letterSpacing: 1.0 }

                                RowLayout {
                                    Layout.fillWidth: true

                                    ColumnLayout {
                                        spacing: 2
                                        Text {
                                            text: (container.monitorData.wifi && container.monitorData.wifi.name) ? container.monitorData.wifi.name : "Offline"
                                            color: "#ffffff"
                                            font.pixelSize: 15
                                            font.bold: true
                                            elide: Text.ElideRight
                                            Layout.maximumWidth: 180
                                        }
                                        Text {
                                            text: (container.monitorData.wifi && container.monitorData.wifi.is_tethering) ? "📱 Mobile Hotspot Tethering" : "Wi-Fi Connection Active"
                                            color: "#38bdf8"
                                            font.pixelSize: 10
                                        }
                                    }

                                    Item { Layout.fillWidth: true }

                                    ColumnLayout {
                                        spacing: 2
                                        Layout.alignment: Qt.AlignRight

                                        Text {
                                            text: container.monitorData.ping ? container.monitorData.ping : "..."
                                            color: container.getPingColor(container.monitorData.ping)
                                            font.pixelSize: 16
                                            font.bold: true
                                            Layout.alignment: Qt.AlignRight
                                        }
                                        Text {
                                            text: "Cloudflare 1.1.1.1"
                                            color: "#64748b"
                                            font.pixelSize: 9
                                            Layout.alignment: Qt.AlignRight
                                        }
                                    }
                                }
                            }
                        }

                        // Background Services Card
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            color: container.tileColor("#1b1f2a")
                            radius: 12
                            border.color: container.tileColor("#282d3c"); border.width: 1

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 7

                                Text { text: "⚡ BACKGROUND SERVICES"; color: "#90a4ae"; font.pixelSize: 12; font.bold: true; font.letterSpacing: 1.0 }

                                Repeater {
                                    model: [
                                        { name: "Syncthing (Save Sync)", icon: "syncthing", ok: (container.monitorData.services && container.monitorData.services.syncthing), state: (container.monitorData.services && container.monitorData.services.syncthing) ? "ACTIVE" : "OFF" },
                                        { name: "Dropbox (Decky Cloud)", icon: "dropbox", ok: (container.monitorData.services && container.monitorData.services.dropbox), state: (container.monitorData.services && container.monitorData.services.dropbox) ? "SYNCED" : "OFF" },
                                        { name: "Google Drive (rclone)", icon: "folder-remote", ok: (container.monitorData.services && container.monitorData.services.rclone), state: (container.monitorData.services && container.monitorData.services.rclone) ? "MOUNTED" : "OFF" },
                                        { name: "Tailscale Mesh VPN", icon: "network-vpn", ok: (container.monitorData.services && container.monitorData.services.tailscale), state: (container.monitorData.services && container.monitorData.services.tailscale) ? "ONLINE" : "OFF" },
                                        { name: "Tmux Terminal Sessions", icon: "utilities-terminal", ok: (container.monitorData.services && container.monitorData.services.tmux_sessions > 0), state: (container.monitorData.services && container.monitorData.services.tmux_sessions > 0) ? (container.monitorData.services.tmux_sessions + " SESSIONS") : "0 SESSIONS" }
                                    ]

                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 30
                                        color: container.tileColor("#222736")
                                        radius: 6

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 8
                                            anchors.rightMargin: 8

                                            Kirigami.Icon {
                                                source: modelData.icon
                                                Layout.preferredWidth: 14
                                                Layout.preferredHeight: 14
                                            }
                                            Text {
                                                text: modelData.name
                                                color: "#e2e8f0"
                                                font.pixelSize: 11
                                                font.bold: true
                                            }
                                            Item { Layout.fillWidth: true }
                                            Text {
                                                text: modelData.state
                                                color: modelData.ok ? "#4ade80" : "#64748b"
                                                font.pixelSize: 10
                                                font.bold: true
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
