import QtQuick

// Small pill showing a steamAF verdict ("Worth it", "No rush", …). Hidden when there is none.
Rectangle {
    id: badge
    property string verdict: ""
    property bool small: false
    property real fs: 1               // size scale (1 = default)

    readonly property color tone: {
        switch (badge.verdict) {
        case "worth-it": return "#34d399";
        case "good-deal": return "#5eead4";
        case "no-rush": return "#66c0f4";
        case "wait": return "#fbbf24";
        default: return "#94a3b8";
        }
    }
    readonly property string label: {
        switch (badge.verdict) {
        case "worth-it": return "Worth it";
        case "good-deal": return "Good deal";
        case "no-rush": return "No rush";
        case "wait": return "Wait";
        case "free": return "Free";
        case "coming-soon": return "Soon";
        default: return "";
        }
    }

    visible: label.length > 0
    implicitWidth: inner.implicitWidth + Math.round((small ? 12 : 16) * fs)
    implicitHeight: Math.round((small ? 16 : 20) * fs)
    width: implicitWidth
    height: implicitHeight
    radius: height / 2
    color: Qt.rgba(tone.r, tone.g, tone.b, 0.16)
    border.color: Qt.rgba(tone.r, tone.g, tone.b, 0.45)
    border.width: 1

    Row {
        id: inner
        anchors.centerIn: parent
        spacing: Math.round(4 * badge.fs)
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.round((badge.small ? 5 : 6) * badge.fs)
            height: width
            radius: width / 2
            color: badge.tone
        }
        Text {
            id: txt
            anchors.verticalCenter: parent.verticalCenter
            text: badge.label
            color: badge.tone
            font.pixelSize: Math.round((badge.small ? 9 : 10) * badge.fs)
            font.bold: true
        }
    }
}
