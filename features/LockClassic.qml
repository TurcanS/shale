import QtQuick
import QtQuick.Layouts
import Quickshell
import "../core"
import "../services"
import "../components" as C

// The classic lock screen: a large clock over the blurred wallpaper, your picture and the password field.
Item {
    id: root
    required property var context
    property string screenName: ""
    property real reveal: 0
    Component.onCompleted: reveal = 1
    opacity: context.unlocking ? 0 : reveal
    Behavior on opacity {
        NumberAnimation {
            duration: Theme.reduced ? 0 : 220
            easing.type: Easing.OutCubic
        }
    }
    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    LockBackdrop {
        anchors.fill: parent
        screenName: root.screenName
    }
    LockStatus {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 28
    }

    ColumnLayout {
        id: centre
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -30
        width: Math.min(parent.width - 48, 360)
        spacing: 0
        transform: Translate { y: Theme.reduced ? 0 : (1 - root.reveal) * 14 }
        C.Label {
            text: Qt.formatDateTime(clock.date, "dddd · d MMMM").toUpperCase()
            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.95)
            font.pixelSize: 13
            font.weight: Font.DemiBold
            font.letterSpacing: 3
            elide: Text.ElideNone
            Layout.alignment: Qt.AlignHCenter
        }
        // The lock in the station's words; the plain word ("Locked") when they are off.
        C.StationText {
            text: ShellState.word("unattended")
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 4
            Accessible.name: "Locked"
        }
        // Tabular figures keep the clock from shifting as the minutes change.
        C.Label {
            text: Qt.formatDateTime(clock.date, ShellState.setting("clock24h", true) ? "HH:mm" : "h:mm")
            font.pixelSize: 132
            font.weight: Font.ExtraLight
            font.letterSpacing: -4
            font.features: {"tnum": 1}
            elide: Text.ElideNone
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: -6
            Layout.bottomMargin: 36
        }
        LockAvatar {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 72
            Layout.preferredHeight: 72
        }
        C.Label {
            text: Quickshell.env("USER") || ""
            font.pixelSize: Theme.body + 1
            font.weight: Font.Medium
            elide: Text.ElideNone
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 12
            Layout.bottomMargin: 18
        }
        // The next order, only when the owner chose to show titles on the lock screen.
        C.Label {
            visible: ShellState.setting("lockTitles", false) && !!Day.nextItem
            text: Day.nextItem ? Day.nextItem.text : ""
            color: Theme.muted
            font.pixelSize: Theme.small
            elide: Text.ElideRight
            Layout.maximumWidth: 330
            Layout.alignment: Qt.AlignHCenter
            Layout.bottomMargin: 12
        }
        LockField {
            id: field
            context: root.context
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Math.min(centre.width, 330)
            Layout.preferredHeight: 52
            // A short shake on a wrong password; reduced motion keeps only the message.
            transform: Translate { id: shakeOffset }
            SequentialAnimation {
                id: shake
                NumberAnimation { target: shakeOffset; property: "x"; to: -10; duration: 45 }
                NumberAnimation { target: shakeOffset; property: "x"; to: 9; duration: 70 }
                NumberAnimation { target: shakeOffset; property: "x"; to: -6; duration: 60 }
                NumberAnimation { target: shakeOffset; property: "x"; to: 3; duration: 50 }
                NumberAnimation { target: shakeOffset; property: "x"; to: 0; duration: 40 }
            }
            Connections {
                target: root.context
                function onFailed() {
                    if (!Theme.reduced)
                        shake.restart();
                }
            }
        }
        LockNote {
            context: root.context
            Layout.fillWidth: true
            Layout.topMargin: 12
            Layout.preferredHeight: Math.max(implicitHeight, 18)
        }
    }

    // Bottom row: what's playing (with controls) and the power button.
    RowLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 28
        spacing: Theme.gapL
        LockMedia {
            Layout.preferredWidth: Math.min(360, root.width / 2 - 40)
        }
        Item {
            Layout.fillWidth: true
        }
        LockPower {
            context: root.context
            onReleased: field.focusField()
        }
    }
}
