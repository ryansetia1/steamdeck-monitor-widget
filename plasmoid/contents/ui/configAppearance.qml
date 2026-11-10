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
    }
}
