import QtQuick
import QtQuick.Controls
import "../core"
import "." as C

TextField {
    id: root
    color: enabled ? Theme.text : Theme.textFaint
    placeholderTextColor: Theme.textFaint
    font.family: Theme.font
    font.pixelSize: Theme.body
    selectionColor: Theme.accentLine
    selectedTextColor: Theme.text
    implicitHeight: Theme.controlLarge
    leftPadding: Theme.gapM
    rightPadding: Theme.gapM
    selectByMouse: true
    verticalAlignment: TextInput.AlignVCenter
    Accessible.name: placeholderText
    // A wrong entry (a password, a name in use): the field shakes and dies away. Callers say when.
    function shake() {
        shaker.start();
    }
    transform: C.Shake {
        id: shaker
    }
    // Taking focus, the accent edge warms up like a lamp before settling.
    onActiveFocusChanged: if (activeFocus && !Motion.calm) edgeGlow.restart()
    // A module-coloured key; focus lights its edge with the accent.
    background: Rectangle {
        radius: Theme.radiusKey
        color: root.hovered && !root.activeFocus ? Theme.mix(Theme.module, Theme.text, 0.04) : Theme.module
        border.width: 1
        border.color: root.activeFocus ? Theme.accentLine : "transparent"
        Behavior on color {
            ColorAnimation {
                duration: Theme.fast
            }
        }
        Behavior on border.color {
            ColorAnimation {
                duration: Theme.fast
            }
        }
    }
    Rectangle {
        id: edge
        anchors.fill: parent
        radius: Theme.radiusKey
        color: "transparent"
        border.width: 1.5
        border.color: Theme.accent
        opacity: 0
        visible: opacity > 0
        SequentialAnimation {
            id: edgeGlow
            NumberAnimation { target: edge; property: "opacity"; from: 0; to: 0.9; duration: Motion.ms(80); easing.type: Easing.OutQuad }
            NumberAnimation { target: edge; property: "opacity"; to: 0; duration: Motion.ms(320); easing.type: Easing.InOutQuad }
        }
    }
    // Reached with Tab: the same 2 px ring as every other control (search fields that open focused keep their edge).
    C.FocusRing {
        visible: root.activeFocus && (root.focusReason === Qt.TabFocusReason || root.focusReason === Qt.BacktabFocusReason)
        radius: Theme.radiusKey
    }
}
