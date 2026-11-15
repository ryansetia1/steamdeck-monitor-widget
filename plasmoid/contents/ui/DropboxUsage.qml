import QtQuick

// Hover popover for the Dropbox service: local folder size vs. the plan quota.
Rectangle {
    id: pop
    property real usedBytes: -1          // from the daemon (services.dropbox_used), -1 = unknown
    property real quotaGB: 2
    property real fs: 1                  // size scale
    property bool glass: false

    readonly property real usedGB: usedBytes / 1073741824
    readonly property real pct: quotaGB > 0 ? Math.min(100, usedGB / quotaGB * 100) : 0
    readonly property color barColor: pct >= 85 ? "#ff5252" : (pct >= 70 ? "#ffa726" : "#00e676")
    function px(n) { return Math.round(n * fs) }
    function gb(v) { return v >= 10 ? v.toFixed(1) : v.toFixed(2) }

    width: px(190)
    height: col.implicitHeight + px(20)
    radius: px(10)
    color: glass ? Qt.rgba(0.07, 0.08, 0.11, 0.94) : "#151922"
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.14)

    Column {
        id: col
        anchors.left: parent.left; anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: pop.px(10)
        spacing: pop.px(6)

        Text {
            text: "DROPBOX STORAGE"
            color: "#90a4ae"
            font.pixelSize: pop.px(9); font.bold: true; font.letterSpacing: 0.8
        }
        Row {
            spacing: pop.px(4)
            Text {
                text: pop.usedBytes < 0 ? "…" : pop.gb(pop.usedGB) + " GB"
                color: "#ffffff"
                font.pixelSize: pop.px(15); font.bold: true
                anchors.baseline: quotaText.baseline
            }
            Text {
                id: quotaText
                text: "/ " + pop.quotaGB + " GB"
                color: "#8b99ad"
                font.pixelSize: pop.px(11); font.bold: true
            }
        }
        Rectangle {
            width: parent.width; height: pop.px(5); radius: height / 2
            color: Qt.rgba(1, 1, 1, 0.10)
            Rectangle {
                width: parent.width * pop.pct / 100; height: parent.height; radius: parent.radius
                color: pop.barColor
            }
        }
        Item {
            width: parent.width; height: freeText.implicitHeight
            Text {
                id: freeText
                text: pop.usedBytes < 0 ? "" : pop.gb(Math.max(0, pop.quotaGB - pop.usedGB)) + " GB free"
                color: "#b0bec5"
                font.pixelSize: pop.px(10); font.bold: true
            }
            Text {
                anchors.right: parent.right
                text: pop.usedBytes < 0 ? "" : Math.round(pop.pct) + "%"
                color: pop.barColor
                font.pixelSize: pop.px(10); font.bold: true
            }
        }
    }
}
