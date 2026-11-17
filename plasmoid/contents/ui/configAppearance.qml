import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kcmutils as KCMUtils
import org.kde.kirigami as Kirigami

KCMUtils.SimpleKCM {
    id: appearancePage

    property alias cfg_fontSizeScale: fontSizeSlider.value
    property alias cfg_backgroundStyle: styleBox.currentIndex
    property alias cfg_glassOpacity: opacitySlider.value
    // Both keys are driven by the single "On external monitors" choice below
    property bool cfg_showOnExternal
    property bool cfg_autoScreenMigrate

    // Called by Plasma on Apply/OK: publish the shared choice to every widget via the daemon
    function saveConfig() {
        var xhr = new XMLHttpRequest();
        xhr.open("POST", "http://127.0.0.1:19842/prefs");
        xhr.setRequestHeader("Content-Type", "application/json");
        xhr.send(JSON.stringify({ external_mode: externalModeBox.currentIndex }));
    }
    property alias cfg_deckFullscreen: deckFullscreenCheck.checked
    property alias cfg_deckSolidBg: deckSolidBgCheck.checked
    property alias cfg_showGames: showGamesCheck.checked
    property alias cfg_showRlog: showRlogCheck.checked
    property alias cfg_showSyncthing: svcSyncthing.checked
    property alias cfg_showDropbox: svcDropbox.checked
    property alias cfg_showGDrive: svcGDrive.checked
    property alias cfg_showTailscale: svcTailscale.checked
    property alias cfg_showTmux: svcTmux.checked
    property alias cfg_dropboxQuotaGB: quotaSpin.value
    property string cfg_gamesCurrency
    property alias cfg_gamesMainStory: mainStoryCheck.checked
    property alias cfg_gamesIslandStyle: islandBox.currentIndex
    property alias cfg_gamesIslandOpacity: islandSlider.value

    // Same regions steamAF supports (lib/price.ts CURRENCY_CATALOG)
    readonly property var currencies: [
        "USD", "CAD", "BRL", "MXN", "ARS", "CLP", "COP", "PEN", "UYU", "CRC",
        "GBP", "EUR", "PLN", "CHF", "NOK", "SEK", "DKK", "CZK", "HUF", "RON",
        "TRY", "UAH", "ILS", "AED", "SAR", "QAR", "KWD", "ZAR", "KZT", "INR",
        "PKR", "IDR", "MYR", "PHP", "SGD", "THB", "VND", "TWD", "HKD", "CNY",
        "JPY", "KRW", "AUD", "NZD"
    ]

    Kirigami.FormLayout {
        RowLayout {
            Kirigami.FormData.label: i18n("Font Size:")
            spacing: Kirigami.Units.largeSpacing

            QQC2.Slider {
                id: fontSizeSlider
                Layout.preferredWidth: Kirigami.Units.gridUnit * 12
                from: 10
                to: 18
                stepSize: 1
                snapMode: QQC2.Slider.SnapAlways
            }

            QQC2.Label {
                id: sizeValueLabel
                text: fontSizeSlider.value + " px"
                font.bold: true
                Layout.preferredWidth: Kirigami.Units.gridUnit * 3
            }
        }

        QQC2.Label {
            text: i18n("Default: 12 px (range 10 - 18 px)")
            color: Kirigami.Theme.disabledTextColor
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
        }

        Item { Kirigami.FormData.isSection: true }

        QQC2.ComboBox {
            id: styleBox
            Kirigami.FormData.label: i18n("Background:")
            model: [i18n("Solid"), i18n("Glass")]
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Glass opacity:")
            enabled: styleBox.currentIndex === 1
            spacing: Kirigami.Units.largeSpacing

            QQC2.Slider {
                id: opacitySlider
                Layout.preferredWidth: Kirigami.Units.gridUnit * 12
                from: 10
                to: 90
                stepSize: 5
                snapMode: QQC2.Slider.SnapAlways
            }

            QQC2.Label {
                text: opacitySlider.value + " %"
                font.bold: true
                Layout.preferredWidth: Kirigami.Units.gridUnit * 3
            }
        }

        Item { Kirigami.FormData.isSection: true }

        QQC2.ComboBox {
            id: externalModeBox
            Kirigami.FormData.label: i18n("On external monitors:")
            // 0 = hide while the Deck screen is on, 1 = always show, 2 = never show
            model: [
                i18n("Hide while the Deck screen is on"),
                i18n("Always show (floating widget)"),
                i18n("Never show")
            ]
            currentIndex: !appearancePage.cfg_showOnExternal ? 2 : (appearancePage.cfg_autoScreenMigrate ? 0 : 1)
            // This choice is shared by every widget instance through the monitor daemon,
            // so it also reaches the widget on the other screen (which may be hidden).
            Component.onCompleted: {
                var xhr = new XMLHttpRequest();
                xhr.open("GET", "http://127.0.0.1:19842/status");
                xhr.onreadystatechange = function() {
                    if (xhr.readyState !== XMLHttpRequest.DONE || xhr.status !== 200) return;
                    try {
                        var m = (JSON.parse(xhr.responseText).prefs || {}).external_mode;
                        if (m !== undefined) currentIndex = m;
                    } catch (e) {}
                };
                xhr.send();
            }
            onActivated: (index) => {
                appearancePage.cfg_showOnExternal = index !== 2;
                appearancePage.cfg_autoScreenMigrate = index === 0;
            }
        }

        QQC2.Label {
            text: [
                i18n("While docked with the Deck screen on, the widget only appears on the Deck screen. If you turn the Deck screen off, it moves back to the external monitor."),
                i18n("Shows the floating widget on external monitors too, so while docked you get it on the monitor and the dashboard on the Deck screen at the same time."),
                i18n("Keeps external monitors completely clean. The widget only appears on the Steam Deck's built-in screen, docked or handheld.")
            ][externalModeBox.currentIndex]
            color: Kirigami.Theme.disabledTextColor
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }

        Item { Kirigami.FormData.isSection: true }

        QQC2.CheckBox {
            id: deckFullscreenCheck
            Kirigami.FormData.label: i18n("Deck Screen Layout:")
            text: i18n("Use Fullscreen Dashboard layout on Steam Deck screen while docked")
        }

        QQC2.Label {
            text: i18n("Fills the Steam Deck screen with a large, at-a-distance dashboard while an external monitor is connected. In handheld mode the regular floating widget is used. You can also toggle this with the button on the widget header.")
            color: Kirigami.Theme.disabledTextColor
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }

        QQC2.CheckBox {
            id: deckSolidBgCheck
            Kirigami.FormData.label: i18n("Deck Screen Background:")
            text: i18n("Always use solid background on Steam Deck screen while docked")
        }

        QQC2.Label {
            text: i18n("Ensures maximum contrast and crisp readability on the Steam Deck screen while docked on your desk.")
            color: Kirigami.Theme.disabledTextColor
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }

        Item { Kirigami.FormData.isSection: true }

        QQC2.CheckBox { id: svcSyncthing; Kirigami.FormData.label: i18n("Services:"); text: i18n("Syncthing") }
        QQC2.CheckBox { id: svcDropbox; text: i18n("Dropbox") }
        QQC2.CheckBox { id: svcGDrive; text: i18n("Google Drive (rclone)") }
        QQC2.CheckBox { id: svcTailscale; text: i18n("Tailscale") }
        QQC2.CheckBox { id: svcTmux; text: i18n("tmux") }
        RowLayout {
            Kirigami.FormData.label: i18n("Dropbox plan:")
            QQC2.SpinBox { id: quotaSpin; from: 1; to: 100000; editable: true }
            QQC2.Label { text: i18n("GB (hover the Dropbox tile to see usage)") }
        }

        QQC2.Label {
            text: i18n("Shown on the floating card (two per row) and the docked dashboard. Uncheck all to hide the Services section.")
            color: Kirigami.Theme.disabledTextColor
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }

        Item { Kirigami.FormData.isSection: true }

        QQC2.CheckBox {
            id: showRlogCheck
            Kirigami.FormData.label: i18n("RLog:")
            text: i18n("Show the RLog row (Playing and Up next)")
        }

        QQC2.Label {
            text: i18n("Reads r-log.vercel.app through the monitor daemon. The token lives in ~/.config/rlog/widget.env (WIDGET_TOKEN=…). The island uses the same background as the results island below.")
            color: Kirigami.Theme.disabledTextColor
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }

        Item { Kirigami.FormData.isSection: true }

        QQC2.CheckBox {
            id: showGamesCheck
            Kirigami.FormData.label: i18n("Game search:")
            text: i18n("Show steamAF + HowLongToBeat search row")
        }

        QQC2.ComboBox {
            enabled: showGamesCheck.checked
            Kirigami.FormData.label: i18n("steamAF currency:")
            model: appearancePage.currencies
            currentIndex: Math.max(0, appearancePage.currencies.indexOf(appearancePage.cfg_gamesCurrency))
            onActivated: (index) => appearancePage.cfg_gamesCurrency = appearancePage.currencies[index]
        }

        QQC2.CheckBox {
            id: mainStoryCheck
            enabled: showGamesCheck.checked
            text: i18n("Show Main Story hours on steamAF results")
        }

        QQC2.ComboBox {
            id: islandBox
            enabled: showGamesCheck.checked
            Kirigami.FormData.label: i18n("Results island:")
            model: [i18n("Auto (stays readable)"), i18n("Same as widget"), i18n("Custom opacity")]
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Island opacity:")
            enabled: showGamesCheck.checked && islandBox.currentIndex === 2
            spacing: Kirigami.Units.largeSpacing

            QQC2.Slider {
                id: islandSlider
                Layout.preferredWidth: Kirigami.Units.gridUnit * 12
                from: 10
                to: 100
                stepSize: 5
                snapMode: QQC2.Slider.SnapAlways
            }

            QQC2.Label {
                text: islandSlider.value + " %"
                font.bold: true
                Layout.preferredWidth: Kirigami.Units.gridUnit * 3
            }
        }

        QQC2.Label {
            text: i18n("Results open in a floating island under the card, above other widgets. Searches go through the monitor daemon (steamaf.vercel.app and HowLongToBeat).")
            color: Kirigami.Theme.disabledTextColor
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }
    }
}
