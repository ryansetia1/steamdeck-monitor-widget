import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kcmutils as KCMUtils
import org.kde.kirigami as Kirigami

KCMUtils.SimpleKCM {
    id: appearancePage

    property alias cfg_fontSizeScale: fontSizeSlider.value

    Kirigami.FormLayout {
        QQC2.Slider {
            id: fontSizeSlider
            Kirigami.FormData.label: i18n("Font Size:")
            from: 10
            to: 18
            stepSize: 1
            snapMode: QQC2.Slider.SnapAlways
        }

        QQC2.Label {
            text: fontSizeSlider.value + " px (" + (fontSizeSlider.value <= 11 ? "Small" : (fontSizeSlider.value <= 13 ? "Medium / Default" : (fontSizeSlider.value <= 15 ? "Large" : "Extra Large"))) + ")"
            color: Kirigami.Theme.disabledTextColor
        }
    }
}
