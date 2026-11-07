import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root
    property string ping: "..."

    toolTipMainText: "Ping 1.1.1.1"

    function pingColor(s) {
        var v = parseFloat(s);
        if (isNaN(v)) return "#ff5252";
        if (v <= 80) return "#00e676";
        if (v <= 150) return "#ffa726";
        return "#ff5252";
    }

    Timer {
        interval: 2000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: {
            var xhr = new XMLHttpRequest();
            xhr.open("GET", "http://127.0.0.1:19842/status");
            xhr.timeout = 1500;
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== 4) return;
                try { root.ping = JSON.parse(xhr.responseText).ping || "Offline"; }
                catch (e) { root.ping = "Offline"; }
            };
            xhr.send();
        }
    }

    compactRepresentation: Item {
        id: compact
        implicitWidth: label.implicitWidth + 28
        Layout.minimumWidth: implicitWidth
        Layout.preferredWidth: implicitWidth

        // thin separator on the left, away from the tray chevron
        Rectangle {
            width: 1
            height: parent.height * 0.5
            anchors.left: parent.left
            anchors.leftMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            color: Kirigami.Theme.textColor
            opacity: 0.3
        }

        // thin separator on the right, before the clock
        Rectangle {
            width: 1
            height: parent.height * 0.5
            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            color: Kirigami.Theme.textColor
            opacity: 0.3
        }

        PlasmaComponents.Label {
            id: label
            anchors.centerIn: parent
            text: "Ping " + root.ping
            color: root.pingColor(root.ping)
            font.bold: true
        }
    }

    fullRepresentation: PlasmaComponents.Label {
        text: "Ping 1.1.1.1: " + root.ping
        color: root.pingColor(root.ping)
    }
}
