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
    property bool showOnExternal: (Plasmoid.configuration && Plasmoid.configuration.showOnExternal !== undefined) ? Plasmoid.configuration.showOnExternal : true
    property bool autoScreenMigrate: (Plasmoid.configuration && Plasmoid.configuration.autoScreenMigrate !== undefined) ? Plasmoid.configuration.autoScreenMigrate : true
    property bool deckFullscreen: (Plasmoid.configuration && Plasmoid.configuration.deckFullscreen !== undefined) ? Plasmoid.configuration.deckFullscreen : true
    property bool deckSolidBg: (Plasmoid.configuration && Plasmoid.configuration.deckSolidBg !== undefined) ? Plasmoid.configuration.deckSolidBg : true

    property bool isOnDeckScreen: false
    property bool isDualScreenActive: false
    property bool shouldBeVisible: true

    // "Docked" = this widget is on the Deck panel while an external monitor is also connected.
    // In handheld mode the Deck panel takes over screen 0, so the desktop (and its small
    // floating widget) that normally lives on the external monitor appears there instead;
    // dock-only layouts must not kick in for that widget.
    readonly property bool isDocked: root.isOnDeckScreen && root.isDualScreenActive
    // Only use the dashboard when this widget actually covers (most of) the screen. Plasma can hand
    // the Deck panel a desktop whose widget is a small floating card (e.g. when the Deck screen is
    // made primary while docked); that one stays a floating card instead of a squeezed dashboard.
    readonly property bool fillsScreen: root.width >= root.Screen.width * 0.75 && root.height >= root.Screen.height * 0.75
    readonly property bool isFullscreenDashboard: root.isDocked && root.deckFullscreen && root.fillsScreen
    readonly property bool effectiveGlassMode: (root.isDocked && root.deckSolidBg) ? false : root.glassMode

    readonly property int compactWidth: 320 + (baseFontSize - 12) * 15
    property int extDriveCount: 0
    readonly property int compactHeight: 390 + (baseFontSize - 12) * 16 + extDriveCount * (baseFontSize * 2 + 24)

    function setDeckFullscreen(val) {
        root.deckFullscreen = val;
        if (Plasmoid.configuration) {
            Plasmoid.configuration.deckFullscreen = val;
        }
    }

    preferredRepresentation: fullRepresentation
    implicitWidth: 320 + (baseFontSize - 12) * 15
    implicitHeight: compactHeight + 16
    Layout.minimumWidth: 280
    Layout.minimumHeight: 350
    Layout.preferredWidth: implicitWidth
    Layout.preferredHeight: implicitHeight

    visible: shouldBeVisible

    // External-monitor behaviour: 0 = hide while the Deck screen is on, 1 = always show, 2 = never show.
    // The daemon holds the shared value so a change made in one widget's settings also reaches
    // widgets that are currently hidden (and so can't be right-clicked). Local config is the fallback.
    property int sharedExternalMode: -1
    readonly property int externalMode: sharedExternalMode >= 0 ? sharedExternalMode
        : (!showOnExternal ? 2 : (autoScreenMigrate ? 0 : 1))
    onExternalModeChanged: updateScreenState()

    function updateScreenState() {
        var screens = Qt.application.screens;
        var hasEdp = false;
        var hasExt = false;

        if (screens && screens.length > 0) {
            for (var i = 0; i < screens.length; i++) {
                var s = screens[i];
                if (s && s.name && s.name.toLowerCase().indexOf("edp") !== -1) {
                    hasEdp = true;
                } else if (s && s.name) {
                    hasExt = true;
                }
            }
        }

        // Plasma's containment screen numbers and Qt's screen list use different orderings, so
        // only trust the screen name. While it is not known yet (e.g. mid-hotplug), keep the last
        // value; the 2s timer re-checks.
        var scrName = (root.Screen && root.Screen.name) ? root.Screen.name : "";
        if (scrName.length > 0) {
            root.isOnDeckScreen = scrName.toLowerCase().indexOf("edp") !== -1;
        }

        root.isDualScreenActive = (hasEdp && hasExt);

        if (root.externalMode === 2 && !root.isOnDeckScreen) {
            root.shouldBeVisible = false;
        } else if (root.externalMode === 0 && root.isDualScreenActive) {
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
        property var ejectState: ({})      // mount -> "busy" | error message
        property string ejectNotice: ""

        function setEjectState(mount, val) {
            var o = {};
            for (var k in ejectState) o[k] = ejectState[k];
            if (val === undefined) delete o[mount]; else o[mount] = val;
            ejectState = o;
        }

        function ejectDrive(mount) {
            if (ejectState[mount] === "busy") return;
            var name = mount.split("/").pop();
            var ext = monitorData.external_drives || [];
            for (var i = 0; i < ext.length; i++) if (ext[i].mount === mount) name = ext[i].name;
            setEjectState(mount, "busy");
            var xhr = new XMLHttpRequest();
            xhr.open("POST", "http://127.0.0.1:19842/eject");
            xhr.setRequestHeader("Content-Type", "application/json");
            xhr.timeout = 90000;
            var fail = function(msg) {
                setEjectState(mount, msg);
                ejectErrorTimer.mounts.push(mount);
                ejectErrorTimer.restart();
            };
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE) return;
                var res = {};
                try { res = JSON.parse(xhr.responseText); } catch (e) {}
                if (xhr.status === 200 && res.ok) {
                    setEjectState(mount, undefined);
                    ejectNotice = name + (res.message === "Safe to remove" ? " is safe to remove" : " unmounted");
                    noticeTimer.restart();
                    fetchMetrics();
                } else {
                    fail(res.error || (xhr.status === 0 ? "Monitor daemon not responding" : "Eject failed"));
                }
            };
            xhr.ontimeout = function() { fail("Eject timed out"); };
            xhr.send(JSON.stringify({ mount: mount }));
        }

        Timer {
            id: ejectErrorTimer
            property var mounts: []
            interval: 6000
            onTriggered: { for (var i = 0; i < mounts.length; i++) container.setEjectState(mounts[i], undefined); mounts = []; }
        }
        Timer { id: noticeTimer; interval: 6000; onTriggered: container.ejectNotice = "" }

        function applyPrefs(prefs) {
            prefs = prefs || {};
            root.sharedExternalMode = (prefs.external_mode !== undefined) ? prefs.external_mode : -1;
        }

        function fetchPrefs() {
            var xhr = new XMLHttpRequest();
            xhr.open("GET", "http://127.0.0.1:19842/prefs");
            xhr.timeout = 1800;
            xhr.onreadystatechange = function() {
                if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                    try { container.applyPrefs(JSON.parse(xhr.responseText).prefs); } catch (e) {}
                }
            };
            xhr.send();
        }

        function fetchMetrics() {
            var xhr = new XMLHttpRequest();
            xhr.open("GET", "http://127.0.0.1:19842/status");
            xhr.timeout = 3500;   // the daemon may need ~0.5s to wake up after being idle
            xhr.onreadystatechange = function() {
                if (xhr.readyState === XMLHttpRequest.DONE) {
                    if (xhr.status === 200) {
                        try {
                            container.monitorData = JSON.parse(xhr.responseText);
                            root.extDriveCount = (container.monitorData.external_drives || []).length;
                            container.applyPrefs(container.monitorData.prefs);
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
            // keep polling slowly while hidden so shared prefs can bring the widget back
            interval: root.shouldBeVisible ? 2000 : 5000
            running: true
            repeat: true
            triggeredOnStart: true
            onTriggered: root.shouldBeVisible ? container.fetchMetrics() : container.fetchPrefs()
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
            x: root.isFullscreenDashboard ? 0 : ((container.width > root.compactWidth + 32) ? (container.width - root.compactWidth - 16) : 0)
            y: root.isFullscreenDashboard ? 0 : 16
            width: root.isFullscreenDashboard ? container.width : root.compactWidth
            height: root.isFullscreenDashboard ? container.height : root.compactHeight
            color: root.effectiveGlassMode ? Qt.rgba(0.09, 0.10, 0.14, root.glassOpacity) : (root.isFullscreenDashboard ? "#11141c" : "#161820")
            radius: root.isFullscreenDashboard ? 0 : 16
            border.color: root.isFullscreenDashboard ? "transparent" : (root.effectiveGlassMode
                ? (container.isConnected ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 0.32, 0.32, 0.5))
                : (container.isConnected ? "#2c3242" : "#4a2424"))
            border.width: root.isFullscreenDashboard ? 0 : 1
            clip: true

            // Only the view that is actually shown gets instantiated; the other one (and both,
            // while the widget is hidden) costs no memory and no per-poll binding updates.

            // --- COMPACT VIEW (FLOATING CARD) ---
            Loader {
                anchors.fill: parent
                active: root.shouldBeVisible && !root.isFullscreenDashboard
                sourceComponent: Component {
            ColumnLayout {
                id: compactView
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

                    // Fullscreen Dashboard Toggle Button (only while docked, on a full-screen widget)
                    Rectangle {
                        visible: root.isDocked && root.fillsScreen
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

                    // Shown after an eject, in the space the removed drive row used to take
                    Text {
                        visible: container.ejectNotice !== ""
                        Layout.fillWidth: true
                        text: "✓ " + container.ejectNotice
                        color: "#4ade80"
                        font.pixelSize: root.baseFontSize - 2
                        font.bold: true
                        elide: Text.ElideRight
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
                                    Layout.maximumWidth: parent.width * 0.6
                                }
                                Rectangle {
                                    readonly property bool busy: container.ejectState[modelData.mount] === "busy"
                                    Layout.preferredWidth: root.baseFontSize + 8
                                    Layout.preferredHeight: root.baseFontSize + 8
                                    radius: 5
                                    color: ejectArea.containsMouse && !busy ? container.tileColor("#2a3040") : "transparent"
                                    border.color: container.tileColor("#2c3242")
                                    border.width: 1
                                    Image {
                                        anchors.centerIn: parent
                                        width: parent.width * 0.6; height: width
                                        source: Qt.resolvedUrl("../icons/eject.svg")
                                        sourceSize: Qt.size(32, 32)
                                        opacity: parent.busy ? 0.35 : 1
                                    }
                                    MouseArea {
                                        id: ejectArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        enabled: !parent.busy
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: container.ejectDrive(modelData.mount)
                                    }
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
                                    readonly property var st: container.ejectState[modelData.mount]
                                    text: st === "busy" ? "Ejecting…" : (st ? st : ((modelData.used_gb >= 1000 ? (modelData.used_gb/1024).toFixed(1) + "T" : Math.round(modelData.used_gb || 0) + "G") + "/" + (modelData.total_gb >= 1000 ? (modelData.total_gb/1024).toFixed(1) + "T" : Math.round(modelData.total_gb || 0) + "G")))
                                    color: (st && st !== "busy") ? "#ff6b6b" : "#90a4ae"
                                    font.pixelSize: root.baseFontSize - 3
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
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

                        Repeater {
                            model: {
                                var s = container.monitorData.services || {};
                                var t = s.tmux_sessions || 0;
                                return [
                                    { name: "Syncthing",    icon: "syncthing.svg",    ok: !!s.syncthing, on: "ACTIVE",  off: "OFF" },
                                    { name: "Dropbox",      icon: "dropbox.svg",      ok: !!s.dropbox,   on: "SYNCED",  off: "OFF" },
                                    { name: "GDrive",       icon: "google-drive.svg", ok: !!s.rclone,    on: "MOUNTED", off: "OFF" },
                                    { name: "Tailscale",    icon: "tailscale.svg",    ok: !!s.tailscale, on: "ONLINE",  off: "OFF" },
                                    { name: "tmux",         icon: "tmux.png",         ok: t > 0,
                                      on: t + (t === 1 ? " SESSION" : " SESSIONS"), off: "NO SESSION" }
                                ];
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.columnSpan: index === 4 ? 2 : 1   // tmux spans the full row
                                Layout.preferredWidth: 1
                                implicitHeight: root.baseFontSize + 14
                                radius: 8
                                color: container.tileColor("#1e222d")

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 7
                                    Image {
                                        source: Qt.resolvedUrl("../icons/" + modelData.icon)
                                        Layout.preferredWidth: root.baseFontSize + 3
                                        Layout.preferredHeight: root.baseFontSize + 3
                                        sourceSize: Qt.size(48, 48)
                                        fillMode: Image.PreserveAspectFit
                                        smooth: true
                                        opacity: modelData.ok ? 1.0 : 0.5
                                    }
                                    Text {
                                        text: modelData.name
                                        color: modelData.ok ? "#e6ebf2" : "#8b99ad"
                                        font.pixelSize: root.baseFontSize - 1
                                        font.bold: true
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                    Text {
                                        text: modelData.ok ? modelData.on : modelData.off
                                        color: modelData.ok ? "#4ade80" : "#8b99ad"
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
            }

            // --- FULLSCREEN DASHBOARD VIEW (Steam Deck panel, 1280x800) ---
            Loader {
                anchors.fill: parent
                active: root.shouldBeVisible && root.isFullscreenDashboard
                sourceComponent: Component {
                    DashboardView {
                        d: container.monitorData
                        connected: container.isConnected
                        glass: root.effectiveGlassMode
                        ejectState: container.ejectState
                        notice: container.ejectNotice
                        onRestoreRequested: root.setDeckFullscreen(false)
                        onEjectRequested: (mount) => container.ejectDrive(mount)
                    }
                }
            }
        }
    }
}
