import QtQuick
import QtQuick.Layouts
import org.kde.plasma.core as PlasmaCore

// RLog row for the Deck Monitor card (RLog's docs/PLAN.md, "Deck Monitor integration", D1).
// The row names the Playing game on top; tapping it opens an island under the card with that
// game large, the rest of Playing as a small carousel and the queue's top three.
// Read-only: every action opens RLog in the browser. Data: GET http://127.0.0.1:19842/rlog
// (the daemon fetches RLog's /api/widget with the token in ~/.config/rlog/widget.env).
Item {
    id: rs

    // ── Inputs ──────────────────────────────────────────────────────────────
    property Item anchorItem: parent
    property bool glassMode: false
    property real glassOpacity: 0.55
    property int islandStyle: 0           // same setting as the game search island
    property real islandOpacity: 0.94
    property bool otherIslandOpen: false  // the search island took the spot: close ours
    property string pinned: ""            // entry id picked in the carousel (widget config)
    signal pinRequested(string entryId)

    property real fs: 1
    function px(n) { return Math.round(n * fs); }

    implicitHeight: px(34)

    readonly property string api: "http://127.0.0.1:19842/rlog"
    readonly property string appUrl: "https://r-log.vercel.app"
    readonly property int pad: px(10)

    // ── Look (matches GamesSection) ─────────────────────────────────────────
    function tileColor(solid) { return rs.glassMode ? Qt.rgba(1, 1, 1, 0.08) : solid; }
    readonly property color cardColor: glassMode ? Qt.rgba(0.09, 0.10, 0.14, glassOpacity) : "#161820"
    readonly property color cardBorder: glassMode ? Qt.rgba(1, 1, 1, 0.22) : "#262a36"
    readonly property color islandColor: {
        switch (islandStyle) {
        case 1: return cardColor;
        case 2: return Qt.rgba(0.09, 0.10, 0.14, islandOpacity);
        default: return glassMode ? Qt.rgba(0.09, 0.10, 0.14, Math.max(glassOpacity, 0.94)) : "#161820";
        }
    }
    readonly property color green: "#34d399"
    readonly property color mute: "#6b7385"
    readonly property color ink2: "#cfd8dc"

    // ── Data ────────────────────────────────────────────────────────────────
    property var summary: null            // RLog summary (see RLog src/widget.ts)
    property string error: ""
    property bool stale: false
    property bool loading: false
    readonly property var playing: summary ? summary.playing : []
    readonly property var upNext: summary ? summary.up_next : []
    readonly property var current: {
        for (var i = 0; i < playing.length; i++) if (playing[i].entry_id === pinned) return playing[i];
        return playing.length ? playing[0] : null;
    }

    function load(refresh) {
        rs.loading = true;
        var xhr = new XMLHttpRequest();
        xhr.open("GET", rs.api + (refresh ? "?refresh=1" : ""));
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (!rs) return;                  // this widget instance was destroyed meanwhile
            rs.loading = false;
            var r;
            try { r = JSON.parse(xhr.responseText); }
            catch (e) { r = { ok: false, error: xhr.status ? "RLog failed (HTTP " + xhr.status + ")" : "Monitor daemon is not reachable" }; }
            if (r.data) rs.summary = r.data;
            rs.stale = !!r.stale;
            rs.error = r.error || "";
        };
        xhr.send();
    }
    Component.onCompleted: load(false)
    Timer { interval: 10 * 60 * 1000; running: true; repeat: true; onTriggered: rs.load(false) }

    // ── Formatting ──────────────────────────────────────────────────────────
    function fmtHours(h) {
        if (!h || h <= 0) return "";
        if (h < 0.75) return "½h";
        var r = h < 10 ? Math.round(h * 2) / 2 : Math.round(h);
        var whole = Math.floor(r);
        return whole + (r - whole ? "½" : "") + "h";
    }
    function rowRight(g) {
        if (!g) return "";
        if (g.main_h && g.played_h) return g.played_h < g.main_h ? "~" + fmtHours(g.main_h - g.played_h) + " left" : fmtHours(g.played_h) + " played";
        return g.main_h ? "~" + fmtHours(g.main_h) : "";
    }
    function ago(ms) {
        if (!ms) return "";
        var d = Math.floor((Date.now() - ms) / 86400000);
        if (d <= 0) return "today";
        if (d === 1) return "yesterday";
        if (d < 14) return d + " days ago";
        if (d < 60) return Math.round(d / 7) + " wk ago";
        return Math.round(d / 30) + " mo ago";
    }
    function franchiseLine(g) {
        if (!g || !g.franchise) return "";
        var f = g.franchise;
        return f.name + " " + f.done + "/" + f.total + (f.next ? " · Next: " + f.next : "");
    }
    function openUrl(url) { Qt.openUrlExternally(url); }
    function statusColor(st) {
        switch (st) {
        case "playing": return rs.green;
        case "completed": return "#60a5fa";
        case "on_hold": return "#fbbf24";
        default: return "#8b99ad";
        }
    }
    function statusLabel(st) {
        switch (st) {
        case "playing": return "Playing";
        case "completed": return "Completed";
        case "on_hold": return "On hold";
        case "backlog": return "Backlog";
        case "owned": return "Shelf";
        case "dropped": return "Dropped";
        default: return "Not in your library";
        }
    }
    function fmtDate(d) {
        if (!d) return "";
        var m = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
        var p = d.split("-");
        return (p[2] ? Number(p[2]) + " " : "") + (p[1] ? m[Number(p[1]) - 1] + " " : "") + p[0];
    }

    // ── Detail page (a game opened from the top card, Up next or a franchise list) ──
    property var trail: []                // item ids opened, newest last; ‹ goes back one
    property var detail: null
    property bool detailLoading: false
    property string detailError: ""
    property var media: []
    property int detailReq: 0
    readonly property bool detailOpen: trail.length > 0
    readonly property int maxDetailH: Math.max(px(240), screenRect.y + screenRect.height - islandTop - px(6) - 2 * pad - px(16))
    property int islandTop: 0
    readonly property rect screenRect: Qt.rect(Screen.virtualX, Screen.virtualY, Screen.width, Screen.height)

    function openDetail(itemId) {
        if (!itemId) return;
        trail = trail.concat([itemId]);
        fetchDetail(itemId);
    }
    function back() {
        theater.close();
        trail = trail.slice(0, -1);
        if (trail.length) fetchDetail(trail[trail.length - 1]);
        else { detail = null; media = []; detailReq++; }
    }
    function fetchDetail(itemId) {
        var rq = ++detailReq;
        detail = null; media = []; detailError = ""; detailLoading = true;
        detFlick.contentY = 0;
        get("http://127.0.0.1:19842/rlog/detail?item=" + encodeURIComponent(itemId), r => {
            if (rq !== rs.detailReq) return;
            rs.detailLoading = false;
            if (!r.ok) { rs.detailError = r.error || "Couldn't open this game"; return; }
            rs.detail = r.data;
            if (r.data.igdb_id || r.data.steam_appid)
                rs.get("http://127.0.0.1:19842/rlog/media?igdb=" + (r.data.igdb_id || "") + "&steam=" + (r.data.steam_appid || ""), m => {
                    if (rq === rs.detailReq && m.media) rs.media = m.media;
                });
        });
    }
    function get(url, cb) {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", url);
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (!rs) return;
            var r;
            try { r = JSON.parse(xhr.responseText); }
            catch (e) { r = { ok: false, error: xhr.status ? "RLog failed (HTTP " + xhr.status + ")" : "Monitor daemon is not reachable" }; }
            cb(r);
        };
        xhr.send();
    }
    // Carousel: a Steam game's header first; otherwise its first screenshot (portrait covers crop badly)
    readonly property string mediaCover: !detail ? ""
        : detail.steam_appid ? "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/" + detail.steam_appid + "/header.jpg"
        : (media.length && media[0].type === "image" ? media[0].src : (detail.cover || ""))
    readonly property var mediaRest: detail && !detail.steam_appid && media.length && media[0].type === "image" ? media.slice(1) : media

    // ── Island state ────────────────────────────────────────────────────────
    property bool open_: false
    readonly property bool islandOpen: open_ && rs.visible && !otherIslandOpen
    onOtherIslandOpenChanged: if (otherIslandOpen) open_ = false
    onIslandOpenChanged: {
        if (islandOpen) { island.place(); load(false); }
        else { theater.close(); trail = []; detail = null; media = []; detailReq++; }
    }
    function toggle() {
        open_ = !open_;
        if (open_) focusSink.forceActiveFocus();
    }

    // Takes keyboard focus while the island is open, like the search fields: clicking elsewhere
    // (or focusing a search field) drops it and closes the island; Esc closes it too.
    Item {
        id: focusSink
        onActiveFocusChanged: if (!activeFocus) rs.open_ = false
        Keys.onEscapePressed: {
            if (theater.shown) theater.close();
            else if (rs.detailOpen) rs.back();
            else rs.open_ = false;
        }
        Keys.onLeftPressed: if (theater.shown) theater.step(-1)
        Keys.onRightPressed: if (theater.shown) theater.step(1)
    }

    // Full-screen media of the open game (shared with steamAF's detail)
    MediaTheater {
        id: theater
        items: carousel.items
        title: rs.detail ? rs.detail.title : ""
        appId: rs.detail && rs.detail.steam_appid ? String(rs.detail.steam_appid) : ""
        screenRect: rs.screenRect
        onIndexPicked: (i) => carousel.currentIndex = i
    }

    // ── Cover: the image, or the title on a dark tile while it loads / when there is none ──
    component Cover: Rectangle {
        id: cv
        property string src: ""
        property string label: ""
        property bool selected: false
        radius: rs.px(6)
        color: rs.tileColor("#2a2f3d")
        clip: true
        Text {
            visible: img.status !== Image.Ready
            anchors.fill: parent
            anchors.margins: rs.px(4)
            text: cv.label
            color: "#ffffff"
            font.pixelSize: Math.max(rs.px(9), Math.round(cv.width / 8))
            font.bold: true
            wrapMode: Text.Wrap
            verticalAlignment: Text.AlignBottom
            elide: Text.ElideRight
        }
        Image {
            id: img
            anchors.fill: parent
            source: cv.src
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            smooth: true
        }
        Rectangle {
            anchors.fill: parent
            anchors.margins: -1
            color: "transparent"
            radius: cv.radius + 1
            border.width: cv.selected ? 2 : 0
            border.color: rs.green
        }
    }

    component Dot: Rectangle {
        width: rs.px(7); height: width; radius: width / 2
        color: rs.green
    }

    component SectionLabel: Text {
        color: rs.mute
        font.pixelSize: rs.px(10)
        font.bold: true
        font.letterSpacing: 0.8
    }

    // ── The row in the card ─────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        radius: 10
        color: rowArea.containsMouse ? rs.tileColor("#283041") : rs.tileColor("#212532")
        border.width: 1
        border.color: rs.open_ ? rs.green : rs.tileColor("#2c3242")

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: rs.px(8)
            anchors.rightMargin: rs.px(10)
            spacing: rs.px(8)

            Rectangle {
                Layout.preferredWidth: markText.implicitWidth + rs.px(10)
                Layout.preferredHeight: rs.px(18)
                radius: 5
                color: Qt.rgba(0.20, 0.83, 0.60, 0.16)
                Text {
                    id: markText
                    anchors.centerIn: parent
                    textFormat: Text.StyledText
                    text: "<b>R<font color='#34d399'>log</font></b>"
                    color: "#ffffff"
                    font.pixelSize: rs.px(11)
                }
            }
            Dot { visible: !!rs.current }
            Text {
                Layout.fillWidth: true
                textFormat: Text.StyledText
                elide: Text.ElideRight
                color: "#ffffff"
                font.pixelSize: rs.px(12)
                text: rs.current
                      ? rs.current.title + (rs.current.franchise ? " <font color='#6b7385'>· " + rs.current.franchise.done + "/" + rs.current.franchise.total + "</font>" : "")
                      : (rs.summary ? "<font color='#6b7385'>Nothing in Playing</font>"
                                 : "<font color='#6b7385'>" + (rs.error || "Loading…") + "</font>")
            }
            Text {
                text: rs.rowRight(rs.current)
                color: rs.ink2
                font.family: "monospace"
                font.pixelSize: rs.px(11)
            }
        }
        MouseArea {
            id: rowArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: rs.toggle()
        }
    }

    // ── Island ──────────────────────────────────────────────────────────────
    PlasmaCore.Dialog {
        id: island
        location: PlasmaCore.Types.Floating
        type: PlasmaCore.Dialog.Tooltip
        backgroundHints: PlasmaCore.Dialog.NoBackground
        flags: Qt.WindowStaysOnTopHint | Qt.WindowDoesNotAcceptFocus
        visible: rs.islandOpen
        onVisibleChanged: if (visible) place()

        function place() {
            var a = rs.anchorItem;
            var p = a.mapToGlobal(0, a.height);
            island.x = Math.round(p.x);
            island.y = Math.round(p.y);
            rs.islandTop = island.y;
        }

        mainItem: Item {
            width: rs.anchorItem ? rs.anchorItem.width : 320
            height: rs.px(6) + card.height

            Rectangle {
                id: card
                y: rs.px(6)
                width: parent.width
                height: (rs.detailOpen ? detFlick.height : col.implicitHeight) + 2 * rs.pad
                color: rs.islandColor
                radius: 16
                border.color: rs.cardBorder
                border.width: 1
                clip: true

                opacity: 0
                transform: Translate { id: slide; y: -8 }
                states: State {
                    name: "open"; when: rs.islandOpen
                    PropertyChanges { card.opacity: 1; slide.y: 0 }
                }
                transitions: Transition {
                    to: "open"
                    NumberAnimation { properties: "opacity,y"; duration: 160; easing.type: Easing.OutCubic }
                }

                // ── Detail page ──
                Flickable {
                    id: detFlick
                    visible: rs.detailOpen
                    x: rs.pad
                    y: rs.pad
                    width: card.width - 2 * rs.pad
                    height: Math.min(det.implicitHeight, rs.maxDetailH)
                    contentHeight: det.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    interactive: contentHeight > height

                    ColumnLayout {
                        id: det
                        width: detFlick.width
                        spacing: rs.px(10)
                        readonly property var d: rs.detail

                        // Header: back, title, mark
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: rs.px(8)
                            Rectangle {
                                Layout.preferredWidth: rs.px(28)
                                Layout.preferredHeight: rs.px(28)
                                radius: 8
                                color: backArea.containsMouse ? rs.tileColor("#2f3647") : rs.tileColor("#212532")
                                border.width: 1
                                border.color: rs.tileColor("#2c3242")
                                Text { anchors.centerIn: parent; text: "‹"; color: "#ffffff"; font.pixelSize: rs.px(17); font.bold: true }
                                MouseArea { id: backArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: rs.back() }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: det.d ? det.d.title : (rs.detailLoading ? "Loading…" : "")
                                color: "#ffffff"
                                font.pixelSize: rs.px(15)
                                font.bold: true
                                elide: Text.ElideRight
                            }
                            Text {
                                textFormat: Text.StyledText
                                text: "<b>R<font color='#34d399'>log</font></b>"
                                color: "#ffffff"
                                font.pixelSize: rs.px(12)
                            }
                        }

                        Text {
                            visible: !det.d && rs.detailError.length > 0
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            color: "#ff6b6b"
                            font.pixelSize: rs.px(12)
                            text: rs.detailError
                        }

                        MediaCarousel {
                            id: carousel
                            visible: !!det.d
                            Layout.fillWidth: true
                            Layout.preferredHeight: implicitHeight
                            fs: rs.fs
                            baseColor: rs.tileColor("#212532")
                            cover: rs.mediaCover
                            media: rs.mediaRest
                            onOpenRequested: (i) => theater.open(i)
                        }

                        // Status · platform · year · started
                        RowLayout {
                            visible: !!det.d
                            Layout.fillWidth: true
                            spacing: rs.px(7)
                            Rectangle { width: rs.px(7); height: width; radius: width / 2; color: rs.statusColor(det.d ? det.d.status : "") }
                            Text {
                                Layout.fillWidth: true
                                textFormat: Text.StyledText
                                wrapMode: Text.Wrap
                                color: rs.ink2
                                font.pixelSize: rs.px(12)
                                text: !det.d ? "" : rs.statusLabel(det.d.status) + "<font color='#6b7385'>"
                                      + (det.d.platform ? " · " + det.d.platform : "")
                                      + (det.d.release_year ? " · " + det.d.release_year : "")
                                      + (det.d.started_on ? " · started " + rs.fmtDate(det.d.started_on) : "") + "</font>"
                            }
                        }

                        // Hours
                        Rectangle {
                            visible: !!(det.d && (det.d.hours || det.d.played_h))
                            Layout.fillWidth: true
                            Layout.preferredHeight: hoursCol.implicitHeight + 2 * rs.px(10)
                            radius: 12
                            color: rs.tileColor("#212532")
                            ColumnLayout {
                                id: hoursCol
                                anchors.fill: parent
                                anchors.margins: rs.px(10)
                                spacing: rs.px(7)
                                readonly property real mainH: det.d && det.d.hours ? (det.d.hours.main || 0) : 0
                                readonly property real playedH: det.d ? (det.d.played_h || 0) : 0
                                readonly property real paceH: det.d && det.d.pace && mainH ? mainH * det.d.pace.ratio : 0
                                SectionLabel { text: "HOURS" }
                                Rectangle {
                                    visible: hoursCol.mainH > 0 && hoursCol.playedH > 0
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: rs.px(5)
                                    radius: height / 2
                                    color: rs.tileColor("#2a2f3d")
                                    Rectangle {
                                        height: parent.height; radius: parent.radius; color: rs.green
                                        width: hoursCol.mainH ? parent.width * Math.min(1, hoursCol.playedH / (hoursCol.paceH || hoursCol.mainH)) : 0
                                    }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        Layout.fillWidth: true
                                        textFormat: Text.StyledText
                                        color: rs.ink2
                                        font.pixelSize: rs.px(11)
                                        text: hoursCol.playedH ? "<b>" + rs.fmtHours(hoursCol.playedH) + "</b> played" : "<font color='#6b7385'>No played time (not on Steam)</font>"
                                    }
                                    Text {
                                        visible: hoursCol.paceH > 0
                                        textFormat: Text.StyledText
                                        color: rs.ink2
                                        font.pixelSize: rs.px(11)
                                        text: "at your pace <b>~" + rs.fmtHours(hoursCol.paceH) + "</b>" + (det.d && det.d.pace ? " (" + det.d.pace.ratio.toFixed(1) + "×)" : "")
                                    }
                                }
                                RowLayout {
                                    visible: !!(det.d && det.d.hours)
                                    Layout.fillWidth: true
                                    spacing: rs.px(6)
                                    Repeater {
                                        model: det.d && det.d.hours ? [["Main", det.d.hours.main, true], ["Main+", det.d.hours.extra, false], ["100%", det.d.hours.complete, false]] : []
                                        delegate: Rectangle {
                                            required property var modelData
                                            Layout.fillWidth: true
                                            Layout.preferredWidth: 1
                                            Layout.preferredHeight: tileCol.implicitHeight + rs.px(10)
                                            radius: 8
                                            color: rs.tileColor("#262b38")
                                            Rectangle { width: 3; height: parent.height - rs.px(10); y: rs.px(5); x: 0; radius: 1.5; color: modelData[2] ? rs.green : rs.mute }
                                            Column {
                                                id: tileCol
                                                x: rs.px(9)
                                                anchors.verticalCenter: parent.verticalCenter
                                                spacing: 1
                                                Text { text: modelData[0]; color: rs.mute; font.pixelSize: rs.px(10) }
                                                Text { text: modelData[1] ? "~" + rs.fmtHours(modelData[1]) : "--"; color: "#ffffff"; font.family: "monospace"; font.bold: true; font.pixelSize: rs.px(12) }
                                            }
                                        }
                                    }
                                }
                                Text {
                                    visible: !!(det.d && det.d.hours && det.d.hours.source !== "hltb")
                                    color: rs.mute
                                    font.pixelSize: rs.px(9)
                                    text: det.d && det.d.hours ? "Estimate from " + (det.d.hours.source === "igdb" ? "IGDB" : "your vault note") : ""
                                }
                            }
                        }

                        // Franchise in release order
                        Rectangle {
                            visible: !!(det.d && det.d.franchise)
                            Layout.fillWidth: true
                            Layout.preferredHeight: frCol.implicitHeight + 2 * rs.px(10)
                            radius: 12
                            color: rs.tileColor("#212532")
                            ColumnLayout {
                                id: frCol
                                anchors.fill: parent
                                anchors.margins: rs.px(10)
                                spacing: 0
                                SectionLabel {
                                    Layout.bottomMargin: rs.px(4)
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: det.d && det.d.franchise ? det.d.franchise.name.toUpperCase() + " · " + det.d.franchise.done + " OF " + det.d.franchise.total + " FINISHED" : ""
                                }
                                Repeater {
                                    model: det.d && det.d.franchise ? det.d.franchise.members : []
                                    delegate: Rectangle {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: rs.px(25)
                                        radius: 6
                                        color: memArea.containsMouse && !modelData.here ? rs.tileColor("#2a2f3d") : "transparent"
                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: rs.px(3)
                                            anchors.rightMargin: rs.px(3)
                                            spacing: rs.px(7)
                                            Item {
                                                Layout.preferredWidth: rs.px(12)
                                                Layout.fillHeight: true
                                                Text {
                                                    anchors.centerIn: parent
                                                    visible: modelData.status !== "playing"
                                                    text: modelData.status === "completed" ? "✓" : (modelData.status ? "○" : "·")
                                                    color: modelData.status === "completed" ? "#60a5fa" : rs.mute
                                                    font.pixelSize: rs.px(11)
                                                    font.bold: true
                                                }
                                                Rectangle {
                                                    anchors.centerIn: parent
                                                    visible: modelData.status === "playing"
                                                    width: rs.px(7); height: width; radius: width / 2; color: rs.green
                                                }
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                text: modelData.title
                                                elide: Text.ElideRight
                                                font.pixelSize: rs.px(12)
                                                font.bold: modelData.here
                                                color: modelData.here ? "#ffffff" : (modelData.status === "completed" ? rs.ink2 : (modelData.status ? "#ffffff" : rs.mute))
                                            }
                                            Rectangle {
                                                visible: modelData.here || modelData.next
                                                Layout.preferredWidth: tagText.implicitWidth + rs.px(10)
                                                Layout.preferredHeight: rs.px(16)
                                                radius: 4
                                                color: modelData.here ? Qt.rgba(0.20, 0.83, 0.60, 0.16) : Qt.rgba(1, 1, 1, 0.07)
                                                Text {
                                                    id: tagText
                                                    anchors.centerIn: parent
                                                    text: modelData.here ? "this" : "next"
                                                    color: modelData.here ? rs.green : rs.ink2
                                                    font.pixelSize: rs.px(9)
                                                    font.bold: true
                                                }
                                            }
                                            Text {
                                                text: modelData.year || ""
                                                color: rs.mute
                                                font.family: "monospace"
                                                font.pixelSize: rs.px(10)
                                            }
                                        }
                                        MouseArea {
                                            id: memArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            enabled: !modelData.here
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: rs.openDetail(modelData.item_id)
                                        }
                                    }
                                }
                            }
                        }

                        // Notes
                        Rectangle {
                            visible: !!(det.d && det.d.notes)
                            Layout.fillWidth: true
                            Layout.preferredHeight: notesCol.implicitHeight + 2 * rs.px(10)
                            radius: 12
                            color: rs.tileColor("#212532")
                            ColumnLayout {
                                id: notesCol
                                anchors.fill: parent
                                anchors.margins: rs.px(10)
                                spacing: rs.px(5)
                                SectionLabel { text: "YOUR NOTES" }
                                Text {
                                    Layout.fillWidth: true
                                    text: det.d ? det.d.notes : ""
                                    color: rs.ink2
                                    font.pixelSize: rs.px(12)
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 8
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        // Past finishes
                        Rectangle {
                            visible: !!(det.d && det.d.finishes.length)
                            Layout.fillWidth: true
                            Layout.preferredHeight: finCol.implicitHeight + 2 * rs.px(10)
                            radius: 12
                            color: rs.tileColor("#212532")
                            ColumnLayout {
                                id: finCol
                                anchors.fill: parent
                                anchors.margins: rs.px(10)
                                spacing: rs.px(5)
                                SectionLabel { text: "FINISHED" }
                                Repeater {
                                    model: det.d ? det.d.finishes : []
                                    delegate: ColumnLayout {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        spacing: 1
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text {
                                                Layout.fillWidth: true
                                                text: (modelData.completed_on ? rs.fmtDate(modelData.completed_on) : "Before RLog") + (modelData.platform ? " · " + modelData.platform : "")
                                                color: "#ffffff"
                                                font.pixelSize: rs.px(12)
                                            }
                                            Text {
                                                visible: !!modelData.rating
                                                text: "★".repeat(modelData.rating || 0)
                                                color: "#fbbf24"
                                                font.pixelSize: rs.px(11)
                                            }
                                        }
                                        Text {
                                            visible: !!modelData.note
                                            Layout.fillWidth: true
                                            text: modelData.note || ""
                                            color: rs.mute
                                            font.pixelSize: rs.px(11)
                                            wrapMode: Text.Wrap
                                        }
                                    }
                                }
                            }
                        }

                        // Open in RLog / Steam
                        RowLayout {
                            visible: !!det.d
                            Layout.fillWidth: true
                            spacing: rs.px(6)
                            Repeater {
                                model: det.d ? [["Open in RLog", det.d.link], ["Open in Steam", det.d.steam_appid ? "https://store.steampowered.com/app/" + det.d.steam_appid : ""]] : []
                                delegate: Rectangle {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 1
                                    Layout.preferredHeight: rs.px(32)
                                    radius: 10
                                    opacity: modelData[1] ? 1 : 0.4
                                    color: dBtnArea.containsMouse && modelData[1] ? rs.tileColor("#2f3647") : rs.tileColor("#212532")
                                    border.width: 1
                                    border.color: rs.tileColor("#2c3242")
                                    Text { anchors.centerIn: parent; text: modelData[0]; color: "#ffffff"; font.pixelSize: rs.px(12); font.bold: true }
                                    MouseArea {
                                        id: dBtnArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        enabled: !!modelData[1]
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: rs.openUrl(modelData[1])
                                    }
                                }
                            }
                        }
                    }
                }

                ColumnLayout {
                    id: col
                    visible: !rs.detailOpen
                    x: rs.pad
                    y: rs.pad
                    width: card.width - 2 * rs.pad
                    spacing: rs.px(10)

                    // Header: mark, finishes this year, freshness, close
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: rs.px(8)
                        Text {
                            textFormat: Text.StyledText
                            text: "<b>R<font color='#34d399'>log</font></b>"
                            color: "#ffffff"
                            font.pixelSize: rs.px(13)
                        }
                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignRight
                            elide: Text.ElideLeft
                            color: rs.error && rs.stale ? "#fbbf24" : rs.mute
                            font.family: "monospace"
                            font.pixelSize: rs.px(10)
                            text: rs.error && rs.stale ? "offline · last copy"
                                  : rs.summary ? rs.summary.finished_this_year + " finished in " + new Date().getFullYear() : ""
                        }
                        Text {
                            text: "✕"
                            color: closeArea.containsMouse ? "#ffffff" : rs.mute
                            font.pixelSize: rs.px(12)
                            MouseArea {
                                id: closeArea
                                anchors.fill: parent
                                anchors.margins: -6
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: rs.open_ = false
                            }
                        }
                    }

                    Text {
                        visible: !rs.summary
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        color: rs.error ? "#ff6b6b" : rs.mute
                        font.pixelSize: rs.px(12)
                        text: rs.error || "Loading RLog…"
                    }

                    // Top card: the picked (or most recently played) Playing game
                    Rectangle {
                        visible: !!rs.current
                        Layout.fillWidth: true
                        Layout.preferredHeight: topRow.implicitHeight + 2 * rs.px(10)
                        radius: 12
                        color: topArea.containsMouse ? rs.tileColor("#283041") : rs.tileColor("#212532")

                        RowLayout {
                            id: topRow
                            anchors.fill: parent
                            anchors.margins: rs.px(10)
                            spacing: rs.px(12)

                            Cover {
                                Layout.preferredWidth: rs.px(96)
                                Layout.preferredHeight: rs.px(128)
                                Layout.alignment: Qt.AlignTop
                                radius: rs.px(8)
                                src: rs.current ? (rs.current.cover || "") : ""
                                label: rs.current ? rs.current.title : ""
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: rs.px(5)
                                Text {
                                    Layout.fillWidth: true
                                    text: rs.current ? rs.current.title : ""
                                    color: "#ffffff"
                                    font.pixelSize: rs.px(16)
                                    font.bold: true
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 3
                                    elide: Text.ElideRight
                                }
                                RowLayout {
                                    spacing: rs.px(6)
                                    Dot {}
                                    Text {
                                        textFormat: Text.StyledText
                                        color: rs.ink2
                                        font.pixelSize: rs.px(11)
                                        text: "Playing" + (rs.current && rs.current.platform ? " <font color='#6b7385'>· " + rs.current.platform + "</font>" : "")
                                    }
                                }
                                Text {
                                    visible: text.length > 0
                                    Layout.fillWidth: true
                                    text: rs.franchiseLine(rs.current)
                                    color: rs.mute
                                    font.pixelSize: rs.px(11)
                                    wrapMode: Text.Wrap
                                }
                                // Hours played against main story
                                Rectangle {
                                    visible: !!(rs.current && rs.current.main_h)
                                    Layout.fillWidth: true
                                    Layout.topMargin: rs.px(3)
                                    Layout.preferredHeight: rs.px(5)
                                    radius: height / 2
                                    color: rs.tileColor("#2a2f3d")
                                    Rectangle {
                                        height: parent.height
                                        radius: parent.radius
                                        color: rs.green
                                        width: rs.current && rs.current.main_h ? parent.width * Math.min(1, (rs.current.played_h || 0) / rs.current.main_h) : 0
                                    }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        Layout.fillWidth: true
                                        color: rs.mute
                                        font.family: "monospace"
                                        font.pixelSize: rs.px(10)
                                        text: rs.current && rs.current.played_h ? rs.fmtHours(rs.current.played_h) + " played"
                                              : (rs.current && rs.current.last_played ? "" : "not on Steam")
                                    }
                                    Text {
                                        visible: !!(rs.current && rs.current.main_h)
                                        color: rs.mute
                                        font.family: "monospace"
                                        font.pixelSize: rs.px(10)
                                        text: rs.current ? "main ~" + rs.fmtHours(rs.current.main_h) : ""
                                    }
                                }
                            }
                        }
                        MouseArea {
                            id: topArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (rs.current) rs.openDetail(rs.current.item_id)
                        }
                    }

                    // Playing carousel: tap swaps the top card
                    SectionLabel {
                        visible: rs.playing.length > 1
                        text: "PLAYING · " + rs.playing.length
                    }
                    ListView {
                        id: strip
                        visible: rs.playing.length > 1
                        Layout.fillWidth: true
                        Layout.preferredHeight: rs.px(88) + rs.px(32)
                        orientation: ListView.Horizontal
                        spacing: rs.px(8)
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        model: rs.playing
                        delegate: Item {
                            required property var modelData
                            width: rs.px(66)
                            height: strip.height
                            Column {
                                anchors.fill: parent
                                anchors.topMargin: 2
                                spacing: rs.px(3)
                                Cover {
                                    width: rs.px(64); height: rs.px(86)
                                    x: 1
                                    src: modelData.cover || ""
                                    label: modelData.title
                                    selected: rs.current && rs.current.entry_id === modelData.entry_id
                                }
                                Text {
                                    width: parent.width
                                    text: modelData.title
                                    color: "#ffffff"
                                    font.pixelSize: rs.px(10)
                                    elide: Text.ElideRight
                                }
                                Text {
                                    width: parent.width
                                    text: rs.ago(modelData.last_played) || (modelData.platform || "")
                                    color: rs.mute
                                    font.family: "monospace"
                                    font.pixelSize: rs.px(9)
                                    elide: Text.ElideRight
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: rs.pinRequested(modelData.entry_id)
                            }
                        }
                    }

                    // Up next: compact rows, no covers
                    SectionLabel { text: "UP NEXT" }
                    Text {
                        visible: rs.summary && rs.upNext.length === 0
                        text: "Your queue is empty."
                        color: rs.mute
                        font.pixelSize: rs.px(11)
                    }
                    ColumnLayout {
                        visible: rs.upNext.length > 0
                        Layout.fillWidth: true
                        Layout.topMargin: -rs.px(6)
                        spacing: 0
                        Repeater {
                            model: rs.upNext
                            delegate: Rectangle {
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                Layout.preferredHeight: rs.px(26)
                                radius: 6
                                color: upArea.containsMouse ? rs.tileColor("#212532") : "transparent"
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: rs.px(4)
                                    anchors.rightMargin: rs.px(4)
                                    spacing: rs.px(8)
                                    Text {
                                        text: index + 1
                                        color: rs.mute
                                        font.family: "monospace"
                                        font.pixelSize: rs.px(10)
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        textFormat: Text.StyledText
                                        elide: Text.ElideRight
                                        color: "#ffffff"
                                        font.pixelSize: rs.px(12)
                                        text: modelData.title + (modelData.platform ? " <font color='#6b7385'>· " + modelData.platform + "</font>" : "")
                                    }
                                    Text {
                                        text: modelData.main_h ? "~" + rs.fmtHours(modelData.main_h) : ""
                                        color: rs.ink2
                                        font.family: "monospace"
                                        font.pixelSize: rs.px(10)
                                    }
                                }
                                MouseArea {
                                    id: upArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: rs.openDetail(modelData.item_id)
                                }
                            }
                        }
                    }

                    // Open the app
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: rs.px(2)
                        spacing: rs.px(6)
                        Repeater {
                            model: [["Queue", "/#/queue?m=game"], ["Open RLog", "/#/home?m=game"]]
                            delegate: Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredHeight: rs.px(32)
                                radius: 10
                                color: btnArea.containsMouse ? rs.tileColor("#2f3647") : rs.tileColor("#212532")
                                border.width: 1
                                border.color: rs.tileColor("#2c3242")
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData[0]
                                    color: "#ffffff"
                                    font.pixelSize: rs.px(12)
                                    font.bold: true
                                }
                                MouseArea {
                                    id: btnArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: rs.openUrl(rs.appUrl + modelData[1])
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
