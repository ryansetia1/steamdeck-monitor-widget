import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kcmutils as KCMUtils
import org.kde.kirigami as Kirigami

KCMUtils.SimpleKCM {
    id: appearancePage

    property alias cfg_fontSizeScale: fontSizeSlider.value

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
    }
}
