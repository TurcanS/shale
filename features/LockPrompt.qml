import QtQuick
import QtQuick.Layouts
import "../core"
import "../components" as C

// The unlock group both styles show at the bottom centre: your picture, a greeting, the password field and the
// status line under it. A wrong password shakes the field; reduced motion keeps only its red edge and the message.
ColumnLayout {
    id: root
    required property var context
    // Any key reaching the field, for styles that wake on activity.
    signal keyPressed()
    function focusField() {
        field.focusField();
    }
    width: 340
    spacing: 12
    LockAvatar {
        Layout.alignment: Qt.AlignHCenter
        Layout.preferredWidth: 64
        Layout.preferredHeight: 64
    }
    C.Label {
        text: "Welcome back"
        font.pixelSize: 16
        font.weight: Font.DemiBold
        elide: Text.ElideNone
        Layout.alignment: Qt.AlignHCenter
    }
    LockField {
        id: field
        context: root.context
        Layout.alignment: Qt.AlignHCenter
        Layout.preferredWidth: 340
        Layout.preferredHeight: 48
        onKeyPressed: root.keyPressed()
        transform: Translate { id: shakeOffset }
        SequentialAnimation {
            id: shake
            // Calm: an even shake. Lively and Playful: harder at first, dying away like a struck panel.
            NumberAnimation { target: shakeOffset; property: "x"; to: Motion.calm ? -6 : -9 * Motion.travel; duration: 60; easing.type: Easing.InOutSine }
            NumberAnimation { target: shakeOffset; property: "x"; to: Motion.calm ? 6 : 7 * Motion.travel; duration: 60; easing.type: Easing.InOutSine }
            NumberAnimation { target: shakeOffset; property: "x"; to: Motion.calm ? -6 : -4.5 * Motion.travel; duration: 60; easing.type: Easing.InOutSine }
            NumberAnimation { target: shakeOffset; property: "x"; to: Motion.calm ? 6 : 2.5 * Motion.travel; duration: 60; easing.type: Easing.InOutSine }
            NumberAnimation { target: shakeOffset; property: "x"; to: Motion.calm ? 0 : -1 * Motion.travel; duration: 60; easing.type: Easing.InOutSine }
            NumberAnimation { target: shakeOffset; property: "x"; to: 0; duration: Motion.calm ? 0 : 70; easing.type: Easing.OutSine }
        }
        Connections {
            target: root.context
            function onFailed() {
                if (!Theme.reduced && !Theme.lowPower)
                    shake.restart();
            }
        }
    }
    LockNote {
        context: root.context
        Layout.fillWidth: true
        Layout.preferredHeight: Math.max(implicitHeight, 18)
    }
}
