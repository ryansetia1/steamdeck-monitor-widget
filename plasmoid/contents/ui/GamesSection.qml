import QtQuick
import QtQuick.Layouts
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami

// Game search row for the Deck Monitor card: steamAF on the left, HowLongToBeat on the right.
// Results open in a floating "island" window under the whole card (PlasmaCore.Dialog, Tooltip
// type, so it never steals keyboard focus) and float above other widgets.
// Data comes from the monitor daemon: GET http://127.0.0.1:19842/games/...
Item {
    id: gs

    // ── Inputs ──────────────────────────────────────────────────────────────
    property Item anchorItem: parent      // island is placed under, and as wide as, this item
    property bool glassMode: false
    property real glassOpacity: 0.55
    property string currency: "USD"
    property bool showMainStory: false
    property int islandStyle: 0           // 0 auto (readable), 1 same as card, 2 custom opacity
    property real islandOpacity: 0.94
    signal configureRequested()

    // Size scale (Deck Monitor's font size setting). Every pixel size below goes through px().
    property real fs: 1
    function px(n) { return Math.round(n * fs); }

    implicitHeight: gs.px(34)

    readonly property string api: "http://127.0.0.1:19842/games/"
    readonly property int pad: px(8)
    readonly property int gap: px(6)
    readonly property int rowH: px(58)          // steamAF result row
    readonly property int hlRowH: px(78)        // HowLongToBeat result row
    readonly property int rowGap: px(6)
    readonly property int maxRows: 10

    // ── Look ────────────────────────────────────────────────────────────────
    function tileColor(solid) {
        return gs.glassMode ? Qt.rgba(1, 1, 1, 0.08) : solid;
    }
    readonly property color cardColor: glassMode ? Qt.rgba(0.09, 0.10, 0.14, glassOpacity) : "#161820"
    readonly property color cardBorder: glassMode ? Qt.rgba(1, 1, 1, 0.22) : "#262a36"
    readonly property color islandColor: {
        switch (islandStyle) {
        case 1: return cardColor;
        case 2: return Qt.rgba(0.09, 0.10, 0.14, islandOpacity);
        default: return glassMode ? Qt.rgba(0.09, 0.10, 0.14, Math.max(glassOpacity, 0.94)) : "#161820";
        }
    }

    // Verdict look (matches steamAF's dealTone)
    function verdictColor(state) {
        switch (state) {
        case "worth-it": return "#34d399";
        case "good-deal": return "#5eead4";
        case "no-rush": return "#66c0f4";
        case "wait": return "#fbbf24";
        default: return "#94a3b8";
        }
    }
    function verdictLabel(state) {
        switch (state) {
        case "worth-it": return "Worth it";
        case "good-deal": return "Good deal";
        case "no-rush": return "No rush";
        case "wait": return "Wait";
        case "free": return "Free";
        case "coming-soon": return "Coming soon";
        case "no-history": return "No history";
        default: return "";
        }
    }
    function verdictText(d) {
        switch (d.state) {
        case "worth-it": return "One of the best prices in 2 years. This is the time to buy.";
        case "good-deal": return "Below the usual sale of " + d.typical + ".";
        case "no-rush": return "The usual sale is around " + d.typical + ".";
        case "wait": return "The 2-year low is " + d.lowest + ".";
        case "no-history": return "No 2-year history yet. No verdict for now.";
        case "free": return "Free to play.";
        case "coming-soon": return "Not released yet.";
        case "unavailable": case "no-price": return "No price data available.";
        default: return "Price data is still loading. Try again in a moment.";
        }
    }
    function fmtHours(h) {
        if (!h || h <= 0) return "--";
        var whole = Math.floor(h);
        return (whole > 0 ? whole : "") + (h - whole >= 0.5 ? "½" : "") + "h";
    }

    // ── Daemon requests ─────────────────────────────────────────────────────
    function getJson(path, params, cb) {
        var qs = Object.keys(params).map(k => k + "=" + encodeURIComponent(params[k])).join("&");
        var xhr = new XMLHttpRequest();
        xhr.open("GET", gs.api + path + "?" + qs);
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            var r;
            try { r = JSON.parse(xhr.responseText); }
            catch (e) { r = { ok: false, error: xhr.status ? "Search failed (HTTP " + xhr.status + ")" : "Monitor daemon is not reachable" }; }
            cb(r);
        };
        xhr.send();
    }

    // ── HowLongToBeat state ─────────────────────────────────────────────────
    property var hlResults: []
    property bool hlLoading: false
    property string hlError: ""
    property string hlLastQuery: ""
    property int hlReq: 0
    readonly property bool hlStatusShown: hlResults.length === 0 && (hlLoading || hlError.length > 0 || hlLastQuery.length >= 2)

    function hlSearch(text) {
        text = text.trim();
        if (text === hlLastQuery && !hlError) return;
        hlLastQuery = text;
        var id = ++hlReq;
        if (text.length < 2) { hlResults = []; hlError = ""; hlLoading = false; return; }
        hlLoading = true;
        hlError = "";
        getJson("hltb", { q: text }, r => {
            if (id !== gs.hlReq) return;      // a newer search is running
            gs.hlLoading = false;
            if (r.ok) gs.hlResults = r.results;
            else { gs.hlError = r.error; gs.hlResults = []; }
        });
    }

    // ── steamAF state ───────────────────────────────────────────────────────
    property var afResults: []
    property bool afLoading: false
    property string afError: ""
    property string afLastQuery: ""
    property int afReq: 0
    readonly property bool afStatusShown: !detail && afResults.length === 0 && (afLoading || afError.length > 0 || afLastQuery.length >= 2)

    property var detail: null            // {id, name} of the open game, plus data once loaded
    property bool detailLoading: false
    property string detailError: ""
    property int detailReq: 0

    property var mainHours: ({})         // appId -> Main Story hours (0 = no HLTB entry)

    function afSearch(text) {
        text = text.trim();
        if (text === afLastQuery && !afError) return;
        afLastQuery = text;
        var id = ++afReq;
        if (text.length < 2) { afResults = []; afError = ""; afLoading = false; return; }
        afLoading = true;
        afError = "";
        getJson("steamaf/search", { q: text, currency: gs.currency }, r => {
            if (id !== gs.afReq) return;
            gs.afLoading = false;
            if (r.ok) { gs.afResults = r.results; gs.fetchMainHours(); }
            else { gs.afError = r.error; gs.afResults = []; }
        });
    }

    function openDetail(id, name) {
        detail = { id: id, name: name };
        detailError = "";
        detailLoading = true;
        var rq = ++detailReq;
        getJson("steamaf/detail", { appId: id, currency: gs.currency, title: name }, r => {
            if (rq !== gs.detailReq) return;
            gs.detailLoading = false;
            if (r.ok) {
                r.name = name;
                gs.detail = r;
                if (r.hltb) { var one = {}; one[r.id] = r.hltb.main; gs.mergeMainHours(one); }
            } else {
                gs.detailError = r.error;
            }
        });
    }

    function closeDetail() {
        detail = null; detailLoading = false; detailError = ""; detailReq++;
    }

    function fetchMainHours() {
        if (!showMainStory || afResults.length === 0) return;
        var pairs = afResults.filter(r => mainHours[r.id] === undefined).map(r => [r.id, r.name]);
        if (pairs.length === 0) return;
        getJson("steamaf/hours", { pairs: JSON.stringify(pairs) }, r => { if (r.ok) gs.mergeMainHours(r.hours); });
    }

    function mergeMainHours(map) {
        var m = Object.assign({}, mainHours);
        for (var k in map) m[k] = map[k];
        mainHours = m;
    }

    onShowMainStoryChanged: fetchMainHours()
    onCurrencyChanged: {
        if (detail) openDetail(detail.id, detail.name);
        afLastQuery = "";
        afSearch(afField.text);
    }

    // ── Island state ────────────────────────────────────────────────────────
    readonly property string activeSide: afField.focused ? "af" : (hlField.focused ? "hl" : "")
    readonly property bool afHasContent: !!detail || afResults.length > 0 || afStatusShown
    readonly property bool hlHasContent: hlResults.length > 0 || hlStatusShown
    // Open while the focused field has something to show. Clicking elsewhere drops focus and
    // closes it; results are kept, so focusing the field again brings the island back.
    readonly property bool islandOpen: (activeSide === "af" && afHasContent) || (activeSide === "hl" && hlHasContent)
    property string shownSide: "af"       // keeps the last side so the island doesn't collapse mid-close
    onActiveSideChanged: if (activeSide) shownSide = activeSide
    onIslandOpenChanged: { if (islandOpen) island.place(); else theater.close(); }
    onDetailChanged: if (!detail) theater.close()
    readonly property rect screenRect: Qt.rect(Screen.virtualX, Screen.virtualY, Screen.width, Screen.height)
    // Bottom of the usable area: above the taskbar when the containment reports it, else the screen edge
    // (same rule as the RLog island). The result lists show only the rows that fit above it.
    property rect availableRect: Qt.rect(0, 0, 0, 0)    // screen-local, from Plasmoid.containment
    readonly property real usableBottom: availableRect.height > 0 ? screenRect.y + availableRect.y + availableRect.height
                                                                  : screenRect.y + screenRect.height - px(48)
    property int islandTop: 0
    // Room for a list: below the island's top, minus its padding, the header line and a small margin.
    readonly property real listRoom: usableBottom - islandTop - gap - 2 * pad - px(20) - pad - px(8)
    function rowsThatFit(h) {
        return Math.max(2, Math.min(maxRows, Math.floor((listRoom + rowGap) / (h + rowGap))));
    }

    // ── Theater: full-screen cover / trailers / screenshots of the open steamAF game ──
    MediaTheater {
        id: theater
        items: carousel.items
        title: gs.detail ? (gs.detail.name || "") : ""
        appId: gs.detail ? String(gs.detail.id) : ""
        screenRect: gs.screenRect
        onIndexPicked: (i) => carousel.currentIndex = i
    }

    // ── Search field ────────────────────────────────────────────────────────
    component SearchField: Rectangle {
        id: field
        property string placeholder: ""
        property bool busy: false
        property alias text: input.text
        readonly property bool focused: input.activeFocus
        signal edited()
        signal submitted()
        signal escapePressed()
        signal moveList(int dy)
        property bool arrowsTaken: false  // ←/→ go to arrow() instead of the text cursor
        signal arrow(int dir)

        function clear() { input.text = ""; }
        function unfocus() { input.focus = false; }

        radius: 10
        color: gs.tileColor("#212532")
        border.color: input.activeFocus ? "#53B7FF" : gs.tileColor("#2c3242")
        border.width: 1

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 9
            anchors.rightMargin: 8
            spacing: 6

            Kirigami.Icon {
                id: icon
                source: field.busy ? "view-refresh" : "search"
                Layout.preferredWidth: gs.px(14)
                Layout.preferredHeight: gs.px(14)
                opacity: 0.7
                RotationAnimation on rotation {
                    running: field.busy
                    from: 0; to: 360; duration: 900
                    loops: Animation.Infinite
                    onStopped: icon.rotation = 0
                }
            }

            TextInput {
                id: input
                Layout.fillWidth: true
                color: "#ffffff"
                selectionColor: "#53B7FF"
                font.pixelSize: gs.px(12)
                clip: true
                verticalAlignment: TextInput.AlignVCenter
                onTextChanged: field.edited()
                onAccepted: field.submitted()
                Keys.onEscapePressed: field.escapePressed()
                Keys.onDownPressed: field.moveList(-800)
                Keys.onUpPressed: field.moveList(800)
                Keys.onLeftPressed: (e) => { if (field.arrowsTaken) field.arrow(-1); else e.accepted = false; }
                Keys.onRightPressed: (e) => { if (field.arrowsTaken) field.arrow(1); else e.accepted = false; }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    visible: !input.text
                    textFormat: Text.StyledText
                    text: field.placeholder
                    color: "#6b7385"
                    font.pixelSize: gs.px(12)
                    elide: Text.ElideRight
                }
            }

            // Clear button: an × inside a filled circle
            Rectangle {
                visible: input.text.length > 0
                Layout.preferredWidth: gs.px(15)
                Layout.preferredHeight: gs.px(15)
                radius: width / 2
                color: clearArea.containsMouse ? "#cfd8dc" : "#6b7385"
                Behavior on color { ColorAnimation { duration: 100 } }
                Repeater {
                    model: [45, -45]
                    Rectangle {
                        required property int modelData
                        anchors.centerIn: parent
                        width: gs.px(7); height: gs.px(1.5); radius: 0.75
                        rotation: modelData
                        color: "#161820"
                        antialiasing: true
                    }
                }
                MouseArea {
                    id: clearArea
                    anchors.fill: parent
                    anchors.margins: -4
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { input.text = ""; field.escapePressed(); input.forceActiveFocus(); }
                }
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 7

        SearchField {
            id: afField
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.fillHeight: true
            placeholder: "<b>steam<font color='#53B7FF'>AF</font></b>…"
            busy: gs.afLoading || gs.detailLoading
            onEdited: afDebounce.restart()
            onSubmitted: { afDebounce.stop(); gs.closeDetail(); gs.afSearch(text); }
            arrowsTaken: theater.shown
            onArrow: (d) => theater.step(d)
            onEscapePressed: {
                if (theater.shown) theater.close();
                else if (gs.detail) gs.closeDetail();
                else if (text) clear();
                else unfocus();
            }
            onMoveList: (dy) => afList.flick(0, dy)
        }

        SearchField {
            id: hlField
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.fillHeight: true
            placeholder: "HowLongToBeat…"
            busy: gs.hlLoading
            onEdited: hlDebounce.restart()
            onSubmitted: { hlDebounce.stop(); gs.hlSearch(text); }
            onEscapePressed: {
                if (text) clear();
                else unfocus();
            }
            onMoveList: (dy) => hlList.flick(0, dy)
        }
    }

    Timer {
        id: afDebounce
        interval: 500
        onTriggered: { gs.closeDetail(); gs.afSearch(afField.text); }
    }
    Timer {
        id: hlDebounce
        interval: 450
        onTriggered: gs.hlSearch(hlField.text)
    }

    // ── Island ──────────────────────────────────────────────────────────────
    PlasmaCore.Dialog {
        id: island
        // Positioned by hand right under the card (automatic visualParent placement can flip
        // the island above the widget when it thinks space is short).
        location: PlasmaCore.Types.Floating
        type: PlasmaCore.Dialog.Tooltip
        backgroundHints: PlasmaCore.Dialog.NoBackground
        flags: Qt.WindowStaysOnTopHint | Qt.WindowDoesNotAcceptFocus
        visible: gs.islandOpen
        onVisibleChanged: if (visible) place()

        function place() {
            var a = gs.anchorItem;
            var p = a.mapToGlobal(0, a.height);
            island.x = Math.round(p.x);
            island.y = Math.round(p.y);
            gs.islandTop = Math.round(p.y);
        }

        mainItem: Item {
            width: gs.anchorItem ? gs.anchorItem.width : 320
            height: gs.gap + islandCard.height

            Rectangle {
                id: islandCard
                y: gs.gap
                width: parent.width
                height: (gs.shownSide === "hl" ? hlColumn.implicitHeight : afColumn.implicitHeight) + 2 * gs.pad
                clip: true
                color: gs.islandColor
                radius: 16
                border.color: gs.cardBorder
                border.width: 1

                // Drop-in: fade + slide each time the island opens
                opacity: 0
                transform: Translate { id: slide; y: -8 }
                states: State {
                    name: "open"; when: gs.islandOpen
                    PropertyChanges { islandCard.opacity: 1; slide.y: 0 }
                }
                transitions: Transition {
                    to: "open"
                    NumberAnimation { properties: "opacity,y"; duration: 160; easing.type: Easing.OutCubic }
                }

                // ── steamAF: results list / game detail ──
                Column {
                    id: afColumn
                    visible: gs.shownSide === "af"
                    x: gs.pad
                    y: gs.pad
                    width: islandCard.width - 2 * gs.pad
                    spacing: gs.pad

                    // Source + currency chip (opens the widget settings)
                    RowLayout {
                        width: parent.width
                        height: gs.px(20)
                        visible: !gs.detail
                        Text {
                            Layout.leftMargin: 2
                            textFormat: Text.StyledText
                            text: "<b>steam<font color='#53B7FF'>AF</font></b> <font color='#6b7385'>· buy verdicts</font>"
                            color: "#cfd8dc"
                            font.pixelSize: gs.px(11)
                        }
                        Item { Layout.fillWidth: true }
                        Rectangle {
                            Layout.preferredHeight: gs.px(20)
                            Layout.preferredWidth: curText.implicitWidth + 14
                            radius: 6
                            color: curArea.containsMouse ? gs.tileColor("#2f3647") : "transparent"
                            border.color: gs.tileColor("#2c3242")
                            border.width: 1
                            Text {
                                id: curText
                                anchors.centerIn: parent
                                text: gs.currency
                                color: "#90a4ae"
                                font.pixelSize: gs.px(10)
                                font.bold: true
                            }
                            MouseArea {
                                id: curArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: gs.configureRequested()
                            }
                        }
                    }

                    // ── Status line (list mode) ──
                    Text {
                        id: statusLine
                        readonly property bool shown: !gs.detail && gs.afResults.length === 0
                            && (gs.afLoading || gs.afError.length > 0 || gs.afLastQuery.length >= 2)
                        visible: shown
                        width: parent.width
                        height: gs.px(28)
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                        color: gs.afError ? "#ff6b6b" : "#6b7385"
                        font.pixelSize: gs.px(12)
                        text: gs.afLoading ? "Searching…" : (gs.afError || "No games found")
                    }

                    // ── Results list ──
                    ListView {
                        id: afList
                        readonly property int shownRows: Math.min(gs.afResults.length, gs.rowsThatFit(gs.rowH))
                        visible: !gs.detail && gs.afResults.length > 0
                        width: parent.width
                        height: visible ? shownRows * gs.rowH + Math.max(0, shownRows - 1) * gs.rowGap : 0
                        model: gs.afResults
                        spacing: gs.rowGap
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        opacity: gs.afLoading ? 0.5 : 1
                        Behavior on opacity { NumberAnimation { duration: 120 } }

                        delegate: Rectangle {
                            id: row
                            required property var modelData
                            width: ListView.view.width
                            height: gs.rowH
                            radius: 10
                            color: rowArea.containsMouse ? (gs.glassMode ? Qt.rgba(1, 1, 1, 0.14) : "#283041") : gs.tileColor("#212532")

                            MouseArea {
                                id: rowArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: gs.openDetail(row.modelData.id, row.modelData.name)
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 10

                                Kirigami.ShadowedImage {
                                    Layout.preferredWidth: gs.px(100)
                                    Layout.preferredHeight: gs.px(38)
                                    radius: 5
                                    color: gs.tileColor("#2a2f3d")
                                    source: row.modelData.thumb
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4

                                    Text {
                                        Layout.fillWidth: true
                                        text: row.modelData.name
                                        color: "#ffffff"
                                        font.pixelSize: gs.px(12)
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6
                                        Text {
                                            text: row.modelData.price || "—"
                                            color: row.modelData.state ? gs.verdictColor(row.modelData.state) : "#cfd8dc"
                                            font.pixelSize: gs.px(11)
                                            font.bold: true
                                        }
                                        Rectangle {
                                            visible: row.modelData.discount > 0
                                            Layout.preferredHeight: gs.px(15)
                                            Layout.preferredWidth: discText.implicitWidth + 8
                                            radius: 4
                                            color: Qt.rgba(0.20, 0.83, 0.60, 0.2)
                                            Text {
                                                id: discText
                                                anchors.centerIn: parent
                                                text: "-" + row.modelData.discount + "%"
                                                color: "#8bd0b7"
                                                font.pixelSize: gs.px(9)
                                                font.bold: true
                                            }
                                        }
                                        // Main Story hours (optional, HLTB)
                                        Row {
                                            readonly property real hours: gs.mainHours[row.modelData.id] || 0
                                            visible: gs.showMainStory && hours > 0
                                            spacing: 4
                                            Rectangle {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: gs.px(3); height: gs.px(10); radius: 1.5
                                                color: "#f87171"
                                            }
                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: gs.fmtHours(parent.hours)
                                                color: "#cfd8dc"
                                                font.pixelSize: gs.px(10)
                                                font.bold: true
                                            }
                                        }
                                        Item { Layout.fillWidth: true }
                                        VerdictBadge { verdict: row.modelData.state; small: true; fs: gs.fs }
                                    }
                                }
                            }
                        }
                    }

                    // ── Detail view ──
                    Column {
                        id: detailView
                        visible: !!gs.detail
                        width: parent.width
                        spacing: gs.pad

                        // Title row with back button
                        RowLayout {
                            width: parent.width
                            spacing: 8

                            Rectangle {
                                Layout.preferredWidth: gs.px(26)
                                Layout.preferredHeight: gs.px(26)
                                radius: 13
                                color: backArea.containsMouse ? gs.tileColor("#2f3647") : gs.tileColor("#212532")
                                Text {
                                    anchors.centerIn: parent
                                    anchors.horizontalCenterOffset: -1
                                    text: "‹"
                                    color: "#cfd8dc"
                                    font.pixelSize: gs.px(18)
                                    font.bold: true
                                }
                                MouseArea {
                                    id: backArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: gs.closeDetail()
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: gs.detail ? gs.detail.name : ""
                                color: "#ffffff"
                                font.pixelSize: gs.px(13)
                                font.bold: true
                                elide: Text.ElideRight
                            }
                            VerdictBadge {
                                fs: gs.fs
                                verdict: gs.detail && !gs.detailLoading ? (gs.detail.state || "") : ""
                            }
                        }

                        // Cover first, then trailers + screenshots; click opens the theater
                        MediaCarousel {
                            id: carousel
                            width: parent.width
                            height: implicitHeight
                            fs: gs.fs
                            baseColor: gs.tileColor("#212532")
                            cover: gs.detail ? (gs.detail.image
                                || "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/" + gs.detail.id + "/header.jpg") : ""
                            media: gs.detail && gs.detail.media ? gs.detail.media : []
                            onOpenRequested: (i) => theater.open(i)
                        }

                        // Loading / error
                        Text {
                            visible: gs.detailLoading || gs.detailError.length > 0
                            width: parent.width
                            height: gs.px(40)
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            color: gs.detailError ? "#ff6b6b" : "#6b7385"
                            font.pixelSize: gs.px(12)
                            text: gs.detailError || "Checking prices…"
                        }

                        // Price block
                        Rectangle {
                            id: priceTile
                            readonly property bool ready: !!gs.detail && !gs.detailLoading && !gs.detailError && gs.detail.state !== undefined
                            readonly property color tone: ready ? gs.verdictColor(gs.detail.state) : "#cfd8dc"
                            visible: ready
                            width: parent.width
                            height: priceCol.implicitHeight + 20
                            radius: 10
                            color: gs.tileColor("#212532")

                            Column {
                                id: priceCol
                                x: 10; y: 10
                                width: parent.width - 20
                                spacing: 8

                                RowLayout {
                                    width: parent.width
                                    spacing: 8
                                    Text {
                                        text: priceTile.ready ? (gs.detail.current || gs.verdictLabel(gs.detail.state) || "—") : ""
                                        color: priceTile.tone
                                        font.pixelSize: gs.px(20)
                                        font.bold: true
                                    }
                                    Rectangle {
                                        visible: priceTile.ready && gs.detail.discount > 0
                                        Layout.preferredHeight: gs.px(18)
                                        Layout.preferredWidth: dText.implicitWidth + 10
                                        radius: 5
                                        color: Qt.rgba(0.20, 0.83, 0.60, 0.2)
                                        Text {
                                            id: dText
                                            anchors.centerIn: parent
                                            text: priceTile.ready ? "-" + gs.detail.discount + "%" : ""
                                            color: "#8bd0b7"
                                            font.pixelSize: gs.px(11)
                                            font.bold: true
                                        }
                                    }
                                    Text {
                                        visible: priceTile.ready && gs.detail.discount > 0 && !!gs.detail.original
                                        text: priceTile.ready ? (gs.detail.original || "") : ""
                                        color: "#6b7385"
                                        font.pixelSize: gs.px(11)
                                        font.strikeout: true
                                    }
                                    Item { Layout.fillWidth: true }
                                }

                                Text {
                                    width: parent.width
                                    wrapMode: Text.WordWrap
                                    text: priceTile.ready ? gs.verdictText(gs.detail) : ""
                                    color: "#cfd8dc"
                                    font.pixelSize: gs.px(11)
                                }

                                Text {
                                    visible: priceTile.ready && !!gs.detail.sale
                                    text: priceTile.ready ? ("⏱ " + (gs.detail.sale || "")) : ""
                                    color: "#fbbf24"
                                    font.pixelSize: gs.px(11)
                                    font.bold: true
                                }

                                // 2-year low / usual sale
                                RowLayout {
                                    visible: priceTile.ready && (!!gs.detail.lowest || !!gs.detail.typical)
                                    width: parent.width
                                    spacing: 6
                                    Repeater {
                                        model: priceTile.ready ? [
                                            { label: "2-YEAR LOW", value: gs.detail.lowest },
                                            { label: "USUAL SALE", value: gs.detail.typical }
                                        ] : []
                                        delegate: Rectangle {
                                            required property var modelData
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: gs.px(36)
                                            radius: 7
                                            color: gs.glassMode ? Qt.rgba(0, 0, 0, 0.22) : "#1a1d27"
                                            Column {
                                                anchors.left: parent.left
                                                anchors.leftMargin: 9
                                                anchors.verticalCenter: parent.verticalCenter
                                                Text { text: modelData.label; color: "#90a4ae"; font.pixelSize: gs.px(9); font.bold: true }
                                                Text { text: modelData.value || "—"; color: "#ffffff"; font.pixelSize: gs.px(12); font.bold: true }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // HowLongToBeat
                        Rectangle {
                            visible: priceTile.ready && !!gs.detail.hltb
                            width: parent.width
                            height: gs.px(62)
                            radius: 10
                            color: gs.tileColor("#212532")

                            Column {
                                x: 10; y: 8
                                width: parent.width - 20
                                spacing: 5
                                Text { text: "HOWLONGTOBEAT"; color: "#90a4ae"; font.pixelSize: gs.px(9); font.bold: true }
                                RowLayout {
                                    width: parent.width
                                    spacing: 6
                                    Repeater {
                                        model: priceTile.ready && gs.detail.hltb ? [
                                            { label: "Main", value: gs.detail.hltb.main, accent: "#f87171" },
                                            { label: "Main+", value: gs.detail.hltb.plus, accent: "#64748b" },
                                            { label: "100%", value: gs.detail.hltb.full, accent: "#64748b" }
                                        ] : []
                                        delegate: Rectangle {
                                            required property var modelData
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: gs.px(28)
                                            radius: 6
                                            color: gs.glassMode ? Qt.rgba(0, 0, 0, 0.22) : "#1a1d27"
                                            Rectangle {
                                                width: gs.px(3); height: parent.height - 12; radius: 1.5
                                                anchors.left: parent.left
                                                anchors.leftMargin: 6
                                                anchors.verticalCenter: parent.verticalCenter
                                                color: modelData.accent
                                            }
                                            Text {
                                                anchors.left: parent.left
                                                anchors.leftMargin: 14
                                                anchors.verticalCenter: parent.verticalCenter
                                                textFormat: Text.StyledText
                                                text: "<font color='#90a4ae'>" + modelData.label + "</font>  <b>" + gs.fmtHours(modelData.value) + "</b>"
                                                color: "#ffffff"
                                                font.pixelSize: gs.px(11)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Links
                        RowLayout {
                            visible: !!gs.detail
                            width: parent.width
                            spacing: 6
                            Repeater {
                                model: gs.detail ? [
                                    { label: "Open in Steam", icon: "steam", url: "https://store.steampowered.com/app/" + gs.detail.id },
                                    { label: "Open steamAF", icon: Qt.resolvedUrl("../icons/steamaf.png"), url: "https://steamaf.vercel.app/game/" + gs.detail.id }
                                ] : []
                                delegate: Rectangle {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: gs.px(30)
                                    radius: 8
                                    color: linkArea.containsMouse ? gs.tileColor("#2f3647") : gs.tileColor("#212532")
                                    border.color: gs.tileColor("#2c3242")
                                    border.width: 1
                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 6
                                        Kirigami.Icon {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: gs.px(16)
                                            height: gs.px(16)
                                            source: modelData.icon
                                        }
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: modelData.label
                                            color: "#cfd8dc"
                                            font.pixelSize: gs.px(11)
                                            font.bold: true
                                        }
                                    }
                                    MouseArea {
                                        id: linkArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Qt.openUrlExternally(modelData.url)
                                    }
                                }
                            }
                        }
                    }
                }

                // ── HowLongToBeat: results list ──
                Column {
                    id: hlColumn
                    visible: gs.shownSide === "hl"
                    x: gs.pad
                    y: gs.pad
                    width: islandCard.width - 2 * gs.pad
                    spacing: gs.pad

                    Text {
                        visible: gs.hlStatusShown
                        width: parent.width
                        height: gs.px(28)
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                        color: gs.hlError ? "#ff6b6b" : "#6b7385"
                        font.pixelSize: gs.px(12)
                        text: gs.hlLoading ? "Searching…" : (gs.hlError || "No games found")
                    }

                    ListView {
                        id: hlList
                        readonly property int shownRows: Math.min(gs.hlResults.length, gs.rowsThatFit(gs.hlRowH))
                        visible: gs.hlResults.length > 0
                        width: parent.width
                        height: visible ? shownRows * gs.hlRowH + Math.max(0, shownRows - 1) * gs.rowGap : 0
                        model: gs.hlResults
                        spacing: gs.rowGap
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        opacity: gs.hlLoading ? 0.5 : 1
                        onModelChanged: positionViewAtBeginning()
                        Behavior on opacity { NumberAnimation { duration: 120 } }

                        delegate: Rectangle {
                            id: row
                            required property var modelData
                            width: ListView.view.width
                            height: gs.px(78)
                            radius: 10
                            color: rowArea.containsMouse ? (gs.glassMode ? Qt.rgba(1, 1, 1, 0.14) : "#283041") : gs.tileColor("#212532")

                            MouseArea {
                                id: rowArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Qt.openUrlExternally("https://howlongtobeat.com/game/" + row.modelData.id)
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 10

                                Kirigami.ShadowedImage {
                                    Layout.preferredWidth: gs.px(46)
                                    Layout.preferredHeight: gs.px(62)
                                    radius: 6
                                    color: gs.tileColor("#2a2f3d")
                                    source: row.modelData.image
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6
                                        Text {
                                            Layout.fillWidth: true
                                            text: row.modelData.name
                                            color: "#ffffff"
                                            font.pixelSize: gs.px(13)
                                            font.bold: true
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            visible: !!row.modelData.year
                                            text: row.modelData.year
                                            color: "#78909c"
                                            font.pixelSize: gs.px(11)
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6
                                        Repeater {
                                            model: [
                                                { label: "Main", value: row.modelData.main, accent: "#f87171" },
                                                { label: "Main+", value: row.modelData.plus, accent: "#64748b" },
                                                { label: "100%", value: row.modelData.full, accent: "#64748b" }
                                            ]
                                            delegate: Rectangle {
                                                required property var modelData
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: gs.px(34)
                                                radius: 7
                                                color: gs.glassMode ? Qt.rgba(0, 0, 0, 0.22) : "#1a1d27"
                                                Rectangle {
                                                    width: gs.px(3)
                                                    height: parent.height - 14
                                                    radius: 1.5
                                                    anchors.left: parent.left
                                                    anchors.leftMargin: 6
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    color: modelData.accent
                                                }
                                                Column {
                                                    anchors.left: parent.left
                                                    anchors.leftMargin: 14
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    spacing: 0
                                                    Text {
                                                        text: modelData.label
                                                        color: "#90a4ae"
                                                        font.pixelSize: gs.px(9)
                                                        font.bold: true
                                                    }
                                                    Text {
                                                        text: gs.fmtHours(modelData.value)
                                                        color: modelData.value > 0 ? "#ffffff" : "#5c6475"
                                                        font.pixelSize: gs.px(13)
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
    }
}
