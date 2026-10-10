import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../core"
import "." as C

ColumnLayout {
    id: root
    property string title: ""
    property string glyph: "volume"
    property real value: 0
    property real maximum: 1
    // A muteable row turns its icon into a mute toggle; muted keeps the real level visible.
    property bool muteable: false
    property bool muted: false
    property string mutedGlyph: "mute"
    signal moved(real value)
    signal iconClicked()
    spacing: 5
    opacity: enabled ? 1 : 0.45
    RowLayout {
        Layout.fillWidth: true
        C.Icon {
            visible: !root.muteable
            name: root.glyph
            size: 16
        }
        C.Button {
            visible: root.muteable
            glyph: root.muted ? root.mutedGlyph : root.glyph
            flat: true
            selected: root.muted
            opacity: root.muted && root.mutedGlyph === root.glyph ? 0.55 : 1
            implicitWidth: 28
            implicitHeight: 28
            Layout.leftMargin: -6
            Layout.topMargin: -4
            Layout.bottomMargin: -4
            hint: (root.muted ? "Unmute " : "Mute ") + root.title.toLowerCase()
            Accessible.role: Accessible.CheckBox
            Accessible.checkable: true
            Accessible.checked: root.muted
            onClicked: root.iconClicked()
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
                color: root.muted ? Theme.hover : Theme.activityLevel3
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
