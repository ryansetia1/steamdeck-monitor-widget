import QtQuick
import QtQuick.Controls as QQC2
import QtMultimedia
import org.kde.plasma.core as PlasmaCore

// Full-screen "theater" for a game's cover, trailers and screenshots: dimmed screen, big stage,
// chevrons, thumbnail strip. Tooltip-type window like the island, so the search field keeps
// keyboard focus; the parent forwards ←/→/Esc to prev()/next()/close().
// Shared byte-identical with steamdeck-monitor-widget.
PlasmaCore.Dialog {
    id: th
    property var items: []               // same shape as MediaCarousel.items
    property string title: ""
    property string appId: ""
    property rect screenRect: Qt.rect(0, 0, 1280, 800)
    property int index: 0
    property bool shown: false
    signal indexPicked(int index)        // lets the carousel follow along

    readonly property var current: items[Math.min(index, items.length - 1)] || ({ type: "", thumb: "", src: "", name: "" })
    readonly property bool isVideo: current.type === "video"

    function open(i) { index = Math.max(0, Math.min(i, items.length - 1)); shown = true; }
    function close() { shown = false; }
    function step(d) {
        if (!items.length) return;
        index = (index + d + items.length) % items.length;
        indexPicked(index);
    }
    function next() { step(1); }
    function prev() { step(-1); }
    function fmt(ms) {
        var s = Math.max(0, Math.floor(ms / 1000));
        return Math.floor(s / 60) + ":" + ("0" + (s % 60)).slice(-2);
    }

    location: PlasmaCore.Types.Floating
    type: PlasmaCore.Dialog.Tooltip
    backgroundHints: PlasmaCore.Dialog.NoBackground
    flags: Qt.WindowStaysOnTopHint | Qt.WindowDoesNotAcceptFocus
    visible: shown
    onVisibleChanged: if (visible) { x = screenRect.x; y = screenRect.y; }

    mainItem: Item {
        id: stageRoot
        width: th.screenRect.width
        height: th.screenRect.height

        readonly property real unit: Math.min(width / 1280, height / 800)
        function u(n) { return Math.round(n * unit); }

        // Dimmed backdrop: click to close
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0.02, 0.03, 0.05, 0.86)
            opacity: th.shown ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 150 } }
            MouseArea { anchors.fill: parent; onClicked: th.close() }
        }

        // ── Stage ──
        Rectangle {
            id: stage
            readonly property real maxW: parent.width - stageRoot.u(200)
            readonly property real maxH: parent.height - stageRoot.u(250)
            width: Math.min(maxW, maxH * 16 / 9)
            height: width * 9 / 16
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.round((parent.height - height - stageRoot.u(150)) / 2) + stageRoot.u(10)
            radius: stageRoot.u(12)
            color: "#0b0d12"
            clip: true
            border.color: Qt.rgba(1, 1, 1, 0.12)
            border.width: 1

            MouseArea { anchors.fill: parent }   // swallow clicks so the backdrop doesn't close

            // Thumbnail first (instant), then the full image on top
            Image {
                anchors.fill: parent
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                source: th.shown ? (th.current.thumb || "") : ""
                visible: full.status !== Image.Ready || th.isVideo
            }
            Image {
                id: full
                anchors.fill: parent
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                visible: !th.isVideo
                source: th.shown && !th.isVideo ? (th.current.src || "") : ""
            }

            // Trailer
            MediaPlayer {
                id: player
                source: th.shown && th.isVideo ? th.current.src : ""
                videoOutput: video
                audioOutput: AudioOutput { id: audio; volume: 0.8 }
                onSourceChanged: { errorText = ""; if (source.toString()) play(); }
                property string errorText: ""
                onErrorOccurred: (err, msg) => errorText = msg || "Playback error"
            }
            VideoOutput {
                id: video
                anchors.fill: parent
                visible: th.isVideo
            }
            QQC2.BusyIndicator {
                anchors.centerIn: parent
                running: th.isVideo && !player.errorText
                         && (player.mediaStatus === MediaPlayer.LoadingMedia || player.mediaStatus === MediaPlayer.BufferingMedia
                             || player.mediaStatus === MediaPlayer.StalledMedia || player.mediaStatus === MediaPlayer.NoMedia)
                visible: running
            }
            Item {
                id: videoArea
                anchors.fill: parent
                visible: th.isVideo
                MouseArea {
                    id: videoMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: player.playbackState === MediaPlayer.PlayingState ? player.pause() : player.play()
                }
            }

            // Playback error → offer the Steam page instead
            Column {
                visible: th.isVideo && player.errorText.length > 0
                anchors.centerIn: parent
                spacing: stageRoot.u(10)
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Can't play this trailer here"
                    color: "#e6ebf2"; font.pixelSize: stageRoot.u(16); font.bold: true
                }
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: openTxt.implicitWidth + stageRoot.u(28); height: stageRoot.u(34); radius: height / 2
                    color: openArea.containsMouse ? "#2a7fc0" : "#1f6aa5"
                    Text { id: openTxt; anchors.centerIn: parent; text: "Watch on Steam"; color: "#ffffff"; font.pixelSize: stageRoot.u(13); font.bold: true }
                    MouseArea {
                        id: openArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { Qt.openUrlExternally("https://store.steampowered.com/app/" + th.appId); th.close(); }
                    }
                }
            }

            // Video controls
            Rectangle {
                visible: th.isVideo && !player.errorText
                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                height: stageRoot.u(46)
                gradient: Gradient {
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.75) }
                }
                Row {
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.bottom: parent.bottom; anchors.margins: stageRoot.u(10)
                    spacing: stageRoot.u(12)
                    Text {
                        id: playBtn
                        text: player.playbackState === MediaPlayer.PlayingState ? "❚❚" : "▶"
                        color: "#ffffff"; font.pixelSize: stageRoot.u(15); font.bold: true
                        width: stageRoot.u(18)
                        MouseArea {
                            anchors.fill: parent; anchors.margins: -stageRoot.u(6); cursorShape: Qt.PointingHandCursor
                            onClicked: player.playbackState === MediaPlayer.PlayingState ? player.pause() : player.play()
                        }
                    }
                    Text {
                        id: timeTxt
                        anchors.verticalCenter: playBtn.verticalCenter
                        text: th.fmt(player.position) + " / " + th.fmt(player.duration)
                        color: "#cfd8dc"; font.pixelSize: stageRoot.u(12); font.bold: true
                    }
                    Item {
                        width: parent.width - playBtn.width - timeTxt.implicitWidth - muteBtn.width - 3 * parent.spacing
                        height: playBtn.height
                        Rectangle {
                            id: track
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width; height: stageRoot.u(4); radius: height / 2
                            color: Qt.rgba(1, 1, 1, 0.22)
                            Rectangle {
                                width: player.duration > 0 ? parent.width * player.position / player.duration : 0
                                height: parent.height; radius: parent.radius
                                color: "#53B7FF"
                            }
                        }
                        MouseArea {
                            anchors.fill: parent; anchors.topMargin: -stageRoot.u(6); anchors.bottomMargin: -stageRoot.u(6)
                            cursorShape: Qt.PointingHandCursor
                            onClicked: (m) => { if (player.seekable && player.duration > 0) player.position = player.duration * m.x / width; }
                        }
                    }
                    Text {
                        id: muteBtn
                        text: audio.muted ? "🔇" : "🔊"
                        font.pixelSize: stageRoot.u(14)
                        width: stageRoot.u(20)
                        MouseArea {
                            anchors.fill: parent; anchors.margins: -stageRoot.u(6); cursorShape: Qt.PointingHandCursor
                            onClicked: audio.muted = !audio.muted
                        }
                    }
                }
            }
        }

        // Close (top right of the stage)
        Rectangle {
            x: stage.x + stage.width + stageRoot.u(14)
            y: stage.y - stageRoot.u(4)
            width: stageRoot.u(36); height: width; radius: width / 2
            color: Qt.rgba(1, 1, 1, closeArea.containsMouse ? 0.22 : 0.12)
            Repeater {
                model: [45, -45]
                Rectangle {
                    required property int modelData
                    anchors.centerIn: parent
                    width: stageRoot.u(14); height: stageRoot.u(2); radius: 1
                    rotation: modelData; color: "#ffffff"; antialiasing: true
                }
            }
            MouseArea { id: closeArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: th.close() }
        }

        // Chevrons
        Repeater {
            model: th.items.length > 1 ? [-1, 1] : []
            Rectangle {
                required property int modelData
                width: stageRoot.u(48); height: width; radius: width / 2
                x: modelData < 0 ? stage.x - width - stageRoot.u(24) : stage.x + stage.width + stageRoot.u(24)
                y: stage.y + (stage.height - height) / 2
                color: Qt.rgba(1, 1, 1, chevArea.containsMouse ? 0.22 : 0.12)
                Text {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -stageRoot.u(2)
                    anchors.horizontalCenterOffset: modelData < 0 ? -stageRoot.u(2) : stageRoot.u(2)
                    text: modelData < 0 ? "‹" : "›"
                    color: "#ffffff"; font.pixelSize: stageRoot.u(32); font.bold: true
                }
                MouseArea { id: chevArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: th.step(parent.modelData) }
            }
        }

        // Caption
        Item {
            id: caption
            x: stage.x; width: stage.width
            y: stage.y + stage.height + stageRoot.u(12)
            height: stageRoot.u(22)
            Text {
                anchors.left: parent.left; anchors.right: count.left; anchors.rightMargin: stageRoot.u(12)
                anchors.verticalCenter: parent.verticalCenter
                text: th.title + "  ·  " + (th.current.type === "cover" ? "Cover" : th.isVideo ? th.current.name : "Screenshot")
                color: "#e6ebf2"; font.pixelSize: stageRoot.u(15); font.bold: true
                elide: Text.ElideRight
            }
            Text {
                id: count
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                text: (th.index + 1) + " / " + th.items.length
                color: "#8b99ad"; font.pixelSize: stageRoot.u(13); font.bold: true
            }
        }

        // Thumbnail strip
        ListView {
            id: strip
            x: stage.x; width: stage.width
            y: caption.y + caption.height + stageRoot.u(12)
            height: stageRoot.u(64)
            orientation: ListView.Horizontal
            spacing: stageRoot.u(8)
            clip: true
            model: th.items
            currentIndex: th.index
            highlightMoveDuration: 200
            highlightRangeMode: ListView.ApplyRange
            preferredHighlightBegin: width / 2 - stageRoot.u(57)
            preferredHighlightEnd: width / 2 + stageRoot.u(57)
            delegate: Rectangle {
                required property var modelData
                required property int index
                width: stageRoot.u(114); height: strip.height
                radius: stageRoot.u(6)
                color: "#0b0d12"
                border.width: index === th.index ? 2 : 1
                border.color: index === th.index ? "#53B7FF" : Qt.rgba(1, 1, 1, thumbArea.containsMouse ? 0.4 : 0.12)
                Image {
                    anchors.fill: parent; anchors.margins: 2
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    source: th.shown ? (modelData.thumb || "") : ""
                    opacity: index === th.index ? 1 : 0.7
                }
                Text {
                    visible: modelData.type === "video"
                    anchors.centerIn: parent
                    text: "▶"; color: "#ffffff"; font.pixelSize: stageRoot.u(16)
                    style: Text.Outline; styleColor: Qt.rgba(0, 0, 0, 0.6)
                }
                MouseArea {
                    id: thumbArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: { th.index = index; th.indexPicked(index); }
                }
            }
        }

        // Keyboard hint
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: strip.y + strip.height + stageRoot.u(10)
            text: "←  →  browse   ·   Esc  close"
            color: "#5f6b7d"; font.pixelSize: stageRoot.u(11)
        }
    }
}
