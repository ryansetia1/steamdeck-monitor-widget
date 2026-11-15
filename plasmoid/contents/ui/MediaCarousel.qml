import QtQuick
import org.kde.kirigami as Kirigami

// Game media strip for the detail view: the cover first, then trailers and screenshots
// (from steamaf.py `detail` → "media"). Chevrons step through; clicking opens the theater.
// Shared byte-identical with steamdeck-monitor-widget (keep `fs` scaling working).
Item {
    id: car
    property string cover: ""            // header image url (always the first slide)
    property var media: []               // [{type: "video"|"image", name, thumb, src}]
    property real fs: 1                  // size scale (1 = default)
    property color baseColor: "#212532"
    property int currentIndex: 0
    signal openRequested(int index)

    readonly property var items: [{ type: "cover", name: "Cover", thumb: car.cover, src: car.cover }]
        .concat(car.media || [])
    readonly property var current: items[Math.min(currentIndex, items.length - 1)] || items[0]
    function px(n) { return Math.round(n * fs); }
    function step(d) { currentIndex = (currentIndex + d + items.length) % items.length; }

    onCoverChanged: currentIndex = 0

    implicitHeight: Math.round(width * 215 / 460)

    Kirigami.ShadowedImage {
        id: img
        anchors.fill: parent
        radius: car.px(8)
        color: car.baseColor
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        source: car.current.thumb || ""
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: car.openRequested(car.currentIndex)
        onWheel: (w) => car.step(w.angleDelta.y > 0 || w.angleDelta.x > 0 ? -1 : 1)
    }

    // Play badge on trailers
    Rectangle {
        visible: car.current.type === "video"
        anchors.centerIn: parent
        width: car.px(42); height: width; radius: width / 2
        color: Qt.rgba(0, 0, 0, area.containsMouse ? 0.7 : 0.55)
        border.color: Qt.rgba(1, 1, 1, 0.6)
        border.width: 1
        Text {
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: car.px(2)
            text: "▶"
            color: "#ffffff"
            font.pixelSize: car.px(16)
        }
    }

    // Kind label (bottom left)
    Rectangle {
        visible: car.current.type !== "cover"
        anchors.left: parent.left; anchors.bottom: parent.bottom
        anchors.margins: car.px(6)
        width: kind.implicitWidth + car.px(12); height: car.px(17); radius: height / 2
        color: Qt.rgba(0, 0, 0, 0.6)
        Text {
            id: kind
            anchors.centerIn: parent
            text: car.current.type === "video" ? "TRAILER" : "SCREENSHOT"
            color: car.current.type === "video" ? "#53B7FF" : "#cfd8dc"
            font.pixelSize: car.px(9); font.bold: true; font.letterSpacing: 0.6
        }
    }

    // Counter (top right)
    Rectangle {
        visible: car.items.length > 1
        anchors.right: parent.right; anchors.top: parent.top
        anchors.margins: car.px(6)
        width: counter.implicitWidth + car.px(12); height: car.px(17); radius: height / 2
        color: Qt.rgba(0, 0, 0, 0.6)
        Text {
            id: counter
            anchors.centerIn: parent
            text: (car.currentIndex + 1) + " / " + car.items.length
            color: "#e6ebf2"
            font.pixelSize: car.px(9); font.bold: true
        }
    }

    // Chevrons
    Repeater {
        model: car.items.length > 1 ? [-1, 1] : []
        Rectangle {
            required property int modelData
            anchors.verticalCenter: parent.verticalCenter
            x: modelData < 0 ? car.px(6) : car.width - width - car.px(6)
            width: car.px(26); height: width; radius: width / 2
            color: Qt.rgba(0, 0, 0, chev.containsMouse ? 0.75 : 0.5)
            border.color: Qt.rgba(1, 1, 1, chev.containsMouse ? 0.5 : 0.25)
            border.width: 1
            Text {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -car.px(1)
                anchors.horizontalCenterOffset: modelData < 0 ? -car.px(1) : car.px(1)
                text: modelData < 0 ? "‹" : "›"
                color: "#ffffff"
                font.pixelSize: car.px(18); font.bold: true
            }
            MouseArea {
                id: chev
                anchors.fill: parent
                anchors.margins: -car.px(4)
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: car.step(parent.modelData)
            }
        }
    }
}
