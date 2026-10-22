import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../core"
import "." as C

ColumnLayout {
    id: root
    property string title: ""
    // A per-app row shows the app's mineral before its name.
    property color mineral: "transparent"
    property string glyph: "volume"
    property real value: 0
    property real maximum: 1
    // A muteable row turns its icon into a mute toggle; muted keeps the real level visible.
    property bool muteable: false
    property bool muted: false
    property string mutedGlyph: "mute"
    // With a hint, a trailing chevron opens this level's detail page.
    property string detailHint: ""
    signal moved(real value)
    signal iconClicked()
    signal detailRequested()
    spacing: Theme.gapXs
    opacity: enabled ? 1 : Theme.disabledOpacity
    RowLayout {
        Layout.fillWidth: true
        C.Icon {
            visible: !root.muteable
            name: root.glyph
        }
        C.Button {
            visible: root.muteable
            glyph: root.muted ? root.mutedGlyph : root.glyph
            flat: true
            selected: root.muted
            opacity: root.muted && root.mutedGlyph === root.glyph ? 0.55 : 1
            implicitWidth: Theme.controlSmall
            implicitHeight: Theme.controlSmall
            Layout.leftMargin: -6
            Layout.topMargin: -4
            Layout.bottomMargin: -4
            hint: (root.muted ? "Unmute " : "Mute ") + root.title.toLowerCase()
            Accessible.role: Accessible.CheckBox
            Accessible.checkable: true
            Accessible.checked: root.muted
            onClicked: root.iconClicked()
        }
        Rectangle {
            visible: root.mineral.a > 0
            Layout.preferredWidth: 8
            Layout.preferredHeight: 8
            radius: 4
            color: root.mineral
        }
        C.Label {
            text: root.title + (root.muted ? " · muted" : "")
            color: root.muted ? Theme.muted : Theme.text
            Layout.fillWidth: true
        }
        C.Label {
            text: Math.round((slider.pressed ? slider.value : root.value) * 100) + "%"
            color: Theme.muted
            font.family: Theme.mono
        }
        C.Button {
            visible: root.detailHint !== ""
            glyph: "chevron"
            flat: true
            hint: root.detailHint
            implicitWidth: Theme.controlSmall
            implicitHeight: Theme.controlSmall
            Layout.rightMargin: -4
            Layout.topMargin: -4
            Layout.bottomMargin: -4
            onClicked: root.detailRequested()
        }
    }
    Slider {
        id: slider
        Layout.fillWidth: true
        from: 0
        to: root.maximum
        value: root.value
        stepSize: 0.05
        wheelEnabled: true
        implicitHeight: 30
        Accessible.name: root.title
        onMoved: root.moved(value)
        background: Rectangle {
            x: slider.leftPadding
            y: (slider.height - height) / 2
            width: slider.availableWidth
            height: 10
            radius: 5
            color: Theme.raised
            Rectangle {
                width: slider.visualPosition * parent.width
                height: parent.height
                radius: 5
                color: root.muted ? Theme.hover : Theme.fill
                Behavior on color {
                    ColorAnimation {
                        duration: Theme.fast
                    }
                }
                Behavior on width {
                    enabled: !slider.pressed
                    NumberAnimation {
                        duration: Theme.fast
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }
        handle: Rectangle {
            x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
            y: (slider.height - height) / 2
            width: slider.pressed ? 18 : 14
            height: slider.pressed ? 18 : 14
            radius: width / 2
            color: root.muted ? Theme.muted : Theme.accent
            border.width: 0
            Behavior on width {
                NumberAnimation {
                    duration: Theme.fast
                }
            }
            Behavior on height {
                NumberAnimation {
                    duration: Theme.fast
                }
            }
            Behavior on color {
                ColorAnimation {
                    duration: Theme.fast
                }
            }
        }
    }
}
