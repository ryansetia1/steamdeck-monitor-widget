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
    property alias cfg_autoScreenMigrate: autoScreenCheck.checked

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

        QQC2.CheckBox {
            id: autoScreenCheck
            Kirigami.FormData.label: i18n("Docking Screen:")
            text: i18n("Show only on Steam Deck screen when dual displays are active")
        }

        QQC2.Label {
            text: i18n("When docked and the Steam Deck screen is ON, automatically shows widget on the Deck screen to keep external monitor clean. When Deck screen is OFF, moves back to external monitor.")
            color: Kirigami.Theme.disabledTextColor
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }
    }
}
